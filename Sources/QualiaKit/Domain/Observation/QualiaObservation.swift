/// A caller-visible non-fatal degradation of an otherwise valid observation.
///
/// Warning codes contain ASCII letters, digits, `.`, `_`, and `-`. Validation
/// establishes syntax only; it does not establish provenance, privacy, or that
/// a code was not derived from caller input.
public struct QualiaWarning: Hashable, Sendable {
    public let code: String

    public init(code: String) throws {
        guard QualiaDomainValidation.isValidWarningCodeSyntax(code) else {
            throw QualiaError.invalidWarningCode
        }
        self.code = code
    }
}

/// The validated result of one analyzer invocation.
///
/// An observation contains semantic values and analyzer provenance. It
/// intentionally contains no raw input text, scene state, haptic identifiers,
/// or operational diagnostics. Model adapters must map raw labels before
/// constructing it.
public struct QualiaObservation: Sendable {
    public let inputID: QualiaInputID
    public let dimensions: QualiaDimensions
    public let signals: [QualiaSignal: QualiaScore]
    public let language: QualiaLanguage
    public let analyzer: QualiaAnalyzerIdentity
    /// Caller-visible degradations relevant to interpreting this result.
    public let warnings: [QualiaWarning]

    public init(
        inputID: QualiaInputID,
        dimensions: QualiaDimensions = .init(),
        signals: [QualiaSignal: QualiaScore] = [:],
        language: QualiaLanguage,
        analyzer: QualiaAnalyzerIdentity,
        warnings: [QualiaWarning] = []
    ) {
        self.inputID = inputID
        self.dimensions = dimensions
        self.signals = signals
        self.language = language
        self.analyzer = analyzer
        self.warnings = warnings
    }
}
