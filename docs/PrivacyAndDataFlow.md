# Privacy and data flow

The core runtime has no networking or analytics transport. Apple preview and local
Core ML execute on device. Host-supplied analyzers and sinks define additional
boundaries; a capability saying on-device is a declaration to verify, not a network
sandbox. Never use semantic scores for diagnosis, mental-state inference, people
scoring or decisions about people.

QualiaInput contains raw text and optional history. A session keeps bounded accepted
history in memory; reset releases it. Context and input IDs may be sensitive.
Codable support is not permission to persist them. Example fixtures contain
repository-authored text and no production data.

## An opt-in explanation of a decision

The default diagnostics sink does nothing. This example uses a bounded in-memory
recording sink and a pure report formatter. The report shows fingerprinted analyzer,
language and policy identity, observation counts, state revisions, planned/attempted
commands, suppressions and timing. It deliberately does not include raw text, input
IDs, arbitrary policy facts, model tensors or signal scores. Use the same metadata
hash locally to match a known analyzer; do not label a fingerprint as a model score.

<!-- snippet: Examples/DeveloperExperience/Sources/QualiaExamples/DecisionReport.swift#decision-report -->
```swift
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
```

RecordingQualiaDiagnosticsSink drops newest events when full and counts drops.
QualiaDecisionReport keeps a bounded tail and reports its own omitted count; these
are different losses. Report text is for a local debug view, not a persisted parsing
schema. Formatting and display happen outside measured inference. OSLog's optional
sink additionally marks its already-redacted payload private. No sample uploads logs.

Custom sinks must return promptly, support concurrent calls and bound storage.
Do not print `localizedDescription` from arbitrary adapters or serialize a whole
response as a debug shortcut. Typed errors retain actionable categories while
sensitive associated metadata is removed. See [troubleshooting](GettingStarted.md).

Model licensing, provenance and asset hashes belong to installation;
[Core ML setup](UsingCoreMLModels.md) keeps them visible. The code license grants
no rights to weights, training text or external datasets.
