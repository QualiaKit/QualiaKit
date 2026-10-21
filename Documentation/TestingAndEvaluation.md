# Testing and evaluation

Spec 0013 separates runtime correctness, semantic quality and experience quality.
Passing the first level never certifies the other two. See the
[evidence status](../Evaluation/cards/current-status.md) and the
[requirement matrix](../Evaluation/requirement-matrix.md).

The opt-in [physical-device harness](DeviceEvaluation.md) records Release-build
timings and real Core Haptics lifecycle evidence. Its first iPhone 17 Pro baseline
is provisional; semantic and complete physical release gates remain open.

## Public deterministic tests

`QualiaTesting` adds four public tools without an XCTest dependency:

- `FixtureAnalyzer` returns immutable observations by input ID; missing and
  duplicate fixtures throw. Its advertised capabilities are synthetic contracts.
- `ControlledAnalyzer` assigns monotonically increasing request numbers, pauses
  invocations, and accepts explicit success/failure completions in any order.
  `waitForRequest(number:)` is a cancellable scheduling barrier. Choose `.respect`
  or `.ignore` cancellation to test both kinds of host analyzers. Use `cancelAll()`
  in teardown to release outstanding requests/barriers and `clearHistory()` to
  release captured synthetic input text. Completing an unknown request throws.
- `TestQualiaClock` implements real suspension against manually advanced monotonic
  time. `waitUntilSleeping(count:)` removes scheduling races before advancement;
  cancellation releases sleepers. Backward advancement throws. `cancelAll()`
  releases outstanding sleepers and observers in teardown.
- `QualiaSessionHarness` connects the public session API to that clock and a
  `RecordingHapticRenderer`. `process(_:advancingBy:)`, `advance(by:)` and
  `reset()` preserve the real reducer, policy, preparation and lifecycle path.

For example, with an explicitly configured synthetic analyzer and session:

```swift
let harness = try await QualiaSessionHarness(
    analyzer: fixtureAnalyzer,
    configuration: configuration
)
let response = try await harness.process(input, advancingBy: .seconds(1))
let commands = harness.renderer.commands
try await harness.reset()
```

Create the harness on MainActor. Advance the clock after a scheduling barrier
when testing debouncing or concurrent work. A barrier deliberately waits for the
requested event; the CI job timeout is only a deadlock backstop, not test timing.
Fixtures must not contain private production text.

Tests live in `Tests/QualiaKitTests/Evaluation` inside the existing test target.
This preserves the root package manifest's checksum in the frozen model audit.
The legacy tests that only reimplemented softmax, asserted output range, or
always skipped without exercising code were removed. Independent public-model
and protected committed-golden parity remain the correctness evidence.

`Tests/Fixtures/testing-v1` contains independently authored tokenizer vectors
and the exact session corpus. Tokenizer cases cover whole-word unknowns,
WordPiece, casing, Unicode, punctuation, padding and truncation using a public
vocabulary. This is the legacy BERT profile, distinct from the manifest-driven
Core ML runtime's ASCII tokenizer and the licensed Russian model's full corpus.
Tokens are compared by exact UTF-8 identity, IDs and masks by exact integers.

The narrative corpus uses explicit synthetic scores, hand-calculated scene
values and complete expected physical descriptors. Only the newly allocated
session owner is substituted when comparing commands. It checks exactly start,
replace, independent impact and owned stop, plus timestamps and reset state.
This proves runtime behavior, not narrative text understanding or comfort.

```sh
swift build
swift test --filter TestingAndEvaluationTests
swift test --filter TestingPrimitivesTests
swift build --target QualiaTesting -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
python3 Tools/TestingFixtures/generate.py
python3 -m unittest discover -s Evaluation/tests -v
```

## Parity tiers and fixture changes

Regular CI executes the public arithmetic Core ML models with no private assets:

```sh
python3 Tools/CoreMLFixtures/verify.py
swift test --package-path Packages/QualiaCoreML
```

