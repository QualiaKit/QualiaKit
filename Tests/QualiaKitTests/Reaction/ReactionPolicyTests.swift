// The focused spec matrix is intentionally kept together for reviewability.
// swiftlint:disable file_length
import XCTest
import QualiaKit
import QualiaTesting

@MainActor
final class ReactionPolicyTests: XCTestCase {
    func testNoSupportedSignalProducesNoCommandAndExplainsDecision() throws {
        let policy = HorrorNarrativePolicy()
        let plan = policy.plan(
            for: try transition(),
            context: context(signals: [.suspense, .impact])
        )

        XCTAssertTrue(plan.hapticCommands.isEmpty)
        XCTAssertEqual(plan.rationale?.ruleIdentifier, "no-supported-signal")
        XCTAssertEqual(plan.rationale?.policyIdentifier, HorrorNarrativePolicy.identifier)
        XCTAssertEqual(plan.rationale?.policyVersion, HorrorNarrativePolicy.version)
    }

    func testStrictHorrorPolicyRejectsValenceOnlyAnalyzer() throws {
        let policy: any QualiaReactionPolicy = HorrorNarrativePolicy()

        XCTAssertThrowsError(
            try policy.validate(
                analyzerCapabilities: capabilities(dimensions: [.valence]),
                hapticCapabilities: .full
            )
        ) { error in
            XCTAssertEqual(
                error as? QualiaReactionConfigurationError,
                .missingAnalyzerSignal(.suspense)
            )
        }
    }

    func testExplicitAccentOnlyCompatibilityIsValidatedAndObservable() throws {
        let configuration = try HorrorNarrativePolicy.Configuration(
            compatibilityMode: .transientAccentsOnly
        )
        let policy = HorrorNarrativePolicy(configuration: configuration)
        let transientOnly = HapticCapabilities(
            supportsHaptics: true,
            supportsContinuousHaptics: false,
            supportsParameterCurves: false
        )

        XCTAssertNoThrow(
            try policy.validate(
                analyzerCapabilities: capabilities(signals: [.impact]),
                hapticCapabilities: transientOnly
            )
        )
        let score = try QualiaScore(value: 0.95, confidence: 0.9)
        let plan = policy.plan(
            for: try transition(evidence: [.impact: score], events: [.impact: score]),
            context: context(signals: [.impact], haptics: transientOnly)
        )

        XCTAssertEqual(plan.hapticCommands.count, 1)
        XCTAssertEqual(plan.rationale?.ruleIdentifier, "accent-play")
        XCTAssertEqual(
            plan.rationale?.facts.first(where: { $0.key == "compatibility-mode" })?.value,
            "transient-accents-only"
        )
    }

    func testStrictPolicyRejectsMissingMandatoryContinuousHaptics() throws {
        let transientOnly = HapticCapabilities(
            supportsHaptics: true,
            supportsContinuousHaptics: false,
            supportsParameterCurves: false
        )

        XCTAssertThrowsError(
            try HorrorNarrativePolicy().validate(
                analyzerCapabilities: capabilities(signals: [.suspense]),
                hapticCapabilities: transientOnly
            )
        ) { error in
            XCTAssertEqual(
                error as? QualiaReactionConfigurationError,
                .unsupportedHapticFeature(.continuousHaptics)
            )
        }

        let plan = HorrorNarrativePolicy().plan(
            for: try transition(
                currentSignals: [.suspense: 0.9],
                currentPhase: .active,
                evidence: [.impact: QualiaScore(value: 1, confidence: 1)],
                events: [.impact: QualiaScore(value: 1, confidence: 1)]
            ),
            context: context(signals: [.suspense, .impact], haptics: transientOnly)
        )
        XCTAssertTrue(plan.hapticCommands.isEmpty)
        XCTAssertEqual(plan.rationale?.ruleIdentifier, "continuous-haptics-unavailable")
    }

