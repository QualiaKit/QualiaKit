import Foundation
import XCTest
import QualiaKit
import QualiaTesting

@MainActor
final class DeveloperExperienceTests: XCTestCase {
    func testPreviewCapabilitiesCannotBeUsedAsNarrativeAnalysis() async throws {
        let analyzer = AppleSentimentAnalyzer()
        XCTAssertEqual(analyzer.capabilities.languages, [try QualiaLanguage(rawValue: "en")])
        XCTAssertEqual(analyzer.capabilities.dimensions, [.valence])
        XCTAssertTrue(analyzer.capabilities.signals.isEmpty)
        XCTAssertFalse(analyzer.capabilities.acceptsContext)
        do {
            _ = try await QualiaSession.horrorNarrative(analyzer: analyzer, renderer: RecordingHapticRenderer(),
                language: .init(policy: .requireExplicit, minimumConfidence: 0.75),
                context: .init(maximumFragments: 0, maximumCharacters: 1000))
            XCTFail("Valence cannot satisfy narrative requirements")
        } catch let error as QualiaError {
            XCTAssertEqual(error, .invalidConfiguration(reason: .configuration))
        }
    }

    func testDecisionReportIsBoundedAndRedactsHostMetadata() throws {
        let secret = "PRIVATE INPUT WITH NEWLINE\nspoofed diagnostic"
        let identity = QualiaDiagnosticIdentity(identifier: secret, version: secret)
        let session = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let events: [QualiaDiagnosticEvent] = [
            .correlated(session: session, generation: 1, event: .installed(analyzer: identity, policy: identity, runtime: identity)),
            .correlated(session: session, generation: 1, event: .language(.init(metadata: secret))),
            .correlated(session: session, generation: 1, event: .policy(identity: identity, rule: .init(metadata: secret), commandCount: 0)),
            .correlated(session: session, generation: 1, event: .failure(stage: .analysis,
                error: .redacted(QualiaError.analyzerUnavailable(identity: try .init(identifier: secret, version: secret)), stage: .analysis))),
            .correlated(session: session, generation: 1, event: .suppressed(.disabled)),
        ]
        let complete = try QualiaDecisionReport(events: events)
        XCTAssertFalse(complete.text.contains(secret))
        XCTAssertFalse(complete.text.contains("PRIVATE INPUT"))
        XCTAssertEqual(complete.lines.count, 5)
        XCTAssertTrue(complete.text.contains("Failure: analysis, modelUnavailable"))
        let tail = try QualiaDecisionReport(events: events, maximumEvents: 1)
        XCTAssertEqual(tail.omittedEventCount, 4)
        XCTAssertEqual(tail.lines, ["[00000000-0000-0000-0000-000000000001 #1] Suppressed: disabled"])
        for bound in [0, -1, 4097] { XCTAssertThrowsError(try QualiaDecisionReport(events: events, maximumEvents: bound)) }
    }

    func testCommandLevelConsumerWorksWithoutInternalImportsOrHardware() async throws {
        let language = try QualiaLanguage(rawValue: "en")
        let id = try QualiaInputID(rawValue: "public-consumer")
        let analyzer = try FixtureAnalyzer(capabilities: .init(languages: [language], dimensions: [.valence], signals: [], acceptsContext: false, execution: .onDevice),
            observations: [.init(inputID: id, dimensions: .init(valence: .init(value: 1)), language: language,
                                 analyzer: .init(identifier: "synthetic-preview", version: "1"))])
        let harness = try await QualiaSessionHarness(analyzer: analyzer, configuration: .init(
            language: .init(policy: .requireExplicit, minimumConfidence: 0.75),
            context: .init(maximumFragments: 0, maximumCharacters: 1000), sceneState: .sentimentPreview,
            reaction: .sentimentPreview(.default)))
        let response = try await harness.process(.init(id: id, text: "A public fixture.", language: language))
        XCTAssertEqual(response.execution.commands.count, 1)
        XCTAssertEqual(response.execution.commands.first?.outcome, .succeeded)
        guard case .play(_, .accent)? = harness.renderer.commands.first else { return XCTFail("Expected a preview accent") }
        try await harness.reset()
        XCTAssertTrue(harness.renderer.activeEffects.isEmpty)
    }
}
