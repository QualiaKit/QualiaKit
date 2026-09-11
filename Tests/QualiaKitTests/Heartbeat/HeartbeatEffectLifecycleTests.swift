import XCTest
@testable import QualiaKit
import QualiaTesting

extension HeartbeatEffectTests {
    func testResetAndBackgroundInvalidateQueuedUpdateAndOnlyStopOwner() throws {
        for background in [false, true] {
            let renderer = RecordingHapticRenderer()
            try renderer.prepare()
            let executor = QualiaReactionExecutor(renderer: renderer, owner: owner)
            let otherOwner = try HapticOwnerID(rawValue: "other-session")
            let other = QualiaReactionExecutor(renderer: renderer, owner: otherOwner)
            try submit(0.91, to: executor)
            try submit(0.91, to: other)
            let stale = executor.beginRequest()
            let before = renderer.commands.count
            if background { try executor.suspend() } else { try executor.reset() }
            XCTAssertEqual(renderer.commands.count, before + 1)
            guard case let .stop(id) = try XCTUnwrap(renderer.commands.last) else { return XCTFail("Expected owned stop") }
            XCTAssertEqual(id.scope, .owned(owner))
            XCTAssertEqual(renderer.activeEffects.count, 1)
            XCTAssertEqual(renderer.activeEffects.keys.first?.scope, .owned(otherOwner))
            executor.resume()
            XCTAssertNil(try executor.execute(for: transition(1), policy: policy, analyzerCapabilities: capabilities,
                                              at: .seconds(1), request: stale))
            XCTAssertTrue(executor.state.activeEffects.isEmpty)
            XCTAssertEqual(renderer.commands.count, before + 1)
            try submit(0.91, to: executor, at: .seconds(2))
            XCTAssertEqual(renderer.activeEffects.count, 2)
        }
    }

    func testDisableInvalidatesPendingWorkWithoutAnotherObservation() throws {
        for preferences in [QualiaHapticPreferences.disabled, try .init(continuousEffectsEnabled: false), try .init(intensityScale: 0)] {
            let renderer = RecordingHapticRenderer()
            try renderer.prepare()
            let executor = QualiaReactionExecutor(renderer: renderer, owner: owner)
            try submit(0.91, to: executor)
            let stale = executor.beginRequest()
            try executor.updatePreferences(preferences)
            XCTAssertTrue(renderer.activeEffects.isEmpty)
            try executor.updatePreferences(.default)
            XCTAssertNil(try executor.execute(for: transition(1), policy: policy, analyzerCapabilities: capabilities,
                                              at: .seconds(1), request: stale))
            XCTAssertEqual(renderer.commands.count, 2)
        }
    }

    func testFailureDoesNotRetryUntilExplicitReset() throws {
        let renderer = RecordingHapticRenderer()
        try renderer.prepare()
        let executor = QualiaReactionExecutor(renderer: renderer, owner: owner)
        renderer.failNext()
        XCTAssertThrowsError(try submit(0.91, to: executor))
        for instant in [1, 3, 15] { try submit(1, to: executor, at: .seconds(instant)) }
        XCTAssertEqual(renderer.commands.count, 1)
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        try executor.reset()
        try submit(0.91, to: executor, at: .seconds(16))
        XCTAssertEqual(renderer.commands.count, 2)
        XCTAssertEqual(renderer.activeEffects.count, 1)
    }

    func testFailureDuringResolveDoesNotRetryAndResetStillStopsOldPattern() throws {
        let renderer = RecordingHapticRenderer()
        try renderer.prepare()
        let executor = QualiaReactionExecutor(renderer: renderer, owner: owner)
        try submit(0.91, to: executor)
        renderer.failNext()
        XCTAssertThrowsError(try submit(0.4, to: executor, at: .seconds(1)))
        try submit(1, to: executor, at: .seconds(2))
        XCTAssertEqual(renderer.commands.count, 2)
        XCTAssertEqual(renderer.activeEffects.count, 1)
        try executor.reset()
        XCTAssertTrue(renderer.activeEffects.isEmpty)
    }

    func testAnalyzerFailureAndSupersededRequestDoNotChangeState() throws {
        let renderer = RecordingHapticRenderer()
        try renderer.prepare()
        let executor = QualiaReactionExecutor(renderer: renderer, owner: owner)
        try submit(0.91, to: executor)
        let state = executor.state
        let stale = executor.beginRequest()
        _ = executor.beginRequest() // failed analysis produces no transition
        XCTAssertEqual(executor.state, state)
        XCTAssertNil(try executor.execute(for: transition(0.1), policy: policy, analyzerCapabilities: capabilities,
                                          at: .seconds(1), request: stale))
        XCTAssertEqual(executor.state, state)
        XCTAssertEqual(renderer.commands.count, 1)
    }

