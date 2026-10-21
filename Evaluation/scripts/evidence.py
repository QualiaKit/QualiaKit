"""Offline evidence admission gate, not a semantic-quality measurement tool.

Requires reviewed, checksum-bound reports for one candidate and a frozen
evaluation protocol. Does not infer evidence from a passing runtime test.
"""
import argparse
import datetime
import hashlib
import itertools
import json
import math
from pathlib import Path
import re

KINDS = ("annotationAgreement", "heldOutMetrics", "hardNegatives", "contextComparison", "devicePerformance")
PHYSICAL_CHECKS = ("start", "update", "independentAccent", "stop", "reset", "background", "disable",
                   "continuousDisabled", "maximumDuration", "intensity", "reduceMotion", "comfort")


class EvidenceError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise EvidenceError(message)


def fields(value, expected, location):
    require(isinstance(value, dict), f"{location}: expected object")
    require(set(value) == set(expected.split()), f"{location}: missing or unknown fields")


def string(value, location):
    require(isinstance(value, str) and bool(value.strip()), f"{location}: nonempty string required")


def number(value, location, minimum=0, maximum=None, integer=False):
    require(type(value) in ((int,) if integer else (int, float)) and math.isfinite(value), f"{location}: finite number required")
    require(value >= minimum and (maximum is None or value <= maximum), f"{location}: out of range")


def sha(value, location):
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None, f"{location}: SHA-256 required")


def strings(value, location):
    require(isinstance(value, list) and len(value) > 0, f"{location}: nonempty array required")
    for item in value:
        string(item, location)
    require(len(set(value)) == len(value), f"{location}: duplicates")


def load(path):
    # Duplicate keys and nonfinite JSON values must never silently change a gate.
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, f"duplicate JSON key: {key}")
            result[key] = value
        return result
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=pairs,
                      parse_constant=lambda value: (_ for _ in ()).throw(EvidenceError(f"invalid JSON number: {value}")))


def artifact(root, reference):
    fields(reference, "path sha256", "artifact")
    string(reference["path"], "artifact.path")
    sha(reference["sha256"], "artifact.sha256")
    relative = Path(reference["path"])
    path = (root / relative).resolve()
    require(not relative.is_absolute() and path.is_relative_to(root.resolve()), "artifact must stay inside evidence directory")
    require(path.is_file(), f"missing evidence artifact: {relative}")
    require(hashlib.sha256(path.read_bytes()).hexdigest() == reference["sha256"], f"checksum drift: {relative}")
    return load(path)


def identity(value):
    fields(value, "model policy runtime build", "identity")
    for key, item in value.items():
        string(item, f"identity.{key}")


def protocol(value, candidate):
    fields(value, "schemaVersion identity status validationDatasetSHA256 heldOutDatasetSHA256 selectedOn "
           "frozenBeforeEvaluation signals languages lengthBuckets thresholds minimumAgreement minimumF1 "
           "maximumHardNegativeRate minimumContextF1Delta maximumWarmP95Milliseconds", "protocol")
    require(type(value["schemaVersion"]) is int and value["schemaVersion"] == 1, "unsupported protocol schema")
    require(value["identity"] == candidate, "protocol identity mismatch")
    require(value["status"] == "frozen" and value["frozenBeforeEvaluation"] is True, "protocol must be frozen before evaluation")
    require(value["selectedOn"] == "validation", "thresholds must be selected on validation")
    for key in ("validationDatasetSHA256", "heldOutDatasetSHA256"):
        sha(value[key], key)
    require(value["validationDatasetSHA256"] != value["heldOutDatasetSHA256"], "validation and held-out datasets must differ")
    for key in ("signals", "languages", "lengthBuckets"):
        strings(value[key], key)
    require(isinstance(value["thresholds"], dict) and set(value["thresholds"]) == set(value["signals"]), "thresholds must cover every signal")
    for key, threshold in value["thresholds"].items():
        number(threshold, f"thresholds.{key}", maximum=1)
    for key in ("minimumAgreement", "minimumF1", "maximumHardNegativeRate", "minimumContextF1Delta"):
        number(value[key], key, maximum=1)
    number(value["maximumWarmP95Milliseconds"], "maximumWarmP95Milliseconds", minimum=0.000001)
    return value


