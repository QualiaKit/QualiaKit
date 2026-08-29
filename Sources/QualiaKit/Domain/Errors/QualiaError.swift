/// Errors produced while validating public QualiaKit domain values.
///
/// Cases deliberately contain no input text or arbitrary framework messages.
public enum QualiaError: Error, Hashable, Sendable {
    case invalidInputID
    case invalidLanguage
    case invalidSignal
    case invalidAnalyzerIdentifier
    case invalidAnalyzerVersion
    case invalidWarningCode
    case emptyInput
    case invalidScore
    case invalidConfidence
}

enum QualiaDomainValidation {
    static func isBlank(_ value: String) -> Bool {
        value.isEmpty || value.allSatisfy(\.isWhitespace)
    }

    static func isValidWarningCodeSyntax(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 46, 48...57, 65...90, 95, 97...122:
                return true
            default:
                return false
            }
        }
    }
}
