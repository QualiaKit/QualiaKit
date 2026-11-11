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
Review [privacy guidance](../../docs/PrivacyAndDataFlow.md) before a real app trial.

## QualiaKitBert

The example package alone bundles QualiaKitBert v10-preview.1, its vocabulary,
manifest and license notices. Root QualiaKit/QualiaCoreML products remain
model-free. `QualiaKitBert.analyzer()` uses the public BERT adapter and
`QualiaKitBert.configuration()` uses the normal session and narrative policy.
The demo explicitly sets the confidence gate to zero because the model does not
provide calibrated confidence. Scores are never relabeled as confidence.

Open the iPhone example's first tab, select a scene and tap **Analyze and feel**.
Use your own English text, optionally continue from two previous accepted
fragments, or **Stop**. The session rejects more than 128 model
tokens including context; it does not truncate or switch to keyword rules.

Run the six fixed, assistant-labeled diagnostic probes and local timings:

```sh
swift run --package-path Examples/DeveloperExperience qualia-walkthrough --bert
```

This prints JSON and does not vibrate. The iPhone Debug build also accepts the
explicit launch argument `--qualiakit-bert-check`: it uses the same fixed probes,
briefly plays a bounded heartbeat when supported, checks suspend/resume and quiet
input, and writes `Documents/qualiakit-bert-device.json`. Normal demo input is
never saved by that check. These diagnostics are not independent accuracy,
comfort or battery evidence. See the [model card](../../Models/QualiaKitBert/MODEL_CARD.md).
