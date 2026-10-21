import Combine
import Foundation
import QualiaKit
import QualiaExamples

@MainActor
final class LivingStoryModel: ObservableObject {
    let narrative: Bool
    init(narrative: Bool = false) { self.narrative = narrative }
    var title: String { narrative ? "LivingStory · scripted" : "SentimentPreview" }
    var explanation: String {
        narrative
            ? "Authored signals drive start, update and accent. Reset stops the heartbeat. The text is not classified by a narrative model."
            : "Apple's on-device English valence baseline. It does not detect suspense, threat or reader emotion."
    }
    private struct SessionBundle {
        let story: QualiaSession
        let preview: QualiaSession
        let hapticsAvailable: Bool
    }

    @Published private(set) var storySession: QualiaSession?
    @Published private(set) var previewSession: QualiaSession?
    @Published private(set) var acceptedEvent: AcceptedStoryEvent?
    @Published private(set) var nextFragmentIndex = 0
    @Published private(set) var ready = false
    @Published private(set) var status = "Preparing explicit sessions…"
    @Published private(set) var previewStatus = "Type three or more characters to preview."
    @Published private(set) var analyzerCapability = "Checking analyzer capabilities…"
    @Published private(set) var hapticCapability = "Checking haptic hardware…"
    @Published private(set) var debug = LivingStoryDebugState()
    @Published private(set) var diagnosticSummary = "disabled in release builds"

    private var script: [StoryFragment] { narrative ? [
        StoryFragment(id: "build", text: "The hallway grows quiet. A distant rhythm starts."),
        StoryFragment(id: "impact", text: "A door slams. The rhythm accelerates with a separate accent."),
    ] : Self.previewScript }
    private static let previewScript = [
        StoryFragment(id: "arrival", text: "The old observatory was quiet and beautiful under the stars."),
        StoryFragment(id: "warning", text: "A terrible warning flashed across the abandoned control panel."),
        StoryFragment(id: "relief", text: "The signal was harmless, and the room felt calm again."),
    ]

    private let diagnostics = LivingStoryDiagnostics()
    private var active = true
    private var visible = false
    private var starting = false
    private var lifecycleTask: Task<Void, Never>?
    private var desiredPreferences = QualiaHapticPreferences.default
    private var lifecycleRevision = 0

    var visibleFragments: ArraySlice<StoryFragment> {
        script.prefix(nextFragmentIndex)
    }

    var hasNextFragment: Bool {
        nextFragmentIndex < script.count
    }

    var hasSessions: Bool {
        storySession != nil && previewSession != nil
    }

    func start(preferences: QualiaHapticPreferences, active: Bool) async {
        visible = true
        self.active = active
        desiredPreferences = preferences
        if hasSessions { setActive(active); return }
        guard !starting else { return }
        starting = true
        defer { starting = false }

        do {
            let sessions = try await makeSessions(preferences: preferences)
            storySession = sessions.story
            previewSession = sessions.preview
            analyzerCapability = analyzerDescription(sessions.story.analyzerCapabilities)
            hapticCapability = sessions.hapticsAvailable
                ? (narrative ? "Continuous haptics available; scripted heartbeat enabled." : "Haptic hardware available; sentiment pulses enabled.")
                : "Haptic hardware unavailable; story analysis remains enabled."
            performLifecycle {
                try await sessions.story.updateHapticPreferences(self.desiredPreferences)
                if !self.active || !self.visible {
                    try await sessions.story.suspend()
                    try await sessions.preview.suspend()
                }
            } success: {
                self.status = "Ready to accept the first stable story event."
            }
        } catch {
            status = "Session setup failed: \(safeError(error))"
            debug = .failure(safeError(error))
            refreshDiagnostics()
        }
    }

