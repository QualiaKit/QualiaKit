import XCTest
import QualiaKit
import QualiaTesting

extension ReactionPolicyTests {
    func testIntensityScaleChangeReplacesAppliedAmbientAtStableTension() throws {
        let policy = HorrorNarrativePolicy()
        let initialState = try activeState(
            policy: policy,
            tension: 0.8,
            intensityScale: 1
        )
        let lowerIntensity = try QualiaHapticPreferences(intensityScale: 0.3)
        let plan = policy.plan(
            for: try transition(
                previousSignals: [.suspense: 0.8],
                currentSignals: [.suspense: 0.8],
                previousPhase: .active,
                currentPhase: .active
            ),
            context: context(
                signals: [.suspense],
                preferences: lowerIntensity,
                state: initialState
            )
        )

        guard case let .replace(effectID, pattern, .ambient) = try XCTUnwrap(
            plan.hapticCommands.first
        ) else {
            return XCTFail("Expected intensity preference change to replace ambient")
        }
        let previous = try XCTUnwrap(initialState.appliedAmbientState(for: effectID))
        let proposed = try XCTUnwrap(plan.nextState.appliedAmbientState(for: effectID))
        XCTAssertEqual(proposed.normalizedValue, 0.8)
        XCTAssertEqual(proposed.intensityScale, 0.3)
        XCTAssertEqual(proposed.pattern, pattern)
        XCTAssertNotEqual(proposed.pattern, previous.pattern)
    }

    func testFailedReplaceKeepsComparisonAgainstLastAppliedTension() throws {
        let policy = HorrorNarrativePolicy()
        let appliedState = try activeState(policy: policy, tension: 0.8)
        let failedPlan = policy.plan(
            for: try transition(
                previousSignals: [.suspense: 0.8],
                currentSignals: [.suspense: 0.9],
                previousPhase: .active,
                currentPhase: .active
            ),
            context: context(signals: [.suspense], state: appliedState)
        )
        XCTAssertEqual(failedPlan.hapticCommands.count, 1)

        // The session deliberately does not commit failedPlan.nextState after
        // renderer failure. Semantic state may still advance independently.
        let reconciliation = policy.plan(
            for: try transition(
                previousSignals: [.suspense: 0.9],
                currentSignals: [.suspense: 0.92],
                previousPhase: .active,
                currentPhase: .active
            ),
            context: context(signals: [.suspense], state: appliedState)
        )

        guard case let .replace(effectID, _, .ambient) = try XCTUnwrap(
            reconciliation.hapticCommands.first
        ) else {
            return XCTFail("Expected reconciliation against applied tension 0.8")
        }
        XCTAssertEqual(
            reconciliation.nextState.appliedAmbientState(for: effectID)?.normalizedValue,
            0.92
        )
    }

    func testSuccessfulRetryCommitsAppliedSnapshotAndStopsFurtherReplace() throws {
        let policy = HorrorNarrativePolicy()
        let renderer = RecordingHapticRenderer()
        try renderer.prepare()

        let start = policy.plan(
            for: try transition(currentSignals: [.suspense: 0.8], currentPhase: .active),
            context: context(signals: [.suspense])
        )
        try execute(start, on: renderer)
        let appliedState = start.nextState

        let failed = policy.plan(
            for: try transition(
                previousSignals: [.suspense: 0.8],
                currentSignals: [.suspense: 0.9],
                previousPhase: .active,
                currentPhase: .active
            ),
            context: context(signals: [.suspense], state: appliedState)
        )
        renderer.failNext()
        XCTAssertThrowsError(try renderer.execute(XCTUnwrap(failed.hapticCommands.first)))
        let stateAfterFailure = failed.reconciledStateAfterFailure(
            from: appliedState,
            rendererActiveEffects: renderer.activeEffects
        )
        XCTAssertEqual(stateAfterFailure, appliedState)

        let retry = policy.plan(
            for: try transition(
                previousSignals: [.suspense: 0.9],
                currentSignals: [.suspense: 0.92],
                previousPhase: .active,
                currentPhase: .active
            ),
            context: context(signals: [.suspense], state: stateAfterFailure)
        )
        try execute(retry, on: renderer)
        let reconciledState = retry.nextState

        let stable = policy.plan(
            for: try transition(
                previousSignals: [.suspense: 0.92],
                currentSignals: [.suspense: 0.94],
                previousPhase: .active,
                currentPhase: .active
            ),
            context: context(signals: [.suspense], state: reconciledState)
        )

        XCTAssertTrue(stable.hapticCommands.isEmpty)
        XCTAssertEqual(stable.rationale?.ruleIdentifier, "ambient-stable")
        let effectID = try XCTUnwrap(reconciledState.activeEffects.first)
        XCTAssertEqual(
            renderer.activeEffects[effectID]?.pattern,
            reconciledState.appliedAmbientState(for: effectID)?.pattern
        )
    }