def validate_report(kind, report, candidate, protocol_hash, plan):
    fields(report, "schemaVersion kind identity protocolSHA256 reviewer status data", kind)
    require(type(report["schemaVersion"]) is int and report["schemaVersion"] == 1, f"{kind}: unsupported schema")
    require(report["kind"] == kind and report["identity"] == candidate, f"{kind}: identity/kind mismatch")
    require(report["protocolSHA256"] == protocol_hash, f"{kind}: protocol mismatch")
    require(report["status"] == "passed", f"{kind}: report not passed")
    string(report["reviewer"], f"{kind}.reviewer")
    data = report["data"]
    if kind == "annotationAgreement":
        fields(data, "method agreement annotators cases", kind)
        string(data["method"], "agreement.method")
        number(data["agreement"], "agreement", maximum=1)
        number(data["annotators"], "annotators", minimum=2, integer=True)
        number(data["cases"], "cases", minimum=1, integer=True)
        require(data["agreement"] >= plan["minimumAgreement"], "annotation agreement below frozen minimum")
    elif kind == "heldOutMetrics":
        fields(data, "datasetSHA256 thresholdDatasetSHA256 evaluations slices", kind)
        require(data["datasetSHA256"] == plan["heldOutDatasetSHA256"], "held-out dataset mismatch")
        require(data["thresholdDatasetSHA256"] == plan["validationDatasetSHA256"], "threshold selection dataset mismatch")
        require(type(data["evaluations"]) is int and data["evaluations"] == 1, "held-out test may be evaluated only once per frozen protocol")
        require(isinstance(data["slices"], list), "metric slices required")
        expected = set(itertools.product(plan["signals"], plan["languages"], plan["lengthBuckets"]))
        observed = set()
        for item in data["slices"]:
            fields(item, "signal language lengthBucket cases precision recall f1 prAUC calibrationError", "slice")
            for key in ("signal", "language", "lengthBucket"):
                string(item[key], key)
            key = (item["signal"], item["language"], item["lengthBucket"])
            require(key not in observed, "duplicate metric slice")
            observed.add(key)
            number(item["cases"], "slice.cases", minimum=1, integer=True)
            for name in ("precision", "recall", "f1", "prAUC", "calibrationError"):
                number(item[name], name, maximum=1)
            p, r = item["precision"], item["recall"]
            f1 = 2 * p * r / (p + r) if p + r else 0
            require(abs(item["f1"] - f1) <= 1e-6, "inconsistent F1")
            require(item["f1"] >= plan["minimumF1"], "held-out F1 below frozen minimum")
        require(observed == expected, "missing or unexpected signal/language/length slices")
    elif kind == "hardNegatives":
        fields(data, "cases falseReactions productionLikeCases provenance rights sanitization removalPolicy", kind)
        number(data["cases"], "hard-negative cases", minimum=1, integer=True)
        number(data["falseReactions"], "false reactions", maximum=data["cases"], integer=True)
        number(data["productionLikeCases"], "production-like cases", minimum=1, maximum=data["cases"], integer=True)
        provenance(data)
        require(data["falseReactions"] / data["cases"] <= plan["maximumHardNegativeRate"], "hard-negative rate above frozen maximum")
    elif kind == "contextComparison":
        fields(data, "datasetSHA256 cases withoutContextF1 withContextF1", kind)
        require(data["datasetSHA256"] == plan["heldOutDatasetSHA256"], "context dataset mismatch")
        number(data["cases"], "context cases", minimum=1, integer=True)
        for key in ("withoutContextF1", "withContextF1"):
            number(data[key], key, maximum=1)
        require(data["withContextF1"] - data["withoutContextF1"] >= plan["minimumContextF1Delta"], "context comparison below frozen minimum")
    else:
        fields(data, "physicalDevice device os configuration concurrency samples tokenizationP95Milliseconds "
               "coldLoadMilliseconds warmP50Milliseconds warmP95Milliseconds peakMemoryBytes modelBytes "
               "statePolicyP95Milliseconds dispatchP95Milliseconds sustainedEnergyThermal", kind)
        require(data["physicalDevice"] is True, "simulator cannot provide physical-device evidence")
        for key in ("device", "os", "configuration", "sustainedEnergyThermal"):
            string(data[key], key)
        require(data["configuration"] == "release", "device benchmarks require release configuration")
        for key in ("concurrency", "samples", "peakMemoryBytes", "modelBytes"):
            number(data[key], key, minimum=1, integer=True)
        for key in ("tokenizationP95Milliseconds", "coldLoadMilliseconds", "warmP50Milliseconds", "warmP95Milliseconds",
                    "statePolicyP95Milliseconds", "dispatchP95Milliseconds"):
            number(data[key], key)
        require(data["warmP50Milliseconds"] <= data["warmP95Milliseconds"] <= plan["maximumWarmP95Milliseconds"], "invalid or excessive device latency")


