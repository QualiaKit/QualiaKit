import XCTest
@testable import QualiaKit
import QualiaTesting

@MainActor
final class HeartbeatEffectTests: XCTestCase {
    let policy = HorrorNarrativePolicy()
    let owner: HapticOwnerID = {
        do { return try HapticOwnerID(rawValue: "heartbeat-test") } catch { preconditionFailure("Invalid test owner: \(error)") }
    }()

    func testDoubleBeatTimingAndBounds() throws {
        for bpm in [55.0, 64, 108, 120] {
            for ratio in [0.18, 0.25, 0.35] {
                let parameters = try HeartbeatParameters(beatsPerMinute: bpm, intensity: HapticValue(0.6),
                                                         sharpness: HapticValue(0.2), secondBeatRatio: ratio)
                let pattern = try HeartbeatPatternFactory().makePattern(parameters: parameters)
                XCTAssertEqual(pattern.duration, .seconds(60 / bpm))
                XCTAssertEqual(pattern.looping, .loop(period: pattern.duration))
                XCTAssertEqual(pattern.playbackDuration, .seconds(12))
                XCTAssertEqual(pattern.events.count, 2)
                XCTAssertEqual(pattern.events[0].startTime, .zero)
                XCTAssertEqual(pattern.events[1].startTime, .seconds(60 / bpm * ratio))
                XCTAssertLessThan(pattern.events[1].startTime, pattern.duration)
                guard case let .transient(_, intensity, _) = pattern.events[1] else {
                    return XCTFail("Expected dub transient")
                }
                XCTAssertEqual(intensity.rawValue, 0.42, accuracy: 0.0001)
            }
        }
    }

    func testInvalidParametersAndConfigurationFailAtSetup() throws {
        for bpm in [54.9, 120.1, .nan, .infinity] {
            XCTAssertThrowsError(try HeartbeatParameters(beatsPerMinute: bpm, intensity: HapticValue(1), sharpness: HapticValue(0)))
        }
        for ratio in [0, 0.17, 0.36, 1, .nan, .infinity] {
            XCTAssertThrowsError(try HeartbeatParameters(beatsPerMinute: 64, intensity: HapticValue(1),
                                                         sharpness: HapticValue(0), secondBeatRatio: ratio))
        }
        for value: Float in [-1, 1.01, .nan, .infinity] {
            XCTAssertThrowsError(try HeartbeatPolicyConfiguration(startThreshold: value))
            XCTAssertThrowsError(try HeartbeatPolicyConfiguration(minimumSignalConfidence: value))
            XCTAssertThrowsError(try HeartbeatPolicyConfiguration(userIntensityScale: value))
            XCTAssertThrowsError(try HeartbeatPolicyConfiguration(minimumIntensityDelta: value))
        }
        XCTAssertThrowsError(try HeartbeatPolicyConfiguration(startThreshold: 0.5, stopThreshold: 0.5))
        XCTAssertThrowsError(try HeartbeatPolicyConfiguration(minimumBPM: 100, maximumBPM: 80))
        XCTAssertThrowsError(try HeartbeatPolicyConfiguration(minimumBPMDelta: 0))
        XCTAssertThrowsError(try HeartbeatPolicyConfiguration(minimumUpdateInterval: .zero))
        XCTAssertThrowsError(try HeartbeatPolicyConfiguration(maximumDuration: .zero))
        XCTAssertThrowsError(try HeartbeatPolicyConfiguration(cooldown: .seconds(-1)))
        XCTAssertThrowsError(try HeartbeatPolicyConfiguration(resolvingDuration: .seconds(13)))
        let parameters = try HeartbeatParameters(beatsPerMinute: 64, intensity: HapticValue(1), sharpness: HapticValue(0))
        XCTAssertThrowsError(try HeartbeatPatternFactory().makePattern(parameters: parameters, maximumDuration: .zero))
    }

