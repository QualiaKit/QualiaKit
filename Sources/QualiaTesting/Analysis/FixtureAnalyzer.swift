import QualiaKit

public enum QualiaTestingError: Error, Hashable, Sendable {
    case duplicateFixture(QualiaInputID)
    case missingFixture(QualiaInputID)
    case unknownRequest(UInt64)
    case missingLanguage
    case nonMonotonicTime
    case invalidWaitCount
}

/// Immutable, explicitly scripted observations. Input IDs select fixtures;
/// text is never interpreted and no semantic model capability is implied.
public struct FixtureAnalyzer: QualiaAnalyzing {
    public let capabilities: QualiaAnalyzerCapabilities
    private let observations: [QualiaInputID: QualiaObservation]

    public init(capabilities: QualiaAnalyzerCapabilities, observations: [QualiaObservation]) throws {
        var indexed: [QualiaInputID: QualiaObservation] = [:]
        for observation in observations {
            guard indexed.updateValue(observation, forKey: observation.inputID) == nil else {
                throw QualiaTestingError.duplicateFixture(observation.inputID)
            }
        }
        self.capabilities = capabilities
        self.observations = indexed
    }

    public func analyze(_ input: QualiaInput) async throws -> QualiaObservation {
        try Task.checkCancellation()
        guard let observation = observations[input.id] else {
            throw QualiaTestingError.missingFixture(input.id)
        }
        return observation
    }
}
