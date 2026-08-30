import XCTest
import QualiaKit
import QualiaTesting

@MainActor
final class HapticRuntimeTests: XCTestCase {
    func testImpactPlaysWithoutStoppingAmbientHeartbeat() throws {
        let renderer = RecordingHapticRenderer()
        let heartbeatID = try effectID("heartbeat", owner: "session-a")
        try renderer.prepare()
        try renderer.execute(
            .start(id: heartbeatID, pattern: heartbeat(), channel: .ambient)
        )

        try renderer.execute(.play(pattern: impact(), channel: .accent))

        XCTAssertEqual(renderer.activeEffects.count, 1)
        XCTAssertEqual(renderer.activeEffects[heartbeatID]?.channel, .ambient)
        XCTAssertEqual(renderer.commands.count, 2)
    }

    func testStopAllIsIdempotentWhenNoEffectsAreActive() throws {
        let renderer = RecordingHapticRenderer()
        try renderer.prepare()

        try renderer.execute(.stopAll)
        try renderer.execute(.stopAll)

        XCTAssertTrue(renderer.activeEffects.isEmpty)
        XCTAssertEqual(renderer.history.map(\.result), [.success, .success])
    }

    func testInvalidPatternIsRejectedBeforeRendererInvocation() throws {
        let renderer = RecordingHapticRenderer()
        try renderer.prepare()

        XCTAssertThrowsError(
            try HapticPattern(
                duration: .seconds(1),
                events: [
                    .continuous(
                        at: .seconds(0.75),
                        duration: .seconds(0.5),
                        intensity: value(0.8),
                        sharpness: value(0.4)
                    )
                ]
            )
        ) { error in
            XCTAssertEqual(error as? HapticError, .invalidHapticPattern)
        }
        XCTAssertTrue(renderer.history.isEmpty)
    }

    func testHapticValueRejectsNonFiniteAndOutOfRangeValues() throws {
        XCTAssertEqual(try HapticValue(0).rawValue, 0)
        XCTAssertEqual(try HapticValue(1).rawValue, 1)

        for invalid: Float in [-0.001, 1.001, .nan, .infinity] {
            XCTAssertThrowsError(try HapticValue(invalid)) { error in
                XCTAssertEqual(error as? HapticError, .invalidHapticValue)
            }
        }

        let encoded = try JSONEncoder().encode(try HapticValue(0.75))
        XCTAssertEqual(try JSONDecoder().decode(HapticValue.self, from: encoded), try HapticValue(0.75))
        XCTAssertThrowsError(
            try JSONDecoder().decode(HapticValue.self, from: Data("2".utf8))
        )
    }

    func testPatternValidatesTimelineOrderingDurationCurvesAndLooping() throws {
        assertInvalidPattern(events: [
            .transient(at: .seconds(-1), intensity: value(1), sharpness: value(1))
        ])
        assertInvalidPattern(events: [
            .continuous(
                at: .zero,
                duration: .zero,
                intensity: value(1),
                sharpness: value(1)
            )
        ])
        assertInvalidPattern(events: [
            .transient(at: .seconds(0.8), intensity: value(1), sharpness: value(1)),
            .transient(at: .seconds(0.2), intensity: value(1), sharpness: value(1)),
        ])
        XCTAssertThrowsError(
            try HapticPattern(
                duration: .seconds(1),
                events: [
                    .transient(at: .zero, intensity: value(1), sharpness: value(1))
                ],
                looping: .loop(period: .seconds(0.9))
            )
        ) { error in
            XCTAssertEqual(error as? HapticError, .invalidHapticPattern)
        }

        let outOfBoundsCurve = try HapticParameterCurve(
            parameter: .intensity,
            controlPoints: [
                try HapticCurveControlPoint(at: .zero, value: value(0.2)),
                try HapticCurveControlPoint(at: .seconds(2), value: value(1)),
            ]
        )
        XCTAssertThrowsError(
            try HapticPattern(
                duration: .seconds(1),
                events: [
                    .transient(at: .zero, intensity: value(1), sharpness: value(1))
                ],
                curves: [outOfBoundsCurve]
            )
        ) { error in
            XCTAssertEqual(error as? HapticError, .invalidHapticPattern)
        }
    }

