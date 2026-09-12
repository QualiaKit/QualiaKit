import XCTest
@testable import QualiaKit
import QualiaTesting

extension HeartbeatEffectTests {
    func testLifecycleCleansPlayerAfterStartAndRollbackFail() throws {
        let actions: [(QualiaReactionExecutor) throws -> Void] = [
            { try $0.reset() },
            { try $0.suspend() },
            { try $0.updatePreferences(.disabled) },
            { try $0.updatePreferences(.init(continuousEffectsEnabled: false)) },
            { try $0.updatePreferences(.init(intensityScale: 0)) },
        ]
        for action in actions {
            let backend = CleanupFailureEngine()
            let renderer = CoreHapticRenderer(backend: backend)
            try renderer.prepare()
            let executor = QualiaReactionExecutor(renderer: renderer, owner: owner)
            backend.failNextStart = true
            XCTAssertThrowsError(try submitForReview(0.91, to: executor))
            XCTAssertTrue(renderer.activeEffects.isEmpty)
            XCTAssertEqual(renderer.pendingCleanupPlayerCount, 1)
            XCTAssertEqual(backend.activePlayerCount, 1)

            try action(executor)

            XCTAssertEqual(renderer.pendingCleanupPlayerCount, 0)
            XCTAssertEqual(backend.activePlayerCount, 0)
            XCTAssertEqual(executor.state, .empty)
        }
    }

    func testResetReportsPendingCleanupFailureAndRetainsStateUntilCleanupSucceeds() throws {
        let backend = CleanupFailureEngine()
        let renderer = CoreHapticRenderer(backend: backend)
        try renderer.prepare()
        let executor = QualiaReactionExecutor(renderer: renderer, owner: owner)
        backend.failNextStart = true
        XCTAssertThrowsError(try submitForReview(0.91, to: executor))
        let failedPlayer = try XCTUnwrap(backend.players.last)
        failedPlayer.stopFailuresRemaining = 1
        let stale = executor.beginRequest()

        XCTAssertThrowsError(try executor.reset()) { error in
            XCTAssertEqual(error as? HapticError, .playerStopFailed)
        }
        XCTAssertNotEqual(executor.state, .empty)
        XCTAssertEqual(renderer.pendingCleanupPlayerCount, 1)
        XCTAssertEqual(backend.activePlayerCount, 1)
        XCTAssertNil(try executor.execute(for: transition(1), policy: policy, analyzerCapabilities: capabilities,
                                          at: .seconds(1), request: stale))

        try executor.reset()
        XCTAssertEqual(renderer.pendingCleanupPlayerCount, 0)
        XCTAssertEqual(backend.activePlayerCount, 0)
        XCTAssertEqual(executor.state, .empty)
    }

    func testOwnerResetDoesNotTouchAnotherOwnersActiveOrPendingPlayers() throws {
        for resetPendingOwnerFirst in [false, true] {
            let backend = CleanupFailureEngine()
            let renderer = CoreHapticRenderer(backend: backend)
            try renderer.prepare()
            let activeOwner = QualiaReactionExecutor(renderer: renderer, owner: try HapticOwnerID(rawValue: "active-owner"))
            let pendingOwner = QualiaReactionExecutor(renderer: renderer, owner: owner)
            try submitForReview(0.91, to: activeOwner)
            let activePlayer = try XCTUnwrap(backend.players.last)
            backend.failNextStart = true
            XCTAssertThrowsError(try submitForReview(0.91, to: pendingOwner))
            let pendingPlayer = try XCTUnwrap(backend.players.last)

            if resetPendingOwnerFirst {
                try pendingOwner.reset()
                XCTAssertEqual(renderer.pendingCleanupPlayerCount, 0)
                XCTAssertTrue(activePlayer.isPlaying)
                XCTAssertEqual(activePlayer.stopCallCount, 0)
                XCTAssertEqual(renderer.activeEffects.count, 1)
                try activeOwner.reset()
            } else {
                let pendingStopCalls = pendingPlayer.stopCallCount
                try activeOwner.reset()
                XCTAssertEqual(renderer.pendingCleanupPlayerCount, 1)
                XCTAssertTrue(pendingPlayer.isPlaying)
                XCTAssertEqual(pendingPlayer.stopCallCount, pendingStopCalls)
                try pendingOwner.reset()
            }
            XCTAssertEqual(backend.activePlayerCount, 0)
        }
    }

    func testResetCleansReplacementAfterStartAndRollbackFail() throws {
        let backend = CleanupFailureEngine()
        let renderer = CoreHapticRenderer(backend: backend)
        try renderer.prepare()
        let executor = QualiaReactionExecutor(renderer: renderer, owner: owner)
        try submitForReview(0.91, to: executor)
        backend.failNextStart = true
        XCTAssertThrowsError(try submitForReview(0.6, to: executor, at: .seconds(1)))
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        XCTAssertEqual(renderer.pendingCleanupPlayerCount, 1)
        XCTAssertEqual(backend.activePlayerCount, 1)

        try executor.reset()

        XCTAssertEqual(renderer.pendingCleanupPlayerCount, 0)
        XCTAssertEqual(backend.activePlayerCount, 0)
    }

