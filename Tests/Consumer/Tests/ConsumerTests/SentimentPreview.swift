// snippet:start sentiment-preview
import QualiaKit

@MainActor
public func makeSentimentPreview() async throws -> QualiaSession {
    let renderer = CoreHapticRenderer()
    guard renderer.capabilities.supportsHaptics else {
        throw QualiaError.hapticsUnavailable
    }
    return try await QualiaSession.sentimentPreview(
        analyzer: AppleSentimentAnalyzer(), renderer: renderer,
        language: .init(policy: .requireExplicit, minimumConfidence: 0.75),
        context: .init(maximumFragments: 0, maximumCharacters: 4_000)
    )
}

public func previewFirstFragment(in session: QualiaSession) async throws -> QualiaResponse {
    let response = try await session.process(QualiaInput(
        id: .init(rawValue: "first-fragment"),
        text: "This is a wonderful, joyful day!", language: .init(rawValue: "en")
    ))
    if let failure = response.execution.failure { throw failure }
    return response
}
// snippet:end sentiment-preview
