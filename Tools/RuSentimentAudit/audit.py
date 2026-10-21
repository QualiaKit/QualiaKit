#!/usr/bin/env python3
"""Read-only recovery of the pinned local RuBERT export. Never changes the legacy contract."""
import argparse, hashlib, json, platform
from pathlib import Path

def sha(path):
    with open(path,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def write(path,value):
    with path.open('x') as f:json.dump(value,f,ensure_ascii=False,indent=2);f.write('\n')

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--snapshot',type=Path,required=True)
    p.add_argument('--safetensors',type=Path,required=True)
    p.add_argument('--model',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();args.output.mkdir(parents=True,exist_ok=False)
    import numpy as np, torch, coremltools as ct, transformers
    from coremltools.libmilstoragepython import _BlobStorageReader
    from safetensors import safe_open
    from transformers import BertConfig, BertForSequenceClassification, BertTokenizer
    root=Path(__file__).resolve().parents[2]
    # Bind the entire source asset to the previous audit, without editing it.
    components={str(p.relative_to(args.model)):sha(p) for p in sorted(args.model.rglob('*')) if p.is_file()}
    expected={'Manifest.json':'a655c85265418a3c567fc48869e4bab5271b2340e33b7b67bdc395f3874bb302','Data/com.apple.CoreML/model.mlmodel':'f7ac2156e756a2aacd1cca8cc3f3aded5e7b143147270ea0aea374747a609a42','Data/com.apple.CoreML/weights/weight.bin':'26c028484b4df267933afbfa3ef9ca421dc7450d48bd02c720146bd4444da2f2'}
    assert components==expected, 'Protected model identity changed'
    spec=ct.utils.load_spec(str(args.model));block=list(spec.mlProgram.functions['main'].block_specializations.values())[0]
    reader=_BlobStorageReader(str(args.model/'Data/com.apple.CoreML/weights/weight.bin'))
    weights=[];matched=set()
    with safe_open(str(args.safetensors),framework='numpy') as source:
        names={'model_'+k.replace('.','_')+'_to_fp16':k for k in source.keys()}
        for op in block.operations:
            if op.type!='const':continue
            name=op.outputs[0].name;val=op.attributes['val']
            if name in names:key=names[name];arr=source.get_tensor(key)
            elif name=='position_embeddings_1_to_fp16':key='bert.embeddings.position_embeddings.weight';arr=source.get_tensor(key)[:128]
            else:continue
            assert val.type.tensorType.dataType==10
            if val.HasField('blobFileValue'):converted=np.asarray(reader.read_fp16_data(val.blobFileValue.offset),dtype=np.uint16).view(np.float16)
            else:converted=np.frombuffer(val.immediateValue.tensor.bytes.values,dtype=np.float16)
            rounded=arr.astype(np.float16).reshape(-1)
            assert rounded.tobytes()==converted.tobytes(), key
            matched.add(key);weights.append({'source':key,'coreML':name,'elements':int(rounded.size),'fp16SHA256':hashlib.sha256(rounded.tobytes()).hexdigest(),'exactMatch':True})
        unmatched=set(source.keys())-matched
        assert unmatched=={'bert.embeddings.position_ids'},unmatched
    producers={o.name:op for op in block.operations for o in op.outputs}
    classify=producers['classLabel_probs'];assert classify.type=='classify'
    labels=[v.immediateValue.tensor.strings.values[0] for v in classify.inputs['classes'].arguments[0].value.immediateValue.list.values]
    assert labels==[f'LABEL_{i}' for i in range(5)]
    cast=producers[classify.inputs['probabilities'].arguments[0].name];assert cast.type=='cast'
    linear=producers[cast.inputs['x'].arguments[0].name];assert linear.type=='linear'
    assert linear.inputs['weight'].arguments[0].name=='model_classifier_weight_to_fp16'
    vocab_sha=sha(args.snapshot/'vocab.txt');assert vocab_sha==sha(root/'LocalArtifacts/current/vocab.txt')
    report={'schemaVersion':1,'source':'sismetanin/rubert-ru-sentiment-rusentiment','sourceRevision':args.snapshot.name,'safetensorsRevision':args.safetensors.parent.name,'safetensorsSHA256':sha(args.safetensors),'sourceFiles':{n:sha(args.snapshot/n) for n in ['config.json','tokenizer_config.json','special_tokens_map.json','vocab.txt']},'coreMLComponents':components,'weights':weights,'exactlyMatchedParameterTensors':len(weights),'matchedElements':sum(w['elements'] for w in weights),'positionEmbeddingNote':'Only positions 0...127 are retained in this fixed-128 export; all retained values match after float16 rounding','unusedSourceBuffer':sorted(unmatched),'outputKind':'logits','outputGraph':['classifier linear','cast float16 to float32','classify in unchanged LABEL_0...4 order'],'vocabularyByteIdentical':True,'environment':{'python':platform.python_version(),'torch':torch.__version__,'transformers':transformers.__version__,'coremltools':ct.__version__,'numpy':np.__version__}}
    write(args.output/'identity.json',report)
    print('Exact weight match:',len(weights),flush=True)
    tokenizer=BertTokenizer.from_pretrained(str(args.snapshot),local_files_only=True)
    config=BertConfig.from_json_file(str(args.snapshot/'config.json'))
    config._attn_implementation='eager'
    model=BertForSequenceClassification(config)
    from safetensors.torch import load_file
    state=load_file(str(args.safetensors));state.pop('bert.embeddings.position_ids',None)
    model.load_state_dict(state,strict=True);model.eval();torch.set_num_threads(4)
    cases=json.loads((Path(__file__).with_name('probes.json')).read_text())['cases'];results=[]
    for item in cases:
        text=item['text']*item.get('repeat',1)
        tokens=tokenizer(text,truncation=True,max_length=128,padding='max_length',return_tensors='pt')
        with torch.inference_mode(): logits=model(**tokens).logits[0].tolist()
        result={'id':item['id'],'group':item['group'],'text':text,'inputIds':tokens['input_ids'][0].tolist(),'attentionMask':tokens['attention_mask'][0].tolist(),'tokenTypeIds':tokens['token_type_ids'][0].tolist(),'sourceLogits':logits,'sourceLabel':labels[int(np.argmax(logits))]}
        results.append(result);print(item['id'],result['sourceLabel'],flush=True)
    write(args.output/'reference.json',{'schemaVersion':1,'purpose':'Diagnostic parity and label hypotheses, not a held-out semantic evaluation','cases':results})
    write(args.output/'request.json',{'cases':results})
if __name__=='__main__':main()
