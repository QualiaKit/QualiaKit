// snippet:start living-story
import QualiaKit
import QualiaTesting

/// Scripted inputs demonstrate orchestration; no text meaning is inferred.
public enum LivingStory {
    public static func analyzer() throws -> FixtureAnalyzer {
        let english = try QualiaLanguage(rawValue: "en")
        let identity = try QualiaAnalyzerIdentity(identifier: "example.scripted-story", version: "1")
        return try FixtureAnalyzer(
            capabilities: .init(languages: [english], dimensions: [],
                signals: [.suspense, .threat, .impact], acceptsContext: true, execution: .onDevice),
            observations: [
                .init(inputID: .init(rawValue: "build"),
                      signals: [.suspense: .init(value: 0.5, confidence: 1)], language: english, analyzer: identity),
                .init(inputID: .init(rawValue: "impact"),
                      signals: [.suspense: .init(value: 1, confidence: 1), .impact: .init(value: 1, confidence: 1)],
                      language: english, analyzer: identity),
            ]
        )
    }

    public static func configuration() throws -> QualiaSessionConfiguration {
        try .init(language: .init(policy: .requireExplicit, minimumConfidence: 0.75),
            context: .init(maximumFragments: 4, maximumCharacters: 1_000), sceneState: .narrative,
            reaction: .horrorNarrative(.init(heartbeat: .init(
                startThreshold: 0.5, stopThreshold: 0.25, minimumBPM: 60, maximumBPM: 120))))
    }

    public static func input(_ id: String) throws -> QualiaInput {
        try .init(id: .init(rawValue: id), text: "Repository-authored scripted scene.", language: .init(rawValue: "en"))
    }

    @MainActor
    public static func makeSession(renderer: any HapticRendering,
                                   clock: any QualiaClock = QualiaContinuousClock()) async throws -> QualiaSession {
        try await QualiaSession.configured(analyzer: analyzer(), renderer: renderer,
                                         configuration: configuration(), clock: clock)
    }
}
// snippet:end living-story
