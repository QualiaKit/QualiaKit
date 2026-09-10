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

        let retry = policy.plan(
            for: try transition(
                previousSignals: [.suspense: 0.9],
                currentSignals: [.suspense: 0.92],
                previousPhase: .active,
                currentPhase: .active
            ),
            context: context(signals: [.suspense], state: appliedState)
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
        on renderer: RecordingHapticRenderer
    ) throws {
        for command in plan.hapticCommands {
            try renderer.execute(command)
        }
    }
}
