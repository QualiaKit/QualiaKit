/// Errors produced by QualiaKit domain validation and analyzer runtime contracts.
///
/// Cases deliberately contain no input text or arbitrary framework messages.
public enum QualiaError: Error, Hashable, Sendable {
    case invalidInputID
    case invalidLanguage
    case invalidSignal
    case invalidAnalyzerIdentifier
    case invalidAnalyzerVersion
    case emptyInput
    case invalidScore
    case invalidConfidence
    case languageUndetermined
    case unsupportedLanguage(QualiaLanguage)
    case unsupportedContext
    case unsupportedInputStructure
    case analyzerUnavailable(identity: QualiaAnalyzerIdentity)
    case invalidAnalyzerOutput(identity: QualiaAnalyzerIdentity)
    case incompatibleFallbackCapabilities
}

enum QualiaDomainValidation {
    static func isBlank(_ value: String) -> Bool {
        value.isEmpty || value.allSatisfy(\.isWhitespace)
    }
}
