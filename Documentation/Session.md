# QualiaSession — model-independent orchestration (0010)

One `QualiaSession` actor owns one accepted-fragment sequence: bounded history,
semantic scene state, generation, current analysis task and an owned reaction
executor. Dependencies are explicit; nothing selects a model, translates text,
substitutes neutral on error, or starts a hidden fallback analyzer.

## Programmatic use

```swift
import QualiaKit

@MainActor
func makeSession(analyzer: any QualiaAnalyzing) async throws -> QualiaSession {
    let clock = QualiaContinuousClock()
    let diagnostics = NoOpQualiaDiagnosticsSink()
    let resolver = try QualiaLanguageResolver(
        policy: .requireExplicit, minimumConfidence: 0.8,
        diagnostics: { diagnostics.record(.preparation($0)) }
    )
    let window = QualiaContextWindow(
        configuration: try QualiaContextConfiguration(
            maximumFragments: 6, maximumCharacters: 16_000, maximumUTF8Bytes: 64_000
        ),
        diagnostics: { diagnostics.record(.preparation($0)) }
    )
    // Share this coordinator across sessions targeting the same renderer.
    let renderer = QualiaSessionRenderer(
        renderer: CoreHapticRenderer(), arbitration: .exclusiveAmbient
    )
    return try await QualiaSession(dependencies: QualiaSessionDependencies(
        analyzer: analyzer, languageResolver: resolver, contextWindow: window,
        stateReducer: QualiaSceneReducer(), reactionPolicy: HorrorNarrativePolicy(),
        diagnostics: diagnostics, clock: clock
    ), renderer: renderer)
}

func acceptFragment(_ session: QualiaSession, id: String, text: String,
                    roomLanguage: QualiaLanguage) async throws -> QualiaResponse {
    let input = try QualiaInput(id: QualiaInputID(rawValue: id), text: text,
                               language: roomLanguage)
    return try await session.process(input)
}

// Host navigation/background lifecycle:
// try await session.suspend()
// try await session.resume()  // Permits fresh input; never replays old effects.
// try await session.reset()   // Required when leaving/replacing the sequence.
```

Limits above are example host choices, not calibrated defaults. The selected
analyzer must advertise the policy's required signals. Use a compatible policy
such as `NoReactionPolicy` and an explicitly injected `NoOpHapticRenderer` for
analysis-only use. Use `maximumFragments: 0` for a context-disabled analyzer.
Policy compatibility and renderer preparation are validated during initialization.
Positive history capacity with a context-disabled analyzer is also rejected at
setup, before the first request can appear to work and fail on the next fragment.

`QualiaResponse` exposes observation/provenance, previous/current transition and
fresh evidence, intended reaction plan/rationale, and execution summary. The
summary lists attempted commands in order, typed outcomes, total planned command
count and reconciled applied reaction state. Commands after a failure are not
attempted. A renderer failure **returns the successful semantic response with
`execution.failure` set**; it does not roll back scene state or accepted context.
The existing heartbeat failure latch prevents automatic replay/retry storms.
Invalid analyzer output, preparation errors and invalid reducer/ownership output
throw before commit. There is no response containing an invented neutral result.

## Ordering and the commit boundary

Every admitted `process` starts a newer generation and cancels the previous
analysis task. Preparation/inference run outside the session actor and MainActor;
the owned task captures dependencies and input, not the session. The analyzer
contract validates input compatibility and output ID/language/capabilities.

Cancellation alone is insufficient. The session checks generation after analysis,
then an explicit MainActor coordinator checks it again immediately before the
commit. Pure reduction, policy evaluation/reconciliation, and the synchronous
command batch are one commit operation. There is no await between that final
check and dispatch. Reducer time is sampled from the injected monotonic clock at
dispatch; clock regression and a reducer transition with the wrong previous state
or instant fail with typed session errors.

A small lock-protected gate connects the session actor to MainActor. It never
holds a lock across await. MainActor leaves one immutable commit receipt; the
actor absorbs it before its next state read or admitted operation. Admission
checks the latest accepted ID and context under the gate lock, using an
unabsorbed receipt when present. Only successful admission drains that receipt,
starts another generation and invalidates old work.
This prevents both gaps: an old result waiting for MainActor cannot mutate state,
and a command batch already committed cannot be forgotten if the actor receives
the next request before the prior `process` returns.

Each request has a separate cancellation signal. Claiming commit and cancelling
a pending request are mutually exclusive transitions under that signal's lock,
which is released before reduction, policy or renderer code runs. The cancellation
handler never acquires the gate lock, including when a renderer synchronously
calls the process task's `cancel()` from inside its command callback.

Cancellation or reset **before** commit is claimed prevents state/context mutation
and all commands. Cancellation **once commit is claimed** cannot undo an accepted event;
`process` returns that committed response, even if its return was delayed.
Similarly, a pre-reset committed response can arrive after reset; it never
reinstalls that response's state or effects. Hosts must use their own UI/navigation
identity when deciding whether to display a returned result on a different screen.

Custom reducers and policies must be pure and bounded. Renderer methods are
synchronous on MainActor. They must not synchronously wait on the session from
inside dispatch. Diagnostics execute outside the gate. No non-model p95 target
is claimed from correctness tests.

## Context and accepted-event semantics

`process` represents an accepted fragment, not a live typing preview. Session
history is authoritative: nonempty caller `input.context` throws
`externalContextNotSupported`, rather than merging or silently discarding it.
The concrete `QualiaContextWindow` dependency exposes the exact configuration
used for both inference input and retained storage.

