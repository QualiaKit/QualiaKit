#!/usr/bin/env python3
"""Stage private local model assets for an explicitly opted-in device-lab build."""
import argparse, hashlib, json, shutil, subprocess
from pathlib import Path

def sha(path):
    with open(path,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--audit',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();root=Path(__file__).resolve().parents[2]
    identity=json.loads((args.audit/'identity.json').read_text())
    assert identity['exactlyMatchedParameterTensors']==201
    model=root/'RuBSentimentModel.mlpackage'
    assert {str(f.relative_to(model)):sha(f) for f in model.rglob('*') if f.is_file()}==identity['coreMLComponents']
    vocab=root/'LocalArtifacts/current/vocab.txt';assert sha(vocab)==identity['sourceFiles']['vocab.txt']
    args.output.mkdir(parents=True,exist_ok=False)
    subprocess.run(['xcrun','coremlcompiler','compile',str(model),str(args.output)],check=True)
    shutil.copyfile(vocab,args.output/'vocab.txt')
    shutil.copyfile(args.audit/'reference.json',args.output/'reference.json')
    manifest={'schemaVersion':1,'source':identity['source'],'sourceRevision':identity['sourceRevision'],
        'sourceComponents':identity['coreMLComponents'],'sourceIdentitySHA256':sha(args.audit/'identity.json'),
        'compiledBy':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),
        'mappingStatus':'empirical hypothesis; not author-confirmed; no narrative signals',
        'files':{str(f.relative_to(args.output)):sha(f) for f in sorted(args.output.rglob('*')) if f.is_file()}}
    (args.output/'asset-manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
    print(args.output)
if __name__=='__main__':main()
