"""Synthetic gate tests only. These are not candidate evaluation results."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/evidence.py"
SPEC = importlib.util.spec_from_file_location("evidence", SCRIPT)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


class NarrativeEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.identity = dict(model="synthetic-test-only:1", policy="test:1", runtime="test:1", build="test-build")
        self.plan = dict(schemaVersion=1, identity=self.identity, status="frozen", validationDatasetSHA256="a" * 64,
                         heldOutDatasetSHA256="b" * 64, selectedOn="validation", frozenBeforeEvaluation=True,
                         signals=["suspense"], languages=["en"], lengthBuckets=["short"], thresholds={"suspense": 0.8},
                         minimumAgreement=0.7, minimumF1=0.8, maximumHardNegativeRate=0.05,
                         minimumContextF1Delta=0.01, maximumWarmP95Milliseconds=100)
        self.candidate = dict(schemaVersion=1, identity=self.identity, protocol=self.write("protocol", self.plan), evidence={})
        self.data = {
            "annotationAgreement": dict(method="synthetic-kappa", agreement=0.8, annotators=2, cases=20),
            "heldOutMetrics": dict(datasetSHA256="b" * 64, thresholdDatasetSHA256="a" * 64, evaluations=1,
                slices=[dict(signal="suspense", language="en", lengthBucket="short", cases=20,
                             precision=0.9, recall=0.9, f1=0.9, prAUC=0.95, calibrationError=0.02)]),
            "hardNegatives": dict(cases=20, falseReactions=0, productionLikeCases=10, provenance="synthetic-test-only",
                                  rights="MIT", sanitization="synthetic", removalPolicy="delete test fixture"),
            "contextComparison": dict(datasetSHA256="b" * 64, cases=20, withoutContextF1=0.8, withContextF1=0.9),
            "devicePerformance": dict(physicalDevice=True, device="synthetic-device", os="test-os", configuration="release",
                concurrency=1, samples=20, tokenizationP95Milliseconds=1, coldLoadMilliseconds=10,
                warmP50Milliseconds=5, warmP95Milliseconds=9, peakMemoryBytes=1024, modelBytes=512,
                statePolicyP95Milliseconds=1, dispatchP95Milliseconds=1, sustainedEnergyThermal="synthetic-test-only"),
        }
        self.reports = {}
        for kind in gate.KINDS:
            self.reports[kind] = dict(schemaVersion=1, kind=kind, identity=self.identity,
                protocolSHA256=self.candidate["protocol"]["sha256"], reviewer="synthetic-reviewer",
                status="passed", data=self.data[kind])
            self.refresh(kind)
        self.path = self.root / "candidate.json"

    def write(self, name, value):
        data = (json.dumps(value, sort_keys=True) + "\n").encode()
        (self.root / f"{name}.json").write_bytes(data)
        return dict(path=f"{name}.json", sha256=hashlib.sha256(data).hexdigest())

    def refresh(self, kind):
        self.candidate["evidence"][kind] = self.write(kind, self.reports[kind])

    def check(self):
        self.write("candidate", self.candidate)
        return gate.narrative(self.path)

    def test_complete_synthetic_bundle_passes_without_claiming_experience_quality(self):
        result = self.check()
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["experienceQuality"], "not-assessed")
        self.assertEqual(result["tactileReleaseApproval"], "not-assessed")

    def test_each_missing_report_blocks_narrative_claim(self):
        for kind in gate.KINDS:
            with self.subTest(kind=kind):
                saved = self.candidate["evidence"].pop(kind)
                with self.assertRaises(gate.EvidenceError):
                    self.check()
                self.candidate["evidence"][kind] = saved

    def test_checksum_drift_missing_files_and_identity_mismatch_fail(self):
        for kind in gate.KINDS:
            with self.subTest(kind=kind):
                path = self.root / f"{kind}.json"
                path.write_text("{}")
                with self.assertRaises(gate.EvidenceError): self.check()
                path.unlink()
                with self.assertRaises(gate.EvidenceError): self.check()
                self.reports[kind]["identity"] = dict(self.identity, model="different-model")
                self.refresh(kind)
                with self.assertRaises(gate.EvidenceError): self.check()
                self.reports[kind]["identity"] = self.identity
                self.refresh(kind)

    def test_simulator_unreviewed_empty_or_nonfinite_evidence_fails(self):
        for kind, key, invalid in [
            ("devicePerformance", "physicalDevice", False), ("devicePerformance", "configuration", "debug"),
            ("devicePerformance", "warmP95Milliseconds", float("nan")), ("devicePerformance", "samples", 0),
            ("annotationAgreement", "annotators", 1), ("annotationAgreement", "agreement", 0.1),
            ("hardNegatives", "productionLikeCases", 0), ("hardNegatives", "sanitization", "raw-production"),
            ("hardNegatives", "falseReactions", 20), ("contextComparison", "withContextF1", 0.1),
            ("heldOutMetrics", "evaluations", 2), ("heldOutMetrics", "slices", []),
        ]:
            with self.subTest(kind=kind, key=key):
                saved = self.data[kind][key]
                self.data[kind][key] = invalid
                self.refresh(kind)
                with self.assertRaises(gate.EvidenceError): self.check()
                self.data[kind][key] = saved
                self.refresh(kind)
        for key, value in [("reviewer", ""), ("status", "pending"), ("protocolSHA256", "c" * 64)]:
            saved = self.reports["annotationAgreement"][key]
            self.reports["annotationAgreement"][key] = value
            self.refresh("annotationAgreement")
            with self.assertRaises(gate.EvidenceError): self.check()
            self.reports["annotationAgreement"][key] = saved
            self.refresh("annotationAgreement")

    def test_tuning_on_test_or_unfrozen_protocol_fails(self):
        for key, invalid in [("selectedOn", "test"), ("frozenBeforeEvaluation", False),
                             ("heldOutDatasetSHA256", "a" * 64), ("thresholds", {})]:
            with self.subTest(key=key):
                changed = dict(self.plan, **{key: invalid})
                self.candidate["protocol"] = self.write("protocol", changed)
                # Rebind reports so failure is about protocol, not stale checksums.
                for kind in gate.KINDS:
                    self.reports[kind]["protocolSHA256"] = self.candidate["protocol"]["sha256"]
                    self.refresh(kind)
                with self.assertRaises(gate.EvidenceError): self.check()

    def test_invalid_metrics_and_missing_slices_fail(self):
        sample = self.data["heldOutMetrics"]["slices"][0]
        for key, invalid in [("precision", -1), ("recall", 2), ("f1", 0.95), ("cases", True), ("language", "ru")]:
            with self.subTest(key=key):
                self.data["heldOutMetrics"]["slices"] = [dict(sample, **{key: invalid})]
                self.refresh("heldOutMetrics")
                with self.assertRaises(gate.EvidenceError): self.check()

    def test_schema_duplicate_keys_path_escape_and_cli_failure(self):
        self.candidate["schemaVersion"] = True
        with self.assertRaises(gate.EvidenceError): self.check()
        self.candidate["schemaVersion"] = 1
        self.candidate["protocol"]["path"] = "../outside.json"
        with self.assertRaises(gate.EvidenceError): self.check()
        self.path.write_text('{"schemaVersion": 1, "schemaVersion": 2}')
        with self.assertRaises(gate.EvidenceError): gate.load(self.path)
        result = subprocess.run([sys.executable, str(SCRIPT), "narrative", str(self.path)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)["status"], "blocked")

    def test_regression_metadata_is_mandatory(self):
        case = dict(id="synthetic-regression", provenance="test", rights="MIT", sanitization="synthetic",
                    removalPolicy="remove fixture", test="TestingAndEvaluationTests.testControlledStaleAndResetCompletionsCannotChangeSession")
        corpus = dict(schemaVersion=1, version="test-v1", cases=[case])
        self.write("regression", corpus)
        self.assertEqual(gate.regression(self.root / "regression.json")["cases"], 1)
        for key in case:
            changed = copy.deepcopy(corpus)
            del changed["cases"][0][key]
            self.write("regression", changed)
            with self.assertRaises(gate.EvidenceError): gate.regression(self.root / "regression.json")

    def test_physical_checklist_cannot_be_replaced_by_simulator_or_partial_evidence(self):
        document = dict(schemaVersion=1, identity=self.identity, device="synthetic-device", os="test-os",
                        physicalDevice=True, testedAt="2026-10-21", reviewer="synthetic-reviewer", status="passed",
                        checklist={key: "passed" for key in gate.PHYSICAL_CHECKS}, notes="synthetic-test-only")
        self.write("physical", document)
        self.assertEqual(gate.physical(self.root / "physical.json")["status"], "passed")
        for key, value in [("physicalDevice", False), ("status", "pending"), ("device", ""), ("testedAt", "invalid")]:
            self.write("physical", dict(document, **{key: value}))
            with self.assertRaises(ValueError): gate.physical(self.root / "physical.json")
        for key in gate.PHYSICAL_CHECKS:
            changed = copy.deepcopy(document)
            changed["checklist"][key] = "pending"
            self.write("physical", changed)
            with self.assertRaises(gate.EvidenceError): gate.physical(self.root / "physical.json")


if __name__ == "__main__":
    unittest.main()