    func testFreshConfidentEvidenceStartsBoundedOwnedHeartbeat() throws {
        let plan = try plan(0.91)
        guard case let .start(id, pattern, .ambient) = try XCTUnwrap(plan.hapticCommands.first) else {
            return XCTFail("Expected heartbeat start")
        }
        XCTAssertEqual(id.scope, .owned(owner))
        let parameters = try XCTUnwrap(plan.nextState.heartbeats[id]?.parameters)
        XCTAssertTrue((64...108).contains(parameters.beatsPerMinute))
        XCTAssertTrue((0...0.65).contains(parameters.intensity.rawValue))
        XCTAssertEqual(pattern.events.count, 2)
        XCTAssertEqual(plan.nextState.heartbeats[id]?.phase, .running)
        XCTAssertEqual(plan.rationale?.facts.first { $0.key == "heartbeat-version" }?.value, "heartbeat-candidate-v1")
    }

    func testMissingLowAndUnrelatedConfidenceCannotStart() throws {
        let cases: [[QualiaSignal: QualiaScore]] = [
            [:], [.suspense: try QualiaScore(value: 0.99)],
            [.suspense: try QualiaScore(value: 0.99, confidence: 0.69)],
            [.threat: try QualiaScore(value: 1, confidence: 1)],
            [.suspense: try QualiaScore(value: 0, confidence: 1)],
        ]
        for evidence in cases {
            XCTAssertTrue(try plan(0.99, evidence: evidence).hapticCommands.isEmpty)
        }
        XCTAssertEqual(try plan(0.99, evidence: [.suspense: QualiaScore(value: 0.9, confidence: 0.7)]).hapticCommands.count, 1)
    }

    func testHysteresisAndInsignificantChangesDoNotRecreatePlayer() throws {
        var state = try plan(0.91).nextState
        // First meaningful drop updates once; threshold chatter then stays stable.
        let update = try plan(0.82, at: .seconds(1), state: state)
        XCTAssertEqual(update.hapticCommands.count, 0) // smoothstep delta is below 4 BPM
        state = update.nextState
        let applied = try plan(0.79, at: .seconds(2), state: state)
        state = applied.nextState
        for (index, tension) in [Float(0.82), 0.79, 0.82, 0.79].enumerated() {
            let next = try plan(tension, at: .seconds(index + 3), state: state)
            XCTAssertTrue(next.hapticCommands.isEmpty)
            XCTAssertEqual(next.nextState.heartbeats.values.first?.phase, .running)
            state = next.nextState
        }
    }

    func testSignificantUpdateIsThrottledAndDoesNotRenewDeadline() throws {
        let start = try plan(0.91)
        XCTAssertTrue(try plan(0.6, at: .milliseconds(499), state: start.nextState).hapticCommands.isEmpty)
        let update = try plan(0.6, at: .milliseconds(500), state: start.nextState)
        guard case let .replace(id, pattern, .ambient) = try XCTUnwrap(update.hapticCommands.first) else {
            return XCTFail("Expected significant update at minimum interval")
        }
        XCTAssertEqual(id, start.nextState.activeEffects.first)
        XCTAssertEqual(pattern.playbackDuration, .milliseconds(11_500))
        XCTAssertEqual(update.nextState.heartbeats[id]?.deadline, .seconds(12))
        XCTAssertTrue(try plan(0.99, at: .milliseconds(499), state: update.nextState).hapticCommands.isEmpty)
    }

    func testResolvingStopsAndCooldownPreventsRestart() throws {
        let start = try plan(0.91)
        let resolving = try plan(0.5, at: .seconds(1), state: start.nextState)
        let id = try XCTUnwrap(start.nextState.activeEffects.first)
        XCTAssertEqual(resolving.nextState.heartbeats[id]?.phase, .resolving)
        XCTAssertEqual(resolving.nextState.activeAmbientEffects[id]?.pattern.playbackDuration, .milliseconds(300))
        XCTAssertTrue(try plan(1, at: .milliseconds(1100), state: resolving.nextState).hapticCommands.isEmpty)
        let stop = try plan(1, at: .milliseconds(1300), state: resolving.nextState)
        XCTAssertEqual(stop.hapticCommands, [.stop(id: id)])
        XCTAssertEqual(stop.nextState.heartbeats[id]?.phase, .cooldown)
        XCTAssertTrue(try plan(1, at: .milliseconds(3299), state: stop.nextState).hapticCommands.isEmpty)
        XCTAssertEqual(try plan(1, at: .milliseconds(3300), state: stop.nextState).hapticCommands.count, 1)
    }

