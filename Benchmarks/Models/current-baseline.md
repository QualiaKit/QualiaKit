# Current model physical-device baseline

Status: **pending consolidated release gate HG-0015-002**
Contract: `current-russian-v1`
Fixture: `current-russian-fixture-v1`

No physical-iPhone measurements are fabricated by repository automation. The orchestrator evaluates this report only after repository-actionable verification passes.

## Repository-verifiable size baseline

| Item | Bytes | Identity |
|---|---:|---|
| Package manifest | 617 | SHA-256 `a655c85265418a3c567fc48869e4bab5271b2340e33b7b67bdc395f3874bb302` |
| Model specification | 141,612 | SHA-256 `f7ac2156e756a2aacd1cca8cc3f3aded5e7b143147270ea0aea374747a609a42` |
| Weights | 355,137,600 | SHA-256 `26c028484b4df267933afbfa3ef9ca421dc7450d48bd02c720146bd4444da2f2` |
| Vocabulary | 1,649,718 | SHA-256 `78106a3d3ae8600d1ba573b967b9bb731d2c2282957cbc6e26ab20935c3da02b` |

The model and vocabulary remain checksum-pinned local inputs and are not redistributed.

## Required physical-iPhone record

The release owner must replace the pending fields below with captured evidence without altering the versioned fixture:

| Field | Required value |
|---|---|
| Supported iPhone model | pending |
| Chip / memory class | pending |
| iOS version and build | pending |
| Xcode / Swift version | pending |
| App build configuration | pending |
| Contract, fixture, model, vocabulary checksums | pending |
| Core ML compute-unit policy | pending |
| Sample count | pending (minimum 100 warm inferences) |
| Cold model load | pending |
| Warm inference p50 / p95 | pending |
| Tokenization p50 / p95 | pending |
| Peak resident memory | pending |
| Sustained-run duration and sample count | pending |
| Energy / thermal start and end state | pending |
| Raw measurement artifact path and checksum | pending |

## Methodology

1. Use a release-equivalent build on a supported physical iPhone, disconnected from Xcode performance instrumentation except for the designated memory capture.
2. Bind the run to the exact manifest, fixture, model-component, and vocabulary checksums.
3. Terminate the app, launch once, and measure model construction through the first ready prediction as cold load.
4. Warm the model with five unrecorded fixture cases. Then run the complete sanitized corpus sequentially, recording tokenization and inference separately with a monotonic clock.
5. Repeat corpus cases as necessary to reach at least 100 recorded warm predictions. Report nearest-rank p50 and p95 and retain raw samples.
6. Record peak resident memory over cold load and the sustained run with one named instrument/method.
7. For energy and thermal evidence, record device battery/power state, thermal state, ambient conditions, run duration, and workload count before and after a sustained sequential run. Do not compare parallel inference until determinism is proven.
8. Store sanitized numeric results only; do not log source text. Record the resulting artifact path and SHA-256 above.

Passing `HG-0015-002` during the final release stage requires device model, OS, build configuration, sample count, p50/p95, memory, and artifact path. Pending evidence here is intentionally not interpreted as repository test failure and does not block implementation specs.
