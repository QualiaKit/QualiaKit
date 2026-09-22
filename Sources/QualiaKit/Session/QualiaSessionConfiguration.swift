/// Immutable language-resolution values. Detection remains an explicitly
/// injected dependency of the session factory.
public struct QualiaLanguageConfiguration: Hashable, Sendable {
    public let policy: QualiaLanguagePolicy
    public let minimumConfidence: Float

    public init(
        policy: QualiaLanguagePolicy,
        minimumConfidence: Float
    ) throws {
        guard minimumConfidence.isFinite, (0...1).contains(minimumConfidence) else {
            throw QualiaError.invalidLanguageConfiguration
        }
        switch policy {
        case .requireExplicit:
            break
        case .detect(let allowed), .preferExplicitThenDetect(let allowed):
            guard !allowed.isEmpty else {
                throw QualiaError.invalidLanguageConfiguration
            }
        }
        self.policy = policy
        self.minimumConfidence = minimumConfidence
    }
}

/// Built-in policy selection. Case names describe the actual semantic
/// capability they require; custom policies remain explicitly injectable.
public enum QualiaReactionConfiguration: Sendable {
    case noReaction
    case sentimentPreview(SentimentPulsePolicy.Configuration)
    case horrorNarrative(HorrorNarrativePolicy.Configuration)
    case custom(any QualiaReactionPolicy)

    var policy: any QualiaReactionPolicy {
        switch self {
        case .noReaction:
            return NoReactionPolicy()
        case .sentimentPreview(let configuration):
            return SentimentPulsePolicy(configuration: configuration)
        case .horrorNarrative(let configuration):
            return HorrorNarrativePolicy(configuration: configuration)
        case .custom(let policy):
            return policy
        }
    }
}

/// Physical feedback values are independent from semantic reaction policy.
public struct QualiaHapticConfiguration: Hashable, Sendable {
    public let preferences: QualiaHapticPreferences
    public let arbitration: QualiaRendererArbitration

    public init(
        preferences: QualiaHapticPreferences = .default,
        arbitration: QualiaRendererArbitration = .independentOwners
    ) {
        self.preferences = preferences
        self.arbitration = arbitration
    }

    public static let `default` = QualiaHapticConfiguration()
}

/// Diagnostics stay opt-in and transport-free. The sink receives only the
/// redacted schema defined by `QualiaDiagnosticEvent`.
public struct QualiaDiagnosticsConfiguration: Sendable {
    public let sink: any QualiaDiagnosticsSink

    public init(sink: any QualiaDiagnosticsSink = NoOpQualiaDiagnosticsSink()) {
        self.sink = sink
    }

    public static let disabled = QualiaDiagnosticsConfiguration()
}

/// Complete immutable configuration for a programmatic `QualiaSession`.
/// Analyzer, renderer, language detector, and clock are dependencies rather
/// than configuration and therefore remain explicit factory arguments.
public typealias QualiaSceneStateConfiguration = QualiaSceneReducerConfiguration

public struct QualiaSessionConfiguration: Sendable {
    public let language: QualiaLanguageConfiguration
    public let context: QualiaContextConfiguration
    public let sceneState: QualiaSceneStateConfiguration
    public let reaction: QualiaReactionConfiguration
    public let haptics: QualiaHapticConfiguration
    public let diagnostics: QualiaDiagnosticsConfiguration

    public init(
        language: QualiaLanguageConfiguration,
        context: QualiaContextConfiguration,
        sceneState: QualiaSceneStateConfiguration,
        reaction: QualiaReactionConfiguration,
        haptics: QualiaHapticConfiguration = .default,
        diagnostics: QualiaDiagnosticsConfiguration = .disabled
    ) {
        self.language = language
        self.context = context
        self.sceneState = sceneState
        self.reaction = reaction
        self.haptics = haptics
        self.diagnostics = diagnostics
    }
}

public extension QualiaSession {
    /// General factory used by programmatic and SwiftUI hosts. Every dependency
    /// and configuration family is explicit; construction validates analyzer,
    /// policy, context, and renderer compatibility before returning.
    @MainActor
    static func configured(
        analyzer: any QualiaAnalyzing,
        renderer: any HapticRendering,
        configuration: QualiaSessionConfiguration,
        languageDetector: any QualiaLanguageDetecting = AppleLanguageDetector(),
        clock: any QualiaClock = QualiaContinuousClock()
    ) async throws -> QualiaSession {
        let diagnostics = configuration.diagnostics.sink
        let resolver = try QualiaLanguageResolver(
            policy: configuration.language.policy,
            minimumConfidence: configuration.language.minimumConfidence,
            detector: languageDetector,
            diagnostics: { diagnostics.emit(.preparation($0)) }
        )
        let dependencies = QualiaSessionDependencies(
            analyzer: analyzer,
            languageResolver: resolver,
            contextWindow: QualiaContextWindow(configuration: configuration.context),
            stateReducer: QualiaSceneReducer(configuration: configuration.sceneState),
            reactionPolicy: configuration.reaction.policy,
            diagnostics: diagnostics,
            clock: clock
        )
        return try await QualiaSession(
            dependencies: dependencies,
            renderer: QualiaSessionRenderer(
                renderer: renderer,
                arbitration: configuration.haptics.arbitration
            ),
            preferences: configuration.haptics.preferences
        )
    }

    /// Valence-only preview. Installation fails unless the analyzer advertises
    /// `.valence` and the renderer advertises haptic playback.
    @MainActor
    static func sentimentPreview(
        analyzer: any QualiaAnalyzing,
        renderer: any HapticRendering,
        language: QualiaLanguageConfiguration,
        context: QualiaContextConfiguration,
        policy: SentimentPulsePolicy.Configuration = .default,
        haptics: QualiaHapticConfiguration = .default,
        diagnostics: QualiaDiagnosticsConfiguration = .disabled,
        languageDetector: any QualiaLanguageDetecting = AppleLanguageDetector(),
        clock: any QualiaClock = QualiaContinuousClock()
    ) async throws -> QualiaSession {
        try await configured(
            analyzer: analyzer,
            renderer: renderer,
            configuration: QualiaSessionConfiguration(
                language: language,
                context: context,
                sceneState: .sentimentPreview,
                reaction: .sentimentPreview(policy),
                haptics: haptics,
                diagnostics: diagnostics
            ),
            languageDetector: languageDetector,
            clock: clock
        )
    }

    /// Narrative suspense/threat runtime. Installation fails unless the
    /// analyzer and renderer satisfy `HorrorNarrativePolicy` capabilities.
    @MainActor
    static func horrorNarrative(
        analyzer: any QualiaAnalyzing,
        renderer: any HapticRendering,
        language: QualiaLanguageConfiguration,
        context: QualiaContextConfiguration,
        policy: HorrorNarrativePolicy.Configuration = .default,
        haptics: QualiaHapticConfiguration = .default,
        diagnostics: QualiaDiagnosticsConfiguration = .disabled,
        languageDetector: any QualiaLanguageDetecting = AppleLanguageDetector(),
        clock: any QualiaClock = QualiaContinuousClock()
    ) async throws -> QualiaSession {
        try await configured(
            analyzer: analyzer,
            renderer: renderer,
            configuration: QualiaSessionConfiguration(
                language: language,
                context: context,
                sceneState: .narrative,
                reaction: .horrorNarrative(policy),
                haptics: haptics,
                diagnostics: diagnostics
            ),
            languageDetector: languageDetector,
            clock: clock
        )
    }
}
