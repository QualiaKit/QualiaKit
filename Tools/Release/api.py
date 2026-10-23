#!/usr/bin/env python3
"""Compiler-derived API inventory. A diff is evidence for review, not an ABI proof."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
MODULES = ("QualiaKit", "QualiaTesting", "QualiaCoreML")


def encoded(value):
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + "\n").encode()


def source_hash(root=ROOT):
    files = [root / "Package.swift", root / "Packages/QualiaCoreML/Package.swift"]
    for directory in ("Sources/QualiaKit", "Sources/QualiaTesting", "Packages/QualiaCoreML/Sources"):
        files.extend((root / directory).rglob("*.swift"))
    digest = hashlib.sha256()
    for item in sorted(files):
        digest.update(item.relative_to(root).as_posix().encode() + b"\0" + item.read_bytes() + b"\0")
    return digest.hexdigest()


def snapshot(graph_root, root=ROOT):
    modules = {}
    for module in MODULES:
        symbols, relationships = {}, []
        for item in sorted((graph_root / module).glob(module + "*.symbols.json")):
            graph = json.loads(item.read_text())
            for symbol in graph["symbols"]:
                # Own declarations, including public extensions of SDK types.
                # Inherited SDK members change with the SDK, not with this library.
                if symbol.get("accessLevel") != "public" or "/Sources/" not in symbol.get("location", {}).get("uri", ""):
                    continue
                if symbol["kind"]["identifier"] == "swift.extension":
                    continue
                identity = symbol["identifier"]["precise"]
                symbols[identity] = {
                    "path": symbol["pathComponents"],
                    "declaration": "".join(p["spelling"] for p in symbol.get("declarationFragments", [])),
                    "availability": symbol.get("availability", []),
                    "generics": symbol.get("swiftGenerics", {}),
                }
            relationships.extend(graph["relationships"])
        if not symbols:
            raise ValueError("No compiler declarations for " + module)
        relations = [{k: r[k] for k in ("source", "target", "kind", "swiftConstraints") if k in r}
                     for r in relationships if r["source"] in symbols]
        modules[module] = {"symbols": symbols, "relationships": sorted(
            {json.dumps(r, sort_keys=True) for r in relations})}
    return {"schemaVersion": 1, "sourceSHA256": source_hash(root), "modules": modules}


def difference(before, after):
    changes = []
    for module in MODULES:
        old, new = before["modules"][module], after["modules"][module]
        for identity in sorted(set(old["symbols"]) | set(new["symbols"])):
            left, right = old["symbols"].get(identity), new["symbols"].get(identity)
            if left != right:
                changes.append({"module": module, "symbol": identity,
                                "kind": "added" if left is None else "removed" if right is None else "changed",
                                "before": left, "after": right})
        if old["relationships"] != new["relationships"]:
            changes.append({"module": module, "kind": "relationships",
                            "before": old["relationships"], "after": new["relationships"]})
    return {"schemaVersion": 1, "changes": changes,
            "potentiallyBreaking": any(c["kind"] != "added" for c in changes)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--baseline", type=Path, default=ROOT / "Tools/Release/api-baseline.json")
    parser.add_argument("--skip-export", action="store_true", help="Use just-exported DocC graphs")
    args = parser.parse_args()
    sys.path.insert(0, str(ROOT / "Tools/DeveloperExperience"))
    from build_docs import GRAPH_ROOT, export_graphs
    if not args.skip_export:
        export_graphs()
    current = snapshot(GRAPH_ROOT)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "api-current.json").write_bytes(encoded(current))
    diff = difference(json.loads(args.baseline.read_text()), current)
    (args.output / "api-diff.json").write_bytes(encoded(diff))
    print(f"API inventory: {len(diff['changes'])} changes; human review required for release")


if __name__ == "__main__":
    main()