    func testCurveRejectsEmptyNegativeAndUnorderedControlPoints() throws {
        XCTAssertThrowsError(
            try HapticCurveControlPoint(at: .seconds(-1), value: value(0.5))
        ) { error in
            XCTAssertEqual(error as? HapticError, .invalidHapticCurve)
        }
        XCTAssertThrowsError(
            try HapticParameterCurve(parameter: .intensity, controlPoints: [])
        ) { error in
            XCTAssertEqual(error as? HapticError, .invalidHapticCurve)
        }
        XCTAssertThrowsError(
            try HapticParameterCurve(
                parameter: .sharpness,
                controlPoints: [
                    try HapticCurveControlPoint(at: .seconds(0.8), value: value(1)),
                    try HapticCurveControlPoint(at: .seconds(0.2), value: value(0)),
                ]
            )
        ) { error in
            XCTAssertEqual(error as? HapticError, .invalidHapticCurve)
        }
    }

    func testRepeatedStartDoesNotDuplicateAndReplacePreservesIdentity() throws {
        let renderer = RecordingHapticRenderer()
        let id = try effectID("heartbeat", owner: "session-a")
        try renderer.prepare()

        try renderer.execute(.start(id: id, pattern: heartbeat(), channel: .ambient))
        try renderer.execute(.start(id: id, pattern: heartbeat(), channel: .ambient))

        XCTAssertEqual(renderer.activeEffects.count, 1)
        let replacement = try heartbeat(duration: .seconds(2))
        try renderer.execute(.replace(id: id, pattern: replacement, channel: .ambient))
        XCTAssertEqual(renderer.activeEffects.count, 1)
        XCTAssertEqual(renderer.activeEffects[id]?.id, id)
        XCTAssertEqual(renderer.activeEffects[id]?.pattern, replacement)
    }

    func testReplaceRequiresAnExistingEffect() throws {
        let renderer = RecordingHapticRenderer()
        let id = try effectID("heartbeat", owner: "session-a")
        try renderer.prepare()

        XCTAssertThrowsError(
            try renderer.execute(.replace(id: id, pattern: heartbeat(), channel: .ambient))
        ) { error in
            XCTAssertEqual(error as? HapticError, .invalidLifecycleState)
        }
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        XCTAssertEqual(renderer.history.last?.result, .failure(.invalidLifecycleState))
    }

    func testEffectOwnershipIsIsolatedEvenForTheSameRawName() throws {
        let renderer = RecordingHapticRenderer()
        let first = try effectID("heartbeat", owner: "session-a")
        let second = try effectID("heartbeat", owner: "session-b")
        try renderer.prepare()
        try renderer.execute(.start(id: first, pattern: heartbeat(), channel: .ambient))
        try renderer.execute(.start(id: second, pattern: heartbeat(), channel: .ambient))

        try renderer.execute(.stop(id: first))

        XCTAssertNil(renderer.activeEffects[first])
        XCTAssertNotNil(renderer.activeEffects[second])
        XCTAssertEqual(renderer.activeEffects.count, 1)
    }

    func testStopAndChannelStopAreSafeWhenNothingMatches() throws {
        let renderer = RecordingHapticRenderer()
        let id = try effectID("missing", owner: "session-a")
        try renderer.prepare()

        try renderer.execute(.stop(id: id))
        try renderer.execute(.stopChannel(.ambient))
        try renderer.execute(.stopChannel(.accent))

        XCTAssertTrue(renderer.activeEffects.isEmpty)
        XCTAssertEqual(renderer.history.count, 3)
        XCTAssertTrue(renderer.history.allSatisfy { $0.result == .success })
    }

    func testLongLivedCommandsRequireLoopingAmbientPatterns() throws {
        let renderer = RecordingHapticRenderer()
        let id = try effectID("invalid", owner: "session-a")
        try renderer.prepare()

        XCTAssertThrowsError(
            try renderer.execute(.start(id: id, pattern: impact(), channel: .ambient))
        ) { error in
            XCTAssertEqual(error as? HapticError, .invalidCommand)
        }
        XCTAssertThrowsError(
            try renderer.execute(.start(id: id, pattern: heartbeat(), channel: .accent))
        ) { error in
            XCTAssertEqual(error as? HapticError, .invalidCommand)
        }
        XCTAssertThrowsError(
            try renderer.execute(.play(pattern: heartbeat(), channel: .accent))
        ) { error in
            XCTAssertEqual(error as? HapticError, .invalidCommand)
        }
    }

