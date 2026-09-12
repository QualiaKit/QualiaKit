/// Composes generic preparation before a host calls `QualiaAnalyzing.analyze`.
/// Owns no history or session lifecycle. Work runs off MainActor; cancellation
/// is checked around each synchronous stage. Diagnostics run on that worker.
public struct QualiaInputPreparer: Sendable {
    private let languageResolver: any QualiaLanguageResolving
    private let contextWindow: any QualiaContextWindowing
    private let diagnostics: (@Sendable (QualiaPreparationDiagnostic) -> Void)?

    public init(
        languageResolver: any QualiaLanguageResolving,
        contextWindow: any QualiaContextWindowing,
        diagnostics: (@Sendable (QualiaPreparationDiagnostic) -> Void)? = nil
    ) {
        self.languageResolver = languageResolver
        self.contextWindow = contextWindow
        self.diagnostics = diagnostics
    }

    public func prepare(
        _ input: QualiaInput,
        for capabilities: QualiaAnalyzerCapabilities
    ) async throws -> QualiaInput {
        try Task.checkCancellation()
        let worker = Task.detached {
            try prepareSynchronously(input, for: capabilities)
        }
        return try await withTaskCancellationHandler {
            do {
                let prepared = try await worker.value
                try Task.checkCancellation()
                return prepared
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            worker.cancel()
        }
    }

    private func prepareSynchronously(
        _ input: QualiaInput,
        for capabilities: QualiaAnalyzerCapabilities
    ) throws -> QualiaInput {
        try Task.checkCancellation()
        // Reject an incompatible explicit hint even under detect policy, before
        // any detector or analyzer work can silently replace that language.
        if let language = input.language, !capabilities.languages.contains(language) {
            diagnostics?(.analyzerRejected(.unsupportedLanguage))
            throw QualiaError.unsupportedLanguage(language)
        }
        let resolution = try languageResolver.resolve(for: input)
        try Task.checkCancellation()
        guard capabilities.languages.contains(resolution.language) else {
            diagnostics?(.analyzerRejected(.unsupportedLanguage))
            throw QualiaError.unsupportedLanguage(resolution.language)
        }
        let resolved = try QualiaInput(
            id: input.id, text: input.text, context: input.context, language: resolution.language
        )
        let bounded = try contextWindow.window(resolved)
        try Task.checkCancellation()
        if !bounded.context.isEmpty, !capabilities.acceptsContext {
            diagnostics?(.analyzerRejected(.unsupportedContext))
            throw QualiaError.unsupportedContext
        }
        try QualiaAnalyzerContract.validate(input: bounded, capabilities: capabilities)
        return bounded
    }
}
