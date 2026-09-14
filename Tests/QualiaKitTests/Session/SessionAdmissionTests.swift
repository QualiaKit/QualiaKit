import XCTest
@testable import QualiaKit
import QualiaTesting

extension SessionOrchestrationTests {
    func testRejectedDuplicateDoesNotCancelAnotherRequestInFlight() async throws {
        for ignoresCancellation in [false, true] {
            for fragments in [0, 4] {
                let clock = SessionTestClock()
                let fixture = SessionFixtureAnalyzer(ignoresCancellation: ignoresCancellation)
                let renderer = RecordingHapticRenderer()
                let diagnostics = SessionDiagnostics()
                let session = try await QualiaSession(
                    dependencies: sessionDependencies(analyzer: fixture, clock: clock,
                                                      fragments: fragments, diagnostics: diagnostics),
                    renderer: QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners)
                )
                _ = try await accept("a", session: session, fixture: fixture, suspense: 0)
                clock.set(.seconds(10))
                let pending = Task { try await session.process(sessionInput("b")) }
                try await waitForSessionEvent(fixture.invocation("b"))

                do { _ = try await session.process(sessionInput("a")); XCTFail("Expected duplicate") }
                catch { XCTAssertEqual(error as? QualiaSessionError, .duplicateInput) }

                try await fixture.complete("b")
                let response = try await pending.value
                let snapshot = await session.snapshot
                XCTAssertEqual(response.observation.inputID, try sessionInput("b").id)
                XCTAssertEqual(response.transition.current.revision, 2)
                XCTAssertEqual(snapshot.scene, response.transition.current)
                XCTAssertEqual(snapshot.retainedFragments, fragments == 0 ? 0 : 2)
                XCTAssertEqual(renderer.commands.map(sessionCommandKind), ["start"])
                XCTAssertTrue(diagnostics.events.contains(.completed(
                    generation: 2, revision: 2, attemptedCommands: 1, rendererFailure: nil
                )))
                try await session.reset()
            }
        }
    }

    func testDuplicateInRetainedHistoryDoesNotCancelAnotherRequest() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer(ignoresCancellation: false)
        let renderer = RecordingHapticRenderer()
        let session = try await QualiaSession(dependencies: sessionDependencies(analyzer: fixture, clock: clock),
            renderer: QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners))
        _ = try await accept("a", session: session, fixture: fixture, suspense: 0)
        _ = try await accept("b", session: session, fixture: fixture, suspense: 0)
        clock.set(.seconds(10))
        let pending = Task { try await session.process(sessionInput("c")) }
        try await waitForSessionEvent(fixture.invocation("c"))
        do { _ = try await session.process(sessionInput("a")); XCTFail("Expected retained duplicate") }
        catch { XCTAssertEqual(error as? QualiaSessionError, .duplicateInput) }
        try await fixture.complete("c")
        let response = try await pending.value
        XCTAssertEqual(response.transition.current.revision, 3)
        XCTAssertEqual(renderer.commands.map(sessionCommandKind), ["start"])
        try await session.reset()
    }

    func testAdmissionUsesUnabsorbedReceiptAndDoesNotRetainEvictedIDs() async throws {
        for fragments in [0, 1] {
            let clock = SessionTestClock()
            let fixture = SessionFixtureAnalyzer()
            let renderer = RecordingHapticRenderer()
            let barrier = SessionDispatchBarrier(holding: [2])
            let bridge = QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners,
                                              afterDispatch: { await barrier.enter($0) })
            let session = try await QualiaSession(
                dependencies: sessionDependencies(analyzer: fixture, clock: clock, fragments: fragments),
                renderer: bridge
            )
            _ = try await accept("a", session: session, fixture: fixture, suspense: 0)
            let pending = Task { try await session.process(sessionInput("b")) }
            try await waitForSessionEvent(fixture.invocation("b"))
            try await fixture.complete("b", suspense: 0)
            try await waitForSessionEvent(barrier.arrival(2))
            // The actor still has A; only the gate's receipt knows B is accepted.
            // Do not read snapshot here: it would absorb that receipt.
            do { _ = try await session.process(sessionInput("b")); XCTFail("Expected committed duplicate") }
            catch { XCTAssertEqual(error as? QualiaSessionError, .duplicateInput) }

            // A has left the bounded window. Admission must use B's receipt,
            // not merge in the actor's stale last ID or retained context.
            clock.set(.seconds(10))
            let reused = try await accept("a", session: session, fixture: fixture, invocation: 2)
            XCTAssertEqual(reused.transition.previous.revision, 2)
            XCTAssertEqual(reused.transition.current.revision, 3)
            let inputs = await fixture.inputs
            XCTAssertEqual(inputs.map(\.id.rawValue), ["a", "b", "a"])
            XCTAssertEqual(inputs.last?.context.map(\.id.rawValue), fragments == 0 ? [] : ["b"])
            await barrier.release(2)
            let delayedResponse = try await pending.value
            XCTAssertEqual(delayedResponse.transition.current.revision, 2)
            let snapshot = await session.snapshot
            XCTAssertEqual(snapshot.scene, reused.transition.current)
            XCTAssertEqual(renderer.commands.map(sessionCommandKind), ["start"])
            try await session.reset()
        }
    }

    func testSynchronousCancellationFromRendererFinishesAcceptedBatch() async throws {
        for failsFirstCommand in [false, true] {
            let clock = SessionTestClock()
            let fixture = SessionFixtureAnalyzer()
            let renderer = CancellingSessionRenderer()
            let session = try await QualiaSession(dependencies: sessionDependencies(analyzer: fixture, clock: clock),
                renderer: QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners))
            let task = Task { try await session.process(sessionInput("a")) }
            renderer.processTask = task
            try await waitForSessionEvent(fixture.invocation("a"))
            if failsFirstCommand { renderer.recording.failNext() }
            try await fixture.complete("a", impact: 1)
            let response = try await task.value
            XCTAssertTrue(task.isCancelled)
            XCTAssertTrue(renderer.cancellationReturned)
            XCTAssertEqual(response.transition.current.revision, 1)
            XCTAssertEqual(response.execution.failure, failsFirstCommand ? .injectedFailure : nil)
            XCTAssertEqual(renderer.recording.commands.map(sessionCommandKind), failsFirstCommand ? ["start"] : ["start", "play"])
            let snapshot = await session.snapshot
            XCTAssertEqual(snapshot.scene, response.transition.current)
            XCTAssertEqual(snapshot.retainedFragments, 1)
            // A finished cancellation handler cannot poison the next request.
            let next = try await accept("b", session: session, fixture: fixture)
            XCTAssertEqual(next.transition.current.revision, 2)
            try await session.reset()
            XCTAssertTrue(renderer.activeEffects.isEmpty)
        }
    }
}

@MainActor
private final class CancellingSessionRenderer: HapticRendering {
    let recording = RecordingHapticRenderer()
    var processTask: Task<QualiaResponse, Error>?
    private(set) var cancellationReturned = false
    var capabilities: HapticCapabilities { recording.capabilities }
    var activeEffects: [HapticEffectID: HapticActiveEffect] { recording.activeEffects }
    func prepare() throws { try recording.prepare() }
    func execute(_ command: HapticCommand) throws {
        cancelProcess()
        try recording.execute(command)
    }
    func execute(_ command: HapticCommand, ownedBy owner: HapticOwnerID) throws {
        cancelProcess()
        try recording.execute(command, ownedBy: owner)
    }
    private func cancelProcess() {
        guard let task = processTask else { return }
        processTask = nil
        // Swift may invoke process's onCancel synchronously inside this call.
        // The callback must return while the gate still owns the command batch.
        task.cancel()
        cancellationReturned = true
    }
    func stopEffects(ownedBy owner: HapticOwnerID) throws { try recording.stopEffects(ownedBy: owner) }
    func suspend() async { await recording.suspend() }
    func resume() async throws { try await recording.resume() }
}
