QualiaKit

Haptic feedback that responds to text.

QualiaKit connects text analysis to haptic playback in Swift. Start with on-device
English sentiment, or bring your own analyzer and reaction rules.

Installation · Quick start · Example app · Advanced integration



Visual demo from an earlier version of QualiaKit. The quick start below uses the current sentiment API.

Why QualiaKit?

A complete text-to-feedback flow. Submit a paragraph, read its sentiment score,
and play a short pulse on a compatible iPhone.

Less lifecycle code. The SwiftUI integration handles setup, cancellation,
and stopping playback when the screen is no longer active.

Local analysis to start. The built-in analyzer uses Apple Natural Language.
No server, API key, or model download is needed.

Use it to prototype tactile feedback in reading and writing interfaces. For
custom reactions or story context, use the session API described below.

<a name="install"></a>

Installation

Add QualiaKit with Swift Package Manager. Requires Swift 5.9+ and
iOS 16+ or macOS 13+.

In Xcode, choose File → Add Package Dependencies and paste:

https://github.com/QualiaKit/QualiaKit.git

Select Branch → main and add the QualiaKit product.

Development API: this example uses main. Existing version tags
1.0.0–3.0.0 contain the legacy API. Pin a tested revision before shipping.

Quick start

Add this screen to your app and open FeedbackView():

import SwiftUI
import QualiaKit

@MainActor
struct FeedbackView: View {
    @StateObject private var feedback = SentimentFeedback()
    @State private var text = "This is a wonderful, joyful day!"

    var body: some View {
        Form {
            TextField("One English paragraph", text: $text, axis: .vertical)
            Button("Analyze and feel") {
                Task { await feedback.analyze(text) }
            }
            .disabled(!feedback.isReady || feedback.isProcessing)

            if let score = feedback.score {
                Text("Sentiment: \(Int((score * 100).rounded()))/100")
                Text(feedback.playedHaptic ? "Pulse played." : "No pulse.")
            }
            if let error = feedback.error {
                Text("Could not finish: \(String(describing: error))")
                Button("Retry setup") { feedback.reset() }
            }
            if !feedback.supportsHaptics {
                Text("Analysis works here. Feel the pulse on a compatible iPhone.")
            }
        }
        .sentimentFeedback(feedback)
    }
}

Use one English paragraph, up to 4,000 characters. The displayed score runs
from 0 (negative) to 100 (positive). Positive text produces a sharper pulse,
negative text a softer one; near-neutral text produces no pulse. Each paragraph
is analyzed independently.

The score describes the text's sentiment. On unsupported hardware, or with
haptics switched off, the same screen still shows the result.

<a name="run-the-example"></a>

Run the example app

Clone the repository and open
QualiaExample.xcodeproj
in Xcode 16.4+. Select your signing team and run on a compatible iPhone to feel
the feedback. The simulator and Mac can show analysis results without vibration.

Try a positive paragraph, a negative one, and a neutral one. The example also
includes a haptics switch so you can compare the experience.

<a name="other-integrations"></a>
<a name="custom-models-and-reactions"></a>

Advanced integration

SentimentFeedback is the built-in starting point. Use QualiaSession when you
need your own analyzer, retained context, or custom haptic rules.

<details>
<summary><strong>Custom models and narrative effects</strong></summary>

Implement QualiaAnalyzing and connect it to a renderer with
QualiaSession.configured(analyzer:renderer:configuration:). Choose a reaction
policy that matches the signals your analyzer provides.

Core ML / BERT: use QualiaCoreML with your own compatible model and assets.
See the integration guide.

Narrative effects: supply an analyzer that provides the required narrative
signals. The built-in sentiment analyzer does not detect suspense or threat,
and no trained narrative model is bundled.

Tests: use QualiaTesting for synthetic analyzers, recording renderers, and
a controllable clock. See the
consumer examples.

The MIT license covers this repository's code; external models and datasets have
separate licenses.

</details>

<details>
<summary><strong>Lifecycle and error handling</strong></summary>

Keep one SentimentFeedback instance per screen and attach its modifier once to
the outer view. New analysis replaces pending work. Leaving the screen stops
playback; returning does not replay earlier text.

Observe feedback.error for setup, analysis, playback, and cleanup failures.
Call feedback.reset() to clear the result and retry setup. To let users disable
vibration, bind a switch with Toggle("Haptics", isOn: $feedback.hapticsEnabled).
Changing hapticsEnabled cancels pending playback and clears the previous result.

For UIKit, retain the feedback object and call setActive(true) only while the
screen is visible and the app is active; call setActive(false) otherwise.

For custom sessions, retain the session across inputs, use unique input IDs,
serialize lifecycle calls, and await suspend(), resume(), and reset().
Handle both thrown errors and response.execution.failure. Use separate sessions
for draft text and accepted story text.

</details>

<details>
<summary><strong>Input limits and existing applications</strong></summary>

The built-in path accepts one nonblank English paragraph of at most 4,000
characters. It does not translate text or infer the reader's emotional state.
Shorten overlong input and submit multiple paragraphs separately.

Qualia and QualiaBert remain available for existing applications. Their APIs
are not source-compatible with QualiaKit. Use SentimentFeedback for the
built-in English path, or configure a session for your own analyzer.

</details>

Privacy and accessibility

No network requests or analytics are used by the built-in path. Custom analyzers
and diagnostic sinks have their own data-handling behavior.

Show a visible result alongside haptics and let users disable vibration.
Continuous effects must respect Reduce Motion and have a bounded duration.

Project

Changelog ·
Contributing ·
Tests ·
Support ·
Security ·
MIT license
