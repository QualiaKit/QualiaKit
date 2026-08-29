/// Errors produced while validating public QualiaKit domain values.
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
}

enum QualiaDomainValidation {
    static func isBlank(_ value: String) -> Bool {
        value.isEmpty || value.allSatisfy(\.isWhitespace)
    }
}
