import Combine
import Foundation
import QualiaKit

@MainActor
final class SentimentModel: ObservableObject {
    @Published private(set) var status = "Preparing…"
    @Published private(set) var isReady = false
    @Published private(set) var isProcessing = false

    private let analyzer: any QualiaAnalyzing
    private let renderer: any HapticRendering
    private var session: QualiaSession?
    private var lifecycleTask: Task<Void, Never>?
    private var revision = UUID()

    convenience init() {
        self.init(renderer: CoreHapticRenderer())
    }

    init(analyzer: any QualiaAnalyzing = AppleSentimentAnalyzer(), renderer: any HapticRendering) {
        self.analyzer = analyzer
        self.renderer = renderer
    }

    @discardableResult
    func setActive(_ active: Bool, reset: Bool = false) -> Task<Void, Never> {
        isReady = false
        let request = UUID()
        revision = request
        let previous = lifecycleTask
        // Finish cleanup before resuming or replacing a session.
        let task = Task {
            await previous?.value
            do {
                if reset, let session {
                    try await session.reset()
                    try await session.suspend()
                    self.session = nil
                }
                if active {
                    if session == nil {
                        guard renderer.capabilities.supportsHaptics else { throw QualiaError.hapticsUnavailable }
                        session = try await QualiaSession.sentimentPreview(
                            analyzer: analyzer, renderer: renderer,
                            language: .init(policy: .requireExplicit, minimumConfidence: 0.75),
                            context: .init(maximumFragments: 0, maximumCharacters: 4_000)
                        )
                    }
                    try await session?.resume()
                } else {
                    try await session?.suspend()
                }
                guard request == revision else { return }
                isReady = active
                status = active ? "Ready. Enter one English paragraph." : "Paused."
            } catch {
                guard request == revision else { return }
                status = (error as? QualiaError) == .hapticsUnavailable
                    ? "Haptics are unavailable. Run this example on a compatible iPhone."
                    : "Could not prepare or stop playback: \(error). Tap Reset to retry."
            }
            if request == revision { lifecycleTask = nil }
        }
        lifecycleTask = task
        return task
    }

    func analyze(_ text: String) async {
        guard isReady, !isProcessing, let session else { return }
        let request = revision
        isProcessing = true
        defer { isProcessing = false }
        do {
            let response = try await session.process(QualiaInput(
                id: .init(rawValue: UUID().uuidString), text: text,
                language: .init(rawValue: "en")
            ))
            guard request == revision else { return }
            if let failure = response.execution.failure {
                isReady = false
                status = "Playback failed: \(failure). Tap Reset to retry."
                return
            }
            let sentiment = response.observation.dimensions.valence?.value ?? 0.5
            status = "Sentiment score: \(Int((sentiment * 100).rounded()))/100. "
                + (response.execution.commands.isEmpty ? "No pulse for this text." : "Pulse played.")
        } catch is CancellationError {
            if request == revision { status = "Cancelled. You can try again." }
        } catch {
            if request == revision { status = "Could not analyze text: \(error)." }
        }
    }
}
