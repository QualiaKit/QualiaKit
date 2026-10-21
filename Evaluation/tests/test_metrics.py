import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from metrics import binary, fleiss_kappa, select_threshold
import study


class MetricTests(unittest.TestCase):
    def test_independent_confusion_pr_area_and_calibration_oracle(self):
        m=binary([1,0,1,0],[.9,.8,.7,.1],.75)
        self.assertEqual((m['truePositives'],m['falsePositives'],m['falseNegatives']),(1,1,1))
        self.assertEqual((m['precision'],m['recall'],m['f1']),(.5,.5,.5))
        self.assertAlmostEqual(m['prAUC'],5/6)
        self.assertAlmostEqual(m['calibrationError'],.325)

    def test_tied_scores_are_grouped_and_order_independent(self):
        self.assertEqual(binary([1,0],[.5,.5],.5)['prAUC'],.5)
        self.assertEqual(binary([0,1],[.5,.5],.5)['prAUC'],.5)
        self.assertEqual(binary([0,0],[.2,.9],1)['f1'],0)
        self.assertEqual(binary([1,1],[1,1],1)['calibrationError'],0)

    def test_agreement_and_threshold_costs(self):
        self.assertEqual(fleiss_kappa([[1,1],[0,0]]),1)
        self.assertEqual(fleiss_kappa([[1,0],[0,1]]),-1)
        with self.assertRaises(ValueError):fleiss_kappa([[1,1],[1,1]])
        threshold,_=select_threshold([1,0,1,0],[.9,.8,.7,.1],[.5,.75,.85],3,1)
        self.assertEqual(threshold,.85)
        with self.assertRaises(ValueError):binary([1],[float('nan')],.5)
        with self.assertRaises(ValueError):binary([True],[.8],.5)


class StudyTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        self.identity=dict(model='synthetic-tool-test',policy='1',runtime='1',build='test')
        self.v=self.make_dataset('validation')
        self.t=self.make_dataset('test')
        self.vp=self.make_predictions(self.v)
        self.tp=self.make_predictions(self.t)
        self.plan=self.save('plan.json',dict(schemaVersion=1,identity=self.identity,thresholdCandidates=[.5,.8],
            costs={'suspense':dict(falsePositive=2,falseNegative=1)},minimumAgreement=.7,minimumF1=.7,
            maximumHardNegativeRate=.1,minimumContextF1Delta=0,maximumWarmP95Milliseconds=50))
        self.out=self.root/'study'

    def save(self,name,data):
        p=self.root/name;p.write_text(json.dumps(data));return p

    def make_dataset(self,split):
        cases=[]
        for index,label in enumerate([0,1,0,1]):
            cases.append(dict(id=f'{split}-{index}',groupID=f'{split}-group-{index}',text=f'Synthetic {split} text {index}',context=['Synthetic prior fragment.'],language='en',lengthBucket='short',labels={'suspense':label},annotations={'a':{'suspense':label},'b':{'suspense':label}},hardNegative=not bool(label),productionLike=True))
        return self.save(split+'.json',dict(schemaVersion=1,version='synthetic-test-only',split=split,provenance='Tool test only, not study evidence',rights='MIT synthetic',sanitization='synthetic',removalPolicy='Delete with test',annotators=['a','b'],signals=['suspense'],languages=['en'],lengthBuckets=['short'],cases=cases))

    def make_predictions(self,path):
        data=json.loads(path.read_text())
        return self.save(data['split']+'-predictions.json',dict(schemaVersion=1,identity=self.identity,datasetSHA256=study.digest(path),rows=[dict(id=c['id'],withoutContext={'suspense':.5},withContext={'suspense':.9 if c['labels']['suspense'] else .1}) for c in data['cases']]))

    def freeze(self):return study.freeze(self.v,self.vp,self.t,self.plan,self.out)

    def test_full_pipeline_is_unreviewed_and_heldout_cannot_be_repeated(self):
        self.freeze()
        result=study.evaluate(self.out,self.t,self.tp)
        self.assertTrue(all(result['numericLimitsMet'].values()))
        report=json.loads((self.out/'heldOutMetrics.json').read_text())
        self.assertEqual(report['status'],'unreviewed')
        self.assertEqual(report['data']['slices'][0]['f1'],1)
        self.assertEqual(report['reviewer'],'')
        with self.assertRaises(FileExistsError):study.evaluate(self.out,self.t,self.tp)
        with self.assertRaises(FileExistsError):self.freeze()

    def test_split_leakage_and_wrong_split_fail(self):
        with self.assertRaises(ValueError):study.freeze(self.t,self.tp,self.v,self.plan,self.out)
        d=json.loads(self.t.read_text());d['cases'][0]['groupID']='validation-group-0';self.t.write_text(json.dumps(d))
        with self.assertRaises(ValueError):self.freeze()

    def test_prediction_mismatch_cannot_be_silently_dropped(self):
        p=json.loads(self.vp.read_text());p['rows'].pop();self.vp.write_text(json.dumps(p))
        with self.assertRaises(ValueError):self.freeze()

    def test_drift_missing_context_and_hard_negatives_fail(self):
        self.freeze()
        d=json.loads(self.t.read_text());d['cases'][0]['text']='changed';self.t.write_text(json.dumps(d))
        with self.assertRaises(ValueError):study.evaluate(self.out,self.t,self.tp)
        self.assertFalse((self.out/'evaluation.lock').exists())

    def test_no_class_coverage_and_negative_cost_fail(self):
        p=json.loads(self.plan.read_text());p['costs']['suspense']['falsePositive']=-1;self.plan.write_text(json.dumps(p))
        with self.assertRaises(ValueError):self.freeze()


if __name__=='__main__':unittest.main()
