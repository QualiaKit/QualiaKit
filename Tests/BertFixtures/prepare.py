#!/usr/bin/env python3
"""Package a local Core ML BERT classifier for the generic QualiaCoreML adapter.

Reads local files only. Requires coremltools for model metadata; it never fetches
weights or performs conversion/training. The caller supplies semantic labels.
"""
import argparse
import hashlib
import json
import shutil
import tempfile
from pathlib import Path


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tokenizer_contract(directory):
    tokenizer = read(directory / 'tokenizer.json')
    tokens = read(directory / 'special_tokens_map.json')
    normalizer = tokenizer.get('normalizer', {})
    model = tokenizer.get('model', {})
    if (normalizer.get('type') != 'BertNormalizer' or
            tokenizer.get('pre_tokenizer') != {'type': 'BertPreTokenizer'} or
            model.get('type') != 'WordPiece' or tokenizer.get('truncation') is not None or
            tokenizer.get('padding') is not None):
        raise ValueError('Expected standard BERT normalizer, pre-tokenizer and WordPiece without saved truncation/padding')
    vocab = (directory / 'vocab.txt').read_text().splitlines()
    if not vocab or len(set(vocab)) != len(vocab) or any(not v for v in vocab):
        raise ValueError('Invalid vocabulary')
    if model['vocab'] != {token: i for i, token in enumerate(vocab)}:
        raise ValueError('vocab.txt and tokenizer.json disagree')
    special = {}
    for role in ['pad', 'unk', 'cls', 'sep', 'mask']:
        token = tokens.get(role + '_token')
        if token is None and role == 'mask':
            continue
        if isinstance(token, dict):
            token = token['content']
        if not isinstance(token, str) or token not in model['vocab']:
            raise ValueError('Missing special token: ' + role)
        special[role] = {'token': token, 'id': model['vocab'][token]}
    expected_added = {value['token']: value['id'] for value in special.values()}
    added = tokenizer.get('added_tokens', [])
    if ({t['content']: t['id'] for t in added} != expected_added or len(added) != len(expected_added) or
            any(not t['special'] or any(t[k] for k in ('single_word', 'lstrip', 'rstrip', 'normalized')) for t in added)):
        raise ValueError('Custom added-token rules require a different tokenizer profile')
    if model['unk_token'] != special['unk']['token']:
        raise ValueError('WordPiece unknown token mismatch')
    post = tokenizer.get('post_processor', {})
    cls, sep = special['cls']['token'], special['sep']['token']
    def sequence(name, segment):
        return {'Sequence': {'id': name, 'type_id': segment}}
    def token(name, segment):
        return {'SpecialToken': {'id': name, 'type_id': segment}}
    expected_special = {name: {'id': name, 'ids': [special[role]['id']], 'tokens': [name]}
                        for role, name in [('cls', cls), ('sep', sep)]}
    if (post.get('type') != 'TemplateProcessing' or
            post.get('single') != [token(cls, 0), sequence('A', 0), token(sep, 0)] or
            post.get('pair') != [token(cls, 0), sequence('A', 0), token(sep, 0), sequence('B', 1), token(sep, 1)] or
            post.get('special_tokens') != expected_special):
        raise ValueError('Expected standard BERT single/pair post-processing')
    strip = normalizer['strip_accents']
    return dict(type='bert-wordpiece-v1', vocabulary='vocab.txt', vocabularySha256=sha(directory/'vocab.txt'),
                vocabularyLineCount=len(vocab), lowercase=normalizer['lowercase'],
                stripAccents=normalizer['lowercase'] if strip is None else strip,
                cleanText=normalizer['clean_text'], tokenizeChineseCharacters=normalizer['handle_chinese_chars'],
                unicodeNormalization='bert', maximumWordCharacters=model['max_input_chars_per_word'],
                continuingSubwordPrefix=model['continuing_subword_prefix'], specialTokens=special)


def inventory(directory):
    paths = sorted(directory.rglob('*'))
    if any(p.is_symlink() for p in paths):
        raise ValueError('Model symlinks are unsupported')
    return {str(p.relative_to(directory)): sha(p) for p in paths if p.is_file()}


