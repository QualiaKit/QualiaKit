# Public consumer examples

This SwiftPM package depends on public QualiaKit, QualiaTesting and QualiaCoreML
products. It never uses `@testable` or package-internal symbols. It supports Swift
5.9+, macOS 13+ and iOS 16+; its command-line walkthrough records commands without
requiring haptic hardware or licensed model assets.

```sh
swift test --package-path Examples/DeveloperExperience
swift run --package-path Examples/DeveloperExperience qualia-walkthrough
```

Sources are the canonical snippets embedded in the root README and developer
manual. Run `python3 Tools/DeveloperExperience/snippets.py` to detect drift;
`--write` refreshes rendered snippets after a deliberate example change.

- SentimentPreview: English Apple valence and a real renderer factory.
- LivingStory: authored observations drive the real narrative policy; no inference claim.
- CustomAnalyzer / CustomPolicy: annotation lookup and a host-specific accent rule.
- ModelSession: actual optional Core ML API, compile-tested without private weights.
- DecisionReport: bounded local formatting of redacted diagnostic events.

The iPhone app imports this package's LivingStory implementation. Its first and
second fragments exercise start, update and accent; Reset stops owned playback.
The consumer test uses a fake clock and independent literal descriptors. A passing
software test does not imply model accuracy or tactile comfort. Read the root
[Getting Started](../../docs/GettingStarted.md) for setup and lifecycle, and
[privacy guidance](../../docs/PrivacyAndDataFlow.md) before handling app text.

## Pilot integration

`PilotComparison` runs the candidate through an internally constructed recording
renderer while the primary session alone owns physical playback. The host
serializes accepted inputs and lifecycle calls. `PilotFeedback` creates only
explicitly consented, closed-schema judgments with fingerprinted installation
metadata; it has no text fields or transport. `PilotTests` verifies single primary
playback, no replay after suspension and the exported privacy boundary.
See the [pilot protocol](../../docs/release/Pilots.md) before a real app trial.
