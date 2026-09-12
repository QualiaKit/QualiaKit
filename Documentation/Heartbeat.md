# Adaptive heartbeat (spec 0009)

The `QualiaKit` product now plans a double-beat ambient heartbeat through
`HorrorNarrativePolicy`. It receives numeric scene state and fresh evidence,
never text or model labels. It does not measure or simulate the reader's pulse.

## Candidate behavior

`HorrorNarrativePolicy.version` is `1.0.0-beta.3` and the physical mapping/defaults
are `HeartbeatPolicyConfiguration.version == "heartbeat-candidate-v1"`.
These are deterministic evaluation values, **not device-calibrated release defaults**.

| Setting | Candidate value |
| --- | --- |
| Tension | `max(suspense, 0.8 * threat, 0.6 * urgency)` from advertised scene signals |
| Start / stop | `0.85` / `0.50` |
| Start evidence | Present, positive driving-signal evidence with confidence `>= 0.70` |
| Curve | `smoothstep(t) = t * t * (3 - 2 * t)` |
| BPM | `64 + 44 * smoothstep(t)` |
| First-beat intensity | `(0.15 + 0.5 * smoothstep(t)) * configurationScale * preferenceScale` |
| Second beat | At `0.25 * cycle`, intensity `0.7 * firstBeat` |
| Sharpness | `0.20` |
| Meaningful update | At least `4 BPM` or `0.05` intensity, or changed user scale |
| Minimum update interval | `500 ms` |
| Maximum segment / cooldown | `12 s` / `2 s`; no automatic renewal |
| Resolution | Up to `300 ms` of weaker pulses, then stop |

The highest weighted accumulated signal is the driving signal; ties use
suspense, then threat, then urgency. Confidence is read only from that signal
in the current transition's evidence. Missing evidence, missing confidence,
explicit zero, and unrelated confidence cannot start a heartbeat. Thresholds
below the defaults can be evaluated with a custom configuration.

Running playback compares parameters with the last successfully applied
pattern. It does not recreate players for insignificant changes. Replacements
carry only the original segment's remaining duration. Resolution is irreversible
until cooldown finishes. A later observation advances all elapsed deadlines in
one evaluation: if the segment and its cooldown have both ended, fresh evidence
can start a new segment immediately, without an extra observation. Disable,
background and reset stop immediately rather than waiting for the update interval or resolution tail. Accents remain one-shot
commands on the independent accent channel.

