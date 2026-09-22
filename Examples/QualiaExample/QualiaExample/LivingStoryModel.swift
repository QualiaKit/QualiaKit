import Combine
import Foundation
import QualiaKit

@MainActor
final class LivingStoryModel: ObservableObject {
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

    private static let script = [
        StoryFragment(id: "arrival", text: "The old observatory was quiet and beautiful under the stars."),
        StoryFragment(id: "warning", text: "A terrible warning flashed across the abandoned control panel."),
        StoryFragment(id: "relief", text: "The signal was harmless, and the room felt calm again."),
    ]

    private let diagnostics = LivingStoryDiagnostics()
    private var active = true
    private var desiredPreferences = QualiaHapticPreferences.default
    private var lifecycleRevision = 0

    var visibleFragments: ArraySlice<StoryFragment> {
        Self.script.prefix(nextFragmentIndex)
    }

    var hasNextFragment: Bool {
        nextFragmentIndex < Self.script.count
    }

    var hasSessions: Bool {
        storySession != nil && previewSession != nil
    }

    func start(preferences: QualiaHapticPreferences, active: Bool) async {
        guard storySession == nil, previewSession == nil else { return }
        self.active = active
        desiredPreferences = preferences

        do {
            let sessions = try await makeSessions(preferences: preferences)
            try await prepareInitialLifecycle(
                story: sessions.story,
                preview: sessions.preview,
                initialPreferences: preferences
            )
            storySession = sessions.story
            previewSession = sessions.preview
            analyzerCapability = analyzerDescription(sessions.story.analyzerCapabilities)
            hapticCapability = sessions.hapticsAvailable
                ? "Haptic hardware available; sentiment pulses enabled."
                : "Haptic hardware unavailable; story analysis remains enabled."
            ready = active
            status = "Ready to accept the first stable story event."
            refreshDiagnostics()
        } catch {
            status = "Session setup failed: \(safeError(error))"
            debug = .failure(safeError(error))
            refreshDiagnostics()
        }
    }

    func acceptNextFragment() {
        guard ready, hasNextFragment else { return }
        let fragment = Self.script[nextFragmentIndex]
        do {
            let input = try QualiaInput(
                id: QualiaInputID(rawValue: fragment.id),
                text: fragment.text,
                language: QualiaLanguage(rawValue: "en")
            )
            nextFragmentIndex += 1
            acceptedEvent = AcceptedStoryEvent(id: fragment.id, input: input)
            status = "Processing accepted event \(nextFragmentIndex) of \(Self.script.count)…"
        } catch {
            status = "Script configuration failed: \(safeError(error))"
            debug = .failure(safeError(error))
        }
    }

    func consumeStoryResult(_ result: Result<QualiaResponse, any Error>) {
        switch result {
        case .success(let response):
            let valence = response.observation.dimensions.valence?.value
            status = valence.map { "Accepted story valence: \(Int(($0 * 100).rounded()))%." }
                ?? "Accepted story event produced no valence."
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
        lifecycleRevision += 1
        let request = lifecycleRevision
        ready = false
        Task {
            do {
                try await storySession.updateHapticPreferences(preferences)
                if request == lifecycleRevision { ready = active }
            } catch is CancellationError {
                return
            } catch {
                status = "Haptic preference update failed: \(safeError(error))"
            }
            refreshDiagnostics()
        }
    }

    func setActive(_ active: Bool) {
        self.active = active
        guard let storySession, let previewSession else { return }
        lifecycleRevision += 1
        let request = lifecycleRevision
        ready = false
        Task {
            do {
                if active {
                    try await storySession.resume()
                    try await previewSession.resume()
                } else {
                    try await storySession.suspend()
                    try await previewSession.suspend()
                }
                if request == lifecycleRevision { ready = active }
            } catch is CancellationError {
                return
            } catch {
                status = "Lifecycle transition failed: \(safeError(error))"
            }
            refreshDiagnostics()
        }
    }

    func resetStory() {
        guard let storySession, let previewSession else { return }
        lifecycleRevision += 1
        let request = lifecycleRevision
        ready = false
        acceptedEvent = nil
        Task {
            do {
                try await storySession.reset()
                try await previewSession.reset()
                if request == lifecycleRevision {
                    nextFragmentIndex = 0
                    ready = active
                    status = "Story reset; owned effects stopped."
                    previewStatus = "Type three or more characters to preview."
                    debug = LivingStoryDebugState()
                }
            } catch is CancellationError {
                return
            } catch {
                status = "Reset failed: \(safeError(error))"
            }
            refreshDiagnostics()
        }
    }

    func leaveStory() {
        ready = false
        acceptedEvent = nil
        guard let storySession, let previewSession else { return }
        Task {
            try? await storySession.reset()
            try? await previewSession.reset()
        }
    }

    private func makeSessions(
        preferences: QualiaHapticPreferences
    ) async throws -> SessionBundle {
        let physicalRenderer = CoreHapticRenderer()
        let supportsHaptics = physicalRenderer.capabilities.supportsHaptics
        let configurations = try makeConfigurations(
            preferences: preferences,
            supportsHaptics: supportsHaptics
        )
        let analyzer = AppleSentimentAnalyzer()
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
                analyzer: analyzer,
                renderer: NoOpHapticRenderer(),
                configuration: configurations.preview
            )
            return SessionBundle(
                story: story,
                preview: preview,
                hapticsAvailable: supportsHaptics
            )
        } catch {
            try? await story.reset()
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
            ? .sentimentPreview(.default)
            : .noReaction
#if DEBUG
        let diagnosticConfiguration = QualiaDiagnosticsConfiguration(sink: diagnostics)
#else
        let diagnosticConfiguration = QualiaDiagnosticsConfiguration.disabled
#endif
        let story = QualiaSessionConfiguration(
            language: explicitLanguage,
            context: context,
            sceneState: .sentimentPreview,
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

    private func prepareInitialLifecycle(
        story: QualiaSession,
        preview: QualiaSession,
        initialPreferences: QualiaHapticPreferences
    ) async throws {
        if desiredPreferences != initialPreferences {
            try await story.updateHapticPreferences(desiredPreferences)
        }
        if !active {
            try await story.suspend()
            try await preview.suspend()
        }
    }

    private func analyzerDescription(_ capabilities: QualiaAnalyzerCapabilities) -> String {
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
