import Combine
import SwiftUI

/// SwiftUI environment key for injecting custom QualiaClient
private struct QualiaClientKey: EnvironmentKey {
    static let defaultValue: QualiaClient = QualiaClient()
}

extension EnvironmentValues {
    /// QualiaClient instance used by `.qualiaFeedback()` modifier
    public var qualiaClient: QualiaClient {
        get { self[QualiaClientKey.self] }
        set { self[QualiaClientKey.self] = newValue }
    }
}

/// ViewModifier that provides haptic feedback based on text sentiment
struct QualiaFeedbackModifier: ViewModifier {
    @Binding var trigger: String
    let config: QualiaConfiguration
    @Environment(\.qualiaClient) private var client

    @State private var debounceTask: Task<Void, Never>?
    @State private var lastValue: String = ""

    func body(content: Content) -> some View {
        content
            .task(id: trigger) {
                // Skip initial trigger
                guard trigger != lastValue else {
                    lastValue = trigger
                    return
                }
                lastValue = trigger

                // Cancel previous debounce task
                debounceTask?.cancel()

                // Debounce to prevent "chainsaw buzzing" during fast typing
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms

                    guard !Task.isCancelled else { return }

                    // Analyze and trigger haptic feedback
                    _ = await client.analyzeAndFeel(trigger)
                }
            }
    }
}

extension View {
    /// Adds automatic haptic feedback based on text sentiment
    ///
    /// This is the "Zero-Config" one-liner for SwiftUI. Observes the binding
    /// and automatically triggers haptic feedback based on sentiment analysis.
    ///
    /// ## Example
    /// ```swift
    /// TextField("Enter text", text: $userInput)
    ///     .qualiaFeedback(trigger: $userInput)
    /// ```
    ///
    /// ## Customization
    /// To use a custom provider or configuration:
    /// ```swift
    /// TextField("Enter text", text: $userInput)
    ///     .environment(\.qualiaClient, QualiaClient(provider: BertProvider(...)))
    ///     .qualiaFeedback(trigger: $userInput)
    /// ```
    ///
    /// - Parameters:
    ///   - trigger: Binding to text that should trigger sentiment analysis
    ///   - config: Haptic configuration. Default: `.standard`
    /// - Returns: Modified view with automatic haptic feedback
    public func qualiaFeedback(
        trigger: Binding<String>,
        config: QualiaConfiguration = .standard
    ) -> some View {
        modifier(QualiaFeedbackModifier(trigger: trigger, config: config))
    }
}
