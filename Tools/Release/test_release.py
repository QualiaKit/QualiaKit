"""Synthetic gate fixtures; none of these records are real release evidence."""
import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from api import MODULES, difference, encoded, source_hash
from model_contribution import validate_model
from release import (CHECKS, DETAILS, DOCS, REQUIRED, ROOT, bundle, prepare, read_json,
                     referenced, sha, validate)


class ReleaseGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "source"
        self.base = Path(self.temp.name) / "evidence"
        self.root.mkdir()
        self.base.mkdir()
        for name in DOCS:
            item = self.root / name
            item.parent.mkdir(parents=True, exist_ok=True)
            item.write_text("# Synthetic test documentation\n" * 5)
        (self.root / "CHANGELOG.md").write_text("## Unreleased\n## 0.1.0-beta.1\n## 1.0.0\n" + "Test migration.\n" * 10)
        for name in ("Models/current/manifest.json", "Models/Runtime/execution.schema.json",
                     "Examples/QualiaExample/QualiaExample/PrivacyInfo.xcprivacy"):
            item = self.root / name
            item.parent.mkdir(parents=True, exist_ok=True)
            item.write_bytes((ROOT / name).read_bytes())
        for name in ("Package.swift", "Packages/QualiaCoreML/Package.swift", "Sources/QualiaKit/Example.swift"):
            item = self.root / name
            item.parent.mkdir(parents=True, exist_ok=True)
            item.write_text("// synthetic source\n")
        self.git("init", "-q")
        self.git("add", ".")
        self.git("-c", "user.name=Release Test", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "Synthetic fixture")
        self.candidate = prepare("0.1.0-beta.1", "beta", self.root)
        current = {"schemaVersion": 1, "sourceSHA256": source_hash(self.root),
                   "modules": {m: {"symbols": {}, "relationships": []} for m in MODULES}}
        self.candidate["apiBaseline"] = self.write("api-baseline.json", current)
        self.candidate["apiCurrent"] = self.write("api-current.json", current)
        self.candidate["apiDiff"] = self.write("api-diff.json", difference(current, current))
        self.raw = self.write("raw.txt", "SYNTHETIC measurement/log, not real release evidence")
        self.migration = self.write("migration.md", "SYNTHETIC migration notes")
        for name in REQUIRED:
            self.candidate["records"][name] = self.make_record(name)
        self.add_pilot("Independent Team A", "reading")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], stderr=subprocess.STDOUT, text=True).strip()

    def write(self, name, value):
        item = self.base / name
        item.parent.mkdir(parents=True, exist_ok=True)
        item.write_bytes(encoded(value) if not isinstance(value, str) else value.encode())
        return {"path": name, "sha256": sha(item)}

    def make_record(self, name, suffix=""):
        details = {field: "synthetic reviewed result" for field in DETAILS.get(name, ("runURL", "toolchain", "command"))}
        details.update(physicalDevice=True, runURL="https://github.com/QualiaKit/QualiaKit/actions/runs/123", conclusion="success")
        if name in ("HG-0015-002", "HG-0015-003"):
            details["energy"] = {"value": 1.2, "unit": "joules", "method": "synthetic meter", "durationSeconds": 300}
        if name == "HG-0015-002":
            for field in ("sampleCount", "modelBytes", "coldLoadMs", "tokenizationP50Ms", "tokenizationP95Ms",
                          "inferenceP50Ms", "inferenceP95Ms", "peakMemoryBytes", "runtimeOverheadMs"):
                details[field] = 10
        if name == "HG-0015-005":
            details["exampleRevision"] = self.candidate["sourceRevision"]
        if name == "api-review":
            details.update(decision="compatible", migrationNotes=self.migration)
        return self.write(f"records/{name}{suffix}.json", {
            "name": name, "status": "passed", "sourceRevision": self.candidate["sourceRevision"],
            "reviewer": "synthetic test producer", "details": details, "artifacts": [self.raw]})

    def add_pilot(self, team, use_case):
        self.candidate["pilots"].append({"team": team, "useCase": use_case, "external": True, "consent": "explicit",
                                         "record": self.make_record("pilot", str(len(self.candidate["pilots"])))})

    def mutate_record(self, name, callback):
        ref = self.candidate["records"][name]
        value = read_json(self.base / ref["path"])
        callback(value)
        self.candidate["records"][name] = self.write(ref["path"], value)

    def check(self):
        self.write("candidate.json", self.candidate)
        return validate(self.base / "candidate.json", self.root)

    def test_complete_beta_dry_run_and_atomic_bundle(self):
        self.check()
        (self.base / "private-unreferenced.txt").write_text("must not ship")
        output = Path(self.temp.name) / "bundle"
        bundle(self.base / "candidate.json", output, self.root)
        self.assertFalse((output / "evidence/private-unreferenced.txt").exists())
        self.assertTrue((output / "source.tar").is_file())
        for name, checksum in read_json(output / "checksums.json").items():
            self.assertEqual(sha(output / name), checksum)
        with self.assertRaisesRegex(ValueError, "already exists"):
            bundle(self.base / "candidate.json", output, self.root)

    def test_pending_candidate_is_not_release_ready(self):
        self.candidate["records"] = {}
        with self.assertRaisesRegex(ValueError, "Missing release evidence"):
            self.check()

    def test_every_critical_job_and_physical_gate_is_mandatory(self):
        original = copy.deepcopy(self.candidate)
        for name in REQUIRED:
            with self.subTest(name=name):
                self.candidate = copy.deepcopy(original)
                del self.candidate["records"][name]
                with self.assertRaisesRegex(ValueError, "Missing release evidence"):
                    self.check()

    def test_historical_acceptance_cannot_be_relabelled_as_candidate(self):
        self.mutate_record("HG-0015-004", lambda r: r.update(sourceRevision="0" * 40))
        with self.assertRaisesRegex(ValueError, "wrong candidate"):
            self.check()

    def test_simulator_and_cpu_time_are_not_physical_energy_evidence(self):
        self.mutate_record("HG-0015-002", lambda r: r["details"].update(physicalDevice=False))
        with self.assertRaisesRegex(ValueError, "Physical iPhone"):
            self.check()
        self.mutate_record("HG-0015-002", lambda r: r["details"].update(physicalDevice=True, energy={"cpuSeconds": 15}))
        with self.assertRaisesRegex(ValueError, "Measured energy"):
            self.check()

    def test_critical_failed_ci_cannot_pass_with_status_label(self):
        self.mutate_record(CHECKS[0], lambda r: r["details"].update(conclusion="failure"))
        with self.assertRaisesRegex(ValueError, "Failed critical CI"):
            self.check()

    def test_checksum_drift_and_dirty_source_fail(self):
        (self.base / "raw.txt").write_text("changed")
        with self.assertRaisesRegex(ValueError, "Checksum drift"):
            self.check()
        (self.root / "Package.swift").write_text("changed source")
        with self.assertRaisesRegex(ValueError, "Dirty source"):
            self.check()

    def test_untracked_source_cannot_escape_release_inventory(self):
        (self.root / "Sources/QualiaKit/Untracked.swift").write_text("// unreviewed source")
        with self.assertRaisesRegex(ValueError, "Dirty source"):
            self.check()

    def test_existing_legacy_semver_cannot_be_reused(self):
        self.git("tag", "0.1.0-beta.1")
        self.git("-c", "user.name=Release Test", "-c", "user.email=fixture@example.invalid",
                 "commit", "--allow-empty", "-qm", "Different source revision")
        self.candidate["sourceRevision"] = self.git("rev-parse", "HEAD")
        with self.assertRaisesRegex(ValueError, "collides"):
            self.check()

    def test_traversal_and_symlink_artifacts_fail(self):
        with self.assertRaisesRegex(ValueError, "escapes"):
            referenced(self.base, {"path": "../source/Package.swift", "sha256": "x"})
        (self.base / "alias.txt").symlink_to(self.base / "raw.txt")
        with self.assertRaisesRegex(ValueError, "Symlink"):
            referenced(self.base, {"path": "alias.txt", "sha256": self.raw["sha256"]})

    def test_duplicate_json_keys_and_nan_fail(self):
        for content in ('{"status":"failed","status":"passed"}', '{"measurement":NaN}'):
            self.write("bad.json", content)
            with self.assertRaises(ValueError):
                read_json(self.base / "bad.json")

    def test_beta_needs_real_external_pilot(self):
        self.candidate["pilots"] = []
        with self.assertRaisesRegex(ValueError, "Insufficient independent"):
            self.check()

    def test_stable_needs_three_teams_two_domains_and_freeze(self):
        self.candidate.update(version="1.0.0", stage="stable")
        with self.assertRaisesRegex(ValueError, "api-freeze"):
            self.check()
        self.candidate["records"]["api-freeze"] = self.make_record("api-freeze")
        self.candidate["records"]["external-contribution"] = self.make_record("external-contribution")
        self.add_pilot("Independent Team B", "reading")
        self.add_pilot("Independent Team C", "reading")
        with self.assertRaisesRegex(ValueError, "Insufficient independent"):
            self.check()
        self.candidate["pilots"][-1]["useCase"] = "game"
        self.check()

    def test_same_team_cannot_be_counted_twice(self):
        self.add_pilot(" independent TEAM a ", "game")
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            self.check()

    def test_unconsented_pilot_fails(self):
        self.candidate["pilots"][0]["consent"] = "assumed"
        with self.assertRaisesRegex(ValueError, "consented"):
            self.check()

    def test_narrative_claim_adds_real_qualification_gate(self):
        self.candidate["narrative"] = True
        with self.assertRaisesRegex(ValueError, "narrative"):
            self.check()

    def test_waiver_cannot_bypass_devices_and_cannot_expire(self):
        self.candidate["waivers"] = [{"requirement": "HG-0015-002", "owner": "test", "reason": "deadline", "expires": "2099-01-01"}]
        with self.assertRaisesRegex(ValueError, "cannot be waived"):
            self.check()
        self.candidate["waivers"][0].update(requirement="QK-REL-011", expires="2000-01-01")
        with self.assertRaisesRegex(ValueError, "Expired"):
            self.check()

    def test_breaking_api_requires_review_and_migration(self):
        old = read_json(self.base / "api-baseline.json")
        old["modules"][MODULES[0]]["symbols"]["removed"] = {"declaration": "func removed()"}
        self.candidate["apiBaseline"] = self.write("api-baseline.json", old)
        current = read_json(self.base / "api-current.json")
        self.candidate["apiDiff"] = self.write("api-diff.json", difference(old, current))
        with self.assertRaisesRegex(ValueError, "Incompatible API"):
            self.check()
        self.mutate_record("api-review", lambda r: r["details"].update(decision="breaking-approved"))
        self.check()

    def test_stale_api_diff_and_snapshot_are_rejected(self):
        self.candidate["apiDiff"] = self.write("api-diff.json", {"changes": []})
        with self.assertRaisesRegex(ValueError, "API diff"):
            self.check()
        current = read_json(self.base / "api-current.json")
        current["sourceSHA256"] = "0" * 64
        self.candidate["apiCurrent"] = self.write("api-current.json", current)
        with self.assertRaisesRegex(ValueError, "Stale compiler"):
            self.check()

    def test_versioned_changelog_and_no_critical_dx_issues_required(self):
        self.candidate["criticalDXIssues"] = ["Repeated installation failure"]
        with self.assertRaisesRegex(ValueError, "critical DX"):
            self.check()
        self.candidate["criticalDXIssues"] = []
        self.candidate["version"] = "0.2.0-beta.1"
        with self.assertRaisesRegex(ValueError, "versioned changelog"):
            self.check()

    def test_opaque_or_unlicensed_model_contribution_is_rejected(self):
        value = {"schemaVersion": 1, "id": "synthetic", "version": "1", "manifestSchemaVersion": 2,
                 "sourceRevision": "synthetic source", "intendedUses": ["test"], "prohibitedUses": ["people scoring"],
                 "redistributionApproved": False, "reviewer": "test", "artifacts": {}, "narrative": False}
        self.write("model.json", value)
        with self.assertRaisesRegex(ValueError, "rights"):
            validate_model(self.base / "model.json")
        value["redistributionApproved"] = True
        self.write("model.json", value)
        with self.assertRaisesRegex(ValueError, "license/evaluation"):
            validate_model(self.base / "model.json")

    def test_model_contribution_completeness_and_narrative_extension(self):
        value = {"schemaVersion": 1, "id": "synthetic", "version": "1", "manifestSchemaVersion": 1,
                 "sourceRevision": "synthetic source", "intendedUses": ["test"], "prohibitedUses": ["people scoring"],
                 "redistributionApproved": True, "reviewer": "test", "narrative": False,
                 "artifacts": {key: self.raw for key in ("manifest", "modelCard", "modelLicense", "datasetLicense",
                                                         "assetInventory", "benchmark", "evaluation")}}
        self.write("model.json", value)
        validate_model(self.base / "model.json")
        value["narrative"] = True
        self.write("model.json", value)
        with self.assertRaisesRegex(ValueError, "evaluation evidence"):
            validate_model(self.base / "model.json")

    def test_failed_bundle_does_not_publish_partial_directory(self):
        self.check()
        (self.base / "raw.txt").write_text("drift before assembly")
        output = Path(self.temp.name) / "never-published"
        with self.assertRaisesRegex(ValueError, "Checksum drift"):
            bundle(self.base / "candidate.json", output, self.root)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
