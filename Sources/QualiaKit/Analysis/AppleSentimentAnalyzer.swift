import NaturalLanguage

/// A stateless on-device English valence baseline backed by Apple Natural Language.
///
/// This analyzer accepts only explicit `"en"` input without context. It maps
/// Apple's `-1...1` sentiment score to `0...1` valence and does not emit signals
/// or confidence.
public struct AppleSentimentAnalyzer: QualiaAnalyzing {
    public let capabilities = QualiaAnalyzerCapabilities(
        languages: [QualiaLanguage(validatedRawValue: "en")],
        dimensions: [.valence],
        signals: [],
        acceptsContext: false,
        execution: .onDevice
    )

    private static let identity = QualiaAnalyzerIdentity(
        validatedIdentifier: "com.qualiakit.apple-sentiment",
        version: "1"
    )

    public init() {}

    public func analyze(_ input: QualiaInput) async throws -> QualiaObservation {
        try Task.checkCancellation()
        guard let language = input.language else {
            throw QualiaError.languageUndetermined
        }

        try QualiaAnalyzerContract.validate(input: input, capabilities: capabilities)
        let appleScore = try await sentimentScore(for: input.text)
        let valence = try Self.normalizedValence(fromAppleScore: appleScore)
        let observation = QualiaObservation(
            inputID: input.id,
            dimensions: QualiaDimensions(valence: valence),
            language: language,
            analyzer: Self.identity
        )
        try QualiaAnalyzerContract.validate(
            observation: observation,
            for: input,
            capabilities: capabilities
        )
        return observation
    }

    static func normalizedValence(fromAppleScore score: Float) throws -> QualiaScore {
        guard score.isFinite, (-1...1).contains(score) else {
            throw QualiaError.invalidAnalyzerOutput(identity: identity)
        }
        return try QualiaScore(value: (score + 1) / 2)
    }

    private func sentimentScore(for text: String) async throws -> Float {
        let worker = Task.detached { () throws -> Float in
            try Task.checkCancellation()

            let tagger = NLTagger(tagSchemes: [.sentimentScore])
            tagger.string = text
            let (tag, _) = tagger.tag(
                at: text.startIndex,
                unit: .paragraph,
                scheme: .sentimentScore
            )

            try Task.checkCancellation()
            guard let rawValue = tag?.rawValue,
                  let score = Float(rawValue) else {
                throw QualiaError.invalidAnalyzerOutput(identity: Self.identity)
            }
            return score
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
