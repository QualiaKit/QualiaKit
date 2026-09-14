# QualiaKit

QualiaKit is an on-device semantic-to-haptics runtime for interactive fiction,
narrative apps and rich text experiences. A session connects a text analyzer,
temporal scene state, a reaction policy and an injected haptic renderer.
Semantic signals describe content and a desired reader experience; they do not
measure a person's emotion or mental state.

Requires Swift 5.9, iOS 16+ or macOS 13+. Haptic playback requires compatible
hardware; analysis-only sessions can use an explicit no-op renderer.

## Installation

```swift
.package(url: "https://github.com/QualiaKit/QualiaKit.git", branch: "main")

// Target dependency:
.product(name: "QualiaKit", package: "QualiaKit")
```

The 2.0 API is under development. Pin a reviewed revision for an application.
`QualiaTesting` provides recording renderers and bounded diagnostic fixtures.
The optional local manifest-driven model adapter is in `Packages/QualiaCoreML`.
The older `Qualia` and `QualiaBert` products are legacy APIs.

## Start here

Open `Examples/QualiaExample/QualiaExample.xcodeproj`. It uses the local package,
Apple's on-device English sentiment baseline, explicit accepted text and haptic
controls. No model download, diagnostics opt-in or network connection is required.
The baseline exposes valence only; it does not claim narrative suspense or fear.

For narrative analyzers declaring the required capabilities, the runtime provides
an adaptive heartbeat with confidence gates, bounded duration, independent
accents and owner-scoped reset. Physical-device calibration is still required.

- [Programmatic session, ordering and lifecycle](Documentation/Session.md)
- [Diagnostics, privacy, safety and accessibility](Documentation/DiagnosticsAndPrivacy.md)
- [Adaptive heartbeat and migration](Documentation/Heartbeat.md)
- [Language and bounded context](Documentation/ContextAndLanguage.md)
- [Optional Core ML runtime and current limitations](Documentation/CoreMLRuntime.md)

Diagnostics default to no-op. The 2.0 products contain no network or analytics
transport. Host-provided analyzers and sinks have their own privacy boundaries.
QualiaKit must not be used for health diagnosis, real-fear measurement,
mental-state inference, people scoring or decisions about people.

Repository code is MIT; see [LICENSE](LICENSE). The repository license does not
grant rights to external models or training data. The current Russian model is
not approved for redistribution; see [its model card](Models/current/MODEL_CARD.md).
