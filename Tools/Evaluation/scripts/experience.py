"""Summarize a paired static/adaptive experience study, separately from semantics."""
import argparse
import json
from pathlib import Path
import statistics
import sys
from evidence import fields, identity, load, number, provenance, require, string


def summarize(path):
    d=load(path)
    fields(d,'schemaVersion identity provenance rights sanitization removalPolicy sessions','experience study')
    require(type(d['schemaVersion']) is int and d['schemaVersion']==1,'unsupported schema')
    identity(d['identity']);provenance(d)
    require(isinstance(d['sessions'],list) and d['sessions'],'paired sessions required')
    participants=set();pairs=[]
    for row in d['sessions']:
        fields(row,'participantID order static adaptive preference','paired session')
        string(row['participantID'],'anonymous participant ID')
        require(row['participantID'] not in participants,'duplicate participant')
        participants.add(row['participantID'])
        require(row['order'] in ['static-first','adaptive-first'],'presentation order required')
        require(row['preference'] in ['static','adaptive','tie'],'preference required')
        for mode in ['static','adaptive']:
            fields(row[mode],'alignment immersion comfort falseReactionComplaints disabled minutes','experience measurements')
            for rating in ['alignment','immersion','comfort']:number(row[mode][rating],rating,minimum=1,maximum=5,integer=True)
            number(row[mode]['falseReactionComplaints'],'complaints',integer=True)
            require(type(row[mode]['disabled']) is bool,'disabled must be boolean')
            number(row[mode]['minutes'],'minutes',minimum=.000001)
        pairs.append(row)
    output=dict(schemaVersion=1,identity=d['identity'],status='measured-unreviewed',participants=len(pairs),
        orderCounts={order:sum(p['order']==order for p in pairs) for order in ['static-first','adaptive-first']},
        preferenceCounts={v:sum(p['preference']==v for p in pairs) for v in ['static','adaptive','tie']},
        pairedMeanAdaptiveMinusStatic={k:statistics.mean(p['adaptive'][k]-p['static'][k] for p in pairs) for k in ['alignment','immersion','comfort']},modes={})
    for mode in ['static','adaptive']:
        output['modes'][mode]={k:statistics.mean(p[mode][k] for p in pairs) for k in ['alignment','immersion','comfort']}
        output['modes'][mode].update(disableRate=sum(p[mode]['disabled'] for p in pairs)/len(pairs),
            falseReactionComplaints=sum(p[mode]['falseReactionComplaints'] for p in pairs),
            complaintsPerHour=60*sum(p[mode]['falseReactionComplaints'] for p in pairs)/sum(p[mode]['minutes'] for p in pairs))
    output['limitations']='Descriptive paired study only. No significance/causality or population claim; reviewer must assess sample size, order balance, recruitment, blinding and protocol. No combined quality score.'
    return output


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('study',type=Path);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    try:
        result=summarize(a.study)
        with a.output.open('x') as f:json.dump(result,f,indent=2,sort_keys=True,allow_nan=False)
        print(json.dumps({'status':result['status'],'participants':result['participants']}))
    except (ValueError,KeyError,TypeError,OSError) as e:print(json.dumps({'status':'blocked','reason':str(e)}));sys.exit(1)
