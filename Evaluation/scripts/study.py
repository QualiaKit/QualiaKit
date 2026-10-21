"""Freeze validation-selected thresholds and compute one held-out evaluation.

Inputs must come from an actual independently annotated study. Generated reports
start as unreviewed, including when numeric limits pass. This tool neither trains
nor runs a model and cannot authenticate study chronology or human independence.
"""
import argparse
import datetime
import hashlib
import itertools
import json
from pathlib import Path
import sys

from evidence import EvidenceError, fields, identity, load, number, protocol, provenance, require, string, strings
from metrics import binary, fleiss_kappa, select_threshold


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    with path.open('x', encoding='utf-8') as output:
        json.dump(value, output, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)
        output.write('\n')


def dataset(path, split):
    data = load(path)
    fields(data, 'schemaVersion version split provenance rights sanitization removalPolicy annotators signals languages lengthBuckets cases', 'dataset')
    require(type(data['schemaVersion']) is int and data['schemaVersion'] == 1, 'unsupported dataset schema')
    require(data['split'] == split, f'expected {split} dataset')
    string(data['version'], 'dataset.version')
    provenance(data)
    for key in ['annotators', 'signals', 'languages', 'lengthBuckets']:
        strings(data[key], key)
    require(len(data['annotators']) >= 2, 'independent annotators required')
    require(isinstance(data['cases'], list) and data['cases'], 'cases required')
    ids = set()
    for case in data['cases']:
        fields(case, 'id groupID text context language lengthBucket labels annotations hardNegative productionLike', 'case')
        for key in ['id','groupID','text']: string(case[key], key)
        require(case['id'] not in ids, 'duplicate case ID')
        ids.add(case['id'])
        require(isinstance(case['context'], list) and all(isinstance(v,str) and v.strip() for v in case['context']), 'context must contain nonempty fragments')
        require(case['language'] in data['languages'] and case['lengthBucket'] in data['lengthBuckets'], 'unexpected slice')
        require(type(case['hardNegative']) is bool and type(case['productionLike']) is bool, 'case flags must be booleans')
        fields(case['annotations'], ' '.join(data['annotators']), 'annotations')
        for labels in [case['labels'], *case['annotations'].values()]:
            fields(labels, ' '.join(data['signals']), 'labels')
            require(all(type(v) is int and v in (0,1) for v in labels.values()), 'adjudicated binary labels required')
        require(not case['hardNegative'] or not any(case['labels'].values()), 'hard negatives must be negative for every evaluated signal')
    return data


def predictions(path, data, dataset_hash, candidate):
    value = load(path)
    fields(value, 'schemaVersion identity datasetSHA256 rows', 'predictions')
    require(type(value['schemaVersion']) is int and value['schemaVersion'] == 1, 'unsupported prediction schema')
    require(value['identity'] == candidate and value['datasetSHA256'] == dataset_hash, 'prediction identity/dataset mismatch')
    require(isinstance(value['rows'], list), 'prediction rows required')
    result = {}
    for row in value['rows']:
        fields(row, 'id withoutContext withContext', 'prediction')
        string(row['id'], 'prediction.id')
        require(row['id'] not in result, 'duplicate prediction')
        for mode in ['withoutContext', 'withContext']:
            fields(row[mode], ' '.join(data['signals']), 'scores')
            for score in row[mode].values(): number(score, 'score', maximum=1)
        result[row['id']] = row
    require(set(result) == {c['id'] for c in data['cases']}, 'missing or extra predictions')
    return result


def validate_splits(validation, heldout):
    for key in ['signals','languages','lengthBuckets']:
        require(validation[key] == heldout[key], f'split {key} mismatch')
    for key in ['id','groupID']:
        require(not ({c[key] for c in validation['cases']} & {c[key] for c in heldout['cases']}), f'{key} leakage across splits')
    # Reject identical current text even when the producer changed the case/group ID.
    require(not ({c['text'].strip() for c in validation['cases']} & {c['text'].strip() for c in heldout['cases']}), 'text leakage across splits')
    for data in [validation, heldout]:
        for signal, language, length in itertools.product(data['signals'],data['languages'],data['lengthBuckets']):
            cases = [c for c in data['cases'] if c['language']==language and c['lengthBucket']==length]
            require({c['labels'][signal] for c in cases} == {0,1}, f'each slice needs positive and negative examples: {signal}/{language}/{length}')