Language resolution and generic bounds follow [0005](ContextAndLanguage.md).
After a successful commit, current text becomes the newest historical fragment;
the retained suffix fits the fragment, Character and UTF-8-byte bounds. Current
text has priority. History is appended on semantic acceptance even if physical
execution fails. Analyzer failure, cancellation and rejected dispatch never append.
There is no second model-token count or context-template implementation here.

An ID matching the last accepted event or an event still in bounded history
throws `duplicateInput` without invalidating or cancelling another request in
flight. This also applies to events committed on MainActor whose response has
not yet returned to the session actor. In-flight revisions of an unaccepted ID can supersede
each other. Deduplication is bounded: an ID older than the retained window may
be accepted again; with zero history only the last accepted ID is remembered.
Reset clears this memory and permits reuse. Global deduplication and preview/edit
replacement semantics are outside this accepted-event profile.

Snapshots expose numeric scene state, lifecycle and retained counts, never text
or IDs. Reset releases session-owned context storage. It cannot revoke a copy of
input already handed to an external analyzer that ignores cancellation, or to
the caller; that analyzer's privacy/cancellation contract still applies.

## Lifecycle and shared rendering

- `reset() async throws` invalidates work first, immediately clears context,
  accepted IDs and semantic state, then stops owned playback. It preserves the
  suspended/active intent. Repeating reset is safe.
- `suspend() async throws` invalidates work, stops owned playback and rejects
  processing with `suspended`. It retains bounded context and semantic state.
- `resume() async throws` retries owned cleanup and renderer preparation, then
  allows new processing. Resume after a long pause does not replay effects;
  the next fresh observation advances reduction against the monotonic clock.
  Repeating resume on an active session is a no-op.
- Cleanup failure is observable and leaves `cleanupRequired`; process is blocked
  until a successful reset/resume retry. Lifecycle transitions reject process
  with `lifecycleTransitionInProgress`. Concurrent lifecycle requests use the
  same generation rule; a superseded operation throws `CancellationError` and
  cannot complete or alter the newer lifecycle state. Caller cancellation does
  not skip required cleanup.

Use one `QualiaSessionRenderer` coordinator for a shared physical renderer.
Each session receives a generated unique owner and separate reaction state.
Choose arbitration explicitly: `independentOwners` lets owned ambient descriptors
coexist; `exclusiveAmbient` rejects a conflicting start/replace with
`ownershipConflict` in the execution summary. It never stops or preempts another
owner. Neither choice promises simultaneous perceptual mixing on every device.

Session lifecycle never invokes global renderer `suspend`, `resume`, `stopAll`
or `stopChannel`. Device/engine lifecycle remains coordinated by the host across
all sessions: suspend affected sessions before global engine shutdown, recover
the renderer, then resume those sessions. No automatic UIKit/SwiftUI notification
bridge, room navigation or deinit cleanup is installed by this stage. Call reset
before dropping a session; asynchronous resource cleanup is an explicit lifecycle.

The new `HapticRendering.execute(_:ownedBy:)` envelope extends ownership to accents.
`CoreHapticRenderer` tracks owner on playing one-shots and pending rollback players,
so reset covers them even when `activeEffects` is empty. Recording entries expose
the supplied owner (one-shots are instantaneous in the recording renderer).
Custom renderers must implement this envelope to support session-owned accents;
the default supports validated owned ambient commands and rejects one-shots with
`ownershipConflict` until tracking is implemented. Direct unscoped renderer calls
keep their previous behavior. Global/foreign commands from a custom session policy
are rejected before any command or semantic commit.

## Diagnostics and evidence

Optional `QualiaDiagnosticsSink` events carry lifecycle, generation, failure or
discard stage, revision, command counts and typed haptic failure. Reuse the sink
on language resolver and context window to collect their detailed 0005 events.
The default sink does nothing. Session events contain no arbitrary strings,
text, input/owner IDs or custom error descriptions. Runtime profile is
`QualiaSessionDiagnostic.runtimeVersion`; analyzer identity and policy version/
configuration rationale remain available in the structured response. A general
diagnostic export/versioning framework remains its own integration scope.

`swift test --filter SessionOrchestrationTests` covers:

| Criterion | Deterministic evidence |
| --- | --- |
| AC-0010-001: N+1 before N | Both cancellation-respecting and cancellation-ignoring fixtures; MainActor barrier before dispatch; neither stale state nor stale commands |
| AC-0010-002: reset during work | Preparation, inference, before dispatch and after commit/before return; semantic reset, scoped cleanup, no restart |
| AC-0010-003: independent sessions | Shared fixture analyzer and recording renderer; A reset preserves B state, context and effects; explicit conflict policy |
| AC-0005-003 / QK-CTX-006 | Real `QualiaSession.reset()` releases retained storage (weak lifetime assertion), clears counts/state and sends no old context to subsequent inference |
| Duplicate admission | Repeating A while B runs leaves B able to commit with either analyzer cancellation behavior; unabsorbed receipts and evicted IDs use the latest accepted window |
| Physical rollback cleanup | Injected Core Haptics backend starts playback then fails start/rollback; owner-only reset clears ambient and accent pending cleanup, preserving the other owner's player |
| Failure and cancellation semantics | Typed analyzer/reducer/configuration/clock errors, cancellation before dispatch and synchronously inside renderer execution, partial renderer batch failure, cleanup retry, concurrent lifecycle requests |
| Memory/privacy | No idle session retain cycle; bounded Unicode history; diagnostics schema excludes text/IDs |

Core ML attachment after parity, Russian model migration, new tokenizers,
`pair`/`formatted`, UI lifecycle adapters and legacy migration are not part of this
rollout. AC-0005-002 (exact **model-token** current-text priority) remains open.
Physical calibration remains the release gate from 0009/0015.
