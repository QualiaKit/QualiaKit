import QualiaKit
import QualiaExamples
import Foundation

@main
struct Walkthrough {
    @MainActor static func main() async throws {
        if CommandLine.arguments.contains("--bert") {
            FileHandle.standardOutput.write(try await QualiaKitBert.evaluationReport())
            return
        }
        print("Scripted LivingStory · recording renderer · no physical sensation or model accuracy claim")
        print(try await explainScriptedDecision())
    }
}
