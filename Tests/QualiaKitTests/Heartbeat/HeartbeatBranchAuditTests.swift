import XCTest
@testable import QualiaKit

extension HeartbeatEffectTests {
    func testIdleBelowThresholdAndNonMonotonicRunningTimeDoNotDispatch() throws {
        let below = try plan(0.2)
        XCTAssertTrue(below.hapticCommands.isEmpty)
        XCTAssertEqual(below.rationale?.ruleIdentifier, "below-threshold")
        let start = try plan(0.91, at: .seconds(5))
        let backwards = try plan(1, at: .seconds(4), state: start.nextState)
        XCTAssertTrue(backwards.hapticCommands.isEmpty)
        XCTAssertEqual(backwards.rationale?.ruleIdentifier, "non-monotonic-time")
        XCTAssertEqual(backwards.nextState, start.nextState)
    }

    func testDefensiveMissingParametersDoesNotInventAReplacement() throws {
        let start = try plan(0.91)
        var restored = start.nextState
        let id = try XCTUnwrap(restored.activeEffects.first)
        restored.heartbeats[id]?.parameters = nil
        let result = try plan(1, at: .seconds(1), state: restored)
        XCTAssertTrue(result.hapticCommands.isEmpty)
        XCTAssertEqual(result.rationale?.ruleIdentifier, "ambient-stable")
        XCTAssertNil(result.nextState.heartbeats[id]?.parameters)
    }

    func testWeightedThreatAndUrgencyCanDriveWithoutSuspenseValue() throws {
        let custom = HorrorNarrativePolicy(configuration: try .init(heartbeat: .init(startThreshold: 0.55, stopThreshold: 0.2)))
        for signal in [QualiaSignal.threat, .urgency] {
            let value = try QualiaScore(value: 1, confidence: 0.9)
            let transition = try QualiaSceneTransition(previous: .initial(),
                current: .init(dimensions: .init(), signals: [signal: 1], trends: [:], phase: .active, revision: 1, updatedAt: .zero),
                evidence: [signal: value], events: [:])
            let result = custom.plan(for: transition, context: context(at: .zero))
            XCTAssertEqual(result.hapticCommands.count, 1)
            guard case .start = result.hapticCommands[0] else { return XCTFail("Expected fresh weighted driver to start") }
            XCTAssertEqual(result.rationale?.facts.first(where: { $0.key == "driving-signal" })?.value, signal.rawValue)
        }
    }
}
