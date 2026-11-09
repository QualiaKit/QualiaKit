# Programmatic and SwiftUI integration

`QualiaSession.process(_:)` is the authoritative integration API. The SwiftUI
modifiers are lifecycle adapters around a session that the application creates,
owns, and cleans up. Importing SwiftUI support does not create an analyzer,
renderer, model, network client, or global session.

## Accepted events

Use `qualiaReaction` only after the host has accepted a message, fragment, or
story event. The event ID is the SwiftUI task identity; keep it stable across
body recomputation and change it only for a new accepted event.

```swift
StoryView(fragment: acceptedEvent.fragment)
    .qualiaReaction(
        eventID: acceptedEvent.id,
        input: acceptedEvent.input,
        session: storySession
    ) { result in
        // MainActor: update UI state. CancellationError means the view task
        // was cancelled or superseded; other typed session errors stay intact.
        viewState.consume(result)
    }
```

SwiftUI cancellation is propagated into `session.process(_:)`. It complements,
but does not replace, the session generation checks that prevent stale analysis
from mutating scene state or rendering haptics.

The application must still call `suspend()`, `resume()`, or `reset()` at the
owning screen/room boundary. A modifier does not infer that lifecycle from a
transient child view.

## Opt-in typing preview

Live typing is deliberately a separate API. Give it a session dedicated to
preview so drafts cannot advance the production story scene.

```swift
TextField("Draft", text: $draft)
    .qualiaLiveReaction(
        text: $draft,
        debounce: .milliseconds(350),
        minimumCharacters: 3,
        session: previewSession,
        onResult: previewState.consume
    )
```

Draft inputs do not declare a language. The preview session must use a language
resolver that supports detection when language is absent. Debounce and minimum
character values are active configuration: negative values are rejected, blank
or shorter drafts are not submitted, and a superseded draft cannot reach the
session even if a custom test clock ignores cancellation.

Live preview sends user text to the explicitly installed analyzer after the
debounce interval. It is opt-in because that has privacy and performance cost.
The modifier never logs or persists the binding value.

## Immutable session configuration

The programmatic factory keeps the six configuration families separate from
runtime dependencies:

```swift
let configuration = QualiaSessionConfiguration(
    language: try QualiaLanguageConfiguration(
        policy: .requireExplicit,
        minimumConfidence: 0.8
    ),
    context: try QualiaContextConfiguration(
        maximumFragments: 0,
        maximumCharacters: 4_000,
        maximumUTF8Bytes: 16_000
    ),
    sceneState: .sentimentPreview,
    reaction: .sentimentPreview(.default),
    haptics: QualiaHapticConfiguration(
        preferences: userPreferences,
        arbitration: .independentOwners
    ),
    diagnostics: QualiaDiagnosticsConfiguration(sink: redactedSink)
)

let session = try await QualiaSession.configured(
    analyzer: analyzer,
    renderer: renderer,
    configuration: configuration
)
```

`configured` also accepts an explicit language detector and clock. No supplied
value is advisory: language, context, reducer, policy, preferences, arbitration,
diagnostic sink, detector, and clock are all installed in the resulting session.
Invalid values and incompatible analyzer/policy/renderer combinations fail before
the factory returns.

`QualiaSession.sentimentPreview` requires a valence analyzer and haptic renderer.
`QualiaSession.horrorNarrative` requires the narrative signals and haptic features
validated by `HorrorNarrativePolicy`. For analysis-only behavior, use
`configured` with `.noReaction` and an explicit `NoOpHapticRenderer`; the named
factories never silently degrade their advertised capability.

## Capabilities and accessibility

Read `await session.hapticCapabilities` before presenting device feedback state.
The session's stable `analyzerCapabilities` and privacy-safe
`analyzerDiagnosticIdentity` expose the analyzer state selected by the host. Use
`updateHapticPreferences(_:)` for user-controlled enablement, reduced intensity,
continuous-effect permission, and maximum duration; do not recreate the session
for each control change.

For construction, lifecycle, renderer arbitration, and diagnostics, see
[Session](Session.md) and [Diagnostics and privacy](DiagnosticsAndPrivacy.md).

## Migration from the legacy modifier

The legacy `.qualiaFeedback(trigger:)` and its implicit environment client were
removed. Replace accepted story/message handling with `qualiaReaction`, using a
stable host event ID and a host-owned session. Use `qualiaLiveReaction` only for
an explicitly chosen draft-preview experience, normally with a separate
analysis-only session. Move screen exit/background behavior to explicit
`reset()`, `suspend()`, and `resume()` calls on the owning session.
