# Diagnostics, privacy and haptic preferences (0012)

The `QualiaKit` session pipeline now has one injectable diagnostics boundary,
redacted runtime failures, and an enforced user-preference snapshot. Diagnostics
are disabled by default. Neither `QualiaKit`, `QualiaTesting`, nor the optional
`Packages/QualiaCoreML` product includes networking or an analytics transport.
A host may deliberately supply a remote analyzer or a sink with its own storage;
that behavior belongs to the host's privacy policy.

## Data flow and lifetime

```text
Host input (ID, text, optional language)
  → session: bounded, memory-only accepted history
  → worker: language resolution and bounded context
  → analyzer: on-device Apple NLP / optional local Core ML / host adapter
  → observation: semantic values and analyzer provenance
  → reducer and policy: numeric state → owned haptic commands
  → MainActor renderer: bounded physical playback

All layers → redacted values → injected diagnostics sink
                               ├─ NoOp: no storage or transport (default)
                               ├─ OSLog: opt-in, private local log payload
                               └─ host sink: explicit host retention/transport
```

Reset invalidates pending work, releases session-owned context and stops owned
ambient and accent players. Suspend retains bounded context and stops playback;
resume requires fresh input. A cancellation-ignoring external analyzer may still
retain the input it received until its invocation finishes. Releasing ownership
is not a promise of cryptographic erasure of every memory copy. The Core ML
adapter snapshots **model assets**, never input text, in a temporary directory
and removes that snapshot on teardown. Framework caches are platform-owned.

## Safe diagnostics

Pass `diagnostics:` to `QualiaSessionDependencies`. `QualiaDiagnosticEvent` has a
versioned schema, with session-generated UUID and generation on `.correlated`
events. Session-only events from 0010 are also emitted for compatibility;
consumers needing multi-session correlation should select `.correlated` events.
`QualiaSessionDiagnostic` remains a typealias. The event schema contains closed
cases, counts, durations, capabilities and SHA-256 fingerprints of metadata.

Events cover installation, lifecycle, analysis success/failure, language,
context truncation, observation counts, scene revisions, policy rule, command
result, cancellation, stale discard, suppression and separate timing stages.
Signal scores are deliberately omitted from standard diagnostics. Raw input,
input/owner IDs, model tensors, policy facts and framework error dumps are never
copied into events. The model adapter's shared sink includes model/contract
versions, load stages and token/truncation **counts**. `FallbackAnalyzer` accepts
the same sink and records an explicitly selected fallback without modifying the
semantic observation. Supply the sink to nested adapters/resolvers when their
own operational detail is wanted; session context-window events are wired by
the session automatically while preserving an existing window callback. Avoid
wiring that callback to the same sink twice if duplicate detail is unwanted.

`QualiaDiagnosticIdentity` hashes identity and version separately. Compare it
with an expected installation identity to trace versions without exposing
arbitrary host strings. Built-in analyzers/policies provide `diagnosticIdentity`;
custom adapters should supply an immutable value. `nil` means the adapter has
not declared a version, not a fabricated version. Successful leaf analyzer
identity is also traced from its observation. These are hashes of **metadata**,
not text hashes or a device/user identifier. Do not treat hashing as a guarantee
that low-entropy metadata cannot be guessed.

```swift
let diagnostics = OSLogQualiaDiagnosticsSink() // Explicit local logging opt-in.
// QualiaSessionDependencies(..., diagnostics: diagnostics, clock: clock)

// For deterministic tests/debugging only:
import QualiaTesting
let recording = try RecordingQualiaDiagnosticsSink(capacity: 256)
// recording.entries / recording.droppedEventCount / recording.drain()
```

Sinks must support concurrent calls and return promptly, including when called
from an actor or MainActor. They must not wait on the session or perform
synchronous network I/O. Host queues must be bounded and document their drop
policy. The recording sink uses a short lock, fixed maximum capacity, monotonic
sequence numbers and **drop-newest** overflow. It stores only in memory. OSLog
marks the whole already-redacted payload private; it does not add an asynchronous
queue or a transport. No-op `emit` evaluates no event autoclosure; timing and
fingerprint construction are skipped when disabled. A host's blocking sink
cannot be made nonblocking by protocol conformance alone.

