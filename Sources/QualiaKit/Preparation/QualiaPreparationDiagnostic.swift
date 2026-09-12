/// Redacted preparation metadata. Payloads cannot carry text, IDs, language
/// strings, model tokens, or arbitrary error descriptions. Nothing is logged
/// unless the caller supplies a sink. Sinks may be called concurrently.
public enum QualiaPreparationDiagnostic: Hashable, Sendable {
    public enum LanguagePolicy: Hashable, Sendable {
        case requireExplicit, detect, preferExplicitThenDetect
    }

    public enum ConfidenceBucket: Hashable, Sendable {
        case belowThreshold, meetsThreshold
    }

    public enum LanguageOutcome: Hashable, Sendable {
        case resolved, undetermined, unsupported
    }

    public enum ContextOutcome: Hashable, Sendable {
        case unchanged, trimmed, currentTextTooLarge
    }

    public enum AnalyzerRejection: Hashable, Sendable {
        case unsupportedLanguage, unsupportedContext
    }

    public struct Counts: Hashable, Sendable {
        /// Historical fragments only. Characters and bytes include current text.
        public let fragments: Int
        public let characters: Int
        public let utf8Bytes: Int
    }

    case language(
        policy: LanguagePolicy,
        source: QualiaLanguageResolution.Source?,
        confidence: ConfidenceBucket?,
        outcome: LanguageOutcome
    )
    case context(before: Counts, after: Counts, outcome: ContextOutcome)
    case analyzerRejected(AnalyzerRejection)
}
