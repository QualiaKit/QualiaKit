# QualiaKit

An on-device runtime that turns text observations into stateful haptic reactions.
Bring an analyzer, choose a reaction policy, and let a session own ordering,
context and playback. Signals describe content and intended reader experience;
they do not measure a person's feelings or mental state.

![QualiaKit demo](qualia-demo.gif)

A recording of the demo. Physical sensation depends on the device and the holder;
a GIF or simulator cannot establish haptic quality.

## Choose your first path

| Path | What it does | What you need |
| --- | --- | --- |
| **SentimentPreview** | A short pulse from English positive/negative valence | `QualiaKit`, Apple's built-in analyzer, a compatible iPhone; no model download |
| **LivingStory, scripted** | Start a heartbeat, update it, play an accent, then stop | The example app or public consumer package; fixed authored observations, no text inference |
| **Narrative integration** | Run the same pipeline using actual narrative predictions | A compatible evaluated analyzer; optional Core ML adapter and separately licensed assets |

Apple sentiment and the recovered Russian sentiment model do not establish
suspense, threat or narrative understanding. There is no bundled production
narrative model.

## Run the demo

Open `Examples/QualiaExample/QualiaExample.xcodeproj`, select your signing team,
and run on a compatible iPhone. Choose **SentimentPreview** for English valence,
or **LivingStory** for the scripted heartbeat. Accept the first fragment, wait
about a second, accept the next, then press Reset. Backgrounding suspends playback;
returning does not replay an effect. The simulator shows state but cannot validate
sensation. This Xcode project requires Xcode 26.6 or newer.

## Integrate through public API

The Swift packages support Swift 5.9+, iOS 16+ and macOS 13+. In Xcode, add
`https://github.com/QualiaKit/QualiaKit.git` and select the **QualiaKit** product.
The 2.0 API is under development; pin a reviewed commit for your app.

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

Create the session once in a long-lived screen model. Call `previewFirstFragment`
from an explicit user action, inspect its response, and retain the session for
later fragments with unique IDs. Call `suspend()` when inactive, `resume()` on
return, and `reset()` when leaving the scene. Handle thrown setup/input errors;
a renderer failure is also present in `response.execution.failure`. The
[complete guide](docs/GettingStarted.md) covers lifecycle, unsupported hardware
and an analysis-only alternative. Near-neutral valence intentionally produces
no pulse; the preview supports one English paragraph without historical context.

## Test without hardware

The external consumer package uses public products only and verifies exact
ordered descriptors, including start, replacement, accent and owned stop:

```sh
swift test --package-path Examples/DeveloperExperience
swift run --package-path Examples/DeveloperExperience qualia-walkthrough
```

`QualiaTesting` provides `FixtureAnalyzer`, `ControlledAnalyzer`,
`RecordingHapticRenderer`, `TestQualiaClock` and `QualiaSessionHarness`.
The walkthrough prints a bounded redacted decision report; it emits no vibration.

## Guides

- [Getting started](docs/GettingStarted.md) · [Architecture](docs/Architecture.md)
- [Choose an analyzer](docs/ChoosingAnAnalyzer.md) · [Use Core ML](docs/UsingCoreMLModels.md)
- [Custom policies](docs/CreatingReactionPolicies.md) · [Haptic patterns](docs/BuildingHapticPatterns.md)
- [Sessions, context and SwiftUI](docs/SessionsAndContext.md) · [Integration testing](docs/TestingYourIntegration.md)
- [Privacy and diagnostics](docs/PrivacyAndDataFlow.md) · [Accessibility](docs/Accessibility.md)
- [Performance](docs/Performance.md) · [Pre-1.0 migration](docs/MigrationBefore1_0.md)
- [Public API reference and DocC](docs/APIReference.md) · [Contributing](CONTRIBUTING.md)
- [Release status and version policy](docs/release/README.md) · [Support](SUPPORT.md) · [Security](SECURITY.md)

The optional `QualiaCoreML` product lives in `Packages/QualiaCoreML`; see its setup
guide. The older `Qualia` and `QualiaBert` products are legacy APIs. The device
lab is an opt-in evaluation build, documented [separately](Documentation/DeviceEvaluation.md).

Diagnostics are off by default. Core has no networking or analytics transport;
host analyzers and sinks have their own privacy boundaries. Do not use QualiaKit
for medical diagnosis, mental-state inference, people scoring or decisions about
people. Code is [MIT](LICENSE); this grants no rights to external models or data.
The [current Russian model](Models/current/MODEL_CARD.md) is not redistributed.
