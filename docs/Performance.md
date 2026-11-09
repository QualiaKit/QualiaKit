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

Measure your application's model and workload; historical sentiment-model runs
do not establish a universal latency budget or narrative semantic quality.
Core ML `.all` does not prove a specific accelerator executed every operation.

Bound generic context, avoid unnecessary overlapping tasks, and keep one explicit
session per event stream. A model actor can serialize inference independently of
MainActor rendering. Larger inputs must respect the model's actual truncation
contract. Prefer measured capability-compatible substitutions to guessed heuristics.
Physical calibration still varies across devices and holders. See
[Accessibility](Accessibility.md) and [Testing](TestingYourIntegration.md).