    func testMaximumDurationStopsEvenAtHighTension() throws {
        let start = try plan(0.91)
        let stop = try plan(1, at: .seconds(12), state: start.nextState)
        XCTAssertEqual(stop.hapticCommands, [.stop(id: try XCTUnwrap(start.nextState.activeEffects.first))])
        XCTAssertEqual(stop.rationale?.ruleIdentifier, "heartbeat-maximum-duration")
        XCTAssertTrue(try plan(1, at: .seconds(13), state: stop.nextState).hapticCommands.isEmpty)
    }

    func testRecordingDeadlineExpiresWithoutAnotherObservation() throws {
        var now = Duration.zero
        let renderer = RecordingHapticRenderer(now: { now })
        try renderer.prepare()
        let start = try plan(0.91)
        try renderer.execute(XCTUnwrap(start.hapticCommands.first))
        now = .seconds(1)
        let update = try plan(0.6, at: now, state: start.nextState)
        try renderer.execute(XCTUnwrap(update.hapticCommands.first))
        now = .milliseconds(11_999)
        renderer.expireEffects()
        XCTAssertEqual(renderer.activeEffects.count, 1)
        now = .seconds(12)
        renderer.expireEffects()
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        XCTAssertEqual(renderer.commands.count, 2)
    }

    func testPreferencesScaleHeartbeatAndAccentRemainsIndependent() throws {
        let start = try plan(0.91)
        let preferences = try QualiaHapticPreferences(intensityScale: 0.25)
        let update = try plan(0.91, at: .seconds(1), state: start.nextState, preferences: preferences)
        let initialIntensity = try XCTUnwrap(start.nextState.heartbeats.values.first?.parameters?.intensity.rawValue)
        XCTAssertEqual(try XCTUnwrap(update.nextState.heartbeats.values.first?.parameters?.intensity.rawValue), initialIntensity * 0.25)
        let impact = try QualiaScore(value: 0.95, confidence: 0.9)
        let accent = try plan(0.91, at: .seconds(2), state: update.nextState,
                              preferences: preferences, events: [.impact: impact])
        XCTAssertEqual(accent.hapticCommands.count, 1)
        guard case .play(_, .accent) = accent.hapticCommands[0] else { return XCTFail("Expected independent accent") }
        XCTAssertEqual(accent.nextState, update.nextState)
        for preferences in [QualiaHapticPreferences.disabled, try .init(intensityScale: 0), try .init(continuousEffectsEnabled: false)] {
            let stop = try plan(1, state: start.nextState, preferences: preferences)
            XCTAssertEqual(stop.hapticCommands, [.stop(id: try XCTUnwrap(start.nextState.activeEffects.first))])
            XCTAssertTrue(stop.nextState.heartbeats.isEmpty)
        }
    }

    func testCandidateMappingIsDeterministicAndPolicyScaleApplies() throws {
        let configured = HorrorNarrativePolicy(configuration: try .init(heartbeat: .init(userIntensityScale: 0.5)))
        let input = try transition(1)
        let context = context(at: .zero)
        let first = configured.plan(for: input, context: context)
        XCTAssertEqual(first, configured.plan(for: input, context: context))
        let parameters = try XCTUnwrap(first.nextState.heartbeats.values.first?.parameters)
        XCTAssertEqual(parameters.beatsPerMinute, 108)
        XCTAssertEqual(parameters.intensity.rawValue, 0.325, accuracy: 0.0001)
    }

