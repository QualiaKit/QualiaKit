# Getting started

Choose **SentimentPreview** to integrate a real English valence baseline without
a model download. Choose **LivingStory** to exercise adaptive heartbeat behavior
with an explicitly scripted analyzer. The five-minute setup target is a design
objective; external developer timing has not yet been collected.

## Installation and first response

Use Swift 5.9+, iOS 16+ or macOS 13+. Add the repository URL through Xcode's
Package Dependencies and select the QualiaKit product. For a local checkout,
add the root package directory. Pin a reviewed revision; `main` is not a stable
release promise. For the checked-in app, open
`Examples/QualiaExample/QualiaExample.xcodeproj` in Xcode 26.6+, select a team and
run on a physical iPhone. No model weights are downloaded by the demo.

<!-- snippet: Examples/DeveloperExperience/Sources/QualiaExamples/SentimentPreview.swift#sentiment-preview -->
```swift
import QualiaKit

@MainActor
public func makeSentimentPreview() async throws -> QualiaSession {
    let renderer = CoreHapticRenderer()
    guard renderer.capabilities.supportsHaptics else {
        throw QualiaError.hapticsUnavailable
    }
    return try await QualiaSession.sentimentPreview(
        analyzer: AppleSentimentAnalyzer(), renderer: renderer,
        language: .init(policy: .requireExplicit, minimumConfidence: 0.75),
        context: .init(maximumFragments: 0, maximumCharacters: 4_000)
    )
}

public func previewFirstFragment(in session: QualiaSession) async throws -> QualiaResponse {
    let response = try await session.process(QualiaInput(
        id: .init(rawValue: "first-fragment"),
        text: "This is a wonderful, joyful day!", language: .init(rawValue: "en")
    ))
    if let failure = response.execution.failure { throw failure }
    return response
}
```

Keep the returned actor in a screen model, create it once, and call
`previewFirstFragment(in:)` from a button's task. The response exposes observation,
state transition, planned commands and attempted command outcomes. For the first
fragment, the reducer initializes its valence from the observation; a value
sufficiently far from neutral produces an accent pulse. Apple output can vary;
near-neutral results legitimately yield no command.

The factory runs on MainActor because it installs a renderer. The analyzer moves
its Natural Language work off MainActor. Subsequent `session.process` calls cross
the session actor. Use an explicit `en` language, one nonempty paragraph and no
history. New accepted fragments need unique IDs; do not resubmit an accepted ID.

## Lifecycle belongs to the screen

Suspend on inactive/background, resume on active, and reset on leaving or replacing
a story. Await cleanup before starting a replacement session. Do not rely on
`deinit`. Resume allows new input; it does not replay the previous effect. Propagate
cleanup errors to UI and keep processing disabled until recovery succeeds.
<doc:SessionsAndContext> explains cancellation and typing.

## If there is no effect

| Result | Next action |
| --- | --- |
| `hapticsUnavailable` | Use a compatible iPhone; for analysis only, explicitly configure NoReactionPolicy and NoOpHapticRenderer |
| No planned command | Inspect valence, preferences and diagnostics; a neutral result is not an inference failure |
| Unsupported language/input structure | Use one English paragraph for Apple preview, or choose another validated analyzer |
| `response.execution.failure` | Surface the typed renderer failure; stop/reset before retrying |
| Cancelled/stale request | Treat as control flow; submit only the latest accepted event |

A simulator can validate responses and commands, never tactile sensation.
For a reproducible computer-only path, run the
<doc:TestingYourIntegration> and scripted walkthrough. For physical
LivingStory, choose that tab, accept the first fragment, wait a second, accept the
second and Reset. Its scores are authored fixtures, not inferred text meaning.

Before using app text or distributing a model, read <doc:PrivacyAndDataFlow>,
<doc:UsingCoreMLModels>, and <doc:Accessibility>.
