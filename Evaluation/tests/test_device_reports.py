import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'Tools/DeviceEvaluation'))
from summarize import summarize, BENCHMARKS, COREML, CHECKS


class DeviceReportTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.report=Path(self.tmp.name)/'report.json';self.build=Path(self.tmp.name)/'build.json'
        self.build.write_text(json.dumps(dict(sourceIdentity={'sourceSHA256':'a'*64},simulator=False,configuration='Release')))
        def m(name,n):return dict(name=name,milliseconds=[1]*n,p50=1,p95=1,maximum=1)
        benchmark=dict(measurements=[m(k,v) for k,v in BENCHMARKS.items()],physicalFootprintBytes=10,lifetimePeakPhysicalFootprintBytes=20,elapsedSeconds=1,processCPUSeconds=1,firstAppleAnalysisMilliseconds=10)
        self.data=dict(schemaVersion=2,runID='synthetic-tool-test',automaticStatus='completed',metadata=dict(sourceSHA256='a'*64,physicalDevice='true',configuration='Release'),benchmarks=[copy.deepcopy(benchmark) for _ in range(3)],coreML=dict(sourceModelBytes=100,computeUnits='cpuOnly',stages=[m(k,200) for k in COREML],initialLoadIncludingCompilationMilliseconds=10,compilationMilliseconds=[5]),technicalChecks={k:'passed' for k in CHECKS},trials=[],humanAssessment={},commands=[],errors=[])

    def read(self):self.report.write_text(json.dumps(self.data));return summarize(self.report,self.build)

    def test_partial_report_keeps_physical_and_human_gaps(self):
        result=self.read()
        self.assertEqual(result['status'],'incomplete')
        self.assertIn('Sustained run missing',result['blockers'])
        self.assertIn('Unrated tactile variant: baseline',result['blockers'])
        self.assertIn('Renderer command trace missing',result['blockers'])

    def test_missing_trace_cannot_pass_an_otherwise_complete_report(self):
        self.data['sustained']=dict(requestedSeconds=300,elapsedSeconds=300,completedAnalyses=1,
            latency=dict(milliseconds=[1],p50=1,p95=1,maximum=1),
            samples=[dict(elapsedSeconds=300,processCPUSeconds=1,completedAnalyses=1,physicalFootprintBytes=10,thermalState=0)])
        assessment=dict(calm='distinct',acceleration='distinct',accent='distinct',comfort='comfortable')
        self.data['trials']=[dict(profile=p,status='completed',assessment=assessment) for p in ['baseline','medium','strong']]
        self.data['humanAssessment']={'preferred-profile':'medium','background':'passed'}
        self.data['technicalChecks'].update({'actual-scene-deactivation-cleanup':'passed','system-reduce-motion-ambient-suppressed':'passed'})
        self.assertEqual(self.read()['blockers'],['Renderer command trace missing'])
        self.data['commands']=[dict(successful=True,kind='start')]
        self.assertEqual(self.read()['status'],'device-suite-complete')

    def test_raw_distribution_and_build_binding_are_required(self):
        self.data['benchmarks'][0]['measurements'][0]['p95']=2
        with self.assertRaises(ValueError):self.read()
        self.data['benchmarks'][0]['measurements'][0]['p95']=1
        self.data['metadata']['sourceSHA256']='b'*64
        with self.assertRaises(ValueError):self.read()

    def test_interrupted_and_simulator_never_become_physical_success(self):
        self.data['automaticStatus']='interrupted'
        with self.assertRaises(ValueError):self.read()
        self.data['automaticStatus']='completed';self.data['metadata']['physicalDevice']='false'
        self.assertTrue(any('simulator' in b for b in self.read()['blockers']))
