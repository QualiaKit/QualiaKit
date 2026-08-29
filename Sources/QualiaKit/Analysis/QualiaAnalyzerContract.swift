package enum QualiaAnalyzerContract {
    package static func analyze(
        _ analyzer: any QualiaAnalyzing,
        input: QualiaInput
    ) async throws -> QualiaObservation {
        try Task.checkCancellation()
        try validate(input: input, capabilities: analyzer.capabilities)

        let observation = try await analyzer.analyze(input)

        try Task.checkCancellation()
        try validate(
            observation: observation,
            for: input,
            capabilities: analyzer.capabilities
        )
        return observation
    }

    package static func validate(
        input: QualiaInput,
        capabilities: QualiaAnalyzerCapabilities
    ) throws {
        if let language = input.language,
           !capabilities.languages.contains(language) {
            throw QualiaError.unsupportedLanguage(language)
        }

        if !input.context.isEmpty, !capabilities.acceptsContext {
            throw QualiaError.unsupportedContext
        }
    }

    package static func validate(
        observation: QualiaObservation,
        for input: QualiaInput,
        capabilities: QualiaAnalyzerCapabilities
    ) throws {
        guard observation.inputID == input.id else {
            throw QualiaError.invalidAnalyzerOutput(identity: observation.analyzer)
        }
        guard capabilities.languages.contains(observation.language) else {
            throw QualiaError.invalidAnalyzerOutput(identity: observation.analyzer)
        }
        if observation.dimensions.valence != nil,
           !capabilities.dimensions.contains(.valence) {
            throw QualiaError.invalidAnalyzerOutput(identity: observation.analyzer)
        }
        guard Set(observation.signals.keys).isSubset(of: capabilities.signals) else {
            throw QualiaError.invalidAnalyzerOutput(identity: observation.analyzer)
        }
    }
}
