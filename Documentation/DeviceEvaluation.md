# Physical-device evaluation harness v2

Build/run/collect entry point: `Tools/DeviceEvaluation/run.py`. The opt-in
`QUALIA_DEVICE_EVALUATION` build uses the example app with a separate bundle ID.
Normal example UI remains the default. An explicit local
`--russian-assets` build also enables [real RuBERT tests](RussianModelEvaluation.md)
with separate reports and controls. The public arithmetic Core ML fixture is
copied unchanged into `DeviceEvaluationAssets.bundle`; the default build includes
no protected model or production text.

## One physical session

The app opens idle. Press **Начать полный прогон** only when ready to keep the
phone in the foreground for about five minutes. The stages are:

1. Three sequential baseline repetitions: Apple English valence for three text
   lengths, scene/policy, and bounded context-window overhead.
2. Public Core ML fixture: initial load including compilation; separate tokenization,
   tensor preparation, prediction and transformation timings; exact source size.
3. Eleven technical Core Haptics checks, including a two-second physical deadline.
4. Five-minute load at up to 20 Apple analysis calls/second. CPU, memory and thermal
   state are sampled every five seconds; individual analysis timings are retained.
5. Three manually started tactile variants, then actual background and system
   Reduce Motion checks. These stages require the device holder's observations.

**Короткая проверка без нагрузки** explicitly skips the sustained stage and cannot
pass the complete-suite check. Reduce Motion skips ambient automatic scenarios;
that is recorded as incomplete, never passing.

Tactile A/B/C use intensity scales 0.5/0.75/1, thresholds 0.5/0.25 and a 60–120 BPM
mapping. Each plays three seconds of initial rhythm, three seconds of acceleration,
then an independent accent and two seconds before stopping. The physical ceiling
is twelve seconds. At initial scripted suspense 0.5 the mapping yields 90 BPM;
this is a relative low-tension comparison, not a physiological resting-pulse claim.
The initial v1 user report found A's rhythm indistinguishable. In the later
[v2 device report](../ReleaseEvidence/spec-0013/2026-10-21-tactile-iphone17pro/README.md),
the same holder rated all three variants distinct and comfortable on iPhone 17 Pro,
and confirmed background stop/no replay. Both observations are retained. Preferred
variant and system Reduce Motion remain unrecorded in that export. Production
policy defaults and immutable fixtures were not retuned.

Each completed variant requires separate rhythm, acceleration, accent and comfort
ratings. Choose a preferred variant after rating it. Interrupted variants cannot
receive a completed rating. For background, start the dedicated button and leave
while vibration is active, then return and record stop/no-replay. For accessibility,
turn on the actual system Reduce Motion setting, return, and run its check.

## Reproduction

From the repository root, with the example project's signing team available:

```sh
# Builds only; embeds a fingerprint of the actual compiled sources/resources.
python3 Tools/DeviceEvaluation/run.py build

# DEVICE_ID comes from xcrun devicectl list devices.
python3 Tools/DeviceEvaluation/run.py install --device DEVICE_ID

# Optional automated start; opening the app normally remains idle.
python3 Tools/DeviceEvaluation/run.py run --device DEVICE_ID
# Add --quick to omit the five-minute load.

# Use a fresh output filename; collection does not overwrite old evidence.
python3 Tools/DeviceEvaluation/run.py collect --device DEVICE_ID --output /private/tmp/device-run.json
python3 Tools/DeviceEvaluation/summarize.py /private/tmp/device-run.json \
  --build /private/tmp/qualiakit-device-evaluation-v2-build/device-build.json \
  --require-complete --output /private/tmp/device-summary.json
```

The build is Release arm64 with `SWIFT_DEFAULT_ACTOR_ISOLATION=nonisolated` and
explicit MainActor UI/renderer isolation. The runner records toolchain, SDK,
source hashes, executable SHA-256 and build settings in `device-build.json`. The
embedded identity survives launches from the home-screen icon. Build fails if
sources drift during compilation. Keep the build record beside collected reports.
`source_identity.py --json` lists the exact inputs; generated identity JSON itself
is excluded to avoid circular hashing.