    func testOwnerCleanupStopsActiveEffectsEvenWhenPendingCleanupFails() throws {
        let backend = CleanupFailureEngine()
        let renderer = CoreHapticRenderer(backend: backend)
        try renderer.prepare()
        let activeID = try HapticEffectID(rawValue: "other-owned-effect", scope: .owned(owner))
        let pattern = try XCTUnwrap(plan(0.91).nextState.activeAmbientEffects.values.first?.pattern)
        try renderer.execute(.start(id: activeID, pattern: pattern, channel: .ambient))
        let executor = QualiaReactionExecutor(renderer: renderer, owner: owner)
        backend.failNextStart = true
        XCTAssertThrowsError(try submitForReview(0.91, to: executor))
        let pendingPlayer = try XCTUnwrap(backend.players.last)
        pendingPlayer.stopFailuresRemaining = 1

        XCTAssertThrowsError(try executor.reset())

        XCTAssertTrue(renderer.activeEffects.isEmpty)
        XCTAssertEqual(renderer.pendingCleanupPlayerCount, 1)
        XCTAssertEqual(backend.activePlayerCount, 1)
        XCTAssertTrue(pendingPlayer.isPlaying)
        try executor.reset()
        XCTAssertEqual(backend.activePlayerCount, 0)
    }

    func testExecutorStartsNewSegmentAfterPhysicalCompletionAndQuietCooldown() throws {
        var now = Duration.zero
        let renderer = RecordingHapticRenderer(now: { now })
        try renderer.prepare()
        let executor = QualiaReactionExecutor(renderer: renderer, owner: owner)
        try submitForReview(0.91, to: executor)
        now = .seconds(20)
        renderer.expireEffects()
        XCTAssertTrue(renderer.activeEffects.isEmpty)

        let restarted = try XCTUnwrap(submitForReview(0.91, to: executor, at: now))

        XCTAssertEqual(restarted.hapticCommands.count, 2)
        XCTAssertEqual(renderer.activeEffects.count, 1)
        XCTAssertEqual(executor.state.heartbeats.values.first?.deadline, .seconds(32))
    }

    func testRunningAdvancesPastElapsedCooldownAndUsesFirstFreshEvidence() throws {
        let running = try plan(0.91)
        for instant in [Duration.seconds(14), .seconds(20)] {
            try assertNewSegment(after: running, at: instant)
        }
    }

    func testResolvingAdvancesPastElapsedCooldownAndUsesFirstFreshEvidence() throws {
        let running = try plan(0.91)
        let resolving = try plan(0.5, at: .seconds(1), state: running.nextState)
        for instant in [Duration.milliseconds(3300), .seconds(20)] {
            try assertNewSegment(after: resolving, at: instant)
        }
    }

    func testTimeJumpStillRequiresFreshEvidenceAndHonorsUnelapsedCooldown() throws {
        let running = try plan(0.91)
        let id = try XCTUnwrap(running.nextState.activeEffects.first)
        let waiting = try plan(0.91, at: .milliseconds(13999), state: running.nextState)
        XCTAssertEqual(waiting.hapticCommands, [.stop(id: id)])
        XCTAssertEqual(waiting.nextState.heartbeats[id]?.phase, .cooldown)
        let missing = try plan(0.91, at: .seconds(20), state: running.nextState, evidence: [:])
        XCTAssertEqual(missing.hapticCommands, [.stop(id: id)])
        XCTAssertEqual(missing.rationale?.ruleIdentifier, "missing-heartbeat-evidence")
        XCTAssertEqual(missing.nextState, .empty)
    }

    private func assertNewSegment(after previous: QualiaReactionPlan, at instant: Duration) throws {
        let restarted = try plan(0.91, at: instant, state: previous.nextState)
        let oldID = try XCTUnwrap(previous.nextState.activeEffects.first)
        XCTAssertEqual(restarted.hapticCommands.count, 2)
        XCTAssertEqual(restarted.hapticCommands.first, .stop(id: oldID))
        guard case let .start(id, pattern, .ambient) = try XCTUnwrap(restarted.hapticCommands.last) else {
            return XCTFail("The first observation after elapsed cooldown must start a new segment")
        }
        XCTAssertEqual(id, oldID)
        XCTAssertEqual(pattern.playbackDuration, .seconds(12))
        XCTAssertEqual(restarted.nextState.heartbeats[id]?.startedAt, instant)
        XCTAssertEqual(restarted.nextState.heartbeats[id]?.deadline, instant + .seconds(12))
    }

    @discardableResult
    private func submitForReview(
        _ tension: Float,
        to executor: QualiaReactionExecutor,
        at instant: Duration = .zero
    ) throws -> QualiaReactionPlan? {
        try executor.execute(for: transition(tension), policy: policy, analyzerCapabilities: capabilities,
                             at: instant, request: executor.beginRequest())
    }
}

@MainActor
private final class CleanupFailureEngine: HapticRuntimeEngine {
    let capabilities: HapticCapabilities = .full
    var stoppedHandler: (@Sendable () -> Void)?
    var resetHandler: (@Sendable () -> Void)?
    var failNextStart = false
    var players: [CleanupFailurePlayer] = []
    var activePlayerCount: Int { players.filter(\.isPlaying).count }

    func start() throws {}
    func stop() async throws {}
    func makePlayer(pattern: HapticPattern) throws -> any HapticRuntimePlayer {
        let player = CleanupFailurePlayer(failsOnStart: failNextStart)
        failNextStart = false
        players.append(player)
        return player
    }
}

@MainActor
private final class CleanupFailurePlayer: HapticRuntimePlayer {
    var completionHandler: (@Sendable () -> Void)?
    var isPlaying = false
    var stopFailuresRemaining: Int
    var stopCallCount = 0
    let failsOnStart: Bool

    init(failsOnStart: Bool) {
        self.failsOnStart = failsOnStart
        stopFailuresRemaining = failsOnStart ? 1 : 0
    }

    func start() throws {
        isPlaying = true
        if failsOnStart { throw HapticError.playerStartFailed }
    }

    func stop() throws {
        stopCallCount += 1
        if stopFailuresRemaining > 0 {
            stopFailuresRemaining -= 1
            throw HapticError.playerStopFailed
        }
        isPlaying = false
    }
}