`HeartbeatParameters` validates BPM in `55...120`, second-beat ratio in
`0.18...0.35`, and normalized `HapticValue` intensity/sharpness. The pure
`HeartbeatPatternFactory` returns exactly two transients and a loop period of
`60 / BPM`. Every heartbeat pattern has a positive `playbackDuration`.
`CoreHapticRenderer` schedules its physical stop using Core Haptics'
[`stop(atTime:)`](https://developer.apple.com/documentation/corehaptics/chhapticpatternplayer/stop(attime:)),
so an absent next observation cannot produce indefinite playback. Completion
removes only the matching player; an old player's callback cannot remove its
replacement. Bounded effects are never restored after an engine reset, including
explicitly global effects.

## Host integration and lifecycle

For accepted-fragment processing, prefer the model-independent
[QualiaSession](Session.md), which integrates preparation, analyzer validation,
state reduction and this executor. The lower-level API below remains available
for hosts that intentionally own the entire orchestration boundary.

`QualiaReactionExecutor` is a narrow MainActor execution boundary. When using it
directly, analyzer, context and reducer orchestration remain host responsibilities.
Use one executor and one stable `HapticOwnerID` per session. A shared
renderer is supported; owner lifecycle stops do not stop another owner's effects.

```swift
import QualiaKit

// On MainActor, during setup:
let renderer = CoreHapticRenderer()
let owner = try HapticOwnerID(rawValue: "reader-scene")
let policy = HorrorNarrativePolicy()
try policy.validate(
    analyzerCapabilities: analyzer.capabilities,
    hapticCapabilities: renderer.capabilities
)
try renderer.prepare()
let executor = QualiaReactionExecutor(renderer: renderer, owner: owner)
let clock = ContinuousClock()
let origin = clock.now

// Before asynchronous analysis, capture a token on MainActor:
let request = executor.beginRequest()
// Host analyzes and reduces a successful observation to `transition`.
// On failure, propagate the error without submitting a transition.

// On MainActor, after successful analysis/reduction:
let plan = try executor.execute(
    for: transition,
    policy: policy,
    analyzerCapabilities: analyzer.capabilities,
    at: origin.duration(to: clock.now),
    request: request
)
// nil means the request was stale, consumed, foreign, or suspended.
```

The host must call `executor.suspend()` when backgrounding or interrupted,
`executor.reset()` on scene/renderer reset, and `executor.updatePreferences(_:)`
when controls change. These methods invalidate queued requests before stopping
owned effects, without an asynchronous gap. If the renderer itself needs
recovery, the host coordinates `prepare`/`resume` and then calls
`executor.resume()`. Resume never replays old effects. A new request with fresh
evidence is required. Reset before replacing a policy/configuration or owner.

Callers using pure `plan` directly must serialize generation validation and
command dispatch themselves. Commit `nextState` after successful execution and
use `reconciledStateAfterFailure` with the renderer snapshot after failure.
Custom `HapticRendering` implementations must implement
`stopEffects(ownedBy:)`. It must cover active and pending-rollback players,
including those absent from `activeEffects`, and throw until all of the owner's
cleanup succeeds. It must never stop another owner's players. The executor
uses this operation for reset, suspend and disabling preferences; it clears
state only on success. `RecordingHapticRenderer` records the owner stop as a
lifecycle event as well as the resulting commands.

Keep this reaction state opaque: reconstructing it from `activeAmbientEffects`
alone discards heartbeat timing, and the policy safely stops such restored
playback rather than assuming a new segment.

## Failure strategy and diagnostics

A failed start or replacement latches heartbeat suppression until explicit
reset, including failures that removed the old player. If the old pattern is
still physically playing, its original scheduled stop remains in force. A new
player can also start physically and then fail while scheduling its deadline;
if rollback fails, its pending-cleanup record retains the effect ID and owner.
An owner reset must stop that player, rather than assuming the deadline exists.
A successful ambient command followed by a failed accent retains the applied
ambient state. No automatic vibration retry is performed. Execution errors
remain visible as thrown typed renderer errors; the recording renderer also
records command outcomes and timestamps.

Decision rationale contains policy/curve version, lifecycle state, tension,
driving evidence/confidence when starting, physical parameters and the rule
(start, stable, throttled, resolving, cooldown, duration limit, or suppression).
It contains no raw text. `RecordingHapticRenderer.expireEffects()` advances
physical completion against its injected clock, without a synthetic observation.

## Migration from spec 0007

The generic continuous ambient vibration is replaced by heartbeat in the
`QualiaKit` product. Existing legacy `Qualia` APIs are unchanged.

- Move ambient settings to `HorrorNarrativePolicy.Configuration(heartbeat: ...)`.
  `HeartbeatPolicyConfiguration` replaces the old top-level start/stop thresholds,
  normalized update delta, intensity range, and static cycle duration.
- Update fixtures to include explicit fresh confidence when a heartbeat should
  start. High scene intensity alone no longer qualifies.
- Expect a finite resolution replacement before stop for falling tension;
  lifecycle/user-disable stops remain immediate.
- Default effect name changes to `qualia.horror-narrative.heartbeat`. Reset owned
  effects when changing policy versions; do not adopt old active effects as new.
- After renderer failure, retain reconciled state instead of discarding it to
  force a retry. Reset is the explicit recovery action.

## Release calibration: HG-0015-004 (pending)

Run these scripts on at least two iPhone generations with the same fixture
signals and monotonic timestamps. Record device, OS, policy/configuration version,
recognition, comfort, discontinuities, stop latency and participant stop requests.
Do not collect physiological measurements or infer a participant's emotions.
Stop on user request and respect disabled/continuous-disabled controls.

| Script | Inputs/actions | Expected behavior |
| --- | --- | --- |
| Recognition | Suspense `0.91`, confidence `0.9`, hold for one segment | Recognizable lub/dub; finite stop by 12 s |
| Threshold chatter | Start, then alternate `0.82` / `0.79` each second | Stable rhythm without repeated recreation |
| Adaptation | Start `0.91`, fall to `0.60` after 1 s, then rise | Bounded BPM/intensity, no deadline renewal |
| Accent overlap | During heartbeat, impact `0.95`, confidence `0.9` | Independent accent; heartbeat preserved |
| Resolution | Fall to `0.50` after 2 s | Weaker tail, stop within 300 ms, 2 s cooldown |
| Preferences | Compare full, half and reduced intensity; disable mid-cycle | Scaled intensity; immediate disable; no restart from queued input |
| Lifecycle | Background/reset/interruption during start and replace | Owned stop; no replay on resume |
| Quiet input | Start and submit no further text | Physical stop by maximum segment duration |

No physical-device result is claimed by this PR. Recognition, comfort, energy,
and replacement continuity must be approved at the release gate before promoting
these candidates to release defaults.