There is no raw-text logging feature, including in debug builds. Hosts that add
one must make it an explicit developer-build opt-in with a conspicuous warning;
it must never become a release default. Even redacted timing/language/semantic
metadata can be sensitive in some domains.

## Errors and migration

The public taxonomy adds model availability/manifest/compatibility,
tokenization/inference/output, configuration and haptic categories. Reasons use
`QualiaFailureReason`, a closed enum, rather than the illustrative `String`
signatures in the spec. `modelUnavailable` carries a metadata fingerprint.
Existing domain errors keep their direct-call signatures; descriptions omit
associated arbitrary language/identity strings. Session boundaries additionally
convert those payloads to safe categories/fingerprints:

| Before session boundary | Exposed by session |
| --- | --- |
| Unknown analyzer/framework error | `inferenceFailed(reason: .adapterFailure)` |
| `analyzerUnavailable(identity:)` | `modelUnavailable(identifier:)` |
| `invalidAnalyzerOutput(identity:)` | `invalidModelOutput(reason: .modelOutput)` |
| `unsupportedLanguage(...)` | `unsupportedLanguageIdentifier(...)` |
| Unknown preparation error | `invalidConfiguration(reason: .configuration)` |
| Unknown renderer error | Redacted haptic failure; no framework dump |
| `CancellationError` | `CancellationError`, not an inference failure |

Closed `HapticError` and `QualiaSessionError` categories remain recoverable.
Core ML errors conform to `QualiaErrorConvertible` so session mapping retains
model-stage categories. Diagnostic failures sanitize even host-provided typed
errors. Analyzer failure returns no observation and commits no state, history or
reaction. A renderer command failure retains the accepted semantic response and
reports its failed command. Playback is latched off until an explicit successful
reset/preference update; repeated observations never retry vibration implicitly.
Cleanup can still be retried explicitly even while playback is suppressed.

The legacy `Qualia` / `QualiaBert` products are the frozen pre-2.0 path and are
not the session API described here. Their model-contract archaeology, neutral
fallbacks and legacy logging are not new privacy guarantees. They are no longer
used by the official example or recommended in the README. Their protected
model behavior and immutable audit inputs remain unchanged. Use `QualiaKit` for
new integrations; SwiftUI convenience migration is specification 0011.

## Accessibility and lifecycle

`QualiaHapticPreferences` defaults: enabled, continuous allowed, intensity 1,
maximum continuous duration **30 seconds**. Duration must be positive and no
more than one hour; the default and this absolute validation ceiling are
provisional safety choices, not calibrated sensory recommendations. Built-in
heartbeat also obeys its smaller policy limit.

```swift
try await session.updateHapticPreferences(.disabled)
try await session.updateHapticPreferences(try .init(
    enabled: true,
    continuousEffectsEnabled: false,
    intensityScale: 0.35,
    maximumContinuousDuration: .seconds(5)
))
let capabilities = await session.hapticCapabilities
```

Every preference update invalidates queued analysis and stops all this session's
players immediately, even for a reduction in intensity or duration. It preserves
semantic history and suspend intent. Fresh accepted input is required to restart.
A failed stop leaves cleanup required and prevents processing until explicit
recovery. A host-wide switch must apply the same disabled snapshot to **every**
owned session; one session never stops another owner's effects.

The final executor boundary enforces these settings even for a host policy that
ignores them: global disable/zero intensity suppress all playback; continuous
disable suppresses ambient starts/replacements and continuous accents, while
allowing transient accents. Built-in policies multiply their mapping by the
intensity scale; final validation also caps custom event/curve intensity at that
scale. Replacement cannot extend the original physical deadline. Native Core
Haptics schedules the stop on its player, independently of another observation.
After a custom ambient segment physically completes at its deadline, the
executor removes its applied state before planning the next observation. A new
segment can start without an invalid replacement or suppression of accents.
The recording renderer tests descriptors; it does not emulate time passing.

Call `suspend` for background/navigation/interruption and `reset` when leaving
or replacing a sequence. Engine interruption/reset stops native players and
never automatically retries a failed heartbeat. The sample uses ordinary
SwiftUI lifecycle hooks around the programmatic API; this does not introduce
the reusable SwiftUI integration from 0011. It shows unavailable hardware,
provides enable/continuous/intensity/duration controls, and uses on-device
`AppleSentimentAnalyzer`. The author-app adoption remains specification 0013.

