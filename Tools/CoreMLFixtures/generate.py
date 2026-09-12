#!/usr/bin/env python3
"""Rebuild public synthetic fixtures (no training data or protected assets).

Generation only: Python 3.11 + requirements.lock. Normal CI uses the committed
models and the independent math references, and needs no coremltools install.
Each contract is immutable: changes require a new directory/version.
"""
import argparse
import hashlib
import tempfile
import json
from pathlib import Path

import coremltools as ct
import numpy as np
from coremltools.models import datatypes
from coremltools.models.neural_network import NeuralNetworkBuilder

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'Packages/QualiaCoreML/Tests/QualiaCoreMLTests/Resources/CoreML'
VOCAB = ['[PAD]', '[UNK]', '[CLS]', '[SEP]', 'quiet', 'storm', 'rises', 'falls', 'café', 'CAFÉ', '🙂', 'storm!',
         'r\u00e9sum\u00e9', 're\u0301sume\u0301', 'nai\u0308ve']
EVIDENCE = 'Tools/CoreMLFixtures/generate.py and reference.py; public synthetic arithmetic fixture, not a trained language model'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + '\n')


def verified(value):
    return dict(status='verified', value=value, evidence=EVIDENCE)


def generate(name, length, roles, dtype, probability=False, independent=False, rank_two=False):
    folder = DEST / name
    folder.mkdir(parents=True, exist_ok=True)
    feature_names = list(roles)
    labels = ['LABEL_0', 'LABEL_1', 'LABEL_2']
    score_name, winner = ('distribution', 'chosen') if probability else ('energies', 'selected')
    shape = [1, length] if rank_two else [length]
    b = NeuralNetworkBuilder([(f, datatypes.Array(*shape)) for f in feature_names],
                             [('values', datatypes.Array(3))], mode='classifier', disable_rank5_shape_mapping=True)
    if len(feature_names) > 1:
        b.add_concat_nd('join', feature_names, 'joined', axis=0)
        input_blob = 'joined'
    else:
        input_blob = feature_names[0]
    # Exact dyadic coefficients. Independent reference.py implements the arithmetic
    # directly and neither loads these weights nor invokes this generator.
    coefficients = []
    for row in range(3):
        weights = []
        for role in roles.values():
            base = {'tokenIDs': [1/32, -1/64, 1/128], 'attentionMask': [1/16, 1/8, -1/16],
                    'tokenTypeIDs': [1/8, -1/8, 1/4]}[role][row]
            weights.extend([base * (i + 1) for i in range(length)])
        coefficients.append(weights)
    raw_name = 'raw' if probability else 'values'
    b.add_inner_product('affine', np.array(coefficients, dtype=np.float32), np.array([0, 1/4, -1/2]),
                        length * len(roles), 3, True, input_blob, raw_name)
    if probability:
        b.add_softmax('normalized', 'raw', 'values')
    b.set_class_labels(labels, predicted_feature_name=winner, prediction_blob='values')
    b.spec.description.predictedProbabilitiesName = score_name
    b.spec.description.output[0].name = score_name
    for f in b.spec.description.input:
        f.type.multiArrayType.dataType = {'Int32': 131104, 'Float32': 65568, 'Double': 65600}[dtype]
        f.type.isOptional = roles[f.name] == 'tokenTypeIDs'
    metadata = b.spec.description.metadata
    metadata.author = 'QualiaKit contributors'
    metadata.license = 'MIT; see repository LICENSE'
    metadata.shortDescription = 'Synthetic arithmetic fixture. No language understanding; no trained weights.'
    metadata.versionString = name
    metadata.userDefined['sourceFramework'] = 'hand-authored arithmetic'
    metadata.userDefined['sourceDialect'] = 'NeuralNetworkBuilder'
    metadata.userDefined['coremltools'] = '8.3.0'
    metadata.userDefined['conversionDate'] = '2026-09-12'
    (folder / 'model.mlmodel').write_bytes(b.spec.SerializeToString(deterministic=True))
    model_sha = sha((folder / 'model.mlmodel').read_bytes())
    vocab = ('\n'.join(VOCAB) + '\n').encode()
    (folder / 'vocab.txt').write_bytes(vocab)
    task = 'independent' if independent else 'exclusive'
    generator_sha = sha(Path(__file__).read_bytes())
    lock_sha = sha((Path(__file__).parent / 'requirements.lock').read_bytes())
    manifest = {
        'schemaVersion': 1, 'contractVersion': name,
        'compatibility': {'v1Additions': 'optional-only-with-preserved-meaning',
                          'breakingChangesRequireSchemaIncrement': True, 'consumersMustRejectUnsupportedVersions': True},
        'model': {'identifier': 'com.qualiakit.fixture.' + name, 'version': 'sha256-' + model_sha,
                  'identityBasis': 'SHA256 of the single model.mlmodel source artifact',
                  'componentSha256': {'model.mlmodel': model_sha}, 'packageIdentitySha256': model_sha,
                  'task': verified(task), 'architectureFamily': verified({'family': 'synthetic-affine-classifier', 'version': '1'}),
                  'languages': ['en'], 'license': verified('MIT'),
                  'redistribution': {'status': 'allowed', 'allowed': True, 'reason': 'Repository-authored synthetic fixture; MIT'}},
        'tokenizer': {'type': 'qualia-ascii-whitespace-v1', 'vocabulary': 'vocab.txt', 'vocabularySha256': sha(vocab),
                      'vocabularyLineCount': len(VOCAB), 'lowercase': True, 'unicodeNormalization': 'none',
                      'maxSequenceLength': length,
                      'specialTokens': {k: {'id': i, 'token': VOCAB[i]} for i, k in enumerate(['pad', 'unk', 'cls', 'sep'])},
                      'trainingIdentity': verified('qualia-ascii-whitespace-v1'), 'trainingVersion': verified('1'),
                      'contextPairSupport': verified({'mode': 'singleText', 'template': '[CLS] text [SEP]'}),
                      'reconstructionBoundary': 'Tokenizer is defined by this public fixture contract; no training or BERT parity claim'},
        'inputs': {f: {'dataType': dtype, 'shape': shape, 'required': role != 'tokenTypeIDs'} for f, role in roles.items()},
        'outputs': {'classLabel': 'String', 'scores': score_name, 'scoresType': 'Dictionary<String,Double>',
                    'kind': verified('mutually-exclusive-probabilities' if probability else 'logits'),
                    'labels': [{'name': label, 'productSignal': 'com.qualiakit.fixture.component' + str(i),
                                'semanticMeaning': verified({'canonicalMeaning': 'Synthetic arithmetic component ' + str(i)})}
                               for i, label in enumerate(labels)]},
        'runtimeRefactorGate': {'status': 'open', 'rule': 'blocked-if-any-condition-is-unresolved',
                               'conditions': {k: 'resolved' for k in ['labelSemantics', 'outputKind', 'provenance', 'tokenizerTrainingParity']}},
        'runtime': {'version': 1, 'model': {'path': 'model.mlmodel', 'format': 'mlmodel', 'sha256': model_sha},
                    'inputRoles': roles, 'classLabelFeature': winner, 'classification': task,
                    'transform': 'none' if probability else ('sigmoid' if independent else 'softmax'),
                    'confidence': 'unavailable', 'truncation': 'right-preserve-sep', 'padding': 'right'},
        'provenance': {'source': verified({'identifier': 'QualiaKit/QualiaKit/Tools/CoreMLFixtures/generate.py',
                                         'revision': name, 'artifactSha256': generator_sha}),
                       'dataset': verified({'identifier': 'synthetic-arithmetic-no-training-dataset', 'version': '1', 'license': 'MIT'}),
                       'domain': verified(['runtime-integration-tests-only']),
                       'classBalance': verified({'split': 'no-training-examples', 'countsByLabel': {label: 0 for label in labels}}),
                       'trainingConfiguration': verified({'trainingArtifactSha256': generator_sha,
                                                          'exportArtifactSha256': generator_sha, 'environmentLockSha256': lock_sha}),
                       'exportMetadata': {'status': 'verified-from-coreml-metadata', 'sourceFramework': 'hand-authored arithmetic',
                                          'sourceDialect': 'NeuralNetworkBuilder', 'coremltools': '8.3.0', 'conversionDate': '2026-09-12'}},
        'ownership': {'contract': 'QualiaKit contributors', 'modelEvidence': 'Tools/CoreMLFixtures'},
        'releaseRisks': [{'field': 'quality', 'status': 'fixture-only', 'releaseImpact': 'Must not be used to infer sentiment or narrative signals'}],
    }
    # Reference generation is an independent module; golden output is its arithmetic, not Core ML output.
    from reference import cases, expected
    golden = [expected(case, length, roles, probability, independent) for case in cases()]
    write_json(folder / 'golden.json', golden)
    golden_sha = sha((folder / 'golden.json').read_bytes())
    manifest['fixture'] = {'version': name, 'immutable': True, 'caseCount': len(golden),
                           'directory': str((ROOT / 'Packages/QualiaCoreML/Tests/QualiaCoreMLTests/Resources/CoreML' / name).relative_to(ROOT)), 'corpusSha256': sha(json.dumps(cases(), sort_keys=True).encode()),
                           'goldenSha256': golden_sha, 'calibrationSha256': sha((Path(__file__).parent / 'reference.py').read_bytes())}
    manifest['floatingPointTolerance'] = {'comparison': 'absolute', 'derivation': '1e-6 Float32 arithmetic comparison budget against independent analytical reference; tested in normal CI, not production calibration',
                                          'absoluteByField': {'rawScores': 1e-6, 'signals': 1e-6},
                                          'calibrationProcessCount': 1, 'holdoutProcessCount': 1}
    write_json(folder / 'manifest.json', manifest)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true', help='Explicitly write reviewed fixture contracts; changed released contracts need new versions')
    args = parser.parse_args()
    committed = DEST
    temporary = tempfile.TemporaryDirectory()
    if not args.write:
        DEST = Path(temporary.name)
    generate('exclusive-logits-v2', 8, {'pieces': 'tokenIDs', 'visible': 'attentionMask'}, 'Int32')
    generate('exclusive-probabilities-v2', 6, {'words': 'tokenIDs', 'presence': 'attentionMask', 'segments': 'tokenTypeIDs'}, 'Float32', probability=True)
    generate('independent-logits-v2', 8, {'symbols': 'tokenIDs'}, 'Double', independent=True, rank_two=True)
    if not args.write:
        for generated in sorted(DEST.rglob('*')):
            if generated.is_file():
                saved = committed / generated.relative_to(DEST)
                assert saved.read_bytes() == generated.read_bytes(), f'Fixture drift: {saved.relative_to(ROOT)}'
        print('Public model generation is byte-reproducible with the pinned environment.')
    temporary.cleanup()
