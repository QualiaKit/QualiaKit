public struct QualiaAnalyzerIdentity: Hashable, Sendable {
    /// Exact, case-sensitive implementation identifier preserved without
    /// trimming, case folding, or Unicode normalization.
    public let identifier: String
    /// Exact, case-sensitive implementation version preserved without
    /// trimming, case folding, or Unicode normalization.
    public let version: String

    public init(identifier: String, version: String) throws {
        guard !QualiaDomainValidation.isBlank(identifier) else {
            throw QualiaError.invalidAnalyzerIdentifier
        }
        guard !QualiaDomainValidation.isBlank(version) else {
            throw QualiaError.invalidAnalyzerVersion
        }
        self.identifier = identifier
        self.version = version
    }

    init(validatedIdentifier identifier: String, version: String) {
        self.identifier = identifier
        self.version = version
    }
}

public enum QualiaExecutionMode: Hashable, Sendable {
    case onDevice
    case remote
    case hybrid
}

public struct QualiaAnalyzerCapabilities: Hashable, Sendable {
    public let languages: Set<QualiaLanguage>
    public let dimensions: Set<QualiaDimension>
    public let signals: Set<QualiaSignal>
    public let acceptsContext: Bool
    public let execution: QualiaExecutionMode

    public init(
        languages: Set<QualiaLanguage>,
        dimensions: Set<QualiaDimension>,
        signals: Set<QualiaSignal>,
        acceptsContext: Bool,
        execution: QualiaExecutionMode
    ) {
        self.languages = languages
        self.dimensions = dimensions
        self.signals = signals
        self.acceptsContext = acceptsContext
        self.execution = execution
    }
}

/// An asynchronous analyzer that maps one validated input to one observation.
///
/// Implementations must keep `capabilities` stable for their lifetime, preserve
/// cancellation, and return an observation whose input ID and outputs conform
/// to the request and advertised capabilities.
public protocol QualiaAnalyzing: Sendable {
    var capabilities: QualiaAnalyzerCapabilities { get }

    func analyze(_ input: QualiaInput) async throws -> QualiaObservation
}

/// A typed condition that may permit an explicitly configured fallback.
public enum QualiaFallbackCause: Hashable, Sendable {
    case languageUndetermined
    case unsupportedLanguage
    case analyzerUnavailable
}
