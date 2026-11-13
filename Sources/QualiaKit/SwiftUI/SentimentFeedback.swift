import Combine
import Foundation

/// On-device English sentiment with an optional short haptic pulse.
/// Keep one instance per screen and attach `View.sentimentFeedback(_:)` in SwiftUI.
/// UIKit hosts call `setActive(_:)` at their visibility and app-activity boundaries.
@MainActor
public final class SentimentFeedback: ObservableObject {
    @Published public private(set) var response: QualiaResponse?
    @Published public private(set) var error: (any Error)?
    @Published public private(set) var isReady = false
    @Published public private(set) var isProcessing = false

    /// Disabling feedback cancels pending work and stops playback before allowing
    /// further analysis. It never replays the previous text when re-enabled.
    @Published public var hapticsEnabled: Bool {
        didSet {
            if hapticsEnabled != oldValue { transition(to: wantsActive, clearResult: true) }
        }
    }

    public let supportsHaptics: Bool
    /// Content valence from 0 (negative) to 1 (positive), not a confidence score.
    public var score: Float? { response?.observation.dimensions.valence?.value }
    public var playedHaptic: Bool {
        guard let response, response.execution.failure == nil else { return false }
        return !response.execution.commands.isEmpty
    }

    private let analyzer: any QualiaAnalyzing
    private let renderer: any HapticRendering
    private var session: QualiaSession?
    private var lifecycleTask: Task<Void, Never>?
    private var analysisTask: Task<QualiaResponse, Error>?
    private var revision = UUID()
    private var analysisRevision = UUID()
    private var wantsActive = false

    public convenience init(hapticsEnabled: Bool = true) {
        self.init(analyzer: AppleSentimentAnalyzer(), renderer: CoreHapticRenderer(),
                  hapticsEnabled: hapticsEnabled)
    }

    init(analyzer: any QualiaAnalyzing, renderer: any HapticRendering, hapticsEnabled: Bool = true) {
        self.analyzer = analyzer
        self.renderer = renderer
        self.hapticsEnabled = hapticsEnabled
        supportsHaptics = renderer.capabilities.supportsHaptics
    }

    /// Starts or stops this screen's feedback. Lifecycle calls are ordered;
    /// observe `error` for setup/cleanup failures, or await the returned task.
    @discardableResult
    public func setActive(_ active: Bool) -> Task<Void, Never> {
        transition(to: active, clearResult: false)
    }

    /// Clears the result and retries failed setup or playback while active.
    @discardableResult
    public func reset() -> Task<Void, Never> {
        transition(to: wantsActive, clearResult: true)
    }

    @discardableResult
    func transition(to active: Bool, clearResult: Bool) -> Task<Void, Never> {
        wantsActive = active
        isReady = false
        isProcessing = false
        analysisTask?.cancel()
        analysisTask = nil
        if clearResult { response = nil }
        let request = UUID()
        revision = request
        analysisRevision = request
        let previous = lifecycleTask
        let task = Task {
            // Cleanup must finish even when the view disappears or a newer request arrives.
            await previous?.value
            do {
                if let session {
                    try await session.suspend()
                    self.session = nil
                }
                if active {
                    let playsHaptics = hapticsEnabled && supportsHaptics
                    session = try await QualiaSession.configured(
                        analyzer: analyzer,
                        renderer: playsHaptics ? renderer : NoOpHapticRenderer(),
                        configuration: .init(
                            language: .init(policy: .requireExplicit, minimumConfidence: 0.75),
                            context: .init(maximumFragments: 0, maximumCharacters: 4_000),
                            sceneState: .sentimentPreview,
                            reaction: playsHaptics ? .sentimentPreview(.default) : .noReaction
                        )
                    )
                }
                guard request == revision else { return }
                error = nil
                isReady = active
            } catch {
                guard request == revision else { return }
                self.error = error
            }
            if request == revision { lifecycleTask = nil }
        }
        lifecycleTask = task
        return task
    }

    /// Analyzes one English paragraph, up to 4,000 characters. Publishes `response`
    /// or `error`, including playback errors. A newer call cancels the older one.
    /// Unsupported hardware and disabled haptics still produce a sentiment score.
    public func analyze(_ text: String) async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        analysisRevision = request
        analysisTask?.cancel()
        analysisTask = nil
        isProcessing = false
        let lifecycleRevision = revision
        await lifecycleTask?.value
        guard !Task.isCancelled, lifecycleRevision == revision,
              request == analysisRevision else { return }
        guard isReady, let session else {
            if error == nil { error = QualiaSessionError.suspended }
            return
        }
        response = nil
        error = nil
        isProcessing = true
        let task = Task {
            // Each paragraph is independent; scene smoothing must not carry a
            // previous positive/negative score into a neutral text's pulse.
            try await session.reset()
            try Task.checkCancellation()
            return try await session.process(QualiaInput(
                id: .init(rawValue: UUID().uuidString), text: text,
                language: .init(rawValue: "en")
            ))
        }
        analysisTask = task
        defer {
            if request == analysisRevision {
                isProcessing = false
                analysisTask = nil
            }
        }
        await withTaskCancellationHandler {
            do {
                let result = try await task.value
                guard request == analysisRevision else { return }
                response = result
                if let failure = result.execution.failure {
                    error = failure
                    isReady = false
                }
            } catch is CancellationError {
                // Cancellation is expected when leaving the screen or replacing text.
            } catch {
                let snapshot = await session.snapshot
                if request == analysisRevision {
                    self.error = error
                    isReady = snapshot.lifecycle == .active
                }
            }
        } onCancel: {
            task.cancel()
        }
    }
}
