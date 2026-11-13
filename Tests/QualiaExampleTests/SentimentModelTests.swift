import XCTest
import QualiaKit
import QualiaTesting
@testable import QualiaExampleSupport

@MainActor
final class SentimentModelTests: XCTestCase {
    private func analyzer() throws -> ControlledAnalyzer {
        try ControlledAnalyzer(
            capabilities: .init(languages: [.init(rawValue: "en")], dimensions: [.valence],
                                signals: [], acceptsContext: false, execution: .onDevice),
            identity: .init(identifier: "example-test", version: "1"),
            cancellationBehavior: .ignore
        )
    }

    func testPulseSuspendResumeAndReset() async throws {
        let analyzer = try analyzer()
        let renderer = RecordingHapticRenderer()
        let model = SentimentModel(analyzer: analyzer, renderer: renderer)
        await model.setActive(true).value
        XCTAssertTrue(model.isReady)

        let work = Task { await model.analyze("A synthetic positive paragraph.") }
        _ = try await analyzer.waitForRequest(number: 1)
        try await analyzer.complete(1, dimensions: .init(valence: .init(value: 1)))
        await work.value
        XCTAssertEqual(renderer.commands.count, 1)
        XCTAssertTrue(model.status.contains("Pulse played"))

        await model.setActive(false).value
        XCTAssertFalse(model.isReady)
        let count = renderer.commands.count
        await model.setActive(true).value
        XCTAssertTrue(model.isReady)
        XCTAssertEqual(renderer.commands.count, count, "Resuming must not replay text")

        await model.setActive(false, reset: true).value
        XCTAssertFalse(model.isReady)
        XCTAssertFalse(model.isProcessing)
        XCTAssertTrue(renderer.activeEffects.isEmpty)
    }

    func testBackgroundDuringAnalysisCannotPlayOrReplacePausedStatus() async throws {
        let analyzer = try analyzer()
        let renderer = RecordingHapticRenderer()
        let model = SentimentModel(analyzer: analyzer, renderer: renderer)
        await model.setActive(true).value
        let work = Task { await model.analyze("A delayed paragraph.") }
        _ = try await analyzer.waitForRequest(number: 1)
        await model.setActive(false).value
        try await analyzer.complete(1, dimensions: .init(valence: .init(value: 1)))
        await work.value
        XCTAssertTrue(renderer.commands.isEmpty)
        XCTAssertFalse(model.isReady)
        XCTAssertEqual(model.status, "Paused.")
    }

    func testUnsupportedHardwareStaysDisabled() async {
        let model = SentimentModel(renderer: NoOpHapticRenderer())
        await model.setActive(true).value
        XCTAssertFalse(model.isReady)
        XCTAssertTrue(model.status.contains("compatible iPhone"))
    }

    func testPlaybackFailureRequiresResetBeforeRetry() async throws {
        let analyzer = try analyzer()
        let renderer = RecordingHapticRenderer()
        let model = SentimentModel(analyzer: analyzer, renderer: renderer)
        await model.setActive(true).value
        renderer.failNext()
        let work = Task { await model.analyze("A synthetic positive paragraph.") }
        _ = try await analyzer.waitForRequest(number: 1)
        try await analyzer.complete(1, dimensions: .init(valence: .init(value: 1)))
        await work.value
        XCTAssertFalse(model.isReady)
        XCTAssertTrue(model.status.contains("Tap Reset"))
        await model.setActive(true, reset: true).value
        XCTAssertTrue(model.isReady)
    }
}