    func testPlanningDoesNotInvokeRenderer() throws {
        let renderer = RecordingHapticRenderer()
        try renderer.prepare()
        let owner = try HapticOwnerID(rawValue: "session-pure-planning")
        let plan = HorrorNarrativePolicy().plan(
            for: try transition(currentSignals: [.suspense: 0.9], currentPhase: .active),
            context: context(signals: [.suspense], ownerID: owner)
        )

        XCTAssertTrue(renderer.commands.isEmpty)
        XCTAssertEqual(plan.hapticCommands.count, 1)

        for command in plan.hapticCommands {
            try renderer.execute(command)
        }
        XCTAssertEqual(renderer.commands, plan.hapticCommands)
    }

    func testNoReactionPolicyAlwaysRetainsStateWithoutCommands() throws {
        let id = try HapticEffectID(rawValue: "existing", scope: .global)
        let state = QualiaReactionState(activeEffects: [id])
        let suppliedContext = context(signals: [], state: state)

        let first = NoReactionPolicy().plan(
            for: try transition(currentSignals: [.suspense: 1]),
            context: suppliedContext
        )
        let second = NoReactionPolicy().plan(
            for: try transition(currentSignals: [.impact: 1]),
            context: suppliedContext
        )

        XCTAssertTrue(first.hapticCommands.isEmpty)
        XCTAssertTrue(second.hapticCommands.isEmpty)
        XCTAssertEqual(first.nextState, state)
        XCTAssertEqual(second.nextState, state)
        XCTAssertEqual(first.rationale?.ruleIdentifier, "no-reaction-policy")
    }

    func testSentimentPreviewRequiresNamedValenceCapability() throws {
        let policy = SentimentPulsePolicy()

        XCTAssertThrowsError(
            try policy.validate(
                analyzerCapabilities: capabilities(),
                hapticCapabilities: .full
            )
        ) { error in
            XCTAssertEqual(
                error as? QualiaReactionConfigurationError,
                .missingAnalyzerDimension(.valence)
            )
        }
    }

    func testSentimentPreviewEmitsBoundedScaledPulse() throws {
        let policy = SentimentPulsePolicy()
        let preferences = try QualiaHapticPreferences(intensityScale: 0.5)
        let plan = policy.plan(
            for: try transition(currentValence: 1),
            context: context(
                dimensions: [.valence],
                preferences: preferences
            )
        )

        guard case let .play(pattern, channel) = try XCTUnwrap(plan.hapticCommands.first),
              case let .transient(_, intensity, sharpness) = try XCTUnwrap(pattern.events.first) else {
            return XCTFail("Expected one sentiment accent")
        }
        XCTAssertEqual(channel, .accent)
        XCTAssertEqual(intensity.rawValue, 0.4, accuracy: 0.0001)
        XCTAssertEqual(sharpness.rawValue, 0.7)
        XCTAssertEqual(plan.rationale?.ruleIdentifier, "positive-valence-pulse")
        XCTAssertTrue(plan.rationale?.policyIdentifier.contains("preview") == true)
    }

    func testSentimentPreviewTreatsNeutralAndMissingAsNoReaction() throws {
        let policy = SentimentPulsePolicy()
        let suppliedContext = context(dimensions: [.valence])

        let missing = policy.plan(for: try transition(), context: suppliedContext)
        let neutral = policy.plan(
            for: try transition(currentValence: 0.5),
            context: suppliedContext
        )

        XCTAssertTrue(missing.hapticCommands.isEmpty)
        XCTAssertEqual(missing.rationale?.ruleIdentifier, "no-supported-signal")
        XCTAssertTrue(neutral.hapticCommands.isEmpty)
        XCTAssertEqual(neutral.rationale?.ruleIdentifier, "below-threshold")
    }

    func testZeroIntensityPreferenceSuppressesNewReaction() throws {
        let preferences = try QualiaHapticPreferences(intensityScale: 0)
        let plan = SentimentPulsePolicy().plan(
            for: try transition(currentValence: 1),
            context: context(dimensions: [.valence], preferences: preferences)
        )

        XCTAssertTrue(plan.hapticCommands.isEmpty)
        XCTAssertEqual(plan.rationale?.ruleIdentifier, "zero-intensity")
    }

