import XCTest
@testable import QualiaKit
import QualiaTesting

@MainActor
final class SessionOrchestrationTests: XCTestCase {
    func testFixturePipelineReturnsStructuredResponseAndExactOwnedCommands() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer(now: { clock.now })
        let bridge = QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners)
        let session = try await QualiaSession(dependencies: sessionDependencies(analyzer: fixture, clock: clock), renderer: bridge)
        let first = try await accept("a", session: session, fixture: fixture)
        clock.set(.seconds(1))
        let second = try await accept("b", session: session, fixture: fixture, suspense: 0.5, impact: 1)
        clock.set(.seconds(5))
        let third = try await accept("c", session: session, fixture: fixture, suspense: 0)
        XCTAssertEqual(first.observation.analyzer, fixture.identity)
        XCTAssertEqual(first.transition.current.revision, 1)
        XCTAssertEqual(second.transition.previous, first.transition.current)
        XCTAssertEqual(third.transition.previous, second.transition.current)
        for response in [first, second, third] {
            XCTAssertNil(response.execution.failure)
            XCTAssertEqual(response.execution.commands.map(\.command), response.reaction.hapticCommands)
            XCTAssertEqual(response.execution.reactionState, response.reaction.nextState)
        }
        XCTAssertEqual(renderer.commands.map(sessionCommandKind), ["start", "replace", "play", "replace"])
        XCTAssertTrue(renderer.history.allSatisfy { $0.owner == session.owner })
        XCTAssertEqual(renderer.history.map(\.timestamp), [.zero, .seconds(1), .seconds(1), .seconds(5)])
        try await session.reset()
        XCTAssertEqual(renderer.commands.map(sessionCommandKind), ["start", "replace", "play", "replace", "stop"])
        XCTAssertTrue(renderer.activeEffects.isEmpty)
    }

    func testNewerResultWinsWithCancellationRespectingAndIgnoringAnalyzers() async throws {
        for ignoresCancellation in [false, true] {
            let clock = SessionTestClock()
            let fixture = SessionFixtureAnalyzer(ignoresCancellation: ignoresCancellation)
            let renderer = RecordingHapticRenderer()
            let session = try await makeSession(fixture, clock, renderer)
            let old = Task { try await session.process(sessionInput("old")) }
            try await waitForSessionEvent(fixture.invocation("old"))
            let newest = try await accept("new", session: session, fixture: fixture)
            try await waitForSessionEvent(fixture.cancellation("old"))
            let before = await session.snapshot
            let commands = renderer.commands
            try await fixture.complete("old", suspense: 0)
            await assertSessionCancelled(old)
            let after = await session.snapshot
            XCTAssertEqual(after.scene, newest.transition.current)
            XCTAssertEqual(after.scene, before.scene)
            XCTAssertEqual(after.retainedFragments, 1)
            XCTAssertEqual(renderer.commands, commands)
            XCTAssertEqual(renderer.commands.map(sessionCommandKind), ["start"])
        }
    }

    func testMainActorDelayCannotCommitOlderStateOrDispatchOlderCommands() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let barrier = SessionDispatchBarrier(holding: [1])
        let bridge = QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners,
                                          beforeDispatch: { await barrier.enter($0) }, afterDispatch: nil)
        let session = try await QualiaSession(dependencies: sessionDependencies(analyzer: fixture, clock: clock), renderer: bridge)
        let old = Task { try await session.process(sessionInput("old")) }
        try await waitForSessionEvent(fixture.invocation("old"))
        try await fixture.complete("old", suspense: 0.3)
        try await waitForSessionEvent(barrier.arrival(1))
        let staged = await session.snapshot
        XCTAssertEqual(staged.scene.revision, 0)
        XCTAssertEqual(staged.retainedFragments, 0)
        XCTAssertTrue(renderer.commands.isEmpty)
        let newest = try await accept("new", session: session, fixture: fixture)
        let commands = renderer.commands
        await barrier.release(1)
        await assertSessionCancelled(old)
        let final = await session.snapshot
        XCTAssertEqual(final.scene, newest.transition.current)
        XCTAssertEqual(newest.transition.previous.revision, 0)
        XCTAssertEqual(renderer.commands, commands)
    }

    func testCommittedReceiptIsAbsorbedBeforeAnotherRequestEvenIfReturnIsDelayed() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let barrier = SessionDispatchBarrier(holding: [1])
        let bridge = QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners,
                                          afterDispatch: { await barrier.enter($0) })
        let session = try await QualiaSession(dependencies: sessionDependencies(analyzer: fixture, clock: clock), renderer: bridge)
        let first = Task { try await session.process(sessionInput("a")) }
        try await waitForSessionEvent(fixture.invocation("a"))
        try await fixture.complete("a")
        try await waitForSessionEvent(barrier.arrival(1))
        let second = try await accept("b", session: session, fixture: fixture)
        XCTAssertEqual(second.transition.previous.revision, 1)
        let received = await fixture.inputs
        XCTAssertEqual(received.last?.context.map(\.id.rawValue), ["a"])
        await barrier.release(1)
        let earlier = try await first.value
        let final = await session.snapshot
        XCTAssertEqual(earlier.transition.current.revision, 1)
        XCTAssertEqual(final.scene.revision, 2)
    }

    func testResetClearsRealSessionContextStateAndOwnedEffectsDuringIgnoredInference() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let session = try await makeSession(fixture, clock, renderer)
        _ = try await accept("accepted", session: session, fixture: fixture)
        weak var retained = await session.contextStorage
        XCTAssertNotNil(retained)
        let old = Task { try await session.process(sessionInput("inflight")) }
        try await waitForSessionEvent(fixture.invocation("inflight"))
        try await session.reset()
        XCTAssertNil(retained, "AC-0005-003: session-owned context storage must be released")
        let cleared = await session.snapshot
        XCTAssertEqual(cleared.scene, .initial())
        XCTAssertEqual(cleared.retainedFragments, 0)
        XCTAssertEqual(cleared.retainedCharacters, 0)
        XCTAssertEqual(cleared.retainedUTF8Bytes, 0)
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        let commands = renderer.commands
        try await fixture.complete("inflight")
        await assertSessionCancelled(old)
        XCTAssertEqual(renderer.commands, commands)
        _ = try await accept("after-reset", session: session, fixture: fixture)
        let received = await fixture.inputs
        XCTAssertTrue(received.last!.context.isEmpty)
    }

    func testResetWhileDispatchIsDelayedPreventsStateAndHeartbeatRestart() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let barrier = SessionDispatchBarrier(holding: [2])
        let bridge = QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners,
                                          beforeDispatch: { await barrier.enter($0) }, afterDispatch: nil)
        let session = try await QualiaSession(dependencies: sessionDependencies(analyzer: fixture, clock: clock), renderer: bridge)
        _ = try await accept("a", session: session, fixture: fixture)
        let old = Task { try await session.process(sessionInput("b")) }
        try await waitForSessionEvent(fixture.invocation("b"))
        try await fixture.complete("b")
        try await waitForSessionEvent(barrier.arrival(2))
        try await session.reset()
        let commands = renderer.commands
        await barrier.release(2)
        await assertSessionCancelled(old)
        let snapshot = await session.snapshot
        XCTAssertEqual(snapshot.scene.revision, 0)
        XCTAssertEqual(snapshot.retainedFragments, 0)
        XCTAssertEqual(renderer.commands, commands)
        XCTAssertTrue(renderer.activeEffects.isEmpty)
    }

    func testResetDuringPreparationPreventsAnalyzerInvocation() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let started = expectation(description: "Language resolution started")
        let release = DispatchSemaphore(value: 0)
        let deps = try sessionDependencies(analyzer: fixture, clock: clock,
                                          resolver: SessionBlockingResolver(started: started, release: release))
        let session = try await QualiaSession(dependencies: deps,
            renderer: QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners))
        let task = Task { try await session.process(sessionInput("a")) }
        try await waitForSessionEvent(started)
        try await session.reset()
        release.signal()
        await assertSessionCancelled(task)
        let inputs = await fixture.inputs
        XCTAssertTrue(inputs.isEmpty)
        XCTAssertTrue(renderer.commands.isEmpty)
    }

    func testTwoSessionsShareAnalyzerAndRendererWithoutSharingStateContextOrEffects() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let bridge = QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners)
        let deps = try sessionDependencies(analyzer: fixture, clock: clock)
        let a = try await QualiaSession(dependencies: deps, renderer: bridge)
        let b = try await QualiaSession(dependencies: deps, renderer: bridge)
        XCTAssertNotEqual(a.owner, b.owner)
        _ = try await accept("a1", session: a, fixture: fixture)
        _ = try await accept("b1", session: b, fixture: fixture)
        let bState = await b.snapshot
        let bEffects = renderer.activeEffects.filter { $0.key.scope == .owned(b.owner) }
        XCTAssertEqual(renderer.activeEffects.count, 2)
        try await a.reset()
        let bAfter = await b.snapshot
        XCTAssertEqual(bAfter.scene, bState.scene)
        XCTAssertEqual(bAfter.retainedFragments, bState.retainedFragments)
        XCTAssertEqual(renderer.activeEffects, bEffects)
        _ = try await accept("b2", session: b, fixture: fixture)
        let inputs = await fixture.inputs
        XCTAssertEqual(inputs.last?.context.map(\.id.rawValue), ["b1"])
        XCTAssertFalse(renderer.lifecycleHistory.contains(.suspend))
        XCTAssertFalse(renderer.lifecycleHistory.contains(.resume))
    }

    func testSuspendRetainsSemanticContextAndResumeRequiresFreshEvidence() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let session = try await makeSession(fixture, clock, renderer)
        let before = try await accept("a", session: session, fixture: fixture)
        try await session.suspend()
        try await session.suspend()
        let suspended = await session.snapshot
        XCTAssertEqual(suspended.lifecycle, .suspended)
        XCTAssertEqual(suspended.scene, before.transition.current)
        XCTAssertEqual(suspended.retainedFragments, 1)
        do { _ = try await session.process(sessionInput("rejected")); XCTFail("Expected suspended") }
        catch { XCTAssertEqual(error as? QualiaSessionError, .suspended) }
        let commands = renderer.commands
        clock.set(.seconds(100))
        try await session.resume()
        try await session.resume()
        XCTAssertEqual(renderer.commands, commands)
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        let resumed = try await accept("b", session: session, fixture: fixture)
        XCTAssertEqual(resumed.transition.current.revision, 2)
        XCTAssertEqual(renderer.activeEffects.count, 1)
        let inputs = await fixture.inputs
        XCTAssertEqual(inputs.last?.context.map(\.id.rawValue), ["a"])
    }

    func testResetCleanupFailureIsVisibleAndPreventsProcessingUntilRetry() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let session = try await makeSession(fixture, clock, renderer)
        _ = try await accept("a", session: session, fixture: fixture)
        renderer.failNext(with: .playerStopFailed)
        do { try await session.reset(); XCTFail("Expected cleanup failure") }
        catch { XCTAssertEqual(error as? HapticError, .playerStopFailed) }
        let failed = await session.snapshot
        XCTAssertEqual(failed.lifecycle, .cleanupRequired)
        XCTAssertEqual(failed.scene.revision, 0)
        XCTAssertEqual(failed.retainedFragments, 0)
        XCTAssertEqual(renderer.activeEffects.count, 1)
        do { _ = try await session.process(sessionInput("blocked")); XCTFail("Expected cleanup gate") }
        catch { XCTAssertEqual(error as? QualiaSessionError, .cleanupRequired) }
        try await session.resume()
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        let ready = await session.snapshot
        XCTAssertEqual(ready.lifecycle, .active)
        XCTAssertEqual(ready.scene.revision, 0)
    }

    func testRendererFailureReturnsSemanticResponseAndBoundedAcceptedContext() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let session = try await makeSession(fixture, clock, renderer)
        renderer.failNext(with: .playerStartFailed)
        let response = try await accept("a", session: session, fixture: fixture)
        XCTAssertEqual(response.execution.failure, .playerStartFailed)
        XCTAssertEqual(response.execution.commands.count, 1)
        XCTAssertEqual(response.execution.plannedCommandCount, 1)
        XCTAssertTrue(response.execution.reactionState.activeEffects.isEmpty)
        let snapshot = await session.snapshot
        XCTAssertEqual(snapshot.scene, response.transition.current)
        XCTAssertEqual(snapshot.retainedFragments, 1)
        let commandCount = renderer.commands.count
        clock.set(.seconds(20))
        _ = try await accept("b", session: session, fixture: fixture)
        XCTAssertEqual(renderer.commands.count, commandCount, "No automatic retry after failed start")
    }

    func testExclusiveAmbientArbitrationRejectsConflictWithoutPreemption() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let bridge = QualiaSessionRenderer(renderer: renderer, arbitration: .exclusiveAmbient)
        let deps = try sessionDependencies(analyzer: fixture, clock: clock)
        let a = try await QualiaSession(dependencies: deps, renderer: bridge)
        let b = try await QualiaSession(dependencies: deps, renderer: bridge)
        _ = try await accept("a", session: a, fixture: fixture)
        let effects = renderer.activeEffects
        let rejected = try await accept("b", session: b, fixture: fixture)
        XCTAssertEqual(rejected.execution.failure, .ownershipConflict)
        XCTAssertEqual(rejected.transition.current.revision, 1)
        XCTAssertEqual(renderer.activeEffects, effects)
        XCTAssertEqual(renderer.commands.count, 1)
        try await b.reset()
        XCTAssertEqual(renderer.activeEffects, effects)
        try await a.reset()
        _ = try await accept("b-again", session: b, fixture: fixture)
        XCTAssertEqual(renderer.activeEffects.keys.first?.scope, .owned(b.owner))
    }

    func testAnalyzerFailureAndInvalidOutputDoNotChangeStateContextOrHaptics() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let session = try await makeSession(fixture, clock, renderer)
        _ = try await accept("a", session: session, fixture: fixture)
        let before = await session.snapshot
        let commands = renderer.commands
        for id in ["unavailable", "invalid"] {
            let task = Task { try await session.process(sessionInput(id)) }
            try await waitForSessionEvent(fixture.invocation(id))
            let expected: QualiaError
            if id == "unavailable" {
                expected = .analyzerUnavailable(identity: fixture.identity)
                await fixture.fail(id, with: expected)
            } else {
                expected = .invalidAnalyzerOutput(identity: fixture.identity)
                try await fixture.complete(id, outputID: "foreign")
            }
            do { _ = try await task.value; XCTFail("Expected analyzer error") }
            catch { XCTAssertEqual(error as? QualiaError, expected) }
            let after = await session.snapshot
            XCTAssertEqual(after.scene, before.scene)
            XCTAssertEqual(after.retainedFragments, before.retainedFragments)
            XCTAssertEqual(renderer.commands, commands)
        }
    }

    func testCallerCancellationIsEnforcedDuringIgnoredInferenceAndDelayedDispatch() async throws {
        for delayed in [false, true] {
            let clock = SessionTestClock()
            let fixture = SessionFixtureAnalyzer()
            let renderer = RecordingHapticRenderer()
            let barrier = SessionDispatchBarrier(holding: delayed ? [1] : [])
            let bridge = QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners,
                                              beforeDispatch: { await barrier.enter($0) }, afterDispatch: nil)
            let session = try await QualiaSession(dependencies: sessionDependencies(analyzer: fixture, clock: clock), renderer: bridge)
            let task = Task { try await session.process(sessionInput("a")) }
            try await waitForSessionEvent(fixture.invocation("a"))
            if delayed {
                try await fixture.complete("a")
                try await waitForSessionEvent(barrier.arrival(1))
            }
            task.cancel()
            if delayed { await barrier.release(1) }
            else { try await fixture.complete("a") }
            await assertSessionCancelled(task)
            let snapshot = await session.snapshot
            XCTAssertEqual(snapshot.scene.revision, 0)
            XCTAssertEqual(snapshot.retainedFragments, 0)
            XCTAssertTrue(renderer.commands.isEmpty)
        }
    }

    func testRetainedWindowUsesAllBoundsAndKeepsUnicodeBytes() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let deps = try sessionDependencies(analyzer: fixture, clock: clock, fragments: 2, characters: 4, bytes: 6)
        let session = try await QualiaSession(dependencies: deps,
            renderer: QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners))
        for (id, text) in [("a", "é"), ("b", "e\u{0301}"), ("c", "я")] {
            _ = try await accept(id, text: text, session: session, fixture: fixture)
            let snapshot = await session.snapshot
            XCTAssertLessThanOrEqual(snapshot.retainedFragments, 2)
            XCTAssertLessThanOrEqual(snapshot.retainedCharacters, 4)
            XCTAssertLessThanOrEqual(snapshot.retainedUTF8Bytes, 6)
        }
        let inputs = await fixture.inputs
        XCTAssertEqual(inputs.last?.context.map { Data($0.text.utf8) }, [Data("e\u{0301}".utf8)])
        let snapshot = await session.snapshot
        XCTAssertEqual(snapshot.retainedFragments, 2)
        XCTAssertEqual(snapshot.retainedUTF8Bytes, 5)
    }

    func testZeroHistoryAndDuplicatePolicyRemainBoundedAndResetAllowsIDReuse() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer(acceptsContext: false)
        let renderer = RecordingHapticRenderer()
        let deps = try sessionDependencies(analyzer: fixture, clock: clock, fragments: 0)
        let session = try await QualiaSession(dependencies: deps,
            renderer: QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners))
        _ = try await accept("a", session: session, fixture: fixture)
        do { _ = try await session.process(sessionInput("a")); XCTFail("Expected duplicate") }
        catch { XCTAssertEqual(error as? QualiaSessionError, .duplicateInput) }
        _ = try await accept("b", session: session, fixture: fixture)
        let snapshot = await session.snapshot
        XCTAssertEqual(snapshot.retainedFragments, 0)
        let inputs = await fixture.inputs
        XCTAssertTrue(inputs.allSatisfy(\.context.isEmpty))
        try await session.reset()
        _ = try await accept("a", session: session, fixture: fixture, invocation: 2)
    }

    func testExplicitUnsupportedLanguageAndExternalContextFailBeforeInference() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer(languages: [try .init(rawValue: "ru")])
        let renderer = RecordingHapticRenderer()
        let session = try await makeSession(fixture, clock, renderer)
        do { _ = try await session.process(sessionInput("a")); XCTFail("Expected unsupported language") }
        catch { XCTAssertEqual(error as? QualiaError, try .unsupportedLanguage(.init(rawValue: "en"))) }
        let external = try QualiaInput(id: .init(rawValue: "b"), text: "current",
            context: [.init(id: .init(rawValue: "history"), text: "external")], language: .init(rawValue: "ru"))
        do { _ = try await session.process(external); XCTFail("Expected explicit context rejection") }
        catch { XCTAssertEqual(error as? QualiaSessionError, .externalContextNotSupported) }
        let inputs = await fixture.inputs
        XCTAssertTrue(inputs.isEmpty)
        XCTAssertTrue(renderer.commands.isEmpty)
    }

    func testNonMonotonicClockAndInvalidReducerOutputAreTypedBeforeDispatch() async throws {
        for badReducer in [false, true] {
            let clock = SessionTestClock()
            let fixture = SessionFixtureAnalyzer()
            let renderer = RecordingHapticRenderer()
            let reducer: any QualiaSceneReducing = badReducer ? InvalidSessionReducer() : QualiaSceneReducer()
            let deps = try sessionDependencies(analyzer: fixture, clock: clock, reducer: reducer)
            let session = try await QualiaSession(dependencies: deps,
                renderer: QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners))
            if !badReducer { clock.set(.seconds(-1)) }
            do { _ = try await accept("a", session: session, fixture: fixture); XCTFail("Expected typed rejection") }
            catch { XCTAssertEqual(error as? QualiaSessionError, badReducer ? .invalidReducerOutput : .nonMonotonicClock) }
            let snapshot = await session.snapshot
            XCTAssertEqual(snapshot.scene.revision, 0)
            XCTAssertTrue(renderer.commands.isEmpty)
        }
    }

    func testPolicySetupMismatchFailsBeforePreparingRenderer() async throws {
        let fixture = SessionFixtureAnalyzer(signals: [])
        let renderer = RecordingHapticRenderer()
        do {
            _ = try await makeSession(fixture, SessionTestClock(), renderer)
            XCTFail("Expected setup mismatch")
        } catch { XCTAssertNotNil(error as? QualiaReactionConfigurationError) }
        XCTAssertTrue(renderer.lifecycleHistory.isEmpty)
    }

    func testContextDisabledAnalyzerRequiresZeroHistoryAtSetup() async throws {
        let fixture = SessionFixtureAnalyzer(acceptsContext: false)
        let renderer = RecordingHapticRenderer()
        do {
            _ = try await makeSession(fixture, SessionTestClock(), renderer)
            XCTFail("Expected incompatible retained-history configuration")
        } catch { XCTAssertEqual(error as? QualiaError, .unsupportedContext) }
        XCTAssertTrue(renderer.lifecycleHistory.isEmpty)
    }

    func testAnalysisOnlySessionUsesExplicitNoOpRendererAndNoReactionPolicy() async throws {
        let fixture = SessionFixtureAnalyzer(signals: [])
        let deps = try sessionDependencies(analyzer: fixture, clock: SessionTestClock(), policy: NoReactionPolicy())
        let session = try await QualiaSession(dependencies: deps,
            renderer: QualiaSessionRenderer(renderer: NoOpHapticRenderer(), arbitration: .independentOwners))
        let response = try await accept("a", session: session, fixture: fixture)
        XCTAssertEqual(response.transition.current.revision, 1)
        XCTAssertTrue(response.reaction.hapticCommands.isEmpty)
        XCTAssertNil(response.execution.failure)
        try await session.reset()
        let snapshot = await session.snapshot
        XCTAssertEqual(snapshot.scene.revision, 0)
    }

    func testDiagnosticsAreTextFreeAndIdleSessionHasNoRetainCycle() async throws {
        let clock = SessionTestClock()
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let diagnostics = SessionDiagnostics()
        var session: QualiaSession? = try await QualiaSession(
            dependencies: sessionDependencies(analyzer: fixture, clock: clock, diagnostics: diagnostics),
            renderer: QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners))
        weak var weakSession = session
        _ = try await accept("PRIVATE_ID_889", text: "PRIVATE_TEXT_781", session: session!, fixture: fixture)
        try await session!.reset()
        XCTAssertTrue(diagnostics.events.contains(.lifecycle(.reset)))
        XCTAssertTrue(diagnostics.events.contains { if case .completed = $0 { return true }; return false })
        for event in diagnostics.events {
            assertNoText(event)
            XCTAssertFalse(String(reflecting: event).contains("PRIVATE_"))
        }
        session = nil
        XCTAssertNil(weakSession)
    }

    private func makeSession(_ fixture: SessionFixtureAnalyzer, _ clock: SessionTestClock,
                             _ renderer: RecordingHapticRenderer) async throws -> QualiaSession {
        try await QualiaSession(dependencies: sessionDependencies(analyzer: fixture, clock: clock),
            renderer: QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners))
    }

    private func assertNoText(_ value: Any) {
        XCTAssertFalse(value is String)
        for child in Mirror(reflecting: value).children { assertNoText(child.value) }
    }
}

private struct InvalidSessionReducer: QualiaSceneReducing {
    func reduce(state: QualiaSceneState, observation: QualiaObservation, at instant: Duration) -> QualiaSceneTransition {
        QualiaSceneReducer().reduce(state: .initial(at: .seconds(-1)), observation: observation, at: instant)
    }
}