    func testCapabilitiesRejectUnavailableContinuousAndCurveFeatures() throws {
        let unavailable = RecordingHapticRenderer(capabilities: .unavailable)
        XCTAssertThrowsError(try unavailable.prepare()) { error in
            XCTAssertEqual(error as? HapticError, .hapticsUnavailable)
        }

        let transientOnly = RecordingHapticRenderer(
            capabilities: HapticCapabilities(
                supportsHaptics: true,
                supportsContinuousHaptics: false,
                supportsParameterCurves: false
            )
        )
        try transientOnly.prepare()
        XCTAssertThrowsError(
            try transientOnly.execute(.play(pattern: continuousOneShot(), channel: .accent))
        ) { error in
            XCTAssertEqual(
                error as? HapticError,
                .unsupportedFeature(.continuousHaptics)
            )
        }

        XCTAssertThrowsError(
            try transientOnly.execute(.play(pattern: curvedImpact(), channel: .accent))
        ) { error in
            XCTAssertEqual(
                error as? HapticError,
                .unsupportedFeature(.parameterCurves)
            )
        }
    }

    func testSuspendStopsAmbientAndResumeRestoresLifecycleNotEffects() async throws {
        let renderer = RecordingHapticRenderer()
        let id = try effectID("heartbeat", owner: "session-a")
        try renderer.prepare()
        try renderer.execute(.start(id: id, pattern: heartbeat(), channel: .ambient))

        await renderer.suspend()

        XCTAssertTrue(renderer.activeEffects.isEmpty)
        XCTAssertTrue(renderer.isSuspended)
        XCTAssertFalse(renderer.isPrepared)
        XCTAssertThrowsError(try renderer.execute(.stopAll)) { error in
            XCTAssertEqual(error as? HapticError, .invalidLifecycleState)
        }

        try await renderer.resume()
        XCTAssertTrue(renderer.isPrepared)
        XCTAssertFalse(renderer.isSuspended)
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        XCTAssertEqual(renderer.lifecycleHistory, [.prepare, .suspend, .resume])
    }

    func testInjectedFailureIsTypedRecordedAndDoesNotMutateEffects() throws {
        let renderer = RecordingHapticRenderer()
        let id = try effectID("heartbeat", owner: "session-a")
        try renderer.prepare()
        renderer.failNext(with: .playerStartFailed)

        XCTAssertThrowsError(
            try renderer.execute(.start(id: id, pattern: heartbeat(), channel: .ambient))
        ) { error in
            XCTAssertEqual(error as? HapticError, .playerStartFailed)
        }
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        XCTAssertEqual(renderer.history.last?.result, .failure(.playerStartFailed))
    }

    func testRecordingHistoryUsesDeterministicSequenceAndTimestamps() throws {
        var now = Duration.seconds(1)
        let renderer = RecordingHapticRenderer(now: { now })
        try renderer.prepare()
        try renderer.execute(.play(pattern: impact(), channel: .accent))
        now = .seconds(3)
        try renderer.execute(.stopAll)

        XCTAssertEqual(renderer.history.map(\.sequence), [1, 2])
        XCTAssertEqual(renderer.history.map(\.timestamp), [.seconds(1), .seconds(3)])
        renderer.resetHistory()
        XCTAssertTrue(renderer.history.isEmpty)
        XCTAssertTrue(renderer.lifecycleHistory.isEmpty)
    }

