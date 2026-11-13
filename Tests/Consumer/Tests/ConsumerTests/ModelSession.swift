// snippet:start model-session
import Foundation
import QualiaKit
import QualiaCoreML

@MainActor
public func makeNarrativeSession(bundle: Bundle, subdirectory: String) async throws -> QualiaSession {
    let analyzer = try await CoreMLQualiaAnalyzer(source: BundledQualiaModelSource(
        bundle: bundle, subdirectory: subdirectory
    ))
    return try await QualiaSession.horrorNarrative(
        analyzer: analyzer, renderer: CoreHapticRenderer(),
        language: .init(policy: .requireExplicit, minimumConfidence: 0.75),
        context: .init(maximumFragments: 0, maximumCharacters: 4_000)
    )
}
// snippet:end model-session