    func testPreferencesAndPolicyConfigurationsRejectInvalidValues() throws {
        for invalid: Float in [-0.01, 1.01, .nan, .infinity] {
            XCTAssertThrowsError(try QualiaHapticPreferences(intensityScale: invalid))
        }
        XCTAssertThrowsError(
            try HorrorNarrativePolicy.Configuration(
                startThreshold: 0.4,
                stopThreshold: 0.4
            )
        ) { error in
            XCTAssertEqual(
                error as? QualiaReactionConfigurationError,
                .invalidThresholds
            )
        }
        XCTAssertThrowsError(
            try HorrorNarrativePolicy.Configuration(ambientCycleDuration: .zero)
        ) { error in
            XCTAssertEqual(
                error as? QualiaReactionConfigurationError,
                .invalidDuration
            )
        }
        XCTAssertThrowsError(
            try SentimentPulsePolicy.Configuration(
                minimumIntensity: 0.8,
                maximumIntensity: 0.2
            )
        )
    }
}

extension ReactionPolicyTests {
    func testHorrorPolicyStartsUpdatesAndStopsStableOwnedAmbientEffect() throws {
        let policy = HorrorNarrativePolicy()
        let owner = try HapticOwnerID(rawValue: "session-hysteresis")
        var state = QualiaReactionState.empty

        let start = policy.plan(
            for: try transition(currentSignals: [.suspense: 0.8], currentPhase: .active),
            context: context(signals: [.suspense], state: state, ownerID: owner)
        )
        state = start.nextState
        let stable = policy.plan(
            for: try transition(
                previousSignals: [.suspense: 0.80],
                currentSignals: [.suspense: 0.76],
                previousPhase: .active,
                currentPhase: .resolving
            ),
            context: context(signals: [.suspense], state: state, ownerID: owner)
        )
        let update = policy.plan(
            for: try transition(
                previousSignals: [.suspense: 0.76],
                currentSignals: [.suspense: 0.62],
                previousPhase: .resolving,
                currentPhase: .resolving
            ),
            context: context(signals: [.suspense], state: state, ownerID: owner)
        )
        state = update.nextState
        let stop = policy.plan(
            for: try transition(
                previousSignals: [.suspense: 0.62],
                currentSignals: [.suspense: 0.39],
                previousPhase: .resolving,
                currentPhase: .resolving
            ),
            context: context(signals: [.suspense], state: state, ownerID: owner)
        )

        guard case let .start(startID, _, .ambient) = try XCTUnwrap(start.hapticCommands.first),
              case let .replace(updateID, _, .ambient) = try XCTUnwrap(update.hapticCommands.first),
              case let .stop(stopID) = try XCTUnwrap(stop.hapticCommands.first) else {
            return XCTFail("Expected start, replace, and stop lifecycle")
        }
        XCTAssertEqual(startID, updateID)
        XCTAssertEqual(updateID, stopID)
        XCTAssertEqual(startID.scope, .owned(owner))
        XCTAssertTrue(stable.hapticCommands.isEmpty)
        XCTAssertEqual(stable.rationale?.ruleIdentifier, "ambient-stable")
        XCTAssertTrue(stop.nextState.activeEffects.isEmpty)
    }

    func testHysteresisDoesNotFlapAcrossStartThreshold() throws {
        let policy = HorrorNarrativePolicy()
        var state = QualiaReactionState.empty
        let start = policy.plan(
            for: try transition(currentSignals: [.suspense: 0.72], currentPhase: .active),
            context: context(signals: [.suspense], state: state)
        )
        state = start.nextState

        for (previous, current) in [(0.72 as Float, 0.69 as Float), (0.69, 0.71), (0.71, 0.69)] {
            let plan = policy.plan(
                for: try transition(
                    previousSignals: [.suspense: previous],
                    currentSignals: [.suspense: current],
                    previousPhase: .resolving,
                    currentPhase: current >= 0.7 ? .active : .resolving
                ),
                context: context(signals: [.suspense], state: state)
            )
            XCTAssertTrue(plan.hapticCommands.isEmpty)
            XCTAssertEqual(plan.nextState, state)
            state = plan.nextState
        }
    }

