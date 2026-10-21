#!/usr/bin/env python3
"""Check real app report restoration in a disposable simulator; no physical evidence."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import time
import uuid


def simctl(*args):
    return subprocess.check_output(['xcrun', 'simctl', *args], text=True).strip()


def check(app, runtime):
    bundle = plistlib.loads((app / 'Info.plist').read_bytes())['CFBundleIdentifier']
    device = simctl('create', 'Qualia report restoration',
                    'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro', runtime)
    cases = []
    try:
        simctl('boot', device)
        simctl('bootstatus', device, '-b')
        simctl('install', device, str(app))
        documents = Path(simctl('get_app_container', device, bundle, 'data')) / 'Documents'
        documents.mkdir(exist_ok=True)
        latest = documents / 'device-evaluation.json'
        for automatic, russian in [('running', None), ('completed', None), ('not-started', 'running')]:
            run_id = str(uuid.uuid4()).upper()
            command = dict(kind='start', elapsedMilliseconds=0.25, successful=True,
                           owner='synthetic-restoration-test', activeAmbientCount=1)
            assessment = dict(calm='distinct', acceleration='distinct', accent='distinct', comfort='comfortable')
            fixture = dict(schemaVersion=2, runID=run_id, startedAt='2026-10-21T00:00:00Z',
                automaticStatus=automatic, russianStatus=russian,
                metadata={'physicalDevice': 'false', 'purpose': 'synthetic persistence regression'},
                benchmarks=[], technicalChecks={}, commands=[command],
                trials=[dict(id='rated', profile='medium', intensityScale=0.75, status='completed', assessment=assessment),
                        dict(id='unfinished', profile='strong', intensityScale=1.0, status='running', assessment={})],
                humanAssessment={'preferred-profile': 'medium'}, errors=[])
            latest.write_text(json.dumps(fixture))
            for launch in range(2):
                # Decoder ignores this key; its disappearance proves save() ran.
                before = json.loads(latest.read_text())
                before['restorationTestSentinel'] = True
                latest.write_text(json.dumps(before))
                simctl('launch', device, bundle)
                deadline = time.monotonic() + 30
                while True:
                    saved = json.loads(latest.read_text())
                    if 'restorationTestSentinel' not in saved:
                        break
                    if time.monotonic() >= deadline:
                        raise AssertionError('App did not restore the report within 30 seconds')
                    time.sleep(0.2)
                assert saved['runID'] == run_id
                assert saved['commands'] == [command], 'Saved command trace was erased or replayed'
                assert saved['trials'][0] == fixture['trials'][0], 'Completed ratings changed'
                assert saved['trials'][1]['status'] == 'interrupted'
                assert saved['humanAssessment'] == fixture['humanAssessment']
                assert saved['automaticStatus'] == ('interrupted' if automatic == 'running' else automatic)
                assert saved.get('russianStatus') == ('interrupted' if russian == 'running' else russian)
                expected_errors = ['App process ended before automatic checks completed'] if automatic == 'running' else []
                assert saved['errors'] == expected_errors, 'Restoration added duplicate errors'
                archived = json.loads((documents / 'DeviceEvaluationRuns' / (run_id + '.json')).read_text())
                assert archived == saved, 'Archive and latest snapshot differ'
                simctl('terminate', device, bundle)
            cases.append(dict(automaticStatus=automatic, russianStatus=russian, launches=2, status='passed'))
    finally:
        subprocess.run(['xcrun', 'simctl', 'shutdown', device], capture_output=True)
        simctl('delete', device)
    return dict(status='passed', physicalEvidence=False, cases=cases)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--runtime', default='com.apple.CoreSimulator.SimRuntime.iOS-26-5')
    args = parser.parse_args()
    print(json.dumps(check(args.app.resolve(), args.runtime), sort_keys=True))