    func testFailureAfterAppliedReplaceKeepsProposedSnapshot() throws {
        let policy = HorrorNarrativePolicy()
        let renderer = RecordingHapticRenderer()
        let previousState = try activeState(policy: policy, tension: 0.8)
        let impact = try QualiaScore(value: 0.95, confidence: 0.9)
        try renderer.prepare()
        try renderer.execute(
            .start(
                id: XCTUnwrap(previousState.activeEffects.first),
                pattern: XCTUnwrap(previousState.activeAmbientEffects.values.first).pattern,
                channel: .ambient
            )
        )

        let plan = policy.plan(
            for: try transition(
                previousSignals: [.suspense: 0.8],
                currentSignals: [.suspense: 0.9],
                previousPhase: .active,
                currentPhase: .active,
                evidence: [.impact: impact],
                events: [.impact: impact]
            ),
            context: context(signals: [.suspense, .impact], state: previousState)
        )
        XCTAssertEqual(plan.hapticCommands.count, 2)
        try renderer.execute(plan.hapticCommands[0])
        renderer.failNext()
        XCTAssertThrowsError(try renderer.execute(plan.hapticCommands[1]))

        let reconciled = plan.reconciledStateAfterFailure(
            from: previousState,
            rendererActiveEffects: renderer.activeEffects
        )

        XCTAssertEqual(reconciled, plan.nextState)
    }

    func testPartialReplaceFailureRestartsAboveUpdateDelta() throws {
        try assertPartialReplaceFailureRestarts(nextTension: 0.92)
    }

    func testPartialReplaceFailureRestartsInsideUpdateDelta() throws {
        try assertPartialReplaceFailureRestarts(nextTension: 0.82)
    }

    func testIndependentOwnersDoNotShareOrStopEachOthersAmbientEffect() throws {
        let policy = HorrorNarrativePolicy()
        let renderer = RecordingHapticRenderer()
        let ownerA = try HapticOwnerID(rawValue: "session-a")
        let ownerB = try HapticOwnerID(rawValue: "session-b")
        try renderer.prepare()

        let startA = policy.plan(
            for: try transition(currentSignals: [.suspense: 0.9], currentPhase: .active),
            context: context(signals: [.suspense], effectScope: .owned(ownerA))
        )
        let startB = policy.plan(
            for: try transition(currentSignals: [.suspense: 0.9], currentPhase: .active),
            context: context(signals: [.suspense], effectScope: .owned(ownerB))
        )
        try execute(startA, on: renderer)
        try execute(startB, on: renderer)

        let effectA = try XCTUnwrap(startA.nextState.activeEffects.first)
        let effectB = try XCTUnwrap(startB.nextState.activeEffects.first)
        XCTAssertNotEqual(effectA, effectB)
        XCTAssertEqual(renderer.activeEffects.count, 2)

        let stopA = policy.plan(
            for: try transition(
                previousSignals: [.suspense: 0.9],
                currentSignals: [.suspense: 0.3],
                previousPhase: .active,
                currentPhase: .resolving
            ),
            context: context(
                signals: [.suspense],
                state: startA.nextState,
                effectScope: .owned(ownerA)
            )
        )
        try execute(stopA, on: renderer)

        XCTAssertNil(renderer.activeEffects[effectA])
        XCTAssertNotNil(renderer.activeEffects[effectB])
        XCTAssertEqual(renderer.activeEffects.count, 1)
    }

    func testCustomPolicyConvenienceExplicitlyPreservesAppliedState() throws {
        let state = try activeState(tension: 0.8)
        let suppliedContext = context(signals: [.suspense], state: state)
        let plan = QualiaReactionPlan.preservingState(
            hapticCommands: [],
            rationale: nil,
            from: suppliedContext
        )

        XCTAssertEqual(plan.nextState, state)
    }

