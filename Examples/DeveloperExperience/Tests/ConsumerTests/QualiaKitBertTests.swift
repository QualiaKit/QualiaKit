import XCTest
import QualiaExamples
import QualiaKit
import QualiaTesting

@MainActor
final class QualiaKitBertTests: XCTestCase {
    func testUnsupportedHardwareStillAnalyzes() async throws {
        let model = QualiaKitBertDemoModel(renderer: RecordingHapticRenderer(capabilities: .unavailable))
        model.activate(preferences: .default)
        await model.waitUntilIdle()
        XCTAssertTrue(model.ready)
        XCTAssertFalse(model.hapticsAvailable)
        model.submit(QualiaKitBert.scenes[1].text, continuingStory: false)
        await model.waitUntilIdle()
        XCTAssertEqual(model.signals.count, 11)
        XCTAssertTrue(model.status.contains("unavailable"))
    }

    func testStopPreventsLateAnalysisFromReplaying() async throws {
        let analyzer = ControlledAnalyzer(
            capabilities: .init(languages: [try .init(rawValue: "en")], dimensions: [], signals: [.suspense], acceptsContext: true, execution: .onDevice),
            identity: try .init(identifier: "test.bert-demo", version: "1"), cancellationBehavior: .ignore)
        let renderer = RecordingHapticRenderer()
        let model = QualiaKitBertDemoModel(renderer: renderer, load: { analyzer })
        model.activate(preferences: .default)
        await model.waitUntilIdle()
        model.submit(QualiaKitBert.scenes[1].text, continuingStory: false)
        let request = try await analyzer.waitForRequest(number: 1)
        model.stop()
        try await analyzer.complete(request.number, signals: [.suspense: .init(value: 1)])
        await model.waitUntilIdle()
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        XCTAssertTrue(model.signals.isEmpty)
        XCTAssertTrue(model.history.isEmpty)
        XCTAssertFalse(renderer.commands.contains { if case .start = $0 { return true }; return false })
    }

    func testBundledModelUsesRealInferenceAndStopsThroughSession() async throws {
        let analyzer = try await QualiaKitBert.analyzer()
        XCTAssertEqual(analyzer.identity.identifier, "qualiakit.bert")
        let harness = try await QualiaSessionHarness(analyzer: analyzer, configuration: QualiaKitBert.configuration())
        let quiet = try await harness.process(.init(id: .init(rawValue: "quiet"), text: QualiaKitBert.scenes[0].text))
        XCTAssertEqual(quiet.observation.signals.count, 11)
        XCTAssertTrue(quiet.observation.signals.values.allSatisfy { $0.confidence == nil })
        XCTAssertTrue(quiet.reaction.hapticCommands.isEmpty)
        try await harness.reset()
        let tension = try await harness.process(.init(id: .init(rawValue: "suspense"), text: QualiaKitBert.scenes[1].text))
        guard case let .start(_, pattern, .ambient) = tension.reaction.hapticCommands.first else {
            return XCTFail("Real suspense scene should start the bounded demo heartbeat: \(tension.observation.signals)")
        }
        XCTAssertEqual(pattern.playbackDuration, .seconds(6))
        XCTAssertFalse(harness.renderer.activeEffects.isEmpty)
        try await harness.session.suspend()
        XCTAssertTrue(harness.renderer.activeEffects.isEmpty)
        let commandCount = harness.renderer.commands.count
        try await harness.session.resume()
        XCTAssertEqual(harness.renderer.commands.count, commandCount)
        try await harness.reset()
        let safe = try await harness.process(.init(id: .init(rawValue: "safe"), text: QualiaKitBert.scenes[2].text))
        XCTAssertTrue(safe.reaction.hapticCommands.isEmpty)
        do {
            _ = try await harness.process(.init(id: .init(rawValue: "long"), text: String(repeating: "waiting ", count: 200)))
            XCTFail("Oversized scenes must be rejected")
        } catch {}
    }

    func testModelDemoLifecyclePreferencesContextAndInvalidInput() async throws {
        let renderer = RecordingHapticRenderer()
        let model = QualiaKitBertDemoModel(renderer: renderer)
        model.activate(preferences: .default)
        await model.waitUntilIdle()
        XCTAssertTrue(model.ready)
        model.submit(QualiaKitBert.scenes[1].text, continuingStory: false)
        await model.waitUntilIdle()
        XCTAssertEqual(model.history.count, 1)
        XCTAssertFalse(renderer.activeEffects.isEmpty)
        model.deactivate()
        model.activate(preferences: .disabled)
        await model.waitUntilIdle()
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        XCTAssertTrue(model.ready)
        model.submit(QualiaKitBert.scenes[2].text, continuingStory: true)
        await model.waitUntilIdle()
        XCTAssertEqual(model.history.count, 2)
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        model.submit("Это длинная сцена на русском языке, а не английский текст для модели.", continuingStory: false)
        await model.waitUntilIdle()
        XCTAssertTrue(model.history.isEmpty)
        XCTAssertTrue(model.signals.isEmpty)
        XCTAssertTrue(model.status.contains("Could not process"))
        model.stop()
        await model.waitUntilIdle()
        XCTAssertTrue(renderer.activeEffects.isEmpty)
    }
}
