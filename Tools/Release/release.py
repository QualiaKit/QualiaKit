#!/usr/bin/env python3
"""Validate repository contracts or fail closed on an exact-source release bundle."""
import argparse
from datetime import date
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

from api import difference, encoded, source_hash

ROOT = Path(__file__).resolve().parents[2]
CHECKS = (
    "lint-and-format", "swift-build-minimum-toolchain", "swift-build-current-toolchain",
    "strict-concurrency", "unit-tests", "fixture-model-parity", "protected-model-parity",
    "public-api-check", "docc-build", "example-build", "package-resolution", "coverage-report",
)
GATES = tuple(f"HG-0015-{i:03}" for i in range(1, 6))
REQUIRED = CHECKS + GATES + ("privacy", "api-review", "author-pilot")
DETAILS = {
    "HG-0015-001": ("rationale", "unresolvedRisks", "checklist", "supportOwner"),
    "HG-0015-002": ("device", "os", "buildConfiguration", "modelIdentity", "computePolicy", "sampleCount",
                    "modelBytes", "coldLoadMs", "tokenizationP50Ms", "tokenizationP95Ms", "inferenceP50Ms",
                    "inferenceP95Ms", "peakMemoryBytes", "runtimeOverheadMs", "sustainedMethod", "energy", "thermal"),
    "HG-0015-003": ("deviceMatrix", "accentOverLoop", "interruption", "reset", "background", "rapidReplacement",
                    "longLoopMethod", "energy", "thermal", "failures"),
    "HG-0015-004": ("deviceMatrix", "configurationVersion", "script", "candidateParameters", "reviewers",
                    "recognizability", "comfort", "stopBehavior", "calibrationDecision"),
    "HG-0015-005": ("device", "os", "exampleRevision", "buildConfiguration", "walkthrough", "lifecycle",
                    "accessibility", "observedEffect"),
    "privacy": ("dataFlowReview", "manifestReview", "noHiddenTelemetry", "feedbackReview", "securityChannelVerified"),
    "api-review": ("decision", "migrationNotes", "baselineRevision"),
    "author-pilot": ("app", "acceptedFragment", "explicitLanguage", "boundedContext", "shadowComparison",
                     "singlePhysicalRenderer", "consentedFeedback"),
    "api-freeze": ("pilotReview", "repeatedDXIssuesResolved", "deprecationPolicy", "rationale"),
    "narrative": ("annotation", "heldOut", "hardNegatives", "contextEvaluation", "deviceEvaluation"),
}
DOCS = (
    "CHANGELOG.md", "SECURITY.md", "SUPPORT.md", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", "GOVERNANCE.md",
    "LICENSE", "docs/release/README.md", "docs/release/Compatibility.md", "docs/release/Limitations.md",
    "docs/release/Checklist.md", "docs/release/Pilots.md", "docs/release/Evidence.md", "docs/PrivacyAndDataFlow.md",
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(item):
    return hashlib.sha256(item.read_bytes()).hexdigest()


def read_json(item):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "Duplicate JSON key: " + key)
            result[key] = value
        return result
    return json.loads(item.read_text(), object_pairs_hook=unique,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError("Non-finite JSON: " + value)))


def referenced(base, reference):
    require(isinstance(reference, dict) and set(reference) == {"path", "sha256"}, "Expected path and sha256")
    relative = Path(reference["path"])
    require(not relative.is_absolute() and ".." not in relative.parts, "Artifact escapes evidence directory")
    item = base / relative
    require(item.resolve().is_relative_to(base.resolve()) and item.is_file(), "Missing or escaped artifact: " + str(item))
    cursor = item
    while cursor != base:
        require(not cursor.is_symlink(), "Symlink artifact")
        cursor = cursor.parent
    require(sha(item) == reference["sha256"], "Checksum drift: " + str(item))
    return item


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def inventory(root=ROOT):
    """Trace all tracked source, policy, manifest and documentation bytes, excluding private assets."""
    names = git(root, "ls-files", "-z").split("\0")
    return {name: sha(root / name) for name in sorted(names) if name and (root / name).is_file()}


