#!/usr/bin/env python3
"""Validate raw v2 measurements and report device-suite gaps without inventing passes."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'Evaluation/scripts'))
from evidence import load, number, require, sha

CHECKS={'hardware-support','start','replace-and-independent-impact','reset-stops-ambient',
        'disable-stops-ambient','disabled-produces-no-playback','programmatic-suspend-stops-ambient',
        'resume-does-not-replay','continuous-disabled-accent-still-works','physical-deadline-without-new-input','zero-intensity-no-playback'}
BENCHMARKS={'apple-analysis-49-utf8-bytes':200,'apple-analysis-488-utf8-bytes':200,
            'apple-analysis-1952-utf8-bytes':200,'scene-and-narrative-policy-no-renderer':1000,'bounded-context-window':1000}
COREML={'fixture-coreml-analyze-total','fixture-coreml-tokenized','fixture-coreml-prepared','fixture-coreml-predicted','fixture-coreml-transformed'}


def measurement(value, count=None):
    samples=value['milliseconds']
    require(isinstance(samples,list) and samples,'raw timing samples required')
    if count is not None:require(len(samples)==count,'wrong sample count')
    for x in samples:number(x,'sample')
    ordered=sorted(samples)
    for key,fraction in [('p50',.5),('p95',.95)]:
        require(value[key]==ordered[math.ceil(fraction*len(ordered))-1],'percentile does not match raw samples')
    require(value['maximum']==ordered[-1],'maximum does not match raw samples')
    return {'samples':len(samples),'p50':value['p50'],'p95':value['p95'],'maximum':value['maximum']}


def summarize(report_path, build_path):
    d=load(report_path);build=load(build_path)
    require(type(d['schemaVersion']) is int and d['schemaVersion']==2,'v2 device report required')
    source=d['metadata']['sourceSHA256'];sha(source,'sourceSHA256')
    require(source==build['sourceIdentity']['sourceSHA256'],'report/build source mismatch')
    require(d['automaticStatus']=='completed','automatic run incomplete')
    require(len(d['benchmarks'])==3,'three baseline repeats required')
    simulator = d['metadata'].get('physicalDevice') != 'true'
    expected = {k:v for k,v in BENCHMARKS.items() if not (simulator and d['metadata'].get('appleAnalysis','').startswith('not-run') and k.startswith('apple-'))}
    aggregate={name:[] for name in expected}
    for run in d['benchmarks']:
        require(len(run['measurements'])==len(expected),'benchmark groups missing or duplicated')
        require({m['name'] for m in run['measurements']}==set(expected),'unexpected benchmark groups')
        for m in run['measurements']:aggregate[m['name']].append(measurement(m,expected[m['name']]))
        for key in ['physicalFootprintBytes','lifetimePeakPhysicalFootprintBytes']:number(run[key],key,minimum=1,integer=True)
        for key in ['elapsedSeconds','processCPUSeconds']:number(run[key],key)
        if not simulator:number(run['firstAppleAnalysisMilliseconds'],'first Apple call')
    core=d['coreML'];require(core['sourceModelBytes']>0 and core['computeUnits']=='cpuOnly','public Core ML identity/size required')
    require(len(core['stages'])==5 and {m['name'] for m in core['stages']}==COREML,'Core ML stage samples required')
    for m in core['stages']:measurement(m,200)
    for value in [core['initialLoadIncludingCompilationMilliseconds'],*core['compilationMilliseconds']]:number(value,'load timing')
    blockers=[]
    physical=d['metadata'].get('physicalDevice')=='true' and not build.get('simulator',True)
    if not physical:blockers.append('Physical device required; simulator is software verification only')
    if d['metadata'].get('configuration')!='Release' or build['configuration']!='Release':blockers.append('Release build required')
    for key in sorted(CHECKS):
        if d['technicalChecks'].get(key)!='passed':blockers.append('Technical check incomplete: '+key)
    sustained=d.get('sustained')
    if sustained:
        measurement(sustained['latency'],sustained['completedAnalyses'])
        require(sustained['samples'] and sustained['elapsedSeconds']>=sustained['requestedSeconds'],'sustained run incomplete')
        elapsed=-1;cpu=-1;count=-1
        for sample in sustained['samples']:
            require(sample['elapsedSeconds']>=elapsed and sample['processCPUSeconds']>=cpu and sample['completedAnalyses']>=count,'nonmonotonic sustained sample')
            number(sample['physicalFootprintBytes'],'memory',minimum=1,integer=True)
            number(sample['thermalState'],'thermal',minimum=0,maximum=3,integer=True)
            elapsed=sample['elapsedSeconds'];cpu=sample['processCPUSeconds'];count=sample['completedAnalyses']
        if sustained['requestedSeconds']<300:blockers.append('Five-minute sustained run required')
    else:blockers.append('Sustained run missing')
    for profile in ['baseline','medium','strong']:
        if not any(t['profile']==profile and t['status']=='completed' and set(t['assessment'])=={'calm','acceleration','accent','comfort'} for t in d['trials']):
            blockers.append('Unrated tactile variant: '+profile)
    preferred=d['humanAssessment'].get('preferred-profile')
    matching=[t for t in d['trials'] if t['profile']==preferred and t['status']=='completed' and t['assessment']]
    if not matching or matching[-1]['assessment']!={'calm':'distinct','acceleration':'distinct','accent':'distinct','comfort':'comfortable'}:
        blockers.append('Preferred variant must be distinguishable and comfortable')
    if d['technicalChecks'].get('actual-scene-deactivation-cleanup')!='passed' or d['humanAssessment'].get('background')!='passed':blockers.append('Actual background cleanup and human confirmation required')
    if d['technicalChecks'].get('system-reduce-motion-ambient-suppressed')!='passed':blockers.append('System Reduce Motion test required')
    if not d['commands']:blockers.append('Renderer command trace missing')
    if any(not c['successful'] for c in d['commands']):blockers.append('Renderer command failure recorded')
    return dict(schemaVersion=2,runID=d['runID'],sourceSHA256=source,
        reportSHA256=hashlib.sha256(report_path.read_bytes()).hexdigest(),status='incomplete' if blockers else 'device-suite-complete',
        baselines=aggregate,blockers=blockers,limitations=['No narrative semantic qualification','Public arithmetic Core ML fixture only','CPU/thermal workload is not watt/joule evidence','One holder/device; no population experience claim'],recordedErrors=d['errors'])


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('report',type=Path);p.add_argument('--build',type=Path,required=True);p.add_argument('--output',type=Path);p.add_argument('--require-complete',action='store_true');args=p.parse_args()
    try:
        result=summarize(args.report,args.build)
        if args.output:
            with args.output.open('x') as f:json.dump(result,f,indent=2,sort_keys=True,allow_nan=False)
        print(json.dumps(result,sort_keys=True))
        sys.exit(1 if args.require_complete and result['blockers'] else 0)
    except (ValueError,TypeError,KeyError,OSError) as error:print(json.dumps({'status':'blocked','reason':str(error)}));sys.exit(1)
