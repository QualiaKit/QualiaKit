import XCTest
import QualiaTesting
@testable import QualiaKit

@MainActor
final class SentimentFeedbackTests: XCTestCase {
    private func analyzer() throws -> ControlledAnalyzer {
        try ControlledAnalyzer(
            capabilities: .init(languages: [.init(rawValue: "en")], dimensions: [.valence],
                                signals: [], acceptsContext: false, execution: .onDevice),
            identity: .init(identifier: "feedback-test", version: "1"),
            cancellationBehavior: .ignore
        )
    }

    func testPulseNeutralTextAndFreshInputIdentities() async throws {
        let analyzer = try analyzer()
        let renderer = RecordingHapticRenderer()
        let feedback = SentimentFeedback(analyzer: analyzer, renderer: renderer)
        await feedback.setActive(true).value
        XCTAssertTrue(feedback.isReady)

        let first = Task { await feedback.analyze("A positive paragraph.") }
        let firstInput = try await analyzer.waitForRequest(number: 1).input
        try await analyzer.complete(1, dimensions: .init(valence: .init(value: 1)))
        await first.value
        XCTAssertEqual(feedback.score, 1)
        XCTAssertTrue(feedback.playedHaptic)
        XCTAssertEqual(renderer.commands.count, 1)

        let second = Task { await feedback.analyze("A neutral paragraph.") }
        let secondInput = try await analyzer.waitForRequest(number: 2).input
        try await analyzer.complete(2, dimensions: .init(valence: .init(value: 0.5)))
        await second.value
        XCTAssertNotEqual(firstInput.id, secondInput.id)
        XCTAssertEqual(secondInput.language, try .init(rawValue: "en"))
        XCTAssertTrue(secondInput.context.isEmpty)
        XCTAssertEqual(feedback.score, 0.5)
        XCTAssertFalse(feedback.playedHaptic)
        XCTAssertEqual(renderer.commands.count, 1)

        await feedback.setActive(false).value
        await feedback.setActive(true).value
        XCTAssertEqual(renderer.commands.count, 1, "Returning must not replay text")
        await feedback.reset().value
        XCTAssertNil(feedback.response)
        XCTAssertTrue(feedback.isReady)
        await feedback.setActive(false).value
    }

    func testLeavingDuringAnalysisDiscardsCancellationIgnoringResult() async throws {
        let analyzer = try analyzer()
        let renderer = RecordingHapticRenderer()
        let feedback = SentimentFeedback(analyzer: analyzer, renderer: renderer)
        await feedback.setActive(true).value
        let work = Task { await feedback.analyze("A delayed paragraph.") }
        _ = try await analyzer.waitForRequest(number: 1)
        let cleanup = feedback.transition(to: false, clearResult: true)
        cleanup.cancel()
        await cleanup.value
        try await analyzer.complete(1, dimensions: .init(valence: .init(value: 1)))
        await work.value
        XCTAssertTrue(renderer.commands.isEmpty)
        XCTAssertFalse(feedback.isReady)
        XCTAssertFalse(feedback.isProcessing)
        XCTAssertNil(feedback.response)
        XCTAssertNil(feedback.error)
        XCTAssertTrue(renderer.lifecycleHistory.contains { if case .stopOwnedEffects = $0 { return true }; return false })
        await feedback.reset().value
        XCTAssertFalse(feedback.isReady, "Reset on an invisible screen must not reactivate it")
    }

    func testLatestAnalysisWinsAndCallerCancellationDoesNotPlay() async throws {
        let analyzer = try analyzer()
        let renderer = RecordingHapticRenderer()
        let feedback = SentimentFeedback(analyzer: analyzer, renderer: renderer)
        await feedback.setActive(true).value
        let first = Task { await feedback.analyze("Old text.") }
        _ = try await analyzer.waitForRequest(number: 1)
        let second = Task { await feedback.analyze("New text.") }
        _ = try await analyzer.waitForRequest(number: 2)
        try await analyzer.complete(2, dimensions: .init(valence: .init(value: 0)))
        await second.value
        try await analyzer.complete(1, dimensions: .init(valence: .init(value: 1)))
        await first.value
        XCTAssertEqual(feedback.score, 0)
        XCTAssertEqual(renderer.commands.count, 1)

        let cancelled = Task { await feedback.analyze("Cancelled text.") }
        _ = try await analyzer.waitForRequest(number: 3)
        cancelled.cancel()
        try await analyzer.complete(3, dimensions: .init(valence: .init(value: 1)))
        await cancelled.value
        XCTAssertNil(feedback.response)
        XCTAssertNil(feedback.error)
        XCTAssertFalse(feedback.isProcessing)
        XCTAssertEqual(renderer.commands.count, 1)
        await feedback.setActive(false).value
    }

