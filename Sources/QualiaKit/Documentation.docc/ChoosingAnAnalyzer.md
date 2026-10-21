# Choosing an analyzer

Inspect `QualiaAnalyzing.capabilities` before building an interaction. Capabilities
stay stable for the analyzer's lifetime; the session validates input and output
against them. Declaration alone is not independent model-quality evidence.

| Analyzer | Languages and outputs | Context | Intended use |
| --- | --- | --- | --- |
| AppleSentimentAnalyzer | English valence, no confidence or narrative signals | One paragraph; no history | Lightweight sentiment preview |
| FixtureAnalyzer | Explicitly authored observations indexed by input ID | As declared by the fixture | Tests and clearly labelled scripted demos |
| CoreMLQualiaAnalyzer | Manifest-defined evaluated adapter contract | Manifest-defined | Licensed local model integration |
| Host implementation | Explicit stable capabilities | Explicitly declared | Authored annotations or independently evaluated custom inference |

The strict HorrorNarrativePolicy needs suspense, threat and an accent signal
(impact or shock), plus continuous haptic support. Keep its confidence policy
consistent with the analyzer's actual confidence semantics. Do not rename raw
sentiment labels into narrative signals to pass installation checks.

## A custom analyzer

This example reads host-authored annotations by event ID; it deliberately performs
no keyword classification or model inference. Missing annotations remain absent.
Its immutable storage is Sendable; expensive mutable model inference should be
isolated in an actor or worker, with cancellation checks around that work.

<!-- snippet: Examples/DeveloperExperience/Sources/QualiaExamples/CustomAnalyzer.swift#custom-analyzer -->
```swift
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
```

Return the same input ID and resolved language, only declared signals/dimensions,
finite normalized scores and real producing-analyzer identity. Preserve
CancellationError. Operational failures must throw rather than returning a
neutral observation. The session redacts arbitrary host error descriptions.

FallbackAnalyzer accepts only explicitly configured fallback causes and compatible
output/context contracts. It does not silently recover arbitrary inference errors.
Read <doc:UsingCoreMLModels> for assets and <doc:PrivacyAndDataFlow>
before letting a custom analyzer cross a device/network boundary.