    func testDisabledHapticsStopsKnownAmbientAndClearsLogicalState() throws {
        let policy = HorrorNarrativePolicy()
        let id = try HapticEffectID(
            rawValue: policy.configuration.effectName,
            scope: .global
        )
        let state = QualiaReactionState(activeEffects: [id])
        let preferences = try QualiaHapticPreferences(enabled: false)
        let plan = policy.plan(
            for: try transition(currentSignals: [.suspense: 0.9], currentPhase: .active),
            context: context(
                signals: [.suspense],
                preferences: preferences,
                state: state
            )
        )

        XCTAssertEqual(plan.hapticCommands, [.stop(id: id)])
        XCTAssertTrue(plan.nextState.activeEffects.isEmpty)
        XCTAssertEqual(plan.rationale?.ruleIdentifier, "haptics-disabled")
    }

    func testContinuousPreferenceStopsAmbientButAllowsIndependentAccent() throws {
        let configuration = try HorrorNarrativePolicy.Configuration(
            minimumAccentConfidence: nil
        )
        let policy = HorrorNarrativePolicy(configuration: configuration)
        let id = try HapticEffectID(
            rawValue: configuration.effectName,
            scope: .global
        )
        let preferences = try QualiaHapticPreferences(
            continuousEffectsEnabled: false,
            intensityScale: 0.75
        )
        let impact = try QualiaScore(value: 0.9)
        let plan = policy.plan(
            for: try transition(
                currentSignals: [.suspense: 0.9],
                currentPhase: .active,
                evidence: [.impact: impact],
                events: [.impact: impact]
            ),
            context: context(
                signals: [.suspense, .impact],
                preferences: preferences,
                state: QualiaReactionState(activeEffects: [id])
            )
        )

        XCTAssertEqual(plan.hapticCommands.count, 2)
        guard case .stop(id) = plan.hapticCommands[0],
              case let .play(_, channel) = plan.hapticCommands[1] else {
            return XCTFail("Expected independent ambient stop and accent play")
        }
        XCTAssertEqual(channel, .accent)
        XCTAssertEqual(plan.rationale?.ruleIdentifier, "ambient-stop+accent-play")
    }

    func testMissingExplicitZeroAndLowAccentEvidenceRemainDistinct() throws {
        let configuration = try HorrorNarrativePolicy.Configuration(
            minimumAccentConfidence: nil,
            compatibilityMode: .transientAccentsOnly
        )
        let policy = HorrorNarrativePolicy(configuration: configuration)
        let suppliedContext = context(signals: [.impact])
        let zero = try QualiaScore(value: 0)
        let low = try QualiaScore(value: 0.5)

        let missingPlan = policy.plan(for: try transition(), context: suppliedContext)
        let zeroPlan = policy.plan(
            for: try transition(evidence: [.impact: zero], events: [.impact: zero]),
            context: suppliedContext
        )
        let lowPlan = policy.plan(
            for: try transition(evidence: [.impact: low], events: [.impact: low]),
            context: suppliedContext
        )

        XCTAssertEqual(missingPlan.rationale?.ruleIdentifier, "no-supported-signal")
        XCTAssertEqual(zeroPlan.rationale?.ruleIdentifier, "below-threshold")
        XCTAssertEqual(lowPlan.rationale?.ruleIdentifier, "below-threshold")
        XCTAssertTrue(missingPlan.hapticCommands.isEmpty)
        XCTAssertTrue(zeroPlan.hapticCommands.isEmpty)
        XCTAssertTrue(lowPlan.hapticCommands.isEmpty)
    }