def repository_check(root=ROOT):
    for name in DOCS:
        require((root / name).is_file() and (root / name).stat().st_size > 100, "Missing release document: " + name)
    require("## Unreleased" in (root / "CHANGELOG.md").read_text(), "Missing Unreleased changelog")
    manifest = read_json(root / "Models/current/manifest.json")
    require(manifest["model"]["redistribution"]["allowed"] is False, "Re-review distribution policy before changing it")
    privacy = plistlib.loads((root / "Examples/QualiaExample/QualiaExample/PrivacyInfo.xcprivacy").read_bytes())
    require(privacy.get("NSPrivacyTracking") is False and privacy.get("NSPrivacyCollectedDataTypes") == [],
            "Example privacy manifest requires review")
    # Check links in newly published governance/release docs, including nested pages.
    for name in DOCS:
        item = root / name
        prose = re.sub(r"```.*?```", "", item.read_text(), flags=re.S)
        for target in re.findall(r"\]\(([^)]+)\)", prose):
            if target.startswith(("https://", "http://", "#")):
                continue
            require((item.parent / target.split("#")[0]).exists(), f"Broken link in {name}: {target}")
    for item in [*(root / "Tools/Release").glob("*.py"), *(root / "docs/release").glob("*.md")]:
        for line in item.read_text().splitlines():
            require(line.rstrip() == line and "\t" not in line, f"Whitespace formatting: {item}")


def record(base, reference, name, revision):
    value = read_json(referenced(base, reference))
    require(set(value) == {"name", "status", "sourceRevision", "reviewer", "details", "artifacts"}, "Invalid evidence record: " + name)
    require(value["name"] == name and value["status"] == "passed" and value["sourceRevision"] == revision,
            "Missing pass or wrong candidate: " + name)
    require(isinstance(value["reviewer"], str) and value["reviewer"].strip(), "Missing reviewer/producer: " + name)
    details = value["details"]
    require(isinstance(details, dict), "Invalid details: " + name)
    for field in DETAILS.get(name, ("runURL", "toolchain", "command")):
        require(field in details and details[field] is not None and details[field] != "" and details[field] is not False,
                f"Missing {name}.{field}")
    if name in CHECKS:
        require(details.get("conclusion") == "success", "Failed critical CI job: " + name)
        require(re.fullmatch(r"https://github.com/QualiaKit/QualiaKit/actions/runs/[0-9]+(?:/job/[0-9]+)?",
                             details["runURL"]), "Missing immutable CI run URL")
    require(isinstance(value["artifacts"], list) and value["artifacts"], "Missing raw artifacts: " + name)
    for artifact in value["artifacts"]:
        referenced(base, artifact)
    if name in GATES[1:]:
        require(details.get("physicalDevice") is True, "Physical iPhone evidence required: " + name)
    if name == "HG-0015-002":
        for field in ("sampleCount", "modelBytes", "coldLoadMs", "tokenizationP50Ms", "tokenizationP95Ms",
                      "inferenceP50Ms", "inferenceP95Ms", "peakMemoryBytes", "runtimeOverheadMs"):
            require(type(details[field]) in (int, float) and details[field] >= 0, "Invalid numeric measurement: " + field)
        require(details["sampleCount"] > 0 and details["modelBytes"] > 0 and details["peakMemoryBytes"] > 0,
                "Empty benchmark")
        require(details["tokenizationP95Ms"] >= details["tokenizationP50Ms"] and
                details["inferenceP95Ms"] >= details["inferenceP50Ms"], "Invalid percentiles")
    if name in ("HG-0015-002", "HG-0015-003"):
        energy = details["energy"]
        require(isinstance(energy, dict) and all(energy.get(k) for k in ("method", "durationSeconds", "unit")) and
                type(energy.get("value")) in (int, float) and energy["value"] >= 0,
                "Measured energy and method required; CPU time/thermal state are not energy")
        require(energy["unit"] in ("joules", "milliwatt-hours", "battery-percentage-points"), "Unsupported energy unit")
        require(type(energy["durationSeconds"]) in (int, float) and energy["durationSeconds"] > 0, "Invalid energy duration")
    if name == "HG-0015-005":
        require(details["exampleRevision"] == revision, "Example must match candidate")
    return value


