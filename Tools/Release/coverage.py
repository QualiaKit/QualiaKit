#!/usr/bin/env python3
"""Fail if coverage was not actually exported; preserve the complete LLVM report."""
import json
from pathlib import Path
import shutil
import sys

source, destination = map(Path, sys.argv[1:])
report = json.loads(source.read_text())
files = [item for section in report.get("data", []) for item in section.get("files", [])]
for product in ("QualiaKit", "QualiaTesting"):
    covered = [item for item in files if f"/Sources/{product}/" in item["filename"]]
    if not covered or sum(item["summary"]["lines"]["covered"] for item in covered) == 0:
        raise SystemExit("Missing executed line coverage for " + product)
shutil.copyfile(source, destination)
print("Executed QualiaKit/QualiaTesting coverage exported; no silent fallback")
