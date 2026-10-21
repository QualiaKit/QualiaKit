#!/usr/bin/env python3
"""Reject newly uncovered HeartbeatPlanning regions; Swift does not export branches."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'Sources/QualiaKit/Heartbeat/HeartbeatPlanning.swift'


def audit(path):
    data=json.loads(path.read_text())
    matches=[f for d in data['data'] for f in d['files'] if Path(f['filename']).resolve()==SOURCE]
    if len(matches)!=1:raise ValueError('exactly one HeartbeatPlanning coverage record is required')
    record=matches[0]
    lines=SOURCE.read_text().splitlines()
    # Two invariant traps only: validated bounds make both constructors total.
    allowed=set()
    for index,line in enumerate(lines):
        if 'preconditionFailure("Validated heartbeat produced an invalid pattern:' in line:
            allowed.update([index,index+1])  # catch and trap, one-based
        if 'preconditionFailure("Invalid heartbeat mapping:' in line:allowed.add(index+1)
    if len(allowed)!=3:raise ValueError('fatal invariant source changed; review audit exceptions')
    uncovered=[s for s in record['segments'] if s[2]==0 and s[3] and s[4]]
    unexpected=[s for s in uncovered if s[0] not in allowed]
    if unexpected:raise ValueError('uncovered nonfatal regions: '+str(unexpected))
    if record['summary']['regions']['covered']==0:raise ValueError('no covered regions; coverage input may be incomplete')
    return dict(schemaVersion=1,source=str(SOURCE.relative_to(ROOT)),sourceSHA256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        status='passed-reachable-region-audit',summary=record['summary'],uncoveredFatalRegions=uncovered,
        exceptions=['Pattern construction: validated finite BPM 55...120, valid HapticValue, positive remaining deadline, valid ratio 0.18...0.35.',
                    'Parameter construction: validated BPM endpoints, tension in 0...1, finite scale in 0...1; smoothstep stays bounded.'],
        limitations='Swift LLVM export reports zero branch counters; this is a source-region audit plus explicit transition/guard tests, not a numeric 100% branch-coverage claim.')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('coverage',type=Path);p.add_argument('--output',type=Path)
    args=p.parse_args()
    result=audit(args.coverage)
    rendered=json.dumps(result,indent=2,sort_keys=True)+'\n'
    if args.output:args.output.write_text(rendered)
    print(rendered)


if __name__=='__main__':
    try:main()
    except (ValueError,KeyError,OSError) as error:print(str(error),file=sys.stderr);sys.exit(1)