    func testUnsupportedHardwareStillAnalyzes() async throws {
        let analyzer = try analyzer()
        let renderer = RecordingHapticRenderer(capabilities: .unavailable)
        let feedback = SentimentFeedback(analyzer: analyzer, renderer: renderer)
        await feedback.setActive(true).value
        XCTAssertFalse(feedback.supportsHaptics)
        XCTAssertTrue(feedback.isReady)
        let work = Task { await feedback.analyze("Positive text.") }
        _ = try await analyzer.waitForRequest(number: 1)
        try await analyzer.complete(1, dimensions: .init(valence: .init(value: 1)))
        await work.value
        XCTAssertEqual(feedback.score, 1)
        XCTAssertFalse(feedback.playedHaptic)
        XCTAssertNil(feedback.error)
        XCTAssertTrue(renderer.lifecycleHistory.isEmpty)
        await feedback.setActive(false).value
    }

    func testLatestTextWinsWhileSetupIsStillPending() async {
        let analyzer = AppleSentimentAnalyzer(sentimentScorer: { text in
            text == "Older text." ? 1 : -1
        })
        let feedback = SentimentFeedback(analyzer: analyzer, renderer: NoOpHapticRenderer())
        feedback.setActive(true)
        let first = Task { await feedback.analyze("Older text.") }
        let second = Task { await feedback.analyze("Newer text.") }
        await first.value
        await second.value
        XCTAssertEqual(feedback.score, 0)
        XCTAssertFalse(feedback.isProcessing)
        XCTAssertNil(feedback.error)
        await feedback.setActive(false).value
    }

    func testDisablingHapticsCancelsPendingPlaybackAndKeepsAnalysis() async throws {
        let analyzer = try analyzer()
        let renderer = RecordingHapticRenderer()
        let feedback = SentimentFeedback(analyzer: analyzer, renderer: renderer)
        await feedback.setActive(true).value
        let old = Task { await feedback.analyze("Old text.") }
        _ = try await analyzer.waitForRequest(number: 1)
        feedback.hapticsEnabled = false
        let new = Task { await feedback.analyze("New text without vibration.") }
        _ = try await analyzer.waitForRequest(number: 2)
        try await analyzer.complete(2, dimensions: .init(valence: .init(value: 0.9)))
        await new.value
        try await analyzer.complete(1, dimensions: .init(valence: .init(value: 1)))
        await old.value
        XCTAssertEqual(feedback.score, 0.9)
        XCTAssertFalse(feedback.playedHaptic)
        XCTAssertTrue(renderer.commands.isEmpty)
        XCTAssertTrue(feedback.isReady)
        feedback.hapticsEnabled = true
        await feedback.setActive(true).value
        XCTAssertTrue(renderer.commands.isEmpty)
        await feedback.setActive(false).value
    }

    func testPlaybackFailureIsVisibleAndResetAllowsRetry() async throws {
        let analyzer = try analyzer()
        let renderer = RecordingHapticRenderer()
        let feedback = SentimentFeedback(analyzer: analyzer, renderer: renderer)
        await feedback.setActive(true).value
        renderer.failNext()
        let work = Task { await feedback.analyze("Positive text.") }
        _ = try await analyzer.waitForRequest(number: 1)
        try await analyzer.complete(1, dimensions: .init(valence: .init(value: 1)))
        await work.value
        XCTAssertFalse(feedback.isReady)
        XCTAssertFalse(feedback.playedHaptic)
        XCTAssertNotNil(feedback.error)
        XCTAssertEqual(feedback.score, 1, "Successful analysis remains available after playback fails")
        await feedback.reset().value
        XCTAssertTrue(feedback.isReady)
        XCTAssertNil(feedback.error)
        let retry = Task { await feedback.analyze("Positive text again.") }
        _ = try await analyzer.waitForRequest(number: 2)
        try await analyzer.complete(2, dimensions: .init(valence: .init(value: 1)))
        await retry.value
        XCTAssertTrue(feedback.playedHaptic)
        await feedback.setActive(false).value
    }

