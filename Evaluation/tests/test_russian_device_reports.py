import copy
import hashlib
import json
from pathlib import Path
import sys
import unittest
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'Tools/DeviceEvaluation'))
from summarize_russian import summarize

class RussianDeviceReports(unittest.TestCase):
    def setUp(self):
        self.reference={'cases':[{'id':'one','sourceLabel':'LABEL_0','sourceLogits':[0.0]*5}]}
        self.data=json.dumps(self.reference).encode()
        self.build={'configuration':'Release','simulator':False,'sourceIdentity':{'sourceSHA256':'a'*64},'russianModel':{'assetManifestSHA256':'b'*64,'manifest':{'files':{'reference.json':hashlib.sha256(self.data).hexdigest()}}}}
        parity={'id':'one','group':'synthetic','expectedLabel':'LABEL_0','tokenizerMatches':True,'prediction':{'label':'LABEL_0','logits':[0.0]*5,'probabilities':[.2]*5},'maximumLogitDifference':0.0,'maximumProbabilityDifference':0.0}
        measurements=[{'name':f'ru-{length}-{stage}','milliseconds':[1.0]*30,'p50':1.0,'p95':1.0,'maximum':1.0} for length in [1,8,40] for stage in ['tokenized','prepared','predicted','transformed','total']]
        mode={'initializationMilliseconds':5,'physicalFootprintBytes':1000000,'parity':[parity],'measurements':measurements}
        self.report={'schemaVersion':2,'russianStatus':'completed','metadata':{'physicalDevice':'true','configuration':'Release','sourceSHA256':'a'*64},'errors':[],'russian':{'assetManifestSHA256':'b'*64,'modes':[dict(copy.deepcopy(mode),computeUnits=n) for n in ['cpuOnly','all']]}}
    def result(self):return summarize(self.report,self.build,self.reference,self.data)
    def test_bound_raw_measurements(self):
        self.assertEqual(self.result()['status'],'verified-measurements')
        self.report['russian']['modes'][0]['measurements'][0]['p95']=9
        self.assertIn('Percentile mismatch',self.result()['errors'])
    def test_rejects_model_build_and_source_prediction_tampering(self):
        self.report['russian']['assetManifestSHA256']='c'*64
        self.assertIn('Model/build mismatch',self.result()['errors'])
        self.report['russian']['modes'][0]['parity'][0]['prediction']['probabilities']=[1,0,0,0,0]
        self.assertIn('Softmax mismatch',self.result()['errors'])
    def test_simulator_and_interruption_are_not_success(self):
        self.report['metadata']['physicalDevice']='false';self.report['russianStatus']='interrupted'
        self.assertIn('Not a physical-device run',self.result()['errors'])
        self.assertIn('Russian run did not complete',self.result()['errors'])
