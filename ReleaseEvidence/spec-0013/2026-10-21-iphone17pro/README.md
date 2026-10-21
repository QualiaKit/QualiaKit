# iPhone 17 Pro — provisional device baseline

Measured 2026-10-21 on a physical iPhone 17 Pro (iPhone18,1), iOS 26.6 (23G71).
Release arm64 build with Xcode 27.1 (27A9275), Swift 6.4, SDK build 24A94232.
One in-flight request; Low Power Mode and Reduce Motion off. Paired network
connection; no debugger or Instruments attached during the baseline.

Three fresh process launches completed **11/11 automatic checks each**. Raw
samples are in `run-01.json` through `run-03.json`. `summary.json` records per-run
distributions and checksums; `build.json` records the exact source and executable
identities. The build contains uncommitted spec-0013 work. No personal device
identifier or user text is included.

| Measurement | Samples per run | p50 across runs, ms | p95 across runs, ms |
| --- | ---: | ---: | ---: |
| Apple English valence, 49 UTF-8 bytes | 200 | 1.087–1.125 | 1.151–1.252 |
| Apple English valence, 488 UTF-8 bytes | 200 | 1.100–1.114 | 1.145–1.167 |
| Apple English valence, 1,952 UTF-8 bytes | 200 | 1.120–1.138 | 1.145–1.160 |
| Scene reduction + narrative policy, no renderer | 1,000 | 0.0423–0.0425 | 0.0632–0.0635 |

Each Apple group excludes 20 warmups; policy excludes 100 warmups. Percentiles
use nearest rank. Each text group repeats the same synthetic text, and policy
state persists between steps. The first Apple invocation was 38.66–40.09 ms.
That includes first-use work; it is not isolated cold model-load latency.

Whole-process memory footprint after the benchmark: 16.55–16.70 MiB. Lifetime
peak up to that point: 16.80–16.94 MiB, including UI and before haptics. The benchmark
stage lasted 0.825–0.842 s and consumed 0.843–0.858 s of process CPU time. Thermal
state was nominal before and after; the short duration cannot establish sustained
thermal or energy behavior.

Renderer dispatch across all three runs (small samples, not motor onset latency):

| Command | Count | Median, ms | Maximum, ms |
| --- | ---: | ---: | ---: |
| Start | 12 | 0.570 | 1.089 |
| Replace | 3 | 2.182 | 2.350 |
| Independent accent | 6 | 0.878 | 1.359 |
| Stop owned effects, including empty cleanup | 27 | 0.005 | 0.279 |

The checks exercised hardware support; heartbeat start and replacement; an
independent accent; reset; disable and suppression of later input; programmatic
suspend; resume without replay; accent with ambient disabled; automatic stop
after a two-second limit without new input; and zero-intensity suppression.
Passing means real renderer calls/player-state checks succeeded. It does not by
itself establish perceptual alignment or comfort.

The earlier `interrupted-pilot.json` is excluded. Scene deactivation interrupted
it, revealing overlapping reset/suspend requests in the test harness. Cleanup was
serialized before the three completed runs. The pilot's source fingerprint is
recorded separately in `build.json`; no runtime library change was necessary.

The device holder reported: “спокойное сердцебиение не различимо, остальное норм”.
The calm heartbeat therefore **fails distinguishability** at the test settings;
later stages were reported normal. On leaving the app, vibration stopped immediately
and did not replay on return. The later device snapshot also records successful
scene-deactivation cleanup. These direct observations are preserved separately in
`human-observations.json` and `human-device-snapshot.json`.

The harness used intensity scale 0.5, heartbeat thresholds 0.5/0.25 and a 60–120 BPM
range, overriding policy defaults. Manual playback had an eight-second ceiling;
automatic scenarios used three seconds, with a separate two-second deadline test.
The finding concerns this candidate/configuration; it is not evidence about every
intensity setting. Overall comfort was not separately confirmed. The physical
checklist deliberately remains incomplete and fails the release evidence gate.

System Reduce Motion, a broader device matrix, separate tokenization/context/real-model
measurements, sustained energy/thermal behavior and experience studies remain
unverified. No performance regression limit is inferred from three runs on one
device. These measurements do not evaluate narrative semantics: Apple supplies
English valence only; narrative haptics use `device-scripted-fixture-not-a-model/1`.

Runtime: `qualia-runtime-v2`; policy: `1.0.0-beta.3`; heartbeat:
`heartbeat-candidate-v1`. This is **incomplete release evidence**, not approval
of spec 0013 or a narrative-capable candidate.

See [reproduction and methodology](../../../Documentation/DeviceEvaluation.md).
