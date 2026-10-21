#!/usr/bin/env python3
"""Build, install, run, collect or profile the opt-in device lab. Default is build only."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
from source_identity import identity

ROOT=Path(__file__).resolve().parents[2]
BUNDLE='test.QualiaExample.DeviceEvaluation'
DEFAULT_BUILD=Path('/private/tmp/qualiakit-device-evaluation-v2-build')


def command(args, **kwargs):
    return subprocess.run(args,check=True,cwd=ROOT,**kwargs)


def build(directory, simulator=False, russian_assets=None):
    extra=[]
    russian_manifest=None
    if russian_assets:
        russian_assets=russian_assets.resolve()
        russian_manifest=(russian_assets/'asset-manifest.json').read_bytes()
        extra=['QUALIA_RUSSIAN_ASSETS='+str(russian_assets),'ENABLE_USER_SCRIPT_SANDBOXING=NO']
    source=identity()
    resource=ROOT/'Examples/QualiaExample/QualiaExample/DeviceEvaluationAssets.bundle/build-identity.json'
    resource.write_text(json.dumps(source,indent=2,sort_keys=True)+'\n')
    command(['xcodebuild','-project','Examples/QualiaExample/QualiaExample.xcodeproj','-scheme','QualiaExample',
        '-configuration','Release','-destination','generic/platform=iOS Simulator' if simulator else 'generic/platform=iOS',
        '-derivedDataPath',str(directory),'-allowProvisioningUpdates',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS=QUALIA_DEVICE_EVALUATION','SWIFT_DEFAULT_ACTOR_ISOLATION=nonisolated',
        'PRODUCT_BUNDLE_IDENTIFIER='+BUNDLE,'INFOPLIST_KEY_CFBundleDisplayName=Qualia Device Lab',*extra,'build'])
    if identity()!=source:raise ValueError('Source changed during build; rebuild before measuring')
    product=directory/'Build/Products'/('Release-iphonesimulator' if simulator else 'Release-iphoneos')/'QualiaExample.app'
    embedded=json.loads((product/'DeviceEvaluationAssets.bundle/build-identity.json').read_text())
    if embedded!=source:raise ValueError('Embedded source identity mismatch')
    info=plistlib.loads((product/'Info.plist').read_bytes())
    artifact=dict(schemaVersion=2,sourceIdentity=source,bundle=BUNDLE,configuration='Release',simulator=simulator,
        executableSHA256=hashlib.sha256((product/'QualiaExample').read_bytes()).hexdigest(),
        toolchain=subprocess.check_output(['xcodebuild','-version'],text=True).strip(),sdk=info.get('DTSDKBuild'),
        settings={'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'QUALIA_DEVICE_EVALUATION','SWIFT_DEFAULT_ACTOR_ISOLATION':'nonisolated'})
    if russian_manifest:
        installed=product/'DeviceRussianAssets.bundle'
        if (installed/'asset-manifest.json').read_bytes()!=russian_manifest:raise ValueError('Russian manifest changed')
        manifest=json.loads(russian_manifest)
        actual={str(p.relative_to(installed)) for p in installed.rglob('*') if p.is_file() and p.name!='asset-manifest.json'}
        if actual!=set(manifest['files']):raise ValueError('Russian bundle inventory mismatch')
        for name,expected in manifest['files'].items():
            with (installed/name).open('rb') as stream:actual_hash=hashlib.file_digest(stream,'sha256').hexdigest()
            if actual_hash!=expected:raise ValueError('Russian asset mismatch: '+name)
        artifact['russianModel']={'assetManifestSHA256':hashlib.sha256(russian_manifest).hexdigest(),'manifest':manifest}
    (directory/'device-build.json').write_text(json.dumps(artifact,indent=2,sort_keys=True)+'\n')
    return product


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=['build','install','run','collect','profile'],nargs='?',default='build')
    p.add_argument('--device',help='Identifier from xcrun devicectl list devices')
    p.add_argument('--build-dir',type=Path,default=DEFAULT_BUILD)
    p.add_argument('--output',type=Path,help='New output file; existing evidence is never overwritten')
    p.add_argument('--quick',action='store_true')
    p.add_argument('--russian',action='store_true',help='Run actual local RuBERT measurements')
    p.add_argument('--russian-assets',type=Path,help='Private bundle produced by RuSentimentAudit/prepare_device.py')
    p.add_argument('--simulator-build',action='store_true')
    args=p.parse_args()
    if args.action=='build':print(build(args.build_dir,args.simulator_build,args.russian_assets));return
    if not args.device:p.error('--device is required')
    if args.action in ['collect','profile'] and (not args.output or args.output.exists()):p.error('--output must be a new path')
    base=['xcrun','devicectl','--timeout','60','device']
    if args.action=='install':
        command(base+['install','app','--device',args.device,str(args.build_dir/'Build/Products/Release-iphoneos/QualiaExample.app')])
    elif args.action=='run':
        flag=('--device-evaluation-russian-quick' if args.quick else '--device-evaluation-russian') if args.russian else ('--device-evaluation-quick' if args.quick else '--device-evaluation-full')
        command(base+['process','launch','--device',args.device,'--terminate-existing',BUNDLE,flag])
    elif args.action=='collect':
        command(base+['copy','from','--device',args.device,'--source','Documents/device-evaluation.json','--destination',str(args.output),'--domain-type','appDataContainer','--domain-identifier',BUNDLE])
    else:
        # Launch under Instruments as a separate, overhead-affected run. Do not
        # merge these timings with uninstrumented baselines. Trace locally only.
        command(['xcrun','xctrace','record','--template','Power Profiler','--device',args.device,
            '--time-limit','360s','--output',str(args.output),'--launch','--',BUNDLE,'--device-evaluation-full'])


if __name__=='__main__':
    try:main()
    except (ValueError,OSError,subprocess.CalledProcessError) as error:
        print(str(error),file=sys.stderr);sys.exit(1)
