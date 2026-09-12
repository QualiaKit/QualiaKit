import XCTest
@testable import QualiaKit
import QualiaTesting

extension SessionOrchestrationTests {
    func testConcurrentResetAndSuspendAreSafeAndCannotReviveInFlightWork() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let session = try await QualiaSession(dependencies: sessionDependencies(analyzer: fixture, clock: clock),
            renderer: QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners))
        _ = try await accept("a", session: session, fixture: fixture)
        let pending = Task { try await session.process(sessionInput("b")) }
        try await waitForSessionEvent(fixture.invocation("b"))
        let reset = Task { try await session.reset() }
        let suspend = Task { try await session.suspend() }
        for task in [reset, suspend] {
            do { try await task.value }
            catch is CancellationError { /* A newer lifecycle request superseded this one. */ }
        }
        let snapshot = await session.snapshot
        XCTAssertEqual(snapshot.lifecycle, .suspended)
        XCTAssertEqual(snapshot.scene.revision, 0)
        XCTAssertEqual(snapshot.retainedFragments, 0)
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        let commands = renderer.commands
        try await fixture.complete("b")
        await assertSessionCancelled(pending)
        XCTAssertEqual(renderer.commands, commands)
        try await session.resume()
        XCTAssertEqual(renderer.commands, commands)
    }

    func testRealRendererResetStopsOnlyOwnedAccentsIncludingPendingRollback() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let backend = SessionHapticEngine()
        let renderer = CoreHapticRenderer(backend: backend)
        let bridge = QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners)
        let deps = try sessionDependencies(analyzer: fixture, clock: clock)
        let a = try await QualiaSession(dependencies: deps, renderer: bridge)
        let b = try await QualiaSession(dependencies: deps, renderer: bridge)
        _ = try await accept("b-accent", session: b, fixture: fixture, suspense: 0, impact: 1)
        _ = try await accept("a-accent", session: a, fixture: fixture, suspense: 0, impact: 1)
        XCTAssertEqual(backend.activeCount, 2)
        XCTAssertEqual(renderer.activeOneShotPlayerCount, 2)
        let bPlayer = backend.players[0]
        try await a.reset()
        XCTAssertEqual(backend.activeCount, 1)
        XCTAssertTrue(bPlayer.active)
        XCTAssertEqual(bPlayer.stopCount, 0)

        backend.nextStartFailsAfterPlaying = true
        backend.nextStopFailures = 2 // Rollback, then first reset; retry must succeed.
        let failed = try await accept("a-failed-accent", session: a, fixture: fixture, suspense: 0, impact: 1)
        XCTAssertEqual(failed.execution.failure, .playerStartFailed)
        XCTAssertEqual(renderer.pendingCleanupPlayerCount, 1)
        XCTAssertEqual(backend.activeCount, 2)
        do { try await a.reset(); XCTFail("Expected failed pending cleanup") }
        catch { XCTAssertEqual(error as? HapticError, .playerStopFailed) }
        let snapshot = await a.snapshot
        XCTAssertEqual(snapshot.lifecycle, .cleanupRequired)
        XCTAssertEqual(snapshot.scene.revision, 0)
        XCTAssertEqual(snapshot.retainedFragments, 0)
        XCTAssertEqual(renderer.pendingCleanupPlayerCount, 1)
        XCTAssertTrue(bPlayer.active)
        try await a.reset()
        XCTAssertEqual(renderer.pendingCleanupPlayerCount, 0)
        XCTAssertEqual(backend.activeCount, 1)
        XCTAssertEqual(bPlayer.stopCount, 0)
        try await b.reset()
        XCTAssertEqual(backend.activeCount, 0)
    }

    func testRealRendererResetCleansPendingAmbientAfterPhysicalStartFailure() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let backend = SessionHapticEngine()
        let renderer = CoreHapticRenderer(backend: backend)
        let bridge = QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners)
        let session = try await QualiaSession(dependencies: sessionDependencies(analyzer: fixture, clock: clock), renderer: bridge)
        backend.nextStartFailsAfterPlaying = true
        backend.nextStopFailures = 1
        let failed = try await accept("a", session: session, fixture: fixture)
        XCTAssertEqual(failed.execution.failure, .playerStartFailed)
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        XCTAssertEqual(renderer.pendingCleanupPlayerCount, 1)
        XCTAssertEqual(backend.activeCount, 1)
        try await session.reset()
        XCTAssertEqual(renderer.pendingCleanupPlayerCount, 0)
        XCTAssertEqual(backend.activeCount, 0)
    }

    func testPartialBatchFailurePreservesSemanticAndSuccessfulAmbientState() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = FailingSessionRenderer(failingCommand: 2)
        let bridge = QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners)
        let session = try await QualiaSession(dependencies: sessionDependencies(analyzer: fixture, clock: clock), renderer: bridge)
        let response = try await accept("a", session: session, fixture: fixture, impact: 1)
        XCTAssertEqual(response.reaction.hapticCommands.map(sessionCommandKind), ["start", "play"])
        XCTAssertEqual(response.execution.commands.map(\.outcome), [.succeeded, .failed(.injectedFailure)])
        XCTAssertEqual(response.execution.reactionState.activeEffects.count, 1)
        let snapshot = await session.snapshot
        XCTAssertEqual(snapshot.scene, response.transition.current)
        XCTAssertEqual(snapshot.retainedFragments, 1)
        XCTAssertEqual(renderer.activeEffects.count, 1)
        try await session.reset()
        XCTAssertTrue(renderer.activeEffects.isEmpty)
    }

    func testGlobalPolicyCommandsAreRejectedBeforeAnyCommit() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let deps = try sessionDependencies(analyzer: fixture, clock: clock, policy: GlobalStopSessionPolicy())
        let session = try await QualiaSession(dependencies: deps,
            renderer: QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners))
        do { _ = try await accept("a", session: session, fixture: fixture); XCTFail("Expected ownership rejection") }
        catch { XCTAssertEqual(error as? HapticError, .ownershipConflict) }
        let snapshot = await session.snapshot
        XCTAssertEqual(snapshot.scene.revision, 0)
        XCTAssertEqual(snapshot.retainedFragments, 0)
        XCTAssertTrue(renderer.commands.isEmpty)
    }

    func testResetAfterCommitButBeforeResponseReturnKeepsResetState() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let barrier = SessionDispatchBarrier(holding: [1])
        let bridge = QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners,
                                          afterDispatch: { await barrier.enter($0) })
        let session = try await QualiaSession(dependencies: sessionDependencies(analyzer: fixture, clock: clock), renderer: bridge)
        let task = Task { try await session.process(sessionInput("a")) }
        try await waitForSessionEvent(fixture.invocation("a"))
        try await fixture.complete("a")
        try await waitForSessionEvent(barrier.arrival(1))
        XCTAssertEqual(renderer.activeEffects.count, 1)
        try await session.reset()
        let commands = renderer.commands
        await barrier.release(1)
        let acceptedBeforeReset = try await task.value
        XCTAssertEqual(acceptedBeforeReset.transition.current.revision, 1)
        let snapshot = await session.snapshot
        XCTAssertEqual(snapshot.scene.revision, 0)
        XCTAssertEqual(snapshot.retainedFragments, 0)
        XCTAssertEqual(renderer.commands, commands)
        XCTAssertTrue(renderer.activeEffects.isEmpty)
    }

    func testCancellationAfterCommitDoesNotMisreportAnAcceptedInput() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let barrier = SessionDispatchBarrier(holding: [1])
        let bridge = QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners,
                                          afterDispatch: { await barrier.enter($0) })
        let session = try await QualiaSession(dependencies: sessionDependencies(analyzer: fixture, clock: clock), renderer: bridge)
        let task = Task { try await session.process(sessionInput("a")) }
        try await waitForSessionEvent(fixture.invocation("a"))
        try await fixture.complete("a")
        try await waitForSessionEvent(barrier.arrival(1))
        task.cancel()
        await barrier.release(1)
        let response = try await task.value
        let snapshot = await session.snapshot
        XCTAssertEqual(snapshot.scene, response.transition.current)
        XCTAssertEqual(snapshot.retainedFragments, 1)
        XCTAssertEqual(renderer.commands.count, 1)
        try await session.reset()
    }

    func testCancelledResetCallerStillPerformsOwnedCleanup() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let session = try await QualiaSession(dependencies: sessionDependencies(analyzer: fixture, clock: clock),
            renderer: QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners))
        _ = try await accept("a", session: session, fixture: fixture)
        let reset = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await session.reset()
        }
        try await reset.value
        let snapshot = await session.snapshot
        XCTAssertEqual(snapshot.scene.revision, 0)
        XCTAssertEqual(snapshot.retainedFragments, 0)
        XCTAssertTrue(renderer.activeEffects.isEmpty)
    }
}

