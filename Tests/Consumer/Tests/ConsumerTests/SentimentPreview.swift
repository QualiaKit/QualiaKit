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