def provenance(value):
    for key in ("provenance", "rights", "removalPolicy"):
        string(value[key], key)
    require(value["sanitization"] in ("synthetic", "sanitized", "licensed-public"), "unapproved text provenance")


def narrative(path):
    document = load(path)
    fields(document, "schemaVersion identity protocol evidence", "candidate")
    require(type(document["schemaVersion"]) is int and document["schemaVersion"] == 1, "unsupported candidate schema")
    identity(document["identity"])
    fields(document["evidence"], " ".join(KINDS), "evidence")
    plan = protocol(artifact(path.parent, document["protocol"]), document["identity"])
    for kind in KINDS:
        report = artifact(path.parent, document["evidence"][kind])
        validate_report(kind, report, document["identity"], document["protocol"]["sha256"], plan)
    return {"status": "passed", "level": "semantic-evidence-admission", "identity": document["identity"],
            "experienceQuality": "not-assessed", "tactileReleaseApproval": "not-assessed"}


def regression(path):
    document = load(path)
    fields(document, "schemaVersion version cases", "regression corpus")
    require(type(document["schemaVersion"]) is int and document["schemaVersion"] == 1, "unsupported regression schema")
    string(document["version"], "corpus.version")
    require(isinstance(document["cases"], list) and document["cases"], "regression cases required")
    seen = set()
    for case in document["cases"]:
        fields(case, "id provenance rights sanitization removalPolicy test", "regression case")
        string(case["id"], "regression id")
        require(case["id"] not in seen, "duplicate regression id")
        seen.add(case["id"])
        provenance(case)
        string(case["test"], "regression test")
    return {"status": "passed", "level": "regression-governance", "cases": len(seen)}


def physical(path):
    document = load(path)
    fields(document, "schemaVersion identity device os physicalDevice testedAt reviewer status checklist notes", "physical record")
    require(type(document["schemaVersion"]) is int and document["schemaVersion"] == 1, "unsupported physical schema")
    identity(document["identity"])
    require(document["physicalDevice"] is True, "simulator cannot replace tactile evidence")
    require(document["status"] == "passed", "physical evidence incomplete")
    for key in ("device", "os", "testedAt", "reviewer", "notes"):
        string(document[key], key)
    datetime.date.fromisoformat(document["testedAt"])
    fields(document["checklist"], " ".join(PHYSICAL_CHECKS), "physical checklist")
    require(all(value == "passed" for value in document["checklist"].values()), "physical checklist incomplete")
    return {"status": "passed", "level": "physical-device-checklist", "identity": document["identity"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=("narrative", "regression", "physical"))
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    try:
        result = {"narrative": narrative, "regression": regression, "physical": physical}[args.kind](args.path)
        print(json.dumps(result, sort_keys=True))
        return 0
    except (EvidenceError, OSError, ValueError, TypeError, KeyError) as error:
        print(json.dumps({"status": "blocked", "reason": str(error)}, sort_keys=True))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
