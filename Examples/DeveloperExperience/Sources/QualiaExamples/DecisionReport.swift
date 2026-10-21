// snippet:start decision-report
import QualiaKit
import QualiaTesting

@MainActor
public func explainScriptedDecision() async throws -> String {
    let diagnostics = try RecordingQualiaDiagnosticsSink(capacity: 256)
    let renderer = RecordingHapticRenderer()
    let session = try await QualiaSession.horrorNarrative(
        analyzer: LivingStory.analyzer(), renderer: renderer,
        language: .init(policy: .requireExplicit, minimumConfidence: 0.75),
        context: .init(maximumFragments: 4, maximumCharacters: 1_000),
        diagnostics: .init(sink: diagnostics)
    )
    let response: QualiaResponse
    do { response = try await session.process(LivingStory.input("impact")) }
    catch { try await session.reset(); throw error }
    try await session.reset()
    if let failure = response.execution.failure { throw failure }
    let report = try QualiaDecisionReport(events: diagnostics.entries.map(\.event))
    return report.text + "\nDropped by sink: \(diagnostics.droppedEventCount); omitted by report: \(report.omittedEventCount)"
}
// snippet:end decision-report