    func testRecordingHistoryCapturesDeterministicActiveEffectSnapshots() throws {
        let renderer = RecordingHapticRenderer()
        let second = try effectID("heartbeat", owner: "session-b")
        let first = try effectID("heartbeat", owner: "session-a")
        try renderer.prepare()

        try renderer.execute(.start(id: second, pattern: heartbeat(), channel: .ambient))
        try renderer.execute(.start(id: first, pattern: heartbeat(), channel: .ambient))
        try renderer.execute(.stop(id: second))

        XCTAssertEqual(renderer.activeEffectHistory.map(\.count), [1, 2, 1])
        XCTAssertEqual(renderer.activeEffectHistory[1].map(\.id), [first, second])
        XCTAssertEqual(renderer.activeEffectHistory[2].map(\.id), [first])
    }

    func testInterruptionAndResetStopSessionOwnedEffectsWithBoundedRecovery() throws {
        let renderer = RecordingHapticRenderer()
        let global = try HapticEffectID(rawValue: "global-heartbeat", scope: .global)
        let sessionOwned = try effectID("session-heartbeat", owner: "session-a")
        try renderer.prepare()
        try renderer.execute(.start(id: global, pattern: heartbeat(), channel: .ambient))
        try renderer.execute(.start(id: sessionOwned, pattern: heartbeat(), channel: .ambient))

        renderer.simulateEngineReset()

        XCTAssertEqual(Set(renderer.activeEffects.keys), [global])
        XCTAssertEqual(renderer.lifecycleHistory.last, .engineReset(.success))
        XCTAssertTrue(renderer.isPrepared)

        renderer.simulateEngineInterruption()

        XCTAssertTrue(renderer.activeEffects.isEmpty)
        XCTAssertFalse(renderer.isPrepared)
        XCTAssertEqual(renderer.lastLifecycleError, .engineInterrupted)
        XCTAssertEqual(renderer.lifecycleHistory.last, .engineInterruption)

        try renderer.prepare()
        try renderer.execute(.start(id: global, pattern: heartbeat(), channel: .ambient))
        renderer.failNext(with: .enginePreparationFailed)
        renderer.simulateEngineReset()

        XCTAssertTrue(renderer.activeEffects.isEmpty)
        XCTAssertFalse(renderer.isPrepared)
        XCTAssertEqual(renderer.lastLifecycleError, .enginePreparationFailed)
        XCTAssertEqual(
            renderer.lifecycleHistory.last,
            .engineReset(.failure(.enginePreparationFailed))
        )
    }

    func testImmediateResumeWaitsForDelayedEngineStopCompletion() async throws {
        let backend = ControlledHapticRuntimeEngine()
        backend.delaysEngineStop = true
        let renderer = CoreHapticRenderer(backend: backend)
        let id = try effectID("heartbeat", owner: "session-a")
        try renderer.prepare()
        try renderer.execute(.start(id: id, pattern: heartbeat(), channel: .ambient))
        try renderer.execute(.play(pattern: impact(), channel: .accent))
        XCTAssertEqual(renderer.activeOneShotPlayerCount, 1)

        let suspension = Task { await renderer.suspend() }
        for _ in 0..<10 where !backend.hasPendingEngineStop {
            await Task.yield()
        }

        XCTAssertTrue(backend.hasPendingEngineStop)
        XCTAssertEqual(renderer.lifecycleState, .suspending)
        let resumption = Task { try await renderer.resume() }
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertEqual(backend.startCallCount, 1)
        XCTAssertEqual(renderer.lifecycleState, .suspending)

        backend.completeEngineStop()
        await suspension.value
        try await resumption.value

        XCTAssertEqual(backend.startCallCount, 2)
        XCTAssertEqual(renderer.lifecycleState, .ready)
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        XCTAssertEqual(renderer.activeOneShotPlayerCount, 0)
    }

    func testEngineStopFailureIsRecordedAfterStopCompletion() async throws {
        let backend = ControlledHapticRuntimeEngine()
        backend.delaysEngineStop = true
        let renderer = CoreHapticRenderer(backend: backend)
        try renderer.prepare()

        let suspension = Task { await renderer.suspend() }
        for _ in 0..<10 where !backend.hasPendingEngineStop {
            await Task.yield()
        }
        backend.completeEngineStop(with: .engineStopFailed)
        await suspension.value

        XCTAssertEqual(renderer.lifecycleState, .suspended)
        XCTAssertEqual(renderer.lastLifecycleError, .engineStopFailed)
        XCTAssertFalse(renderer.isPrepared)
    }

