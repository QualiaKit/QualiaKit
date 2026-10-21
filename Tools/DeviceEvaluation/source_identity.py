#!/usr/bin/env python3
"""Fingerprint the sources compiled into the opt-in physical-device harness."""
import hashlib
import json
from pathlib import Path
import sys


def identity():
    root = Path(__file__).resolve().parents[2]
    paths = sorted([
        *root.glob("Sources/QualiaKit/**/*.swift"),
        *root.glob("Packages/QualiaCoreML/Sources/**/*.swift"),
        root / "Packages/QualiaCoreML/Package.swift",
        *[p for p in root.glob("Examples/QualiaExample/QualiaExample/DeviceEvaluationAssets.bundle/*") if p.name != "build-identity.json"],
        *root.glob("Examples/QualiaExample/QualiaExample/**/*.swift"),
        root / "Package.swift",
        root / "Examples/QualiaExample/QualiaExample.xcodeproj/project.pbxproj",
    ])
    digest = hashlib.sha256()
    files = {}
    for path in paths:
        name = path.relative_to(root).as_posix()
        data = path.read_bytes()
        digest.update(name.encode() + b"\0" + data + b"\0")
        files[name] = hashlib.sha256(data).hexdigest()
    return {"sourceSHA256": digest.hexdigest(), "files": files}


if __name__ == "__main__":
    result = identity()
    print(json.dumps(result, indent=2, sort_keys=True) if "--json" in sys.argv else result["sourceSHA256"])