    private func execute(
        _ plan: QualiaReactionPlan,
        on renderer: any HapticRendering
    ) throws {
        for command in plan.hapticCommands {
            try renderer.execute(command)
        }
    }

    private func assertPartialReplaceFailureRestarts(
        nextTension: Float,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let fixture = try makePartialReplaceFailure(file: file, line: line)
        let recovery = fixture.policy.plan(
            for: try transition(
                previousSignals: [.suspense: 0.9],
                currentSignals: [.suspense: nextTension],
                previousPhase: .active,
                currentPhase: .active
            ),
            context: context(
                signals: [.suspense],
                state: fixture.reconciledState,
                effectScope: fixture.effectScope
            )
        )

        guard case let .start(effectID, pattern, .ambient) = try XCTUnwrap(
            recovery.hapticCommands.first,
            file: file,
            line: line
        ) else {
            return XCTFail(
                "Expected missing physical effect to restart at tension \(nextTension)",
                file: file,
                line: line
            )
        }

        try execute(recovery, on: fixture.renderer)
        XCTAssertEqual(fixture.renderer.activeEffects[effectID]?.pattern, pattern)
        XCTAssertEqual(
            recovery.nextState.appliedAmbientState(for: effectID)?.pattern,
            pattern,
            file: file,
            line: line
        )
    }

    private func makePartialReplaceFailure(
        file: StaticString,
        line: UInt
    ) throws -> PartialReplaceFailureFixture {
        let backend = ReplacementStartFailingEngine()
        let renderer = CoreHapticRenderer(backend: backend)
        let policy = HorrorNarrativePolicy()
        let owner = try HapticOwnerID(rawValue: "partial-replace-session")
        let effectScope = HapticEffectScope.owned(owner)
        try renderer.prepare()

        let start = policy.plan(
            for: try transition(currentSignals: [.suspense: 0.8], currentPhase: .active),
            context: context(signals: [.suspense], effectScope: effectScope)
        )
        try execute(start, on: renderer)
        let previousState = start.nextState

        let replacement = policy.plan(
            for: try transition(
                previousSignals: [.suspense: 0.8],
                currentSignals: [.suspense: 0.9],
                previousPhase: .active,
                currentPhase: .active
            ),
            context: context(
                signals: [.suspense],
                state: previousState,
                effectScope: effectScope
            )
        )
        backend.failNextPlayerStart()
        XCTAssertThrowsError(
            try execute(replacement, on: renderer),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? HapticError, .playerStartFailed, file: file, line: line)
        }
        XCTAssertTrue(renderer.activeEffects.isEmpty, file: file, line: line)

        let reconciledState = replacement.reconciledStateAfterFailure(
            from: previousState,
            rendererActiveEffects: renderer.activeEffects
        )
        XCTAssertTrue(reconciledState.activeEffects.isEmpty, file: file, line: line)

        return PartialReplaceFailureFixture(
            policy: policy,
            renderer: renderer,
            effectScope: effectScope,
            reconciledState: reconciledState
        )
    }
}

@MainActor
private struct PartialReplaceFailureFixture {
    let policy: HorrorNarrativePolicy
    let renderer: CoreHapticRenderer
    let effectScope: HapticEffectScope
    let reconciledState: QualiaReactionState
}

@MainActor
private final class ReplacementStartFailingEngine: HapticRuntimeEngine {
    let capabilities: HapticCapabilities = .full
    var stoppedHandler: (@Sendable () -> Void)?
    var resetHandler: (@Sendable () -> Void)?

    private var shouldFailNextPlayerStart = false

    func start() throws {}
    func stop() async throws {}

    func makePlayer(pattern: HapticPattern) throws -> any HapticRuntimePlayer {
        _ = pattern
        return ReplacementStartFailingPlayer(engine: self)
    }

    func failNextPlayerStart() {
        shouldFailNextPlayerStart = true
    }

    func startPlayer() throws {
        guard shouldFailNextPlayerStart else { return }
        shouldFailNextPlayerStart = false
        throw HapticError.playerStartFailed
    }
}

@MainActor
private final class ReplacementStartFailingPlayer: HapticRuntimePlayer {
    var completionHandler: (@Sendable () -> Void)?

    private unowned let engine: ReplacementStartFailingEngine

    init(engine: ReplacementStartFailingEngine) {
        self.engine = engine
    }

    func start() throws {
        try engine.startPlayer()
    }

    func stop() throws {}
}