def prepare(args):
    import coremltools as ct
    if args.out.exists():
        raise ValueError('Destination exists; use a new version directory')
    config = tokenizer_contract(args.tokenizer)
    labels = read(args.labels)
    if (not isinstance(labels, list) or not labels or
            any(set(item) != {'name', 'signal'} or not all(isinstance(v, str) and v.strip() for v in item.values()) for item in labels) or
            len({item['name'] for item in labels}) != len(labels) or
            len({item['signal'] for item in labels}) != len(labels)):
        raise ValueError('Supply an ordered array of distinct {name, signal} labels')
    suffix = args.model.suffix
    if suffix not in ('.mlmodel', '.mlpackage') or args.model.is_symlink():
        raise ValueError('Expected local Core ML .mlmodel or .mlpackage')
    spec = ct.models.MLModel(str(args.model), skip_model_load=True).get_spec()
    roles = read(args.input_roles) if args.input_roles else {
        'input_ids': 'tokenIDs', 'attention_mask': 'attentionMask', 'token_type_ids': 'tokenTypeIDs', 'position_ids': 'positionIDs'}
    names = {f.name for f in spec.description.input}
    if not names.issubset(roles) or (args.input_roles and names != set(roles)):
        raise ValueError('Declare every model input with --input-roles')
    types = {131104: 'Int32', 65568: 'Float32', 65600: 'Double', 65552: 'Float16'}
    inputs = {}
    for feature in spec.description.input:
        array = feature.type.multiArrayType
        shape = list(array.shape)
        dtype = types.get(array.dataType)
        if feature.type.WhichOneof('Type') != 'multiArrayType' or feature.type.isOptional or dtype not in ('Int32', 'Float32', 'Double') or shape not in ([args.length], [1, args.length]):
            raise ValueError('Input must be required fixed [N] or [1,N] Int32/Float32/Double')
        if array.WhichOneof('ShapeFlexibility') is not None:
            raise ValueError('Export a fixed sequence length')
        inputs[feature.name] = dict(role=roles[feature.name], shape=shape, dataType=dtype)
    used_roles = [item['role'] for item in inputs.values()]
    if (len(set(used_roles)) != len(used_roles) or 'tokenIDs' not in used_roles or
            not set(used_roles).issubset({'tokenIDs', 'attentionMask', 'tokenTypeIDs', 'positionIDs'})):
        raise ValueError('Unsupported or repeated input roles')
    if len(spec.description.output) != 1:
        raise ValueError('Export one classification score tensor')
    output = spec.description.output[0]
    array = output.type.multiArrayType
    if (output.type.WhichOneof('Type') != 'multiArrayType' or output.type.isOptional or
            list(array.shape) not in ([len(labels)], [1, len(labels)]) or
            types.get(array.dataType) not in ('Float16', 'Float32', 'Double') or
            array.WhichOneof('ShapeFlexibility') is not None):
        raise ValueError('Output must be a fixed [K] or [1,K] floating classification tensor matching the label order')
    asset = dict(path='model'+suffix, format=suffix[1:])
    asset.update(files=inventory(args.model)) if suffix == '.mlpackage' else asset.update(sha256=sha(args.model))
    manifest = dict(schemaVersion=1, kind='qualia-bert-sequence-classification', identifier=args.identifier,
                    version=args.version, languages=args.languages, model=asset, tokenizer=config,
                    sequence=dict(maximumLength=args.length, template=args.template, contextSeparator=args.context_separator,
                                  padding='right', overflow='reject'), inputs=inputs,
                    output=dict(feature=output.name, shape=list(array.shape), dataType=types[array.dataType],
                                classification=args.classification,
                                transform='none' if args.probabilities else ('sigmoid' if args.classification=='independent' else 'softmax'),
                                labels=labels))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.out.parent) as temporary:
        stage = Path(temporary)/'artifact'
        stage.mkdir()
        destination = stage/asset['path']
        if suffix == '.mlpackage':
            shutil.copytree(args.model, destination)
            if inventory(destination) != asset['files']: raise ValueError('Source changed while copying')
        else:
            shutil.copy2(args.model, destination)
            if sha(destination) != asset['sha256']: raise ValueError('Source changed while copying')
        shutil.copy2(args.tokenizer/'vocab.txt', stage/'vocab.txt')
        if sha(stage/'vocab.txt') != config['vocabularySha256']: raise ValueError('Vocabulary changed while copying')
        (stage/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
        stage.rename(args.out)
    print('Prepared local model:', args.out)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--tokenizer', type=Path, required=True)
    parser.add_argument('--labels', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--identifier', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--languages', nargs='+', required=True)
    parser.add_argument('--length', type=int, required=True)
    parser.add_argument('--template', choices=['singleText', 'contextThenText'], required=True)
    parser.add_argument('--context-separator', default='\n')
    parser.add_argument('--classification', choices=['exclusive', 'independent'], required=True)
    parser.add_argument('--probabilities', action='store_true', help='Output already contains probabilities, not logits')
    parser.add_argument('--input-roles', type=Path, help='JSON object mapping custom feature names to tensor roles')
    args = parser.parse_args()
    if not 3 <= args.length <= 4096: parser.error('--length must be 3...4096')
    if not args.identifier.strip() or not args.version.strip(): parser.error('Identity and version must not be blank')
    prepare(args)


if __name__ == '__main__':
    main()