    func testResetDuringSuspensionNeverRestartsEngine() async throws {
        let backend = ControlledHapticRuntimeEngine()
        backend.delaysEngineStop = true
        let renderer = CoreHapticRenderer(backend: backend)
        let id = try effectID("heartbeat", owner: "session-a")
        try renderer.prepare()
        try renderer.execute(.start(id: id, pattern: heartbeat(), channel: .ambient))

        let suspension = Task { await renderer.suspend() }
        for _ in 0..<10 where !backend.hasPendingEngineStop {
            await Task.yield()
        }
        backend.triggerReset()
        await Task.yield()

        XCTAssertEqual(renderer.lifecycleState, .suspending)
        XCTAssertEqual(backend.startCallCount, 1)
        XCTAssertEqual(renderer.lastLifecycleError, .engineReset)

        backend.completeEngineStop()
        await suspension.value

        XCTAssertEqual(renderer.lifecycleState, .suspended)
        XCTAssertEqual(backend.startCallCount, 1)
        XCTAssertFalse(renderer.isPrepared)
        XCTAssertEqual(renderer.lastLifecycleError, .engineReset)

        backend.triggerReset()
        await Task.yield()

        XCTAssertEqual(renderer.lifecycleState, .suspended)
        XCTAssertEqual(backend.startCallCount, 1)
    }

    func testPartialStopChannelFailureKeepsLogicalAndPhysicalStateAligned() throws {
        let backend = ControlledHapticRuntimeEngine()
        let renderer = CoreHapticRenderer(backend: backend)
        let first = try effectID("a", owner: "session-a")
        let second = try effectID("b", owner: "session-a")
        try renderer.prepare()
        try renderer.execute(.start(id: first, pattern: heartbeat(), channel: .ambient))
        try renderer.execute(.start(id: second, pattern: heartbeat(), channel: .ambient))
        backend.playerStopFailureCalls = [2]

        XCTAssertThrowsError(try renderer.execute(.stopChannel(.ambient))) { error in
            XCTAssertEqual(error as? HapticError, .playerStopFailed)
        }

        XCTAssertEqual(renderer.activeEffects.count, 1)
        XCTAssertEqual(renderer.activeLongLivedPlayerCount, 1)
        XCTAssertEqual(backend.activePlayerCount, 1)

        let stoppedID = try XCTUnwrap(
            Set([first, second])
                .subtracting(renderer.activeEffects.keys)
                .first
        )
        backend.playerStopFailureCalls = []
        try renderer.execute(.start(id: stoppedID, pattern: heartbeat(), channel: .ambient))

        XCTAssertEqual(renderer.activeEffects.count, 2)
        XCTAssertEqual(renderer.activeLongLivedPlayerCount, 2)
        XCTAssertEqual(backend.createdPlayers.count, 3)
    }

    func testPartialOneShotStopFailureRetainsOnlyTheUnstoppedPlayer() throws {
        let backend = ControlledHapticRuntimeEngine()
        let renderer = CoreHapticRenderer(backend: backend)
        try renderer.prepare()
        try renderer.execute(.play(pattern: impact(), channel: .accent))
        try renderer.execute(.play(pattern: impact(), channel: .accent))
        backend.playerStopFailureCalls = [2]

        XCTAssertThrowsError(try renderer.execute(.stopAll)) { error in
            XCTAssertEqual(error as? HapticError, .playerStopFailed)
        }

        XCTAssertEqual(renderer.activeOneShotPlayerCount, 1)
        XCTAssertEqual(backend.activePlayerCount, 1)

        backend.playerStopFailureCalls = []
        try renderer.execute(.stopAll)
        XCTAssertEqual(renderer.activeOneShotPlayerCount, 0)
        XCTAssertEqual(backend.activePlayerCount, 0)
    }