def freeze(validation_path, predictions_path, heldout_path, plan_path, out):
    validation, heldout = dataset(validation_path,'validation'), dataset(heldout_path,'test')
    validate_splits(validation,heldout)
    plan = load(plan_path)
    limits = ['minimumAgreement','minimumF1','maximumHardNegativeRate','minimumContextF1Delta','maximumWarmP95Milliseconds']
    fields(plan, 'schemaVersion identity thresholdCandidates costs ' + ' '.join(limits), 'selection plan')
    require(type(plan['schemaVersion']) is int and plan['schemaVersion']==1, 'unsupported selection plan')
    identity(plan['identity'])
    fields(plan['costs'], ' '.join(validation['signals']), 'costs')
    require(isinstance(plan['thresholdCandidates'], list) and plan['thresholdCandidates'], 'threshold grid required')
    for value in plan['thresholdCandidates']: number(value,'threshold',maximum=1)
    scores = predictions(predictions_path, validation, digest(validation_path), plan['identity'])
    thresholds, selection = {}, {}
    for signal in validation['signals']:
        costs = plan['costs'][signal]
        fields(costs,'falsePositive falseNegative','signal costs')
        for v in costs.values():number(v,'cost')
        thresholds[signal], selection[signal] = select_threshold(
            [c['labels'][signal] for c in validation['cases']],
            [scores[c['id']]['withContext'][signal] for c in validation['cases']],
            plan['thresholdCandidates'], costs['falsePositive'], costs['falseNegative'])
    frozen = dict(schemaVersion=1,identity=plan['identity'],status='frozen',selectedOn='validation',frozenBeforeEvaluation=True,
                  validationDatasetSHA256=digest(validation_path),heldOutDatasetSHA256=digest(heldout_path),
                  thresholds=thresholds,**{k:validation[k] for k in ['signals','languages','lengthBuckets']},**{k:plan[k] for k in limits})
    protocol(frozen, plan['identity'])
    out.mkdir(parents=True,exist_ok=False)
    write(out/'protocol.json', frozen)
    write(out/'selection.json',dict(selectedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        planSHA256=digest(plan_path),predictionsSHA256=digest(predictions_path),protocolSHA256=digest(out/'protocol.json'),
        method='validation weighted FP/FN; ties: fewer FP then higher threshold; with-context scores', candidates=selection))
    return {'status':'frozen','thresholds':thresholds,'output':str(out)}


