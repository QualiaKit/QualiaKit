public enum QualiaLanguagePolicy: Sendable {
    case requireExplicit
    /// Detect current text even if the input contains an explicit language.
    case detect(allowed: Set<QualiaLanguage>)
    /// An explicit but disallowed language fails without running detection.
    case preferExplicitThenDetect(allowed: Set<QualiaLanguage>)
}

public struct QualiaLanguageResolution: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        case explicit, detected
    }

    public let language: QualiaLanguage
    public let source: Source
    public let confidence: Float?

    public init(language: QualiaLanguage, source: Source, confidence: Float?) throws {
        if let confidence, !confidence.isFinite || !(0...1).contains(confidence) {
            throw QualiaError.invalidConfidence
        }
        self.language = language
        self.source = source
        self.confidence = confidence
    }
}

public struct QualiaLanguageDetection: Hashable, Sendable {
    public let language: QualiaLanguage
    public let confidence: Float

    public init(language: QualiaLanguage, confidence: Float) throws {
        guard confidence.isFinite, (0...1).contains(confidence) else {
            throw QualiaError.invalidConfidence
        }
        self.language = language
        self.confidence = confidence
    }
}

public protocol QualiaLanguageDetecting: Sendable {
    /// Return the best unconstrained hypothesis, or nil for undetermined text.
    /// Implementations must support concurrent calls and must not log text.
    func detectLanguage(in text: String) -> QualiaLanguageDetection?
}

public protocol QualiaLanguageResolving: Sendable {
    func resolve(for input: QualiaInput) throws -> QualiaLanguageResolution
}

/// Immutable policy evaluation. Thresholds and detection allow-lists are explicit;
/// analyzer capabilities are checked separately by `QualiaInputPreparer`.
public struct QualiaLanguageResolver: QualiaLanguageResolving {
    public let policy: QualiaLanguagePolicy
    public let minimumConfidence: Float
    private let detector: any QualiaLanguageDetecting
    private let diagnostics: (@Sendable (QualiaPreparationDiagnostic) -> Void)?

    public init(
        policy: QualiaLanguagePolicy,
        minimumConfidence: Float,
        detector: any QualiaLanguageDetecting = AppleLanguageDetector(),
        diagnostics: (@Sendable (QualiaPreparationDiagnostic) -> Void)? = nil
    ) throws {
        guard minimumConfidence.isFinite, (0...1).contains(minimumConfidence) else {
            throw QualiaError.invalidLanguageConfiguration
        }
        switch policy {
        case .requireExplicit:
            break
        case .detect(let allowed), .preferExplicitThenDetect(let allowed):
            guard !allowed.isEmpty else { throw QualiaError.invalidLanguageConfiguration }
        }
        self.policy = policy
        self.minimumConfidence = minimumConfidence
        self.detector = detector
        self.diagnostics = diagnostics
    }

    public func resolve(for input: QualiaInput) throws -> QualiaLanguageResolution {
        switch policy {
        case .requireExplicit:
            guard let language = input.language else {
                emit(source: nil, outcome: .undetermined)
                throw QualiaError.languageUndetermined
            }
            return try explicit(language)
        case .detect(let allowed):
            return try detect(input.text, allowed: allowed)
        case .preferExplicitThenDetect(let allowed):
            if let language = input.language {
                guard allowed.contains(language) else {
                    emit(source: .explicit, outcome: .unsupported)
                    throw QualiaError.unsupportedLanguage(language)
                }
                return try explicit(language)
            }
            return try detect(input.text, allowed: allowed)
        }
    }

    private func explicit(_ language: QualiaLanguage) throws -> QualiaLanguageResolution {
        emit(source: .explicit, outcome: .resolved)
        return try QualiaLanguageResolution(language: language, source: .explicit, confidence: nil)
    }

    private func detect(_ text: String, allowed: Set<QualiaLanguage>) throws -> QualiaLanguageResolution {
        guard let result = detector.detectLanguage(in: text) else {
            emit(source: .detected, outcome: .undetermined)
            throw QualiaError.languageUndetermined
        }
        guard result.confidence >= minimumConfidence else {
            emit(source: .detected, confidence: .belowThreshold, outcome: .undetermined)
            throw QualiaError.languageUndetermined
        }
        guard allowed.contains(result.language) else {
            emit(source: .detected, confidence: .meetsThreshold, outcome: .unsupported)
            throw QualiaError.unsupportedLanguage(result.language)
        }
        emit(source: .detected, confidence: .meetsThreshold, outcome: .resolved)
        return try QualiaLanguageResolution(
            language: result.language, source: .detected, confidence: result.confidence
        )
    }

    private func emit(
        source: QualiaLanguageResolution.Source?,
        confidence: QualiaPreparationDiagnostic.ConfidenceBucket? = nil,
        outcome: QualiaPreparationDiagnostic.LanguageOutcome
    ) {
        let name: QualiaPreparationDiagnostic.LanguagePolicy
        switch policy {
        case .requireExplicit: name = .requireExplicit
        case .detect: name = .detect
        case .preferExplicitThenDetect: name = .preferExplicitThenDetect
        }
        diagnostics?(.language(policy: name, source: source, confidence: confidence, outcome: outcome))
    }
}
