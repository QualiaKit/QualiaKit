// snippet:start integration-test
import XCTest
import QualiaKit
import QualiaTesting
import QualiaExamples

@MainActor
final class LivingStoryIntegrationTests: XCTestCase {
    func testLivingStoryOrderedCommandsAndReset() async throws {
        let harness = try await QualiaSessionHarness(
            analyzer: LivingStory.analyzer(), configuration: LivingStory.configuration()
        )
        _ = try await harness.process(LivingStory.input("build"))
        _ = try await harness.process(LivingStory.input("impact"), advancingBy: .seconds(1))
        try await harness.reset()

        // Independent literal descriptors: no policy or pattern factory is the oracle.
        let id = try HapticEffectID(rawValue: "qualia.horror-narrative.heartbeat", scope: .owned(harness.session.owner))
        let initial = try HapticPattern(duration: .seconds(2.0 / 3), events: [
            .transient(at: .zero, intensity: HapticValue(0.4), sharpness: HapticValue(0.2)),
            .transient(at: .seconds(1.0 / 6), intensity: HapticValue(0.2800000011920929), sharpness: HapticValue(0.2)),
        ], looping: .loop(period: .seconds(2.0 / 3)), playbackDuration: .seconds(12))
        let updated = try HapticPattern(duration: .seconds(0.5423728813559322), events: [
            .transient(at: .zero, intensity: HapticValue(0.5718749761581421), sharpness: HapticValue(0.2)),
            .transient(at: .seconds(0.13559322033898305), intensity: HapticValue(0.40031248331069946), sharpness: HapticValue(0.2)),
        ], looping: .loop(period: .seconds(0.5423728813559322)), playbackDuration: .seconds(11))
        let accent = try HapticPattern(duration: .milliseconds(120), events: [
            .transient(at: .zero, intensity: HapticValue(1), sharpness: HapticValue(0.85))
        ])
        XCTAssertEqual(harness.renderer.commands, [
            .start(id: id, pattern: initial, channel: .ambient),
            .replace(id: id, pattern: updated, channel: .ambient),
            .play(pattern: accent, channel: .accent), .stop(id: id),
        ])
        XCTAssertTrue(harness.renderer.activeEffects.isEmpty)
    }
}
// snippet:end integration-test

@MainActor
final class DeveloperExperienceTests: XCTestCase {
    func testCustomAnalyzerAndPolicyUsePublicContracts() async throws {
        let marked = try QualiaInputID(rawValue: "marked")
        let analyzer = try AnnotatedSceneAnalyzer(annotations: [marked: .init(value: 1, confidence: 1)])
        let harness = try await QualiaSessionHarness(analyzer: analyzer, configuration: .init(
            language: .init(policy: .requireExplicit, minimumConfidence: 0.75),
            context: .init(maximumFragments: 0, maximumCharacters: 1000), sceneState: .narrative,
            reaction: .custom(AuthoredAccentPolicy())))
        let response = try await harness.process(.init(id: marked, text: "An authored beat.", language: .init(rawValue: "en")))
        let expected = try HapticPattern(duration: .milliseconds(100), events: [
            .transient(at: .zero, intensity: HapticValue(0.4), sharpness: HapticValue(0.3))
        ])
        XCTAssertEqual(response.reaction.hapticCommands, [.play(pattern: expected, channel: .accent)])
        XCTAssertEqual(harness.renderer.commands, [.play(pattern: expected, channel: .accent)])
        let absent = try await harness.process(.init(id: .init(rawValue: "unmarked"), text: "An unmarked beat.", language: .init(rawValue: "en")))
        XCTAssertTrue(absent.reaction.hapticCommands.isEmpty)
        try await harness.reset()
    }

    func testScriptDoesNotClaimToAnalyzeUnseenText() async throws {
        do {
            _ = try await LivingStory.analyzer().analyze(LivingStory.input("unseen"))
            XCTFail("A fixture must not guess an observation")
        } catch let error as QualiaTestingError {
            XCTAssertEqual(error, .missingFixture(try .init(rawValue: "unseen")))
        }
    }

    func testPublicDebugReportExplainsActualCommands() async throws {
        let text = try await explainScriptedDecision()
        XCTAssertTrue(text.contains("Command: start; succeeded"))
        XCTAssertTrue(text.contains("Command: play; succeeded"))
        XCTAssertTrue(text.contains("State revision: 0 → 1"))
        XCTAssertFalse(text.contains("Repository-authored"))
        XCTAssertFalse(text.contains("example.scripted-story"))
    }
}
