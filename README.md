# QualiaKit

Turn text into on-device haptic reactions in Swift. A session connects an
analyzer to a reaction policy and owns playback, ordering and context.

## Install

Requires iOS 16+ or macOS 13+, with Swift 5.9+. In Xcode, add
`https://github.com/QualiaKit/QualiaKit.git` and select the **QualiaKit** product.
The session API is under development: pin a reviewed commit. Existing tags
`1.0.0` through `3.0.0` use the legacy API; a broad version range can select them.

## First integration

Create a session once in your screen model, then process text from a button:

```swift
import Foundation
import QualiaKit

@MainActor
func makeSession() async throws -> QualiaSession {
    let renderer = CoreHapticRenderer()
    guard renderer.capabilities.supportsHaptics else {
        throw QualiaError.hapticsUnavailable
    }
    return try await QualiaSession.sentimentPreview(
        analyzer: AppleSentimentAnalyzer(),
        renderer: renderer,
        language: .init(policy: .requireExplicit, minimumConfidence: 0.75),
        context: .init(maximumFragments: 0, maximumCharacters: 4_000)
    )
}

func analyze(_ text: String, in session: QualiaSession) async throws -> QualiaResponse {
    let response = try await session.process(QualiaInput(
        id: .init(rawValue: UUID().uuidString),
        text: text,
        language: .init(rawValue: "en")
    ))
    if let failure = response.execution.failure { throw failure }
    return response
}
```

This uses Apple's built-in analyzer for **one English paragraph**. Positive or
negative valence produces a short pulse; near-neutral text may produce none.
It needs no model download. It does not detect suspense or a person's emotions.

Retain the session across button taps and give each input a unique ID. Await
`suspend()` when the screen becomes inactive, `resume()` when it becomes active,
and `reset()` when leaving or starting over. Serialize these lifecycle calls,
handle cleanup errors before accepting more input, and do not rely on `deinit`.
Resuming never replays a previous effect.

## Run the example

Open [QualiaExample.xcodeproj](Examples/QualiaExample/QualiaExample.xcodeproj),
select your signing team and run on a compatible iPhone. Xcode 16.4+ can open the
project. There is one screen: enter English text, tap **Analyze and feel**, and
read the result. **Reset** clears the session and retries setup after an error.
The simulator can build the app but cannot demonstrate physical haptics.

The complete integration is in three files:

- [QualiaExampleApp.swift](Examples/QualiaExample/QualiaExample/QualiaExampleApp.swift) starts the app.
- [ContentView.swift](Examples/QualiaExample/QualiaExample/ContentView.swift) contains the screen.
- [SentimentModel.swift](Examples/QualiaExample/QualiaExample/SentimentModel.swift) creates the session, processes text and handles lifecycle.

## Other integrations

| Product | Use |
| --- | --- |
| `QualiaKit` | Sessions, Apple sentiment, custom analyzers and haptic policies |
| `QualiaCoreML` | App-owned Core ML and BERT models; see the [model integration guide](Packages/QualiaCoreML/README.md) |
| `QualiaTesting` | Recording renderers, fixture analyzers and a controllable clock for tests without hardware |
| `Qualia`, `QualiaBert` | Legacy API, retained for existing applications |

Implement `QualiaAnalyzing` for another analyzer and pass it to
`QualiaSession.configured(analyzer:renderer:configuration:)`. A reaction policy
must match the analyzer's declared signals. For analysis without vibration, use
`NoReactionPolicy` and `NoOpHapticRenderer` through that factory.

SwiftUI also provides `qualiaReaction` for accepted events and `qualiaLiveReaction`
for debounced drafts. Keep draft preview in a separate session so it does not
advance the accepted story. Public API documentation lives with the source.

When migrating from `Qualia` or `QualiaBert`, replace client calls with a retained
`QualiaSession` and explicit inputs/lifecycle handling. The two APIs are not
source-compatible; legacy model output semantics remain unchanged.

## Privacy and accessibility

The built-in analyzer runs on device. The core library has no networking or
analytics transport; custom analyzers and diagnostic sinks are controlled by
the host app. Diagnostics are off by default. Do not log user text or distribute
private model assets. Signals describe content, not a person's mental state.

Haptic support depends on hardware. Surface unavailable-hardware and playback
errors, provide visible results, and respect the user's haptic preferences. If
using continuous effects, disable them for Reduce Motion and bound their duration.

Code is [MIT](LICENSE). Model and dataset rights are separate; no trained model
is bundled. See [Contributing](CONTRIBUTING.md), [Support](SUPPORT.md) and
[Security](SECURITY.md).