Their [model card](../Tools/CoreMLFixtures/MODEL_CARD.md) specifies provenance,
exact tensors, independent raw/transformed arithmetic references and the 1e-6
Swift absolute floating tolerance. Do not use these models for semantic claims.

The manual `Protected model parity` workflow runs only on `main` in the
`qualia-model-parity` environment. Repository administrators must provision a
trusted self-hosted macOS runner labelled `qualia-protected`, protected environment
reviewers, environment variables `QUALIAKIT_TEST_MODEL_PATH` and
`QUALIAKIT_TEST_VOCAB_PATH`, licensed assets outside the checkout, and the exact
toolchain in `Tools/ModelContract/requirements.lock`. This implementation does
not provision that infrastructure. Missing assets or wrong toolchain fail the
job explicitly. No protected bytes or raw output artifacts are uploaded.
Without a configured runner the job remains queued, which is not passing parity.

Golden versions are immutable. Make fixture changes in an isolated patch with a
new version, regenerate with the documented independent reference, inspect the
literal expectations and provenance, and obtain explicit review. The new public
generator refuses to overwrite an existing version; normal verification only
compares bytes and hashes. Existing Core ML/current-model goldens are unchanged.
Checksums detect drift; they do not establish review approval. Repository branch
protection and reviewer assignment remain administrator responsibilities.

## Semantic and physical evidence

The [semantic/experience tools](SemanticEvaluation.md) compute metrics from
independently annotated data and actual prediction exports, select thresholds on
validation only and reserve one held-out evaluation per frozen study. Reports
remain unreviewed until a person reviews the actual study.

The [v1 format](../Evaluation/schemas/README.md) defines checksum-bound reports
and prespecified acceptance limits. Store candidate reports under
`Evaluation/reports/<candidate-version>/`, frozen licensed/sanitized datasets
under `Evaluation/datasets/<dataset-version>/`, and their rights/split/removal
records with them. No production text is automatically collected.

```sh
python3 Evaluation/scripts/evidence.py narrative Evaluation/reports/<candidate-version>/candidate.json
python3 Evaluation/scripts/evidence.py regression Tests/Fixtures/Regression/session-lifecycle-v1.json
python3 Evaluation/scripts/evidence.py physical ReleaseEvidence/<version>/<device>.json
```

Every missing or invalid item exits nonzero. Narrative admission requires
annotation agreement, all held-out signal/language/length metrics, hard negatives,
context comparison, and physical-device performance bound to the same candidate
and frozen protocol. Synthetic gate tests are not evidence for any real model.
Experience quality stays separate: report alignment, immersion, false-reaction
complaints, disable rate, comfort and static-versus-adaptive preference without
combining them into a runtime/semantic aggregate score.

The [physical template](../ReleaseEvidence/physical-device-template.json) has no
passing defaults. Record a physical device, OS, exact model/policy/runtime/build,
date, reviewer and every lifecycle/comfort check. Simulator results cannot fill
it. Release approval also needs an agreed device matrix and reviewed experience
study. Performance regression limits require an identified-device release-build
baseline, sample distribution and variance methodology; no baseline is invented
by this change.

## Heartbeat audit

`HeartbeatBranchAuditTests.swift` closes missing reachable guards. Run the targeted
suite with coverage and validate the exported source regions:

```sh
swift test --enable-code-coverage --filter HeartbeatEffectTests
python3 Tools/TestingFixtures/heartbeat_coverage.py "$(swift test --show-codecov-path)"
```

The [measured audit](../Evaluation/coverage/heartbeat-audit.json) records 82/87
regions on Xcode 27.1. The remaining regions are two `preconditionFailure` paths
whose constructors receive already-validated finite parameters; exceptions are
explicit. Swift's exporter has no numeric branch counters. The outcome/transition
map and region audit are the evidence, without a fabricated branch percentage.