@MainActor
private final class SessionHapticEngine: HapticRuntimeEngine {
    let capabilities: HapticCapabilities = .full
    var stoppedHandler: (@Sendable () -> Void)?
    var resetHandler: (@Sendable () -> Void)?
    var players: [SessionHapticPlayer] = []
    var nextStartFailsAfterPlaying = false
    var nextStopFailures = 0
    var activeCount: Int { players.filter(\.active).count }
    func start() throws {}
    func stop() async throws {}
    func makePlayer(pattern: HapticPattern) throws -> any HapticRuntimePlayer {
        let player = SessionHapticPlayer(startFails: nextStartFailsAfterPlaying, stopFailures: nextStopFailures)
        nextStartFailsAfterPlaying = false
        nextStopFailures = 0
        players.append(player)
        return player
    }
}

@MainActor
private final class SessionHapticPlayer: HapticRuntimePlayer {
    var completionHandler: (@Sendable () -> Void)?
    var active = false
    var stopCount = 0
    private let startFails: Bool
    private var stopFailures: Int
    init(startFails: Bool, stopFailures: Int) { self.startFails = startFails; self.stopFailures = stopFailures }
    func start() throws { active = true; if startFails { throw HapticError.playerStartFailed } }
    func stop() throws {
        stopCount += 1
        if stopFailures > 0 { stopFailures -= 1; throw HapticError.playerStopFailed }
        active = false
    }
}