    func acceptNextFragment() {
        guard ready, hasNextFragment else { return }
        let fragment = script[nextFragmentIndex]
        do {
            let input = try QualiaInput(
                id: QualiaInputID(rawValue: fragment.id),
                text: fragment.text,
                language: QualiaLanguage(rawValue: "en")
            )
            nextFragmentIndex += 1
            ready = false
            acceptedEvent = AcceptedStoryEvent(id: fragment.id, input: input)
            status = "Processing accepted event \(nextFragmentIndex) of \(script.count)…"
        } catch {
            status = "Script configuration failed: \(safeError(error))"
            debug = .failure(safeError(error))
        }
    }

    func consumeStoryResult(_ result: Result<QualiaResponse, any Error>) {
        switch result {
        case .success(let response):
            ready = active && visible && lifecycleTask == nil
            let valence = response.observation.dimensions.valence?.value
            status = narrative ? "Scripted scene applied. Next fragment updates the rhythm; Reset stops it."
                : (valence.map { "Accepted story valence: \(Int(($0 * 100).rounded()))%." } ?? "Accepted story event produced no valence.")
            if let failure = response.execution.failure { status = "Rendering failed: \(safeError(failure))" }
            debug = .response(response, languageSource: "explicit")
        case .failure(let error) where error is CancellationError:
            return
        case .failure(let error):
            status = "Story analysis failed: \(safeError(error))"
            debug = .failure(safeError(error))
        }
        refreshDiagnostics()
    }

    func consumePreviewResult(_ result: Result<QualiaResponse, any Error>) {
        switch result {
        case .success(let response):
            let valence = response.observation.dimensions.valence?.value
            previewStatus = valence.map { "Isolated draft valence: \(Int(($0 * 100).rounded()))%." }
                ?? "Draft produced no valence."
        case .failure(let error) where error is CancellationError:
            return
        case .failure(let error):
            previewStatus = "Draft preview failed: \(safeError(error))"
        }
        refreshDiagnostics()
    }

    func updatePreferences(_ preferences: QualiaHapticPreferences) {
        desiredPreferences = preferences
        guard let storySession else { return }
        performLifecycle { try await storySession.updateHapticPreferences(preferences) }
    }

    func setActive(_ active: Bool) {
        self.active = active
        guard let storySession, let previewSession else { return }
        let shouldResume = active && visible
        performLifecycle {
            if shouldResume {
                try await storySession.resume()
                try await previewSession.resume()
            } else {
                try await storySession.suspend()
                try await previewSession.suspend()
            }
        }
    }

    func resetStory() {
        guard let storySession, let previewSession else { return }
        clearStoryDisplay()
        performLifecycle {
            try await storySession.reset()
            try await previewSession.reset()
        } success: {
            self.status = "Story reset; owned effects stopped."
        }
    }

    func leaveStory() {
        visible = false
        ready = false
        clearStoryDisplay()
        guard let storySession, let previewSession else { return }
        performLifecycle {
            try await storySession.reset()
            try await previewSession.reset()
        }
    }

    private func clearStoryDisplay() {
        acceptedEvent = nil
        nextFragmentIndex = 0
        previewStatus = "Type three or more characters to preview."
        debug = LivingStoryDebugState()
    }

    /// Serialize host lifecycle work across rapid tab/scene/preference changes.
    /// A later transition cannot re-enable input before an earlier stop completes.
    private func performLifecycle(
        _ operation: @escaping @MainActor () async throws -> Void,
        success: @escaping @MainActor () -> Void = {}
    ) {
        lifecycleRevision += 1
        let request = lifecycleRevision
        let previous = lifecycleTask
        ready = false
        lifecycleTask = Task {
            await previous?.value
            do {
                try await operation()
                success()
                if request == lifecycleRevision {
                    lifecycleTask = nil
                    ready = active && visible
                }
            } catch {
                if request == lifecycleRevision {
                    lifecycleTask = nil
                    ready = false
                    status = "Lifecycle operation failed; reset to retry: \(safeError(error))"
                }
            }
            refreshDiagnostics()
        }
    }

