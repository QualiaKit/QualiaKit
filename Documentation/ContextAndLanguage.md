# Language and context preparation — spec 0005, stage 1

The `QualiaKit` product provides model-independent language resolution and a
bounded context window. `QualiaInputPreparer.prepare(_:for:)` composes these
steps and checks analyzer capabilities before the host calls `analyze(_:)`.
Integration is covered with a private fixture analyzer in
`ContextAndLanguageTests`. No model or session is needed for this stage.

## Language policy

| Policy | Behavior |
| --- | --- |
| `requireExplicit` | Requires `input.language`; otherwise throws `languageUndetermined`. Never invokes detection. Analyzer capabilities determine supported languages. |
| `detect(allowed:)` | Detects current text, even when an explicit hint is present. Requires an allowed, sufficiently confident result. |
| `preferExplicitThenDetect(allowed:)` | Uses explicit language without detecting. A disallowed explicit language throws `unsupportedLanguage`; only an absent language triggers detection. |

The preparer rejects an explicit language outside analyzer capabilities before
any detection, including under `detect`. It also checks the resolved language
before windowing/inference. `detect` can replace a compatible explicit hint;
use `requireExplicit` or `preferExplicitThenDetect` for authoritative room language.
Language identifiers retain the existing exact, case-sensitive domain contract;
there is no region aliasing or automatic `en-US` → `en` conversion.

`QualiaLanguageResolver` requires a finite `minimumConfidence` in `0...1` and
nonempty detection allow-lists. Equality with the threshold is accepted. A nil
hypothesis or confidence below the threshold throws `languageUndetermined`;
a confident disallowed hypothesis throws `unsupportedLanguage`. No path chooses
English as a fallback. Explicit resolutions have nil confidence. The threshold
is unused by `requireExplicit`, but is still validated as configuration.

The default `AppleLanguageDetector` uses Natural Language on-device with a new
recognizer for each invocation. It reads **only current text**. It examines the
best unconstrained hypothesis, then the resolver checks the allow-list; it does
not force the detector to choose from that list or renormalize confidence.
Undetermined Apple results map to nil. Detector language availability and
confidence vary with OS and text; these are not model confidence or calibrated
quality guarantees. Callers can inject a `QualiaLanguageDetecting` implementation
for other on-device detectors or deterministic fixtures. Implementations must
support concurrent calls and return nil for unknown language.

## Generic context window

Configuration has no implicit product defaults:

- `maximumFragments >= 0` counts **historical** fragments; zero disables history.
- `maximumCharacters > 0` counts Swift `Character` values (extended grapheme
  clusters), separately per fragment and current text, then sums them.
- Optional `maximumUTF8Bytes > 0` bounds the sum of exact UTF-8 byte lengths of
  current text and history. Nil disables only this byte bound.

Supply history oldest to newest. The window drops complete oldest fragments
until **all** bounds hold. It keeps a contiguous newest suffix, with IDs and
Unicode representation unchanged; it does not skip a large recent fragment to
retain an older one. Empty historical fragments are legal and count toward the
fragment limit. Fragments are never joined, normalized or sliced. No separator,
special token, or model token estimate is charged to this generic budget.

Current text always has priority. If it alone exceeds a character or byte bound,
preparation throws `currentTextExceedsContextBounds` and returns no prepared input.
There is no silent current-text truncation or temporary limit exception. Invalid
configuration throws `invalidContextConfiguration`; unrepresentable aggregate
counts throw `contextSizeOverflow`. Counting visits the provided text; selection
is linear in fragment count and does not repeatedly remove from an array's front.
No p95 performance claim is made by these correctness tests.

Retained context is rejected with `unsupportedContext` if the analyzer declares
`acceptsContext == false`. A caller may explicitly configure zero history; the
preparer never changes the configured bounds to conceal incompatible capabilities.
Exact token budgeting and accepted input templates remain analyzer responsibilities.

## Composition before analysis

```swift
import QualiaKit

func analyzeAcceptedFragment(
    _ input: QualiaInput, // Host supplies authoritative room language and history.
    using analyzer: any QualiaAnalyzing
) async throws -> QualiaObservation {
    let resolver = try QualiaLanguageResolver(
        policy: .requireExplicit,
        minimumConfidence: 0.8
    )
    // Example host choices, not calibrated defaults. Use zero history for a
    // single-fragment analyzer such as the current Core ML fixture profile.
    let window = QualiaContextWindow(configuration: try QualiaContextConfiguration(
        maximumFragments: 6,
        maximumCharacters: 16_000,
        maximumUTF8Bytes: 64_000
    ))
    let preparer = QualiaInputPreparer(languageResolver: resolver, contextWindow: window)
    let prepared = try await preparer.prepare(input, for: analyzer.capabilities)
    return try await analyzer.analyze(prepared)
}
```

The immutable components may be reused across concurrent requests. The preparer
runs synchronous resolution/windowing off MainActor and propagates cancellation
around each stage and before returning. It cannot preempt a synchronous detector
already executing, but its result cannot escape after cancellation. Direct
`resolve(for:)` and `window(_:)` are synchronous; their caller owns scheduling.
The host still owns analyzer output validation, request ordering and lifecycle
until the session integration in 0010.

## Diagnostics and privacy

Optional `@Sendable` sinks receive `QualiaPreparationDiagnostic` values from the
resolver, window, or preparer. Use the same sink on all three for a full trace.
There is no default logging or persistence. Sinks must handle concurrent calls.
Events carry policy/source, confidence relative to the configured threshold,
resolution outcome, before/after fragment/character/byte counts, and typed
analyzer rejection. A failed oversized-current window reports unchanged counts
and `currentTextTooLarge`, not a successful trimmed input.

The event schema contains no strings, input IDs, fragment IDs, language raw
values, text, or arbitrary backend errors. Model token/template diagnostics are
deferred with their integration. Components retain configuration and dependencies,
not prior inputs; each request supplies its own history. Caller-provided detectors,
resolvers, windows and sinks are responsible for honoring the same privacy contract.

## Evidence and remaining scope

| Spec requirement / acceptance | Evidence or remaining work |
| --- | --- |
| AC-0005-005, language branches, thresholds, allowed languages, no English fallback | `ContextAndLanguageTests`: deterministic detector fixtures plus Apple detector smoke coverage |
| AC-0005-001, unsupported English before Russian-only analysis | Fixture analyzer is never invoked, for every policy; no fallback analyzer is constructed |
| AC-0005-004, generic bounds/current priority/Unicode/diagnostics | Exact count/byte boundaries, newest suffix, oversize rejection, text-free event payloads |
| Concurrent preparation and cancellation | Shared preparer requests; cancellation before/during detection; off-main execution |
| AC-0005-002, **model token** current-text priority | **Pending** model/tokenizer integration; generic-window tests do not complete this criterion |
| AC-0005-003 / QK-CTX-006, **`QualiaSession.reset()`** privacy | **Pending** real session implementation and memory/lifecycle tests in 0010; stateless preparer reuse is not a reset test |
| Russian model migration, exact tokenizer parity, Core ML `pair`/`formatted` | **Pending**; outside this stage |
| Flagship room-language source, accepted/live-preview ownership, legacy pipeline migration | **Pending** host/session and legacy migration scopes |

This PR completes only the first independent stage, not all of spec 0005.
The existing model contract, legacy `Qualia`/`QualiaBert`, and the separate
`QualiaCoreML` package keep their existing integration paths.

Verification: `swift build`, `swift test --filter ContextAndLanguageTests`,
`swift test`, strict-concurrency `QualiaKit` build, and iOS Simulator build.
The existing protected model evidence verification remains applicable.