@MainActor
private final class FailingSessionRenderer: HapticRendering {
    let recording = RecordingHapticRenderer()
    let failingCommand: Int
    var attempted = 0
    var capabilities: HapticCapabilities { recording.capabilities }
    var activeEffects: [HapticEffectID: HapticActiveEffect] { recording.activeEffects }
    init(failingCommand: Int) { self.failingCommand = failingCommand }
    func prepare() throws { try recording.prepare() }
    func execute(_ command: HapticCommand) throws {
        attempted += 1
        if attempted == failingCommand { recording.failNext() }
        try recording.execute(command)
    }
    func execute(_ command: HapticCommand, ownedBy owner: HapticOwnerID) throws {
        attempted += 1
        if attempted == failingCommand { recording.failNext() }
        try recording.execute(command, ownedBy: owner)
    }
    func stopEffects(ownedBy owner: HapticOwnerID) throws { try recording.stopEffects(ownedBy: owner) }
    func suspend() async { await recording.suspend() }
    func resume() async throws { try await recording.resume() }
}

private struct GlobalStopSessionPolicy: QualiaReactionPolicy {
    func plan(for transition: QualiaSceneTransition, context: QualiaReactionContext) -> QualiaReactionPlan {
        .preservingState(hapticCommands: [.stopAll], rationale: nil, from: context)
    }
}
