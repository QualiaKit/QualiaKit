import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from experience import summarize


class ExperienceTests(unittest.TestCase):
    def test_paired_summary_and_order_counts_do_not_merge_quality_levels(self):
        mode=dict(alignment=3,immersion=3,comfort=4,falseReactionComplaints=2,disabled=False,minutes=20)
        study=dict(schemaVersion=1,identity=dict(model='test',policy='1',runtime='1',build='test'),provenance='Synthetic unit test',rights='MIT',sanitization='synthetic',removalPolicy='Delete with test',sessions=[dict(participantID='anonymous-01',order='static-first',static=mode,adaptive=dict(mode,alignment=4,falseReactionComplaints=1),preference='adaptive')])
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'study.json';path.write_text(json.dumps(study))
            result=summarize(path)
            self.assertEqual(result['pairedMeanAdaptiveMinusStatic']['alignment'],1)
            self.assertEqual(result['modes']['adaptive']['complaintsPerHour'],3)
            self.assertEqual(result['status'],'measured-unreviewed')
            self.assertNotIn('qualityScore',result)
            study['sessions'].append(study['sessions'][0]);path.write_text(json.dumps(study))
            with self.assertRaises(ValueError):summarize(path)

    def test_missing_pair_and_invalid_scale_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'study.json';path.write_text('{}')
            with self.assertRaises(ValueError):summarize(path)
