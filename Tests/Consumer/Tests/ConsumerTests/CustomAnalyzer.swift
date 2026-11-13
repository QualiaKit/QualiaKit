// snippet:start custom-analyzer
import QualiaKit

/// The host supplies reviewed annotations. This adapter does not classify text.
public struct AnnotatedSceneAnalyzer: QualiaAnalyzing {
    public let capabilities: QualiaAnalyzerCapabilities
    private let identity: QualiaAnalyzerIdentity
    private let annotations: [QualiaInputID: QualiaScore]

    public init(annotations: [QualiaInputID: QualiaScore]) throws {
        self.annotations = annotations
        identity = try .init(identifier: "example.authored-annotations", version: "1")
        capabilities = try .init(languages: [.init(rawValue: "en")], dimensions: [],
                                signals: [.impact], acceptsContext: false, execution: .onDevice)
    }

    public func analyze(_ input: QualiaInput) async throws -> QualiaObservation {
        try Task.checkCancellation()
        guard let language = input.language else { throw QualiaError.languageUndetermined }
        guard capabilities.languages.contains(language) else { throw QualiaError.unsupportedLanguage(language) }
        guard input.context.isEmpty else { throw QualiaError.unsupportedContext }
        let signals = annotations[input.id].map { [QualiaSignal.impact: $0] } ?? [:]
        return QualiaObservation(inputID: input.id, signals: signals, language: language, analyzer: identity)
    }
}
// snippet:end custom-analyzer
