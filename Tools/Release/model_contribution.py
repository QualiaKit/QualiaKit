#!/usr/bin/env python3
"""Check a reviewed model contribution's contract, rights and evaluation evidence."""
import argparse
from release import read_json, referenced, require


def validate_model(path):
    value = read_json(path)
    require(set(value) == {"schemaVersion", "id", "version", "manifestSchemaVersion", "sourceRevision",
                           "intendedUses", "prohibitedUses", "redistributionApproved", "reviewer", "artifacts",
                           "narrative"}, "Invalid model contribution fields")
    require(value["schemaVersion"] == 1 and type(value["manifestSchemaVersion"]) is int and
            value["manifestSchemaVersion"] > 0, "Unsupported schema")
    for field in ("id", "version", "sourceRevision", "reviewer"):
        require(isinstance(value[field], str) and value[field].strip(), "Missing " + field)
    require(value["redistributionApproved"] is True, "Unreviewed redistribution rights")
    require(value["intendedUses"] and value["prohibitedUses"], "Missing model use boundaries")
    require(type(value["narrative"]) is bool, "Invalid capability claim")
    required = {"manifest", "modelCard", "modelLicense", "datasetLicense", "assetInventory", "benchmark", "evaluation"}
    if value["narrative"]:
        required |= {"annotation", "heldOut", "hardNegatives", "context", "device"}
    require(required <= value["artifacts"].keys(), "Missing model contract/license/evaluation evidence")
    for ref in value["artifacts"].values():
        referenced(path.parent, ref)
    return value


if __name__ == "__main__":
    from pathlib import Path
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("record", type=Path)
    args = parser.parse_args()
    try:
        validate_model(args.record.resolve())
        print("Model contribution evidence complete; qualified human review still required")
    except (ValueError, KeyError, TypeError, OSError) as error:
        parser.exit(1, f"Model contribution FAILED: {error}\n")
