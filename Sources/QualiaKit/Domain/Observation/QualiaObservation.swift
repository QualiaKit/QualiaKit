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

    public init(
        inputID: QualiaInputID,
        dimensions: QualiaDimensions = .init(),
        signals: [QualiaSignal: QualiaScore] = [:],
        language: QualiaLanguage,
        analyzer: QualiaAnalyzerIdentity
    ) {
        self.inputID = inputID
        self.dimensions = dimensions
        self.signals = signals
        self.language = language
        self.analyzer = analyzer
    }
}