    func testStopFailureDuringSuspendDoesNotPoisonStableIDAfterResume() async throws {
        let backend = ControlledHapticRuntimeEngine()
        let renderer = CoreHapticRenderer(backend: backend)
        let id = try effectID("heartbeat", owner: "session-a")
        try renderer.prepare()
        try renderer.execute(.start(id: id, pattern: heartbeat(), channel: .ambient))
        backend.playerStopFailureCalls = [1]

        await renderer.suspend()

        XCTAssertEqual(renderer.lifecycleState, .suspended)
        XCTAssertEqual(renderer.lastLifecycleError, .playerStopFailed)
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        XCTAssertEqual(renderer.activeLongLivedPlayerCount, 0)

        backend.playerStopFailureCalls = []
        try await renderer.resume()
        try renderer.execute(.start(id: id, pattern: heartbeat(), channel: .ambient))

        XCTAssertEqual(renderer.activeEffects.count, 1)
        XCTAssertEqual(renderer.activeLongLivedPlayerCount, 1)
        XCTAssertEqual(backend.createdPlayers.count, 2)
    }

    func testIdentifiersAreValidatedOwnedAndCodable() throws {
        XCTAssertThrowsError(try HapticOwnerID(rawValue: " \n")) { error in
            XCTAssertEqual(error as? HapticError, .invalidHapticIdentifier)
        }
        XCTAssertThrowsError(try HapticEffectID(rawValue: "", scope: .global)) { error in
            XCTAssertEqual(error as? HapticError, .invalidHapticIdentifier)
        }

        let owned = try effectID("heartbeat", owner: "session-a")
        let global = try HapticEffectID(rawValue: "global-heartbeat", scope: .global)
        XCTAssertNotEqual(owned, global)
        XCTAssertEqual(global.scope, .global)

        let data = try JSONEncoder().encode(owned)
        XCTAssertEqual(try JSONDecoder().decode(HapticEffectID.self, from: data), owned)
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                HapticEffectID.self,
                from: Data(#"{"rawValue":"missing-scope"}"#.utf8)
            )
        )
    }

    func testExplicitNoOpAdvertisesUnavailableAndNeverFallsBack() async throws {
        let renderer = NoOpHapticRenderer()

        XCTAssertEqual(renderer.capabilities, .unavailable)
        XCTAssertNoThrow(try renderer.prepare())
        XCTAssertNoThrow(try renderer.execute(.play(pattern: impact(), channel: .accent)))
        await renderer.suspend()
        try await renderer.resume()
    }

    func testCoreRendererExposesHardwareCapabilitiesWithoutSingleton() {
        let first = CoreHapticRenderer()
        let second = CoreHapticRenderer()

        XCTAssertFalse(first === second)
        XCTAssertEqual(
            first.capabilities.supportsContinuousHaptics,
            first.capabilities.supportsHaptics
        )
    }

    func testPublicHapticValuesAreSendable() {
        assertSendable(HapticError.self)
        assertSendable(HapticFeature.self)
        assertSendable(HapticValue.self)
        assertSendable(HapticEvent.self)
        assertSendable(HapticCurveParameter.self)
        assertSendable(HapticCurveControlPoint.self)
        assertSendable(HapticParameterCurve.self)
        assertSendable(HapticLooping.self)
        assertSendable(HapticPattern.self)
        assertSendable(HapticOwnerID.self)
        assertSendable(HapticEffectScope.self)
        assertSendable(HapticEffectID.self)
        assertSendable(HapticChannel.self)
        assertSendable(HapticCommand.self)
        assertSendable(HapticActiveEffect.self)
        assertSendable(HapticCapabilities.self)
        assertSendable(HapticRendererLifecycleState.self)
        assertSendable(HapticRecordingResult.self)
        assertSendable(HapticRecordingEntry.self)
        assertSendable(HapticResetRecoveryResult.self)
        assertSendable(HapticRecordingLifecycleEvent.self)
    }

    private func heartbeat(duration: Duration) throws -> HapticPattern {
        try HapticPattern(
            duration: duration,
            events: [
                .transient(at: .zero, intensity: value(0.8), sharpness: value(0.7)),
                .transient(
                    at: duration / 4,
                    intensity: value(0.55),
                    sharpness: value(0.5)
                ),
            ],
            looping: .loop(period: duration)
        )
    }

    private func heartbeat() -> HapticPattern {
        try! heartbeat(duration: .seconds(1))
    }

    private func impact() -> HapticPattern {
        try! HapticPattern(
            duration: .milliseconds(100),
            events: [
                .transient(at: .zero, intensity: value(1), sharpness: value(0.9))
            ]
        )
    }

    private func continuousOneShot() -> HapticPattern {
        try! HapticPattern(
            duration: .seconds(1),
            events: [
                .continuous(
                    at: .zero,
                    duration: .seconds(1),
                    intensity: value(0.5),
                    sharpness: value(0.5)
                )
            ]
        )
    }

    private func curvedImpact() -> HapticPattern {
        let curve = try! HapticParameterCurve(
            parameter: .intensity,
            controlPoints: [
                try! HapticCurveControlPoint(at: .zero, value: value(0.2)),
                try! HapticCurveControlPoint(at: .milliseconds(100), value: value(1)),
            ]
        )
        return try! HapticPattern(
            duration: .milliseconds(100),
            events: [
                .transient(at: .zero, intensity: value(1), sharpness: value(0.9))
            ],
            curves: [curve]
        )
    }

    private func effectID(_ rawValue: String, owner: String) throws -> HapticEffectID {
        try HapticEffectID(
            rawValue: rawValue,
            scope: .owned(HapticOwnerID(rawValue: owner))
        )
    }

    private func value(_ rawValue: Float) -> HapticValue {
        try! HapticValue(rawValue)
    }

    private func assertInvalidPattern(
        events: [HapticEvent],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try HapticPattern(duration: .seconds(1), events: events),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? HapticError,
                .invalidHapticPattern,
                file: file,
                line: line
            )
        }
    }

    private func assertSendable<T: Sendable>(_: T.Type) {}
}

