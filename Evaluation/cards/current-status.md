# Evidence status

**Current iPhone device-test iteration accepted by the user (2026-10-21).**
The user accepted the reported results and the three recorded exceptions without
requiring further device runs. See the [acceptance record](../../ReleaseEvidence/spec-0013/2026-10-21-tactile-iphone17pro/acceptance.json).
This closes the current device acceptance task; the measurement and broader
semantic/release evidence status below remain factual and unchanged.

The public arithmetic models and scripted analyzers are **test fixtures**. They
do not qualify as narrative-capable models. The legacy Russian model's label
semantics and redistribution limits remain governed by its existing model card.

| Level | Available | Still required |
| --- | --- | --- |
| A: runtime correctness | Independent public tokenizer vectors, public arithmetic Core ML parity, deterministic command corpus, clock/cancellation and session suites | Protected parity on the pinned toolchain for the release revision; explicit fixture/API review |
| B: semantic quality | Report admission gate; threshold freeze, split validation and semantic metric computation with independent numeric tests | Real annotation agreement, frozen validation/test datasets, signal/language/length metrics, hard negatives, context comparison, measured device performance |
| C: experience quality | Physical checklist; v1 iPhone baseline; v2 A/B/C distinguishability and comfort ratings plus background stop/no replay on iPhone 17 Pro; paired static/adaptive experience aggregation | Complete device matrix and remaining v2 checks; perceived alignment, immersion, false-reaction complaints, disable rate, comfort and static-versus-adaptive preference study |

There is no aggregate quality score. Synthetic test data under `Evaluation/tests`
must never be copied into candidate reports as real evidence. No approved
narrative candidate or complete physical release result is supplied by this
implementation. A [provisional device baseline](../../ReleaseEvidence/spec-0013/2026-10-21-iphone17pro/README.md)
contains three measured Release runs, without semantic qualification or sustained
energy measurements. Direct device feedback confirms background stop/no replay,
but the calm heartbeat was indistinguishable at 50% test intensity in that v1 run.
The later v2 report rates all three variants distinct and comfortable; both findings
are retained. Full physical approval remains open. Spec 0013 remains in progress until its evidence gaps and
review requirements are resolved.

Implementation now includes the consolidated v2 device session, per-variant
ratings, actual background/accessibility steps, public Core ML stage timings,
context overhead, sustained workload telemetry, archived reports and build-bound
summary validation. The simulator self-test verifies software execution only.
The [v2 tactile report](../../ReleaseEvidence/spec-0013/2026-10-21-tactile-iphone17pro/README.md)
now contains completed A/B/C ratings, twelve passed technical checks including
actual scene cleanup, and human background confirmation. The export still lacks
a preferred profile, system Reduce Motion observation and the general sustained
stage (quick mode). Those omissions are accepted exceptions for this iteration.
The holder reported liking all variants; no preference was invented. The separate real RuBERT performance session has completed on iPhone
17 Pro; it does not provide narrative-quality or watt/joule results. See
[device procedure](../../Documentation/DeviceEvaluation.md) and
[semantic/experience procedure](../../Documentation/SemanticEvaluation.md).

The Russian source recovery now verifies all 201 retained parameter tensors and
the vocabulary against the identified Hugging Face checkpoint. Its label mapping
is empirical, with weaker evidence for skip; it is not an author-confirmed or
narrative-qualified mapping. The opt-in local lab supports real RuBERT inference,
source-parity probes and device load measurements. See
[the recovery record](../../Documentation/RussianModelEvaluation.md).

[Real RuBERT iPhone measurements](../../ReleaseEvidence/spec-0013/2026-10-21-rubert-iphone17pro/README.md)
include CPU/all source comparisons and a completed five-minute load.
