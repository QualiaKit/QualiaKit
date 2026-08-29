/// Sequentially invokes one primary analyzer and one explicitly configured fallback.
///
/// Only configured `QualiaFallbackCause` values may select the fallback. The
/// returned observation is not rewritten, so it retains the producing leaf
/// analyzer's identity.
public struct FallbackAnalyzer: QualiaAnalyzing {
    public let capabilities: QualiaAnalyzerCapabilities

    private let primary: any QualiaAnalyzing
    private let fallback: any QualiaAnalyzing
    private let causes: Set<QualiaFallbackCause>

    public init(
        primary: any QualiaAnalyzing,
        fallback: any QualiaAnalyzing,
        causes: Set<QualiaFallbackCause>
    ) throws {
        guard primary.capabilities.dimensions == fallback.capabilities.dimensions,
              primary.capabilities.signals == fallback.capabilities.signals,
              primary.capabilities.acceptsContext == fallback.capabilities.acceptsContext else {
            throw QualiaError.incompatibleFallbackCapabilities
        }

        self.primary = primary
        self.fallback = fallback
        self.causes = causes
        self.capabilities = QualiaAnalyzerCapabilities(
            languages: primary.capabilities.languages.union(fallback.capabilities.languages),
            dimensions: primary.capabilities.dimensions,
            signals: primary.capabilities.signals,
            acceptsContext: primary.capabilities.acceptsContext,
            execution: Self.compositeExecution(
                primary.capabilities.execution,
                fallback.capabilities.execution
            )
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
            return try await QualiaAnalyzerContract.analyze(fallback, input: input)
        }
    }

    private static func fallbackCause(for error: any Error) -> QualiaFallbackCause? {
        guard let error = error as? QualiaError else {
            return nil
        }
        switch error {
        case .languageUndetermined:
            return .languageUndetermined
        case .unsupportedLanguage:
            return .unsupportedLanguage
        case .analyzerUnavailable:
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
