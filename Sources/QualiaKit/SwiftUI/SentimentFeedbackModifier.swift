#if canImport(SwiftUI)
import SwiftUI

private struct SentimentFeedbackModifier: ViewModifier {
    let feedback: SentimentFeedback
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                isVisible = true
                feedback.setActive(scenePhase == .active)
            }
            .onChange(of: scenePhase) { phase in
                if isVisible { feedback.setActive(phase == .active) }
            }
            .onDisappear {
                isVisible = false
                feedback.transition(to: false, clearResult: true)
            }
    }
}

public extension View {
    /// Owns screen/app lifecycle for one `SentimentFeedback` instance. Leaving
    /// cancels analysis and stops playback; returning never replays old text.
    /// Attach once to the screen, outside conditionally displayed result views.
    func sentimentFeedback(_ feedback: SentimentFeedback) -> some View {
        modifier(SentimentFeedbackModifier(feedback: feedback))
    }
}
#endif
