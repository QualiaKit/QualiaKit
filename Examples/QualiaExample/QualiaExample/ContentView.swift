import SwiftUI
import QualiaKit

@MainActor
struct ContentView: View {
    @StateObject private var feedback = SentimentFeedback()
    @State private var text = "This is a wonderful, joyful day!"

    var body: some View {
        NavigationStack {
            Form {
                Section("English text") {
                    TextField("Enter one paragraph", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                    Button("Analyze and feel") {
                        Task { await feedback.analyze(text) }
                    }
                    .disabled(!feedback.isReady || feedback.isProcessing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("Result") {
                    if let error = feedback.error {
                        Text("Could not finish: \(String(describing: error)). Tap Reset to retry.")
                    } else if let score = feedback.score {
                        Text("Sentiment: \(Int((score * 100).rounded()))/100")
                        Text(feedback.playedHaptic ? "Pulse played." : "No pulse for this text.")
                    } else {
                        Text(feedback.isReady ? "Enter one English paragraph." : "Preparing…")
                    }
                    Button("Reset") { feedback.reset() }
                }
                Section {
                    Toggle("Haptic feedback", isOn: $feedback.hapticsEnabled)
                        .disabled(!feedback.supportsHaptics)
                    Text(feedback.supportsHaptics
                         ? "Scores run from 0 (negative) to 100 (positive). Neutral text may produce no pulse. Analysis stays on device."
                         : "This device can analyze text but cannot play haptics. Try a compatible iPhone to feel the result.")
                        .font(.footnote)
                }
            }
            .navigationTitle("QualiaKit")
        }
        .sentimentFeedback(feedback)
    }
}
