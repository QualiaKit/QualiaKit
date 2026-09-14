/// Sequentially invokes one primary analyzer and one explicitly configured fallback.
///
/// Only configured `QualiaFallbackCause` values may select the fallback. The
/// returned observation is not rewritten, so it retains the producing leaf
/// analyzer's identity.
public struct FallbackAnalyzer: QualiaAnalyzing {
    public let capabilities: QualiaAnalyzerCapabilities

    public var diagnosticIdentity: QualiaDiagnosticIdentity? {
        .init(identifier: "com.qualiakit.fallback", version: "1")
    }
    private let diagnostics: any QualiaDiagnosticsSink
    private let primary: any QualiaAnalyzing
    private let fallback: any QualiaAnalyzing
    private let causes: Set<QualiaFallbackCause>

    public init(
        primary: any QualiaAnalyzing,
        fallback: any QualiaAnalyzing,
        causes: Set<QualiaFallbackCause>,
        diagnostics: any QualiaDiagnosticsSink = NoOpQualiaDiagnosticsSink()
    ) throws {
        guard primary.capabilities.dimensions == fallback.capabilities.dimensions,
              primary.capabilities.signals == fallback.capabilities.signals,
              primary.capabilities.acceptsContext == fallback.capabilities.acceptsContext else {
            throw QualiaError.incompatibleFallbackCapabilities
        }

        self.diagnostics = diagnostics
        self.primary = primary
        self.fallback = fallback
        self.causes = causes
        let advertisedLanguages = causes.contains(.unsupportedLanguage)
            ? primary.capabilities.languages.union(fallback.capabilities.languages)
            : primary.capabilities.languages
        let advertisedExecution = causes.isEmpty
            ? primary.capabilities.execution
            : Self.compositeExecution(
                primary.capabilities.execution,
                fallback.capabilities.execution
            )
        self.capabilities = QualiaAnalyzerCapabilities(
            languages: advertisedLanguages,
            dimensions: primary.capabilities.dimensions,
            signals: primary.capabilities.signals,
            acceptsContext: primary.capabilities.acceptsContext,
            execution: advertisedExecution
        )
    }

    public func analyze(_ input: QualiaInput) async throws -> QualiaObservation {
        do {
            return try await QualiaAnalyzerContract.analyze(primary, input: input)
        } catch {
            if error is CancellationError {
                throw error
            }
            try Task.checkCancellation()

            guard let cause = Self.fallbackCause(for: error), causes.contains(cause) else {
                throw error
            }
            diagnostics.emit(.fallbackSelected(cause: cause, analyzer: fallback.diagnosticIdentity))
            return try await QualiaAnalyzerContract.analyze(fallback, input: input)
        }
    }

    private static func fallbackCause(for error: any Error) -> QualiaFallbackCause? {
        guard let error = (error as? QualiaErrorConvertible)?.qualiaError ?? (error as? QualiaError) else {
            return nil
        }
        switch error {
        case .languageUndetermined:
            return .languageUndetermined
        case .unsupportedLanguage, .unsupportedLanguageIdentifier:
            return .unsupportedLanguage
        case .analyzerUnavailable, .modelUnavailable:
            return .analyzerUnavailable
        default:
            return nil
        }
    }

    private static func compositeExecution(
        _ primary: QualiaExecutionMode,
        _ fallback: QualiaExecutionMode
    ) -> QualiaExecutionMode {
        primary == fallback ? primary : .hybrid
    }
}
