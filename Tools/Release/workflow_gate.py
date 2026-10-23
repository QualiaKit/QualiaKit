#!/usr/bin/env python3
"""Resolve an immutable evidence commit and validate workflow inputs without shell interpolation."""
import os
from pathlib import Path
import re
import sys
from release import git, require, validate

source, evidence = (Path(argument).resolve() for argument in sys.argv[1:])
for variable, checkout in (("REQUESTED_SOURCE", source), ("REQUESTED_EVIDENCE", evidence)):
    requested = os.environ.get(variable)
    if requested:
        require(re.fullmatch(r"[0-9a-f]{40}", requested) and requested == git(checkout, "rev-parse", "HEAD"),
                "Manual run requires an exact source/evidence commit")
version = os.environ.get("REQUESTED_VERSION") or os.environ["TAG_NAME"].removeprefix("v")
require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[1-9][0-9]*)?", version), "Invalid version")
candidate = validate(evidence / version / "candidate.json", source)
require(candidate["version"] == version, "Tag/request version differs from candidate")
with open(os.environ["GITHUB_OUTPUT"], "a") as output:
    output.write(f"source={candidate['sourceRevision']}\nevidence={git(evidence, 'rev-parse', 'HEAD')}\nversion={version}\n")