## Model provenance, privacy manifests and prohibited use

The published synthetic Core ML **test fixtures** include SHA-256, generated
provenance and MIT license metadata. They are not evaluated language models.
The current Russian model has unresolved provenance/license and remains blocked
for redistribution; see [its model card](../Models/current/MODEL_CARD.md).
No asset downloads or new model redistribution are introduced here.

The sample includes `PrivacyInfo.xcprivacy` declaring no tracking/collection.
Source review found no direct required-reason API in the 2.0 products after
replacing the model worker's system-uptime reads with `ContinuousClock` elapsed
measurements. No boot epoch or file timestamp is read. Consequently no additional
SDK required-reason entry is declared for this implementation. This is a
source-level audit, not an App Store archive attestation. Check the final host
archive and toolchain when adding APIs, persistence, a new SDK or a transport;
Apple maintains the [required-reason API categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

QualiaKit describes content and a desired reader experience. It must not be used
to diagnose health conditions, measure real fear, infer a person's mental state,
score people, or make employment, insurance, education, credit or similar people
decisions. A text signal is not evidence of a user's emotion, psychology,
biometrics or health. Device sensations and preferred intensities vary.

## Verification and evidence

| Requirement / acceptance criterion | Evidence |
| --- | --- |
| AC-0012-001, QK-DIA-003 | Analyzer-error fixture preserves active heartbeat, scene and history; NSError/language/identity redaction scan |
| AC-0012-002 | Active heartbeat stops immediately; pending analysis is discarded; disabled custom policy cannot play; re-enable requires fresh input |
| AC-0012-003, QK-PRV-001/003 | Source/dependency audit test checks the 2.0 products, diagnostics persistence and sample manifest |
| QK-PRV-002/007, QK-DIA-007 | Event schema scan, malicious metadata fixtures, Core ML truncation-count event, fallback-selection test |
| QK-PRV-004 | 0010 weak context-lifetime/reset tests and bounded-history tests remain in the full suite |
| QK-PRV-005/006 | Existing checksummed fixture manifests/model card; prohibited-use and data-flow review above |
| QK-DIA-001/002/005/006 | No-op laziness, injected sinks, model/policy/runtime fingerprints, capability/suppression tests |
| QK-DIA-004 | Separate caller cancellation and superseded-result events; existing session admission/commit regression suite |
| QK-PERF-001 | Session detached-worker assertion and Core ML off-main, serialized inference tests |
| QK-PERF-002 | 100-call fixture measures preparation plus state/policy separately from inference and dispatch; logs local p95 |
| QK-PERF-003 | Concurrent 1,000-call bounded recorder test; no-op has no buffer; documented host/OSLog boundary |
| Haptic safety | Custom-policy intensity ceiling and replacement deadline; cleanup-failure gate; no retry; existing interruption/owner-isolation tests |

Required commands: `swift build` and `swift test --filter DiagnosticsAndPrivacyTests`.
Also run the full root suite, strict-concurrency build, optional Core ML suite and
the sample simulator build. The local fixture target is non-model p95 ≤ 5 ms;
this measurement includes preparation's worker scheduling but excludes model
inference. Dispatch timing measures the synchronous command batch, not a promise
about MainActor contention or physical onset. Physical accessibility calibration,
frame-budget measurements on supported devices and host archive review remain
release validation, not claims established by a desktop fixture.

### Local verification record — 2026-09-14

The required build and 14 `DiagnosticsAndPrivacyTests` passed on the local
macOS/Xcode toolchain. The 100-call diagnostic fixture measured non-model p95
around 0.02 ms and synchronous dispatch p95 below 0.001 ms in a debug build.
100,000 no-op calls took about 9 ms in that debug run; event construction stayed
unevaluated. These are local regression measurements, not device release budgets.
The optional Core ML suite includes 22 passing tests and the sample builds for
both iOS Simulator architectures. The protected-model evidence verification
continues to pass with its original inputs unchanged; model-dependent tests in
the root suite skip when protected assets are absent.
