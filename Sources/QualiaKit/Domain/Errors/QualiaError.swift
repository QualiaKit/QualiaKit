/// Errors produced by QualiaKit domain validation and analyzer runtime contracts.
///
/// Runtime boundaries sanitize legacy host-supplied identifiers. Descriptions
/// never interpolate associated values or arbitrary framework messages.
public enum QualiaError: Error, Hashable, Sendable {
    case unsupportedLanguageIdentifier(QualiaDiagnosticFingerprint)
    case modelUnavailable(identifier: QualiaDiagnosticFingerprint)
    case invalidModelManifest(reason: QualiaFailureReason)
    case incompatibleModel(reason: QualiaFailureReason)
    case tokenizationFailed(reason: QualiaFailureReason)
    case inferenceFailed(reason: QualiaFailureReason)
    case invalidModelOutput(reason: QualiaFailureReason)
    case invalidConfiguration(reason: QualiaFailureReason)
    case invalidHapticPattern(reason: QualiaFailureReason)
    case hapticsUnavailable
    case hapticExecutionFailed(reason: QualiaFailureReason)
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
    case invalidLanguageConfiguration
    case invalidContextConfiguration
    case currentTextExceedsContextBounds
    case contextSizeOverflow
}

enum QualiaDomainValidation {
    static func isBlank(_ value: String) -> Bool {
        value.isEmpty || value.allSatisfy(\.isWhitespace)
    }
}

/// Closed reason vocabulary: never pass localizedDescription or framework dumps.
public enum QualiaFailureReason: String, Hashable, Sendable {
    case adapterFailure, manifestContract, modelContract, tokenizerContract
    case modelOutput, configuration, pattern, renderer, maximumDuration
}

extension QualiaError {
    /// Sanitizes plugin errors at the session boundary. Cancellation is handled
    /// separately by the caller. Existing validation categories stay recoverable.
    public static func redacted(_ error: any Error, stage: QualiaDiagnosticEvent.Stage) -> QualiaError {
        let candidate = (error as? QualiaErrorConvertible)?.qualiaError ?? (error as? QualiaError)
        guard let error = candidate else {
            switch stage {
            case .analysis: return .inferenceFailed(reason: .adapterFailure)
            case .preparation: return .invalidConfiguration(reason: .configuration)
            case .dispatch: return .hapticExecutionFailed(reason: .renderer)
            }
        }
        switch error {
        case .unsupportedLanguage(let language):
            return .unsupportedLanguageIdentifier(.init(metadata: language.rawValue))
        case .analyzerUnavailable(let identity):
            return .modelUnavailable(identifier: .init(metadata: identity.identifier))
        case .invalidAnalyzerOutput:
            return .invalidModelOutput(reason: .modelOutput)
        default: return error
        }
    }
}

/// Adapter errors can opt into a closed, safe public category. The session
/// sanitizes even this value before exposing it or recording a diagnostic.
public protocol QualiaErrorConvertible: Error {
    var qualiaError: QualiaError { get }
}

func redactedRuntimeError(_ error: any Error, stage: QualiaDiagnosticEvent.Stage) -> any Error {
    if error is CancellationError { return CancellationError() }
    // These enums contain only closed cases/numeric context, no arbitrary text.
    if let error = error as? HapticError { return error }
    if let error = error as? QualiaSessionError { return error }
    return QualiaError.redacted(error, stage: stage)
}

extension QualiaError: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .unsupportedLanguageIdentifier: return "unsupportedLanguageIdentifier"
        case .modelUnavailable: return "modelUnavailable"
        case .invalidModelManifest: return "invalidModelManifest"
        case .incompatibleModel: return "incompatibleModel"
        case .tokenizationFailed: return "tokenizationFailed"
        case .inferenceFailed: return "inferenceFailed"
        case .invalidModelOutput: return "invalidModelOutput"
        case .invalidConfiguration: return "invalidConfiguration"
        case .invalidHapticPattern: return "invalidHapticPattern"
        case .hapticsUnavailable: return "hapticsUnavailable"
        case .hapticExecutionFailed: return "hapticExecutionFailed"
        case .invalidInputID: return "invalidInputID"
        case .invalidLanguage: return "invalidLanguage"
        case .invalidSignal: return "invalidSignal"
        case .invalidAnalyzerIdentifier: return "invalidAnalyzerIdentifier"
        case .invalidAnalyzerVersion: return "invalidAnalyzerVersion"
        case .emptyInput: return "emptyInput"
        case .invalidScore: return "invalidScore"
        case .invalidConfidence: return "invalidConfidence"
        case .languageUndetermined: return "languageUndetermined"
        case .unsupportedLanguage: return "unsupportedLanguage"
        case .unsupportedContext: return "unsupportedContext"
        case .unsupportedInputStructure: return "unsupportedInputStructure"
        case .analyzerUnavailable: return "analyzerUnavailable"
        case .invalidAnalyzerOutput: return "invalidAnalyzerOutput"
        case .incompatibleFallbackCapabilities: return "incompatibleFallbackCapabilities"
        case .invalidLanguageConfiguration: return "invalidLanguageConfiguration"
        case .invalidContextConfiguration: return "invalidContextConfiguration"
        case .currentTextExceedsContextBounds: return "currentTextExceedsContextBounds"
        case .contextSizeOverflow: return "contextSizeOverflow"
        }
    }
    public var debugDescription: String { description }
}