def evaluate(study, heldout_path, predictions_path):
    frozen = protocol(load(study/'protocol.json'), load(study/'protocol.json')['identity'])
    selection = load(study/'selection.json')
    require(selection['protocolSHA256']==digest(study/'protocol.json'),'protocol changed after selection')
    require(digest(heldout_path)==frozen['heldOutDatasetSHA256'],'held-out checksum mismatch')
    data = dataset(heldout_path,'test')
    for key in ['signals','languages','lengthBuckets']:require(data[key]==frozen[key],f'{key} mismatch')
    scores = predictions(predictions_path,data,digest(heldout_path),frozen['identity'])
    negative = [c for c in data['cases'] if c['hardNegative']]
    require(negative and any(c['productionLike'] for c in negative),'production-like hard negatives required')
    require(any(c['context'] for c in data['cases']),'context comparison requires actual context')
    # Create before computing any results. Failed/aborted attempts remain reserved.
    write(study/'evaluation.lock',dict(startedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        protocolSHA256=digest(study/'protocol.json'),predictionsSHA256=digest(predictions_path)))
    thresholds = frozen['thresholds']
    slices=[]
    for signal, language, length in itertools.product(data['signals'],data['languages'],data['lengthBuckets']):
        cases=[c for c in data['cases'] if c['language']==language and c['lengthBucket']==length]
        labels=[c['labels'][signal] for c in cases]
        require(set(labels)=={0,1},'metric slice needs both classes')
        measured=binary(labels,[scores[c['id']]['withContext'][signal] for c in cases],thresholds[signal])
        slices.append(dict(signal=signal,language=language,lengthBucket=length,
            **{k:measured[k] for k in ['cases','precision','recall','f1','prAUC','calibrationError']}))
    ratings=[[c['annotations'][a][signal] for a in data['annotators']] for c in data['cases'] for signal in data['signals']]
    agreement=fleiss_kappa(ratings)
    false_reactions=sum(any(scores[c['id']]['withContext'][s]>=thresholds[s] for s in data['signals']) for c in negative)
    context={}
    for mode in ['withoutContext','withContext']:
        tp=fp=fn=0
        for signal in data['signals']:
            m=binary([c['labels'][signal] for c in data['cases']], [scores[c['id']][mode][signal] for c in data['cases']],thresholds[signal])
            tp+=m['truePositives'];fp+=m['falsePositives'];fn+=m['falseNegatives']
        context[mode+'F1']=2*tp/(2*tp+fp+fn) if 2*tp+fp+fn else 0
    measured={
        'annotationAgreement':dict(method='Fleiss kappa over case × signal; fixed independent annotators',agreement=agreement,annotators=len(data['annotators']),cases=len(data['cases'])),
        'heldOutMetrics':dict(datasetSHA256=digest(heldout_path),thresholdDatasetSHA256=frozen['validationDatasetSHA256'],evaluations=1,slices=slices),
        'hardNegatives':dict(cases=len(negative),falseReactions=false_reactions,productionLikeCases=sum(c['productionLike'] for c in negative),**{k:data[k] for k in ['provenance','rights','sanitization','removalPolicy']}),
        'contextComparison':dict(datasetSHA256=digest(heldout_path),cases=len(data['cases']),**context),
    }
    meets={'annotationAgreement':agreement>=frozen['minimumAgreement'],
        'heldOutMetrics':all(s['f1']>=frozen['minimumF1'] for s in slices),
        'hardNegatives':false_reactions/len(negative)<=frozen['maximumHardNegativeRate'],
        'contextComparison':context['withContextF1']-context['withoutContextF1']>=frozen['minimumContextF1Delta']}
    for kind, values in measured.items():
        write(study/(kind+'.json'),dict(schemaVersion=1,kind=kind,identity=frozen['identity'],protocolSHA256=digest(study/'protocol.json'),reviewer='',status='unreviewed',data=values))
    write(study/'measurement.json',dict(numericLimitsMet=meets,admission='blocked pending human review and candidate-specific devicePerformance',
        methods={'prAUC':'non-interpolated average precision; ties grouped','calibrationError':'10 equal-width probability bins, weighted absolute observed frequency minus mean probability','context':'micro F1, same frozen thresholds, matched cases'},
        syntheticAllowedForToolTestsOnly=True))
    return dict(status='measured-unreviewed',numericLimitsMet=meets)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    commands=parser.add_subparsers(dest='command',required=True)
    f=commands.add_parser('freeze')
    for key in ['validation','predictions','test','plan','out']: f.add_argument('--'+key,type=Path,required=True)
    e=commands.add_parser('evaluate')
    for key in ['study','test','predictions']:e.add_argument('--'+key,type=Path,required=True)
    args=parser.parse_args()
    try:
        result=freeze(args.validation,args.predictions,args.test,args.plan,args.out) if args.command=='freeze' else evaluate(args.study,args.test,args.predictions)
        print(json.dumps(result,sort_keys=True))
        return 0
    except (EvidenceError,ValueError,KeyError,TypeError,OSError) as error:
        print(json.dumps({'status':'blocked','reason':str(error)},sort_keys=True))
        return 1


if __name__=='__main__':sys.exit(main())
