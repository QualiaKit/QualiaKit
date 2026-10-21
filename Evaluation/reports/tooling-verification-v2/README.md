# Spec 0013 implementation verification — 2026-10-21

The unified v2 device lab was built in Release and installed on the requested
physical iPhone without starting a new physical run. The user requested one
combined check later. Open Qualia Device Lab and start the full run when ready.

Local verification: 324 root Swift tests, zero failures, 14 external-asset tests
skipped; 22 Core ML tests; 22 Python tests; four spec acceptance tests. Independent
fixture regeneration and asset checksums pass. The frozen current-model audit,
production BERT sources, root Package.swift and their golden files are unchanged.

The simulator software self-test completed three state/context repetitions, actual
public Core ML inference/stage timings, a five-second fixture load and persisted
reports. Apple sentiment was unavailable on this simulator and is explicitly
excluded; physical checks are also excluded. Consequently `simulator-summary.json`
correctly lists 19 physical/manual gaps and cannot pass full-device admission.
It is software verification, not an iPhone performance baseline.

`device-build.json` identifies the signed physical build; `simulator-build.json`
identifies the separate simulator executable. `verification.json` binds raw
software results and build records with checksums. The historical physical v1
baseline and feedback remain under `ReleaseEvidence/spec-0013/2026-10-21-iphone17pro`.

Code/tooling is prepared for the next combined check. Release validation still
requires real physical observations, reviewed fixture/API/coverage exceptions,
a qualified narrative candidate and independently annotated datasets. Protected
legacy parity requires the pinned Xcode 26.6 / Swift 6.3.3 toolchain; this host has
Xcode 27.1 / Swift 6.4. No missing result is converted into a passing gate.

See [device runbook](../../../Documentation/DeviceEvaluation.md),
[semantic/experience runbook](../../../Documentation/SemanticEvaluation.md) and
[requirement matrix](../../requirement-matrix.md).
