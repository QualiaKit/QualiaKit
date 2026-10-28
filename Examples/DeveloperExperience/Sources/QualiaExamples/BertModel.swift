// snippet:start bert-model
import Foundation
import QualiaCoreML

public func makeBertAnalyzer(modelDirectory: URL) async throws -> BertQualiaAnalyzer {
    try await BertQualiaAnalyzer(
        source: FileQualiaModelSource(directory: modelDirectory),
        configuration: .init(computeUnits: .cpuOnly)
    )
}
// snippet:end bert-model
