#!/usr/bin/env python3
"""Verify a real RuBERT device report against its build and frozen source predictions."""
import argparse, hashlib, json, math
from pathlib import Path


def summarize(report, build, reference, reference_bytes):
    errors=[]
    def check(value,message):
        if not value:errors.append(message)
    check(report.get('russianStatus')=='completed','Russian run did not complete')
    check(report.get('metadata',{}).get('physicalDevice')=='true','Not a physical-device run')
    check(report.get('metadata',{}).get('configuration')=='Release','Not Release')
    check(report.get('metadata',{}).get('sourceSHA256')==build.get('sourceIdentity',{}).get('sourceSHA256'),'Source/build mismatch')
    check(report.get('schemaVersion')==2,'Unsupported device report schema')
    check(build.get('configuration')=='Release' and build.get('simulator') is False,'Build is not physical Release')
    source_hash=report.get('metadata',{}).get('sourceSHA256','')
    check(len(source_hash)==64 and all(c in '0123456789abcdef' for c in source_hash),'Invalid source identity')
    result=report.get('russian') or {}; artifact=build.get('russianModel') or {}
    check(bool(artifact) and result.get('assetManifestSHA256')==artifact.get('assetManifestSHA256'),'Model/build mismatch')
    expected_hash=artifact.get('manifest',{}).get('files',{}).get('reference.json')
    check(hashlib.sha256(reference_bytes).hexdigest()==expected_hash,'Reference/build mismatch')
    check(not report.get('errors'),'Runtime errors recorded')
    expected={c['id']:c for c in reference['cases']}
    summaries=[];modes=result.get('modes',[])
    check([m.get('computeUnits') for m in modes]==['cpuOnly','all'],'Expected separate CPU and all-compute modes')
    for mode in modes:
        check(math.isfinite(mode['initializationMilliseconds']) and mode['initializationMilliseconds']>=0,'Invalid model load time')
        check(math.isfinite(mode['physicalFootprintBytes']) and mode['physicalFootprintBytes']>0,'Invalid memory footprint')
        parity=mode.get('parity',[])
        check(len(parity)==len(expected) and {c['id'] for c in parity}==set(expected),'Parity case inventory mismatch')
        deltas=[];pdeltas=[];agreements=0
        for c in parity:
            check(c.get('tokenizerMatches') is True,'Tokenizer mismatch: '+c['id'])
            target=expected.get(c['id'])
            if target is None:continue
            prediction=c['prediction']; logits=prediction['logits']; probabilities=prediction['probabilities']
            check(len(logits)==5 and all(math.isfinite(x) for x in logits),'Invalid logits')
            check(len(probabilities)==5 and all(math.isfinite(x) and 0<=x<=1 for x in probabilities) and abs(sum(probabilities)-1)<1e-6,'Invalid probabilities')
            if len(logits)!=5 or len(probabilities)!=5:continue
            def softmax(values):
                exp=[math.exp(x-max(values)) for x in values];return [x/sum(exp) for x in exp]
            source_p=softmax(target['sourceLogits'])
            check(all(abs(a-b)<1e-9 for a,b in zip(probabilities,softmax(logits))),'Softmax mismatch')
            check(prediction['label']=='LABEL_'+str(logits.index(max(logits))),'Class/score mismatch')
            check(c['expectedLabel']==target['sourceLabel'],'Reference label mismatch')
            delta=max(abs(a-b) for a,b in zip(logits,target['sourceLogits']))
            pdelta=max(abs(a-b) for a,b in zip(probabilities,source_p))
            check(abs(delta-c['maximumLogitDifference'])<1e-9 and abs(pdelta-c['maximumProbabilityDifference'])<1e-9,'Delta not reproducible')
            deltas.append(delta);pdeltas.append(pdelta);agreements+=prediction['label']==target['sourceLabel']
        timing={}
        expected_measurements={f'ru-{length}-{stage}' for length in [1,8,40] for stage in ['tokenized','prepared','predicted','transformed','total']}
        check({m['name'] for m in mode['measurements']}==expected_measurements and len(mode['measurements'])==15,'Timing group inventory mismatch')
        for m in mode['measurements']:
            values=m.get('milliseconds',[])
            check(len(values)==30 and all(math.isfinite(x) and x>=0 for x in values),'Invalid timing samples')
            if values:
                ordered=sorted(values)
                for key,q in [('p50',.5),('p95',.95)]:check(abs(m[key]-ordered[math.ceil(q*len(values))-1])<1e-9,'Percentile mismatch')
                check(abs(m['maximum']-max(values))<1e-9,'Maximum mismatch')
                if m['name'].endswith('-total'):timing[m['name']]={'p50':m['p50'],'p95':m['p95'],'maximum':max(values)}
        summaries.append({'computeUnits':mode['computeUnits'],'cases':len(parity),'sameArgmax':agreements,
            'maximumLogitDifference':max(deltas,default=None),'maximumProbabilityDifference':max(pdeltas,default=None),
            'initializationMilliseconds':mode['initializationMilliseconds'],'latencyMilliseconds':timing,
            'physicalFootprintMiB':mode['physicalFootprintBytes']/1024**2})
    load=result.get('sustained');load_summary=None
    if load:
        check(load['elapsedSeconds']>=load['requestedSeconds']>=300,'Load shorter than five minutes')
        check(load['completedAnalyses']==len(load['latency'].get('milliseconds',[])),'Load count mismatch')
        raw=load['latency']['milliseconds']
        check(bool(raw) and all(math.isfinite(x) and x>=0 for x in raw),'Invalid load latency')
        if raw:
            ordered=sorted(raw)
            for key,q in [('p50',.5),('p95',.95)]:check(abs(load['latency'][key]-ordered[math.ceil(q*len(raw))-1])<1e-9,'Load percentile mismatch')
            check(abs(load['latency']['maximum']-max(raw))<1e-9,'Load maximum mismatch')
        samples=load['samples'];check(bool(samples),'No load samples')
        for sample in samples:
            check(all(math.isfinite(sample[k]) and sample[k]>=0 for k in ['elapsedSeconds','processCPUSeconds','physicalFootprintBytes','completedAnalyses']),'Invalid load telemetry')
            check(sample['thermalState'] in [0,1,2,3],'Invalid thermal state')
        if samples:
            check(all(b['elapsedSeconds']>a['elapsedSeconds'] and b['completedAnalyses']>=a['completedAnalyses'] and b['processCPUSeconds']>=a['processCPUSeconds'] for a,b in zip(samples,samples[1:])),'Nonmonotonic load measurements')
            check(samples[-1]['completedAnalyses']==load['completedAnalyses'],'Final load count mismatch')
            load_summary={'seconds':load['elapsedSeconds'],'analyses':load['completedAnalyses'],'p95Milliseconds':load['latency']['p95'],
                'peakSampledFootprintMiB':max(s['physicalFootprintBytes'] for s in samples)/1024**2,
                'thermalStates':sorted({s['thermalState'] for s in samples}),'processCPUSeconds':samples[-1]['processCPUSeconds']}
    return {'schemaVersion':1,'status':'verified-measurements' if not errors else 'invalid','errors':errors,
        'runID':report.get('runID'),'modes':summaries,'sustained':load_summary,
        'limits':['Raw differences and argmax agreement are diagnostic results, not a calibrated universal tolerance.',
                  'Labels are empirical hypotheses, not author-confirmed.', 'These probes are not independent semantic accuracy data.',
                  'Core ML all selects its own backend; no claim that ANE alone executed the model.',
                  'Process CPU/memory/thermal are not isolated model energy or watts.']}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('report',type=Path);p.add_argument('--build',type=Path,required=True);p.add_argument('--reference',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();data=args.reference.read_bytes()
    result=summarize(json.loads(args.report.read_text()),json.loads(args.build.read_text()),json.loads(data),data)
    with args.output.open('x') as f:json.dump(result,f,ensure_ascii=False,indent=2);f.write('\n')
    print(json.dumps(result,ensure_ascii=False,indent=2))
    if result['errors']:raise SystemExit(1)
if __name__=='__main__':main()