def validate(candidate_path, root=ROOT):
    candidate = read_json(candidate_path)
    require(set(candidate) == {"schemaVersion", "version", "stage", "sourceRevision", "sourceTree", "inventory",
                               "identities", "records", "pilots", "criticalDXIssues", "waivers", "narrative",
                               "apiBaseline", "apiCurrent", "apiDiff"}, "Invalid candidate fields")
    require(candidate["schemaVersion"] == 1, "Unsupported candidate schema")
    version, stage = candidate["version"], candidate["stage"]
    require(stage in ("beta", "stable"), "Unknown release stage")
    require(re.fullmatch(r"0\.[1-9][0-9]*\.[0-9]+-beta\.[1-9][0-9]*" if stage == "beta" else r"[1-9][0-9]*\.[0-9]+\.[0-9]+", version), "Invalid release version")
    revision = candidate["sourceRevision"]
    require(re.fullmatch(r"[0-9a-f]{40}", revision or ""), "Missing exact source revision")
    require(git(root, "rev-parse", "HEAD") == revision and git(root, "rev-parse", "HEAD^{tree}") == candidate["sourceTree"], "Wrong source checkout")
    require(not git(root, "status", "--porcelain", "--untracked-files=all"), "Dirty source checkout")
    for tag in git(root, "tag", "--list").splitlines():
        if tag.removeprefix("v") == version:
            require(git(root, "rev-parse", tag + "^{commit}") == revision, "Version collides with an existing legacy/release tag")
    require(candidate["inventory"] == inventory(root), "Source/manifest/policy inventory drift")
    repository_check(root)
    require(candidate["identities"] == identities(root), "Model, manifest or policy identity drift")
    base = candidate_path.parent
    before = read_json(referenced(base, candidate["apiBaseline"]))
    current = read_json(referenced(base, candidate["apiCurrent"]))
    actual_diff = difference(before, current)
    require(current["sourceSHA256"] == source_hash(root), "Stale compiler API inventory")
    require(read_json(referenced(base, candidate["apiDiff"])) == actual_diff, "API diff does not match inventories")
    required = set(REQUIRED)
    if stage == "stable":
        required.add("api-freeze")
    require(type(candidate["narrative"]) is bool, "Invalid narrative scope")
    if candidate["narrative"]:
        required.add("narrative")
    require(required <= candidate["records"].keys(), "Missing release evidence: " + ", ".join(sorted(required - candidate["records"].keys())))
    records = {name: record(base, ref, name, revision) for name, ref in candidate["records"].items()}
    review = records["api-review"]["details"]
    referenced(base, review["migrationNotes"])
    require(review["decision"] in ("compatible", "breaking-approved"), "API review not approved")
    if actual_diff["potentiallyBreaking"]:
        require(review["decision"] == "breaking-approved", "Incompatible API requires explicit review")
        if stage == "stable":
            require(type(review.get("previousMajor")) is int and review["previousMajor"] >= 0 and
                    int(version.split(".")[0]) > review["previousMajor"], "Stable breaking API requires a reviewed previous major and new major version")
    require(candidate["criticalDXIssues"] == [], "Unresolved critical DX issues")
    teams, use_cases = set(), set()
    for pilot in candidate["pilots"]:
        require(set(pilot) == {"team", "useCase", "external", "consent", "record"}, "Invalid pilot")
        require(pilot["external"] is True and pilot["consent"] in ("public", "explicit"), "External consented pilot required")
        team, use_case = pilot["team"].strip().casefold(), pilot["useCase"].strip().casefold()
        require(team and use_case and team not in teams, "Duplicate or missing independent pilot")
        record(base, pilot["record"], "pilot", revision)
        teams.add(team)
        use_cases.add(use_case)
    require(len(teams) >= (3 if stage == "stable" else 1) and len(use_cases) >= (2 if stage == "stable" else 1),
            "Insufficient independent pilots/external use cases")
    for waiver in candidate["waivers"]:
        require(set(waiver) == {"requirement", "owner", "reason", "expires"}, "Invalid waiver")
        require(waiver["requirement"] == "QK-REL-011", "Mandatory gates cannot be waived")
        require(waiver["owner"].strip() and waiver["reason"].strip() and date.fromisoformat(waiver["expires"]) >= date.today(), "Expired or incomplete waiver")
    if stage == "stable" and not candidate["waivers"]:
        require("external-contribution" in records, "External contribution/integration proof or time-limited QK-REL-011 waiver required")
    require(f"## {version}" in (root / "CHANGELOG.md").read_text(), "Missing versioned changelog")
    return candidate