    func testRestoredAppliedStateWithoutLifecycleCannotRenewPlayback() throws {
        let start = try plan(0.91)
        let restored = try QualiaReactionState(activeAmbientEffects: start.nextState.activeAmbientEffects)
        let stop = try plan(1, state: restored)
        XCTAssertEqual(stop.hapticCommands, [.stop(id: try XCTUnwrap(restored.activeEffects.first))])
        XCTAssertEqual(stop.rationale?.ruleIdentifier, "missing-heartbeat-lifecycle")
        XCTAssertTrue(try plan(1, state: stop.nextState).hapticCommands.isEmpty)
    }

    func testPolicyScaleZeroStopsWhileStillPermittingAccent() throws {
        let start = try plan(0.91)
        let disabled = HorrorNarrativePolicy(configuration: try .init(heartbeat: .init(userIntensityScale: 0)))
        let impact = try QualiaScore(value: 0.95, confidence: 0.9)
        let stop = disabled.plan(for: try transition(1, events: [.impact: impact]),
                                 context: context(at: .seconds(1), state: start.nextState))
        XCTAssertEqual(stop.hapticCommands.count, 2)
        guard case .stop = stop.hapticCommands[0], case .play(_, .accent) = stop.hapticCommands[1] else {
            return XCTFail("Expected heartbeat stop and independent accent")
        }
        XCTAssertTrue(stop.nextState.heartbeats.isEmpty)
    }

    func testDuplicateStartDoesNotRenewRecordingDeadline() throws {
        var now = Duration.zero
        let renderer = RecordingHapticRenderer(now: { now })
        try renderer.prepare()
        let command = try XCTUnwrap(plan(0.91).hapticCommands.first)
        try renderer.execute(command)
        now = .seconds(10)
        try renderer.execute(command)
        now = .seconds(12)
        renderer.expireEffects()
        XCTAssertTrue(renderer.activeEffects.isEmpty)
    }

    func testUnavailableCapabilityPreventsPlanning() throws {
        let result = policy.plan(for: try transition(1), context: context(at: .zero, haptics: .unavailable))
        XCTAssertTrue(result.hapticCommands.isEmpty)
        XCTAssertEqual(result.rationale?.ruleIdentifier, "haptics-unavailable")
    }

    func plan(
        _ tension: Float,
        at instant: Duration = .zero,
        state: QualiaReactionState = .empty,
        preferences: QualiaHapticPreferences = .default,
        evidence: [QualiaSignal: QualiaScore]? = nil,
        events: [QualiaSignal: QualiaScore] = [:]
    ) throws -> QualiaReactionPlan {
        policy.plan(for: try transition(tension, evidence: evidence, events: events),
                    context: context(at: instant, state: state, preferences: preferences))
    }

    func context(
        at instant: Duration,
        state: QualiaReactionState = .empty,
        preferences: QualiaHapticPreferences = .default,
        haptics: HapticCapabilities = .full
    ) -> QualiaReactionContext {
        .init(analyzerCapabilities: capabilities, hapticCapabilities: haptics, preferences: preferences,
              instant: instant, effectScope: .owned(owner), state: state)
    }

    var capabilities: QualiaAnalyzerCapabilities {
        .init(languages: [], dimensions: [], signals: [.suspense, .threat, .urgency, .impact], acceptsContext: false, execution: .onDevice)
    }

    func transition(
        _ tension: Float,
        evidence: [QualiaSignal: QualiaScore]? = nil,
        events: [QualiaSignal: QualiaScore] = [:]
    ) throws -> QualiaSceneTransition {
        try .init(
            previous: .initial(),
            current: .init(dimensions: .init(), signals: [.suspense: tension],
                           trends: [:], phase: .active, revision: 1, updatedAt: .zero),
            evidence: evidence ?? [.suspense: QualiaScore(value: tension, confidence: 0.9)].merging(events) { _, event in event },
            events: events
        )
    }
}