    func testAccentConfidenceGateUsesFreshEventEvidence() throws {
        let policy = HorrorNarrativePolicy(
            configuration: try HorrorNarrativePolicy.Configuration(
                accentThreshold: 0.8,
                minimumAccentConfidence: 0.7,
                compatibilityMode: .transientAccentsOnly
            )
        )
        let suppliedContext = context(signals: [.impact])
        let missingConfidence = try QualiaScore(value: 0.95)
        let lowConfidence = try QualiaScore(value: 0.95, confidence: 0.69)
        let sufficientConfidence = try QualiaScore(value: 0.95, confidence: 0.7)

        let missing = policy.plan(
            for: try transition(
                evidence: [.impact: missingConfidence],
                events: [.impact: missingConfidence]
            ),
            context: suppliedContext
        )
        let low = policy.plan(
            for: try transition(
                evidence: [.impact: lowConfidence],
                events: [.impact: lowConfidence]
            ),
            context: suppliedContext
        )
        let sufficient = policy.plan(
            for: try transition(
                evidence: [.impact: sufficientConfidence],
                events: [.impact: sufficientConfidence]
            ),
            context: suppliedContext
        )

        XCTAssertTrue(missing.hapticCommands.isEmpty)
        XCTAssertTrue(low.hapticCommands.isEmpty)
        XCTAssertEqual(sufficient.hapticCommands.count, 1)
    }

    func testAccumulatedNarrativeStateDoesNotBorrowAnalyzerConfidence() throws {
        let policy = HorrorNarrativePolicy()
        let plan = policy.plan(
            for: try transition(
                currentSignals: [.suspense: 0.9],
                currentPhase: .active,
                evidence: [:]
            ),
            context: context(signals: [.suspense])
        )

        XCTAssertEqual(plan.hapticCommands.count, 1)
        XCTAssertNil(plan.rationale?.facts.first(where: { $0.key.contains("confidence") }))
    }

    func testThreatAndUrgencyUseVersionedNormalizationWeights() throws {
        let policy = HorrorNarrativePolicy()
        let threatPlan = policy.plan(
            for: try transition(currentSignals: [.threat: 1], currentPhase: .active),
            context: context(signals: [.suspense, .threat])
        )
        let urgencyPlan = policy.plan(
            for: try transition(currentSignals: [.urgency: 1], currentPhase: .building),
            context: context(signals: [.suspense, .urgency])
        )

        XCTAssertEqual(threatPlan.hapticCommands.count, 1)
        XCTAssertTrue(urgencyPlan.hapticCommands.isEmpty)
        XCTAssertEqual(urgencyPlan.rationale?.ruleIdentifier, "below-threshold")
        XCTAssertEqual(
            threatPlan.rationale?.facts.first(where: { $0.key == "threshold-curve-version" })?.value,
            "horror-tension-v1"
        )
    }

    func testUnadvertisedSignalsCannotInfluenceNarrativeTension() throws {
        let plan = HorrorNarrativePolicy().plan(
            for: try transition(
                currentSignals: [.suspense: 0.1, .threat: 1],
                currentPhase: .active
            ),
            context: context(signals: [.suspense])
        )

        XCTAssertTrue(plan.hapticCommands.isEmpty)
        XCTAssertEqual(plan.rationale?.ruleIdentifier, "below-threshold")
        XCTAssertEqual(
            plan.rationale?.facts.first(where: { $0.key == "tension" })?.value,
            "0.1000"
        )
    }

    func testFixedInputsProduceIdenticalPlanAndRationale() throws {
        let policy = HorrorNarrativePolicy()
        let owner = try HapticOwnerID(rawValue: "session-deterministic")
        let transition = try transition(
            currentSignals: [.suspense: 0.9, .threat: 0.7],
            currentPhase: .active,
            evidence: [.suspense: QualiaScore(value: 0.95, confidence: 0.8)]
        )
        let suppliedContext = context(
            signals: [.suspense, .threat],
            instant: .seconds(42),
            ownerID: owner
        )

        XCTAssertEqual(
            policy.plan(for: transition, context: suppliedContext),
            policy.plan(for: transition, context: suppliedContext)
        )
    }

    func testUnavailableHapticsProduceExplicitNoOp() throws {
        let plan = HorrorNarrativePolicy().plan(
            for: try transition(currentSignals: [.suspense: 0.9], currentPhase: .active),
            context: context(signals: [.suspense], haptics: .unavailable)
        )

        XCTAssertTrue(plan.hapticCommands.isEmpty)
        XCTAssertEqual(plan.rationale?.ruleIdentifier, "haptics-unavailable")
    }
}
