#!/usr/bin/env python3
"""Verify public fixture schemas, identities and independent references using only stdlib."""
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('model_contract_reference', ROOT / 'Tools/ModelContract/reference_inference.py')
validator = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = validator
spec.loader.exec_module(validator)
from reference import cases, expected


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    return json.loads(path.read_text())


def verify():
    base = read(ROOT / 'Models/current/manifest.schema.json')
    extension = read(ROOT / 'Models/Runtime/execution.schema.json')
    folders = sorted((ROOT / 'Packages/QualiaCoreML/Tests/QualiaCoreMLTests/Resources/CoreML').iterdir())
    for folder in folders:
        manifest = read(folder / 'manifest.json')
        validator.validate_manifest_document(manifest, base)
        runtime = manifest['runtime']
        validator.validate_schema_value(runtime, extension, extension, 'runtime')
        assert runtime['model']['sha256'] == sha((folder / 'model.mlmodel').read_bytes())
        assert manifest['model']['componentSha256'] == {'model.mlmodel': runtime['model']['sha256']}
        assert manifest['model']['packageIdentitySha256'] == runtime['model']['sha256']
        assert manifest['tokenizer']['vocabularySha256'] == sha((folder / 'vocab.txt').read_bytes())
        assert manifest['provenance']['source']['value']['artifactSha256'] == sha((Path(__file__).parent / 'generate.py').read_bytes())
        assert manifest['provenance']['trainingConfiguration']['value']['environmentLockSha256'] == sha((Path(__file__).parent / 'requirements.lock').read_bytes())
        assert manifest['fixture']['goldenSha256'] == sha((folder / 'golden.json').read_bytes())
        assert manifest['fixture']['corpusSha256'] == sha(json.dumps(cases(), sort_keys=True).encode())
        assert manifest['fixture']['calibrationSha256'] == sha((Path(__file__).parent / 'reference.py').read_bytes())
        assert manifest['fixture']['caseCount'] == len(cases())
        actual = read(folder / 'golden.json')
        reference = [expected(case, manifest['tokenizer']['maxSequenceLength'], runtime['inputRoles'],
                              runtime['transform'] == 'none', runtime['classification'] == 'independent') for case in cases()]
        assert len(actual) == len(reference), folder.name
        for observed, oracle in zip(actual, reference):
            assert observed.keys() == oracle.keys(), folder.name
            for field in observed:
                if field in ('raw', 'scores'):
                    assert len(observed[field]) == len(oracle[field]), (folder.name, field)
                    assert all(math.isclose(a, b, rel_tol=0, abs_tol=1e-14)
                               for a, b in zip(observed[field], oracle[field])), (folder.name, field)
                else:
                    assert observed[field] == oracle[field], (folder.name, field)
        print(f'{folder.name}: base v1 + execution schema, pinned assets, {len(actual)} reference cases OK')
    # A structurally valid audit with unknown evidence remains valid, but has no runtime extension.
    current = read(ROOT / 'Models/current/manifest.json')
    validator.validate_manifest_document(current, base)
    assert 'runtime' not in current and current['runtimeRefactorGate']['status'] == 'blocked'


if __name__ == '__main__':
    verify()