    func testFailedCleanupBlocksReplacementUntilResetSucceeds() async throws {
        let renderer = FeedbackCleanupRenderer()
        let feedback = SentimentFeedback(analyzer: try analyzer(), renderer: renderer)
        await feedback.setActive(true).value
        renderer.failCleanup = true
        await feedback.analyze("Cannot play before cleanup completes.")
        XCTAssertFalse(feedback.isReady)
        XCTAssertNotNil(feedback.error)
        await feedback.setActive(false).value
        await feedback.setActive(true).value
        XCTAssertFalse(feedback.isReady)
        XCTAssertNotNil(feedback.error)
        XCTAssertEqual(renderer.prepareCount, 1, "A failed cleanup must not abandon the old session")
        renderer.failCleanup = false
        await feedback.reset().value
        XCTAssertTrue(feedback.isReady)
        XCTAssertNil(feedback.error)
        XCTAssertEqual(renderer.prepareCount, 2)
        await feedback.setActive(false).value
    }

    func testRapidVisibilityChangesEndInRequestedState() async throws {
        let renderer = RecordingHapticRenderer()
        let feedback = SentimentFeedback(analyzer: try analyzer(), renderer: renderer)
        feedback.setActive(true)
        feedback.setActive(false)
        await feedback.setActive(true).value
        XCTAssertTrue(feedback.isReady)
        XCTAssertNil(feedback.error)
        feedback.setActive(false)
        feedback.setActive(true)
        await feedback.setActive(false).value
        XCTAssertFalse(feedback.isReady)
        XCTAssertNil(feedback.error)
        XCTAssertTrue(renderer.commands.isEmpty)
    }

    func testPublicDefaultsValidateInputAndRecoverAfterSetupFailure() async throws {
        let feedback = SentimentFeedback(hapticsEnabled: false)
        await feedback.setActive(true).value
        await feedback.analyze("   ")
        XCTAssertEqual(feedback.error as? QualiaError, .emptyInput)
        await feedback.analyze(String(repeating: "a", count: 4_001))
        XCTAssertEqual(feedback.error as? QualiaError, .currentTextExceedsContextBounds)
        await feedback.analyze("First paragraph.\n\nSecond paragraph.")
        XCTAssertEqual(feedback.error as? QualiaError, .unsupportedInputStructure)
        await feedback.setActive(false).value

        let renderer = RecordingHapticRenderer()
        renderer.failNext()
        let retry = SentimentFeedback(analyzer: try analyzer(), renderer: renderer)
        await retry.setActive(true).value
        XCTAssertFalse(retry.isReady)
        XCTAssertNotNil(retry.error)
        await retry.reset().value
        XCTAssertTrue(retry.isReady)
        XCTAssertNil(retry.error)
        await retry.setActive(false).value
    }
}

@MainActor
private final class FeedbackCleanupRenderer: HapticRendering {
    let base = RecordingHapticRenderer()
    var failCleanup = false
    var prepareCount = 0
    var capabilities: HapticCapabilities { base.capabilities }
    var activeEffects: [HapticEffectID: HapticActiveEffect] { base.activeEffects }
    func prepare() throws { prepareCount += 1; try base.prepare() }
    func execute(_ command: HapticCommand) throws { try base.execute(command) }
    func execute(_ command: HapticCommand, ownedBy owner: HapticOwnerID) throws {
        try base.execute(command, ownedBy: owner)
    }
    func stopEffects(ownedBy owner: HapticOwnerID) throws {
        if failCleanup { throw HapticError.engineInterrupted }
        try base.stopEffects(ownedBy: owner)
    }
    func suspend() async { await base.suspend() }
    func resume() async throws { try await base.resume() }
}
