#!/usr/bin/env python3
"""Generate public arithmetic models and Hugging Face tokenization references.

These tiny models have no learned weights or application data. Core ML outputs
are checked against separate analytical arithmetic, not against their own output.
Run with coremltools 8.3.0, transformers 4.57.1, tokenizers 0.22.2, numpy 2.2.6.
"""
import argparse
import json
import math
import tempfile
from pathlib import Path
from types import SimpleNamespace

import coremltools as ct
import numpy as np
from coremltools.models import datatypes
from coremltools.models.neural_network import NeuralNetworkBuilder
from transformers import BertTokenizerFast
from prepare import prepare

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT/'Packages/QualiaCoreML/Tests/QualiaCoreMLTests/Resources/Bert'
VOCAB = ['[PAD]', '[UNK]', '[CLS]', '[SEP]', '[MASK]', 'hello', 'world', 'cafe', 'Hello', 'CAFÉ',
         'un', '##seen', '!', '中', '文', 'smile', '##s', 'i', 'οσ', 'ab', '##cd', '.', 'naive',
         'a', '##b', 'c', '##d', 'é', 'e', '##x', '𠮷']
CASES = [
    ('basic', [], 'Hello world!'), ('pair', ['hello', 'world'], 'smiles!'),
    ('accent', [], 'CAFÉ cafe\u0301 naïve'), ('special', [], 'a[MASK][SEP]b'),
    ('unicode', [], '中文 İ ΟΣ 𠮷'), ('controls', [], 'ab\u200dcd ab\ue000cd ab\u0378cd'),
    ('whitespace', [], 'ab\u2028cd ab\x0bcd'), ('unknown', [], 'notinvocabulary'),
    ('word-limit', [], 'x'*101), ('wordpiece', [], 'unseen smiles'),
]


def generate(root, only=None):
    for name, pair in [('uncased-pair', True), ('cased-single', False), ('uncased-package', True)]:
        if only and name != only: continue
        length, count = (16, 3) if pair else (12, 2)
        dtype = 'Int32' if pair else 'Float32'
        shape = [1, length] if pair else [length]
        roles = {'input_ids':'tokenIDs','attention_mask':'attentionMask','token_type_ids':'tokenTypeIDs'} if pair else {'pieces':'tokenIDs','offsets':'positionIDs'}
        output_shape = [1, count] if pair else [count]
        output_name = 'logits' if pair else 'class_values'
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            tokenizer_dir = folder/'tokenizer'
            tokenizer_dir.mkdir()
            (tokenizer_dir/'vocab.txt').write_text('\n'.join(VOCAB)+'\n')
            tokenizer = BertTokenizerFast(vocab_file=str(tokenizer_dir/'vocab.txt'), do_lower_case=pair)
            tokenizer.save_pretrained(tokenizer_dir)
            b = NeuralNetworkBuilder([(n,datatypes.Array(*shape)) for n in roles],
                                     [(output_name,datatypes.Array(*output_shape))],disable_rank5_shape_mapping=True)
            b.add_concat_nd('join', list(roles), 'joined', axis=1 if pair else 0)
            weights=[]
            factors={'tokenIDs':1,'attentionMask':2,'tokenTypeIDs':3,'positionIDs':4}
            for row in range(count):
                weights.append([(row+1)*factors[role]*(i+1)/1024 for role in roles.values() for i in range(length)])
            b.add_inner_product('affine', np.array(weights,dtype=np.float32), np.array([i/4 for i in range(count)],dtype=np.float32),
                                length*len(roles),count,True,'joined',output_name)
            for feature in b.spec.description.input:
                feature.type.multiArrayType.dataType=131104 if pair else 65568
            b.spec.description.output[0].type.multiArrayType.dataType=65568
            b.spec.description.metadata.shortDescription='Public arithmetic test fixture; no language understanding or learned weights.'
            b.spec.description.metadata.license='MIT; repository LICENSE'
            model=folder/'model.mlmodel'
            if name == 'uncased-package':
                from coremltools.converters.mil import Builder as mb
                from coremltools.converters.mil.mil import types
                @mb.program(input_specs=[mb.TensorSpec(shape=(1,length),dtype=types.int32) for _ in range(3)],opset_version=ct.target.iOS16)
                def program(input_ids, attention_mask, token_type_ids):
                    joined=mb.concat(values=[input_ids,attention_mask,token_type_ids],axis=1)
                    return mb.linear(x=mb.cast(x=joined,dtype='fp32'),weight=np.array(weights,dtype=np.float32),
                                     bias=np.array([i/4 for i in range(count)],dtype=np.float32),name=output_name)
                converted=ct.convert(program,minimum_deployment_target=ct.target.iOS16,compute_precision=ct.precision.FLOAT32)
                model=folder/'model.mlpackage'
                converted.save(str(model))
            else:
                model.write_bytes(b.spec.SerializeToString(deterministic=True))
            labels=[{'name':f'raw_{i}','signal':f'fixture.{name}.{i}'} for i in range(count)]
            (folder/'labels.json').write_text(json.dumps(labels))
            (folder/'roles.json').write_text(json.dumps(roles))
            destination=root/name
            prepare(SimpleNamespace(model=model,tokenizer=tokenizer_dir,labels=folder/'labels.json',out=destination,
                identifier='fixture.'+name,version='1',languages=['en'],length=length,
                template='contextThenText' if pair else 'singleText',context_separator='\n',
                classification='independent' if pair else 'exclusive',probabilities=False,input_roles=folder/'roles.json'))
            golden=[]
            cases=CASES+ [('exact-limit', [], ' '.join(['hello']*(length-(3 if pair else 2))))]
            for identifier,context,text in cases:
                if not pair: context=[]
                encoded=tokenizer('\n'.join(context),text,padding='max_length',max_length=length,truncation=False) if pair else tokenizer(text,padding='max_length',max_length=length,truncation=False)
                assert len(encoded['input_ids'])==length,identifier
                fields={'tokenIDs':encoded['input_ids'],'attentionMask':encoded['attention_mask'],
                        'tokenTypeIDs':encoded['token_type_ids'],'positionIDs':list(range(length))}
                flat=[v for role in roles.values() for v in fields[role]]
                logits=[sum(a*b for a,b in zip(row,flat))+i/4 for i,row in enumerate(weights)]
                if pair: scores=[1/(1+math.exp(-v)) for v in logits]
                else:
                    exponents=[math.exp(v-max(logits)) for v in logits]
                    scores=[v/sum(exponents) for v in exponents]
                golden.append(dict(id=identifier,text=text,context=context,ids=encoded['input_ids'],mask=encoded['attention_mask'],
                                   types=encoded['token_type_ids'],scores=scores))
            (destination/'golden.json').write_text(json.dumps(golden,ensure_ascii=False,indent=2)+'\n')
            (destination/'tokenizer-reference.json').write_text(json.dumps({'generator':'Hugging Face BertTokenizerFast',
                'transformers':'4.57.1','tokenizers':'0.22.2','model':'synthetic arithmetic; no trained weights'},indent=2)+'\n')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=DEST)
    parser.add_argument('--only',choices=['uncased-pair','cased-single','uncased-package'])
    args=parser.parse_args()
    generate(args.out,args.only)