def identities(root=ROOT):
    manifest = read_json(root / "Models/current/manifest.json")
    policy_files = sorted((root / "Sources/QualiaKit/Reaction").glob("*Policy*.swift"))
    policy_files += sorted((root / "Sources/QualiaKit/Heartbeat").glob("*.swift"))
    return {
        "runtime": "qualia-runtime-v2",
        "manifestSchema": manifest["schemaVersion"],
        "executionSchema": sha(root / "Models/Runtime/execution.schema.json"),
        "currentModel": {"id": manifest["model"]["identifier"], "version": manifest["model"]["version"],
                         "packageSHA256": manifest["model"]["packageIdentitySha256"],
                         "vocabularySHA256": manifest["tokenizer"]["vocabularySha256"],
                         "redistributed": False},
        "policies": {p.relative_to(root).as_posix(): sha(p) for p in policy_files},
    }


def prepare(version, stage, root=ROOT):
    return {"schemaVersion": 1, "version": version, "stage": stage,
            "sourceRevision": git(root, "rev-parse", "HEAD"), "sourceTree": git(root, "rev-parse", "HEAD^{tree}"),
            "inventory": inventory(root), "identities": identities(root), "records": {}, "pilots": [],
            "criticalDXIssues": [], "waivers": [], "narrative": False,
            **{name: {"path": filename, "sha256": "PENDING"} for name, filename in
               (("apiBaseline", "api-baseline.json"), ("apiCurrent", "api-current.json"), ("apiDiff", "api-diff.json"))}}


def bundle(candidate_path, output, root=ROOT):
    candidate = validate(candidate_path, root)
    require(not output.exists(), "Bundle destination already exists")
    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".qualia-release-", dir=output.parent))
    try:
        # Only referenced files, never arbitrary private siblings or external model assets.
        references = set()
        def collect(value):
            if isinstance(value, dict):
                if set(value) == {"path", "sha256"}:
                    item = referenced(candidate_path.parent, value)
                    require(item != candidate_path and item.relative_to(candidate_path.parent).as_posix() != "candidate.json",
                            "Candidate cannot reference itself or reserved candidate.json")
                    if item in references:
                        return
                    references.add(item)
                    if item.suffix == ".json":
                        collect(read_json(item))
                else:
                    for child in value.values():
                        collect(child)
            elif isinstance(value, list):
                for child in value:
                    collect(child)
        collect(candidate)
        evidence = staging / "evidence"
        evidence.mkdir()
        (evidence / "candidate.json").write_bytes(encoded(candidate))
        for item in references:
            target = evidence / item.relative_to(candidate_path.parent)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(item, target)
            require(sha(target) == sha(item), "Artifact changed while copying")
        # Recheck all declared hashes after copying and before publishing the directory.
        validate(evidence / "candidate.json", root)
        subprocess.run(["git", "-C", str(root), "archive", "--format=tar", "-o", str(staging / "source.tar"), candidate["sourceRevision"]], check=True)
        checksums = {p.relative_to(staging).as_posix(): sha(p) for p in sorted(staging.rglob("*")) if p.is_file()}
        (staging / "checksums.json").write_bytes(encoded(checksums))
        os.rename(staging, output)
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--bundle", type=Path, help="Atomically assemble a validated bundle; never publish")
    parser.add_argument("--prepare", type=Path, help="Create a pending candidate in an empty evidence directory")
    parser.add_argument("--version", default="0.1.0-beta.1")
    parser.add_argument("--stage", choices=("beta", "stable"), default="beta")
    args = parser.parse_args()
    try:
        if args.prepare:
            require(not args.candidate and not args.bundle and not args.prepare.exists(), "Use a new candidate path")
            args.prepare.parent.mkdir(parents=True, exist_ok=True)
            args.prepare.write_bytes(encoded(prepare(args.version, args.stage)))
            print("PENDING candidate created; no release gate has passed")
        elif args.candidate:
            if args.bundle:
                bundle(args.candidate.resolve(), args.bundle.resolve())
            else:
                validate(args.candidate.resolve())
            print("Release evidence PASS for exact source; publication still requires owner approval")
        else:
            require(not args.bundle, "--bundle requires --candidate")
            repository_check()
            print("Repository release contracts PASS. Release readiness NOT evaluated; use --candidate. No tag or release created.")
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Release check FAILED: {error}\n")


if __name__ == "__main__":
    main()