The app stores every run under `Documents/DeviceEvaluationRuns/<runID>.json` and
updates `Documents/device-evaluation.json` as the latest snapshot. Manual ratings
stay attached to their trial/run. Existing v1 reports are archived before replacing
the latest snapshot. Share the current JSON using **Экспортировать текущий отчёт**.
A new launch restores the last v2 record; a process killed mid-run is marked
interrupted. New full runs allocate new IDs; partial/failed runs remain in history.
Restoring a report preserves its renderer command trace and completed ratings
without replaying effects. The run mode and current automatic phase are saved
before each stage, so an interrupted quick run is distinguishable from a full run.

`summarize.py` validates distributions against raw samples, source/build identity,
required stages, physical metadata and ratings. `--require-complete` exits nonzero
for any missing step. A complete device suite still does not approve narrative
semantics or establish a population-wide UX claim.
An empty renderer trace is an explicit blocker even when all check flags say passed.

## Power profiling and simulator checks

For a separate instrumented power run (six-minute trace):

```sh
python3 Tools/DeviceEvaluation/run.py profile --device DEVICE_ID --output /private/tmp/qualia-power.trace
```

This launches the full suite under Instruments' Power Profiler. Profiling requires
device/toolchain support and can add timing overhead; retain the trace separately
from the uninstrumented baseline and review its power/thermal timeline. The runner
propagates an unavailable template/service error. The v2 implementation has not
claimed a completed physical power trace. In-app CPU time and thermal state are
not watts, joules or battery-drain measurements.

The simulator-only `--device-evaluation-self-test` exercises three state/context
baselines, real public Core ML inference, a five-second fixture load and report
persistence. Apple sentiment assets were unavailable in the tested simulator,
so Apple measurements are explicitly omitted in this mode. Hardware checks are
also explicitly omitted, and `physicalDevice` is false. The release gate rejects
these results. Build with `run.py build --simulator-build --build-dir <directory>`.
`check_restoration.py --app <built-simulator-app>` creates and removes a disposable
simulator, checking two launches each for interrupted automatic, completed, and
interrupted Russian reports. Its synthetic fixtures are software checks only.

## Methodology and limits

- Baseline v2 has three repetitions in **one process**; do not compare its first-call
  timing to the v1 fresh-process baseline as an equivalent cold-load measurement.
- Apple groups repeat fixed repository-authored English texts of 49, 488 and 1,952
  UTF-8 bytes. Each has 20 warmups and 200 samples spanning `analyze`, including
  validation/scheduling. This is not a varied accuracy corpus or isolated inference.
- State/policy and context-window groups have 100 warmups and 1,000 samples each.
  They exclude rendering. Policy state persists between steps. A consumed checksum
  prevents discarding results. One request is in flight at a time.
- Public Core ML has 20 warmups and 200 samples per stage, CPU-only. The runtime's
  existing timing callbacks are used. Initial load includes validation, snapshot,
  compilation and loading; compilation is additionally reported separately. OS
  caches are uncontrolled. The tiny arithmetic model does not represent a real
  language model's size, latency or semantic quality.
- Percentiles use nearest rank. Keep per-run distributions and maxima; regression
  limits require a reviewed device/load matrix, not a threshold invented from one
  phone. Renderer dispatch is synchronous call duration, not actuator onset.
- Memory footprint/peak are whole-process measurements, including UI. Baseline
  peak is sampled before haptics; sustained footprint samples cover the load stage.
  No isolated-model or entire-process-final-peak claim is made.
- Semantic evaluation uses separate annotated datasets and model prediction
  exports; see [SemanticEvaluation.md](SemanticEvaluation.md). Protected legacy
  assets and unknown labels are not converted into narrative evidence.

The [v1 iPhone 17 Pro baseline](../ReleaseEvidence/spec-0013/2026-10-21-iphone17pro/README.md)
is preserved unchanged as historical evidence, including the distinguishability
failure at 50% intensity and successful background behavior.