@MainActor
private final class ControlledHapticRuntimeEngine: HapticRuntimeEngine {
    let capabilities: HapticCapabilities = .full
    var stoppedHandler: (@Sendable () -> Void)?
    var resetHandler: (@Sendable () -> Void)?
    var delaysEngineStop = false
    var playerStopFailureCalls: Set<Int> = []

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var playerStopCallCount = 0
    private(set) var createdPlayers: [ControlledHapticRuntimePlayer] = []

    var hasPendingEngineStop: Bool { engineStopContinuation != nil }
    var activePlayerCount: Int {
        createdPlayers.filter { $0.isStarted && !$0.isStopped }.count
    }

    private var engineStopContinuation: CheckedContinuation<HapticError?, Never>?

    func start() throws {
        startCallCount += 1
    }

    func stop() async throws {
        stopCallCount += 1
        if delaysEngineStop {
            let failure = await withCheckedContinuation { continuation in
                engineStopContinuation = continuation
            }
            if let failure {
                throw failure
            }
        } else {
            invalidatePlayers()
        }
    }

    func makePlayer(pattern: HapticPattern) throws -> any HapticRuntimePlayer {
        let player = ControlledHapticRuntimePlayer(engine: self)
        createdPlayers.append(player)
        return player
    }

    func completeEngineStop(with failure: HapticError? = nil) {
        invalidatePlayers()
        let continuation = engineStopContinuation
        engineStopContinuation = nil
        continuation?.resume(returning: failure)
    }

    func triggerReset() {
        resetHandler?()
    }

    func triggerInterruption() {
        stoppedHandler?()
    }

    func stopPlayer() throws {
        playerStopCallCount += 1
        if playerStopFailureCalls.contains(playerStopCallCount) {
            throw HapticError.playerStopFailed
        }
    }

    private func invalidatePlayers() {
        createdPlayers.forEach { $0.invalidate() }
    }
}

@MainActor
private final class ControlledHapticRuntimePlayer: HapticRuntimePlayer {
    var completionHandler: (@Sendable () -> Void)?
    private(set) var isStarted = false
    private(set) var isStopped = false

    private unowned let engine: ControlledHapticRuntimeEngine

    init(engine: ControlledHapticRuntimeEngine) {
        self.engine = engine
    }

    func start() throws {
        isStarted = true
        isStopped = false
    }

    func stop() throws {
        try engine.stopPlayer()
        isStopped = true
    }

    func invalidate() {
        isStopped = true
    }
}
