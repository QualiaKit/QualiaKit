# Tests

`swift test` runs library, Core ML and example-screen-model tests. The example
support target is internal to this repository and is not a library product.
`swift test --package-path Tests/Consumer` checks integration through public
products from an independent Swift package.

The small Python directories support checked-in test fixtures:

- `CoreMLFixtures`: synthetic Core ML model generator, arithmetic reference and verifier.
- `BertFixtures/generate.py`: synthetic BERT classifier fixture generator.
- `TestingFixtures/generate.py`: verifies exact, independently authored tokenizer and session vectors.
- `ModelContract`: legacy Russian model contract checks used by `CurrentModelContractTests` and the Core ML schema verifier.

Run the fixture verifiers without installing model-conversion dependencies:

```sh
python3 Tests/CoreMLFixtures/verify.py
python3 Tests/TestingFixtures/generate.py
python3 Tests/ModelContract/reference_inference.py --schema-self-test
python3 Tests/ModelContract/reference_inference.py --comparator-self-test
```

Generators and existing golden data are preserved byte-for-byte. Historical
`Tools/...` paths in their metadata describe the original generation; current
commands are above. For Core ML fixture regeneration, the generator's pinned
dependencies are in `CoreMLFixtures/requirements.lock`. BERT fixture generation
lists its pinned dependencies in the generator itself. Regeneration is a separate
reviewed task, never part of normal tests.

Protected legacy inference tests run only with explicitly supplied
`QUALIAKIT_TEST_MODEL_PATH` and `QUALIAKIT_TEST_VOCAB_PATH`. Public CI does not
receive these assets. The manual protected-model workflow remains available.

`Models/current/checksums.json` inventories the current source and fixture bytes;
updating paths/hashes after repository cleanup does not certify a protected
model run. Existing verification and calibration reports retain their original
source identities. `--verify-committed-evidence` must reject stale attestations;
no historical report is a passing attestation for this new layout.
