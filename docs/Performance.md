# Performance

Measure release builds on identified devices. Record the source/build fingerprint,
analyzer/model manifest, OS, input lengths, warmups, sample counts, concurrency and
raw timing distribution. Separate tokenizer, tensor preparation, inference,
transformation, state/policy overhead and renderer dispatch. Dispatch duration is
not the time until the actuator is felt.

Warm tight loops, cold initialization and paced sustained workloads are different
experiments. Do not combine their percentiles. Whole-process memory includes UI
and other state; it is not an isolated weights-size estimate. CPU time and thermal
samples do not measure watts, joules or battery drain. Disable debug formatting
while collecting timing baselines and report any profiler overhead separately.

The completed iPhone 17 Pro / iOS 26.6 RuBERT run is recorded with its exact builds
and manifest in the repository's
[measured evidence](https://github.com/QualiaKit/QualiaKit/blob/main/ReleaseEvidence/spec-0013/2026-10-21-rubert-iphone17pro/README.md).
It ran 2,867 analyses over 300.020 seconds; paced end-to-end p95 was 14.361 ms.
This is evidence for that sentiment model/workload, not a universal latency budget
or narrative semantic qualification. Core ML `.all` does not prove a specific
accelerator executed every operation. The private model is not part of the quick start.

Bound generic context, avoid unnecessary overlapping tasks, and keep one explicit
session per event stream. A model actor can serialize inference independently of
MainActor rendering. Larger inputs must respect the model's actual truncation
contract. Prefer measured capability-compatible substitutions to guessed heuristics.
Physical calibration still varies across devices and holders. See
[Accessibility](Accessibility.md) and [Testing](TestingYourIntegration.md).
