import Foundation
import QualiaCoreML
import QualiaKit

/// Experimental English narrative model, bundled only with this example package.
public enum QualiaKitBert {
    public static func analyzer() async throws -> BertQualiaAnalyzer {
        try await BertQualiaAnalyzer(source: BundledQualiaModelSource(
            bundle: .module, subdirectory: "QualiaKitBert"))
    }

    public static func configuration(hapticsAvailable: Bool = true) throws -> QualiaSessionConfiguration {
        try .init(
            language: .init(policy: .detect(allowed: [.init(rawValue: "en")]), minimumConfidence: 0.45),
            context: .init(maximumFragments: 2, maximumCharacters: 2_000),
            sceneState: .narrative,
            reaction: hapticsAvailable ? .horrorNarrative(.init(heartbeat: .init(
                startThreshold: 0.5, stopThreshold: 0.25,
                // Sigmoid scores are not calibrated confidence. This is an explicit demo choice.
                minimumSignalConfidence: 0, maximumDuration: .seconds(6)))) : .noReaction,
            haptics: .init(preferences: .init(intensityScale: 0.5, maximumContinuousDuration: .seconds(6))))
    }

    public struct Scene: Identifiable, Sendable {
        public let id: String
        public let text: String
    }

    public static let scenes: [Scene] = [
        .init(id: "Quiet", text: "She set a cup of tea on the table and opened the morning newspaper."),
        .init(id: "Suspense", text: "I hid behind the cupboard as the intruder tried the door. His footsteps stopped. I waited, afraid to breathe."),
        .init(id: "Safe again", text: "The intruder had been arrested. Everyone was safe. I relaxed on the sofa, grateful that it was finally over."),
    ]

    public struct Probes: Decodable, Sendable {
        public let annotation: String
        public let threshold: Float
        public let cases: [Probe]
    }

    public struct Probe: Decodable, Sendable {
        public let id: String
        public let text: String
        public let suspense: Bool
    }

    public static func probes() throws -> Probes {
        guard let url = Bundle.module.url(forResource: "QualiaKitBertProbes", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Probes.self, from: Data(contentsOf: url))
    }
}