    private func makeSessions(
        preferences: QualiaHapticPreferences
    ) async throws -> SessionBundle {
        let physicalRenderer = CoreHapticRenderer()
        let supportsHaptics = physicalRenderer.capabilities.supportsHaptics &&
            (!narrative || physicalRenderer.capabilities.supportsContinuousHaptics)
        let configurations = try makeConfigurations(
            preferences: preferences,
            supportsHaptics: supportsHaptics
        )
        let analyzer: any QualiaAnalyzing = narrative ? try LivingStory.analyzer() : AppleSentimentAnalyzer()
        let storyRenderer: any HapticRendering = supportsHaptics
            ? physicalRenderer
            : NoOpHapticRenderer()
        let story = try await QualiaSession.configured(
            analyzer: analyzer,
            renderer: storyRenderer,
            configuration: configurations.story
        )
        do {
            let preview = try await QualiaSession.configured(
                analyzer: AppleSentimentAnalyzer(),
                renderer: NoOpHapticRenderer(),
                configuration: configurations.preview
            )
            return SessionBundle(
                story: story,
                preview: preview,
                hapticsAvailable: supportsHaptics
            )
        } catch {
            try await story.reset()
            throw error
        }
    }

    private func makeConfigurations(
        preferences: QualiaHapticPreferences,
        supportsHaptics: Bool
    ) throws -> (story: QualiaSessionConfiguration, preview: QualiaSessionConfiguration) {
        let english = try QualiaLanguage(rawValue: "en")
        let context = try QualiaContextConfiguration(
            maximumFragments: 0,
            maximumCharacters: 4_000,
            maximumUTF8Bytes: 16_000
        )
        let explicitLanguage = try QualiaLanguageConfiguration(
            policy: .requireExplicit,
            minimumConfidence: 0.8
        )
        let detectedLanguage = try QualiaLanguageConfiguration(
            policy: .detect(allowed: [english]),
            minimumConfidence: 0.45
        )
        let reaction: QualiaReactionConfiguration = supportsHaptics
            ? (narrative ? try LivingStory.configuration().reaction : .sentimentPreview(.default)) : .noReaction
#if DEBUG
        let diagnosticConfiguration = QualiaDiagnosticsConfiguration(sink: diagnostics)
#else
        let diagnosticConfiguration = QualiaDiagnosticsConfiguration.disabled
#endif
        let story = QualiaSessionConfiguration(
            language: explicitLanguage,
            context: context,
            sceneState: narrative ? .narrative : .sentimentPreview,
            reaction: reaction,
            haptics: .init(preferences: preferences, arbitration: .independentOwners),
            diagnostics: diagnosticConfiguration
        )
        let preview = QualiaSessionConfiguration(
            language: detectedLanguage,
            context: context,
            sceneState: .sentimentPreview,
            reaction: .noReaction,
            haptics: .init(preferences: .disabled, arbitration: .independentOwners),
            diagnostics: diagnosticConfiguration
        )
        return (story, preview)
    }

    private func analyzerDescription(_ capabilities: QualiaAnalyzerCapabilities) -> String {
        if narrative { return "Fixed authored observations · en · suspense, threat, impact · no text inference" }
        let languages = capabilities.languages.map(\.rawValue).sorted().joined(separator: ", ")
        let dimensions = capabilities.dimensions.contains(.valence) ? "valence" : "no standard dimensions"
        return "\(AppleSentimentAnalyzer.identifier) v\(AppleSentimentAnalyzer.version) · \(languages) · \(dimensions) · on-device"
    }

    private func safeError(_ error: any Error) -> String {
        if let error = error as? QualiaError { return error.description }
        if let error = error as? QualiaSessionError { return String(describing: error) }
        if let error = error as? QualiaReactionConfigurationError { return String(describing: error) }
        if let error = error as? HapticError { return String(describing: error) }
        return "redacted runtime error"
    }

    private func refreshDiagnostics() {
        diagnosticSummary = diagnostics.summary
    }
}