    func testRequestCannotBeReplayedOrUsedByAnotherOwner() throws {
        let renderer = RecordingHapticRenderer()
        try renderer.prepare()
        let executor = QualiaReactionExecutor(renderer: renderer, owner: owner)
        let other = QualiaReactionExecutor(renderer: renderer, owner: try HapticOwnerID(rawValue: "foreign"))
        let request = executor.beginRequest()
        XCTAssertNil(try other.execute(for: transition(1), policy: policy, analyzerCapabilities: capabilities,
                                       at: .zero, request: request))
        XCTAssertNotNil(try executor.execute(for: transition(1), policy: policy, analyzerCapabilities: capabilities,
                                             at: .zero, request: request))
        XCTAssertNil(try executor.execute(for: transition(1), policy: policy, analyzerCapabilities: capabilities,
                                          at: .zero, request: request))
        XCTAssertEqual(renderer.commands.count, 1)
    }

    func testEngineResetAndInterruptionDoNotRestartHeartbeat() throws {
        for reset in [false, true] {
            let renderer = RecordingHapticRenderer()
            try renderer.prepare()
            let executor = QualiaReactionExecutor(renderer: renderer, owner: owner)
            try submit(0.91, to: executor)
            if reset { renderer.simulateEngineReset() } else {
                renderer.simulateEngineInterruption()
                try renderer.prepare()
            }
            try submit(1, to: executor, at: .seconds(1))
            XCTAssertTrue(renderer.activeEffects.isEmpty)
            XCTAssertEqual(renderer.commands.count, 1)
            XCTAssertEqual(executor.state.heartbeats.values.first?.phase, .failed)
        }
    }

    func testBoundedGlobalHeartbeatIsNotRestoredOnEngineReset() throws {
        let renderer = RecordingHapticRenderer()
        try renderer.prepare()
        let parameters = try HeartbeatParameters(beatsPerMinute: 64, intensity: HapticValue(0.5), sharpness: HapticValue(0.2))
        try renderer.execute(.start(id: HapticEffectID(rawValue: "global-heartbeat", scope: .global),
                                    pattern: HeartbeatPatternFactory().makePattern(parameters: parameters), channel: .ambient))
        renderer.simulateEngineReset()
        XCTAssertTrue(renderer.activeEffects.isEmpty)
    }

    func testCoreRendererCompletionDoesNotRemoveReplacementPlayer() async throws {
        let backend = HeartbeatTestEngine()
        let renderer = CoreHapticRenderer(backend: backend)
        try renderer.prepare()
        let start = try plan(0.91)
        try renderer.execute(XCTUnwrap(start.hapticCommands.first))
        let oldPlayer = try XCTUnwrap(backend.players.first)
        let update = try plan(0.6, at: .seconds(1), state: start.nextState)
        try renderer.execute(XCTUnwrap(update.hapticCommands.first))
        XCTAssertEqual(backend.patterns.last?.playbackDuration, .seconds(11))
        oldPlayer.completionHandler?()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(renderer.activeEffects.count, 1)
        backend.players.last?.completionHandler?()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        XCTAssertEqual(renderer.activeLongLivedPlayerCount, 0)
    }

    @discardableResult
    private func submit(_ tension: Float, to executor: QualiaReactionExecutor, at instant: Duration = .zero) throws -> QualiaReactionPlan? {
        try executor.execute(for: transition(tension), policy: policy, analyzerCapabilities: capabilities,
                             at: instant, request: executor.beginRequest())
    }
}

@MainActor
private final class HeartbeatTestEngine: HapticRuntimeEngine {
    let capabilities: HapticCapabilities = .full
    var stoppedHandler: (@Sendable () -> Void)?
    var resetHandler: (@Sendable () -> Void)?
    var players: [HeartbeatTestPlayer] = []
    var patterns: [HapticPattern] = []
    func start() throws {}
    func stop() async throws {}
    func makePlayer(pattern: HapticPattern) throws -> any HapticRuntimePlayer {
        let player = HeartbeatTestPlayer()
        players.append(player)
        patterns.append(pattern)
        return player
    }
}

@MainActor
private final class HeartbeatTestPlayer: HapticRuntimePlayer {
    var completionHandler: (@Sendable () -> Void)?
    func start() throws {}
    func stop() throws {}
}
