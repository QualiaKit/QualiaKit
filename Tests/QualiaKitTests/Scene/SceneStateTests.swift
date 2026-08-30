import XCTest
import QualiaKit

final class SceneStateTests: XCTestCase {
    func testInitialStateAndExplicitResetAreDeterministic() throws {
        let reducer = QualiaSceneReducer()
        let initial = QualiaSceneState.initial()
        let transition = reducer.reduce(
            state: initial,
            observation: observation(signals: [.suspense: 0.8]),
            at: .seconds(1)
        )

        let reset = reducer.reset(at: .seconds(10))

        XCTAssertEqual(initial, .initial())
        XCTAssertEqual(reset, .initial(at: .seconds(10)))
        XCTAssertEqual(reset.revision, 0)
        XCTAssertEqual(reset.phase, .idle)
        XCTAssertTrue(reset.signals.isEmpty)
        XCTAssertTrue(reset.trends.isEmpty)
        XCTAssertNotEqual(transition.current, reset)
    }

    func testRisingTensionProgressesDeterministicallyTowardActive() throws {
        let reducer = QualiaSceneReducer(configuration: .narrative)
        var state = QualiaSceneState.initial()

        let first = reducer.reduce(
            state: state,
            observation: observation(signals: [.suspense: 0.48]),
            at: .zero
        )
        state = first.current
        let second = reducer.reduce(
            state: state,
            observation: observation(signals: [.suspense: 0.71]),
            at: .seconds(1)
        )
        state = second.current
        let third = reducer.reduce(
            state: state,
            observation: observation(signals: [.suspense: 0.90]),
            at: .seconds(2)
        )

        XCTAssertEqual(first.current.phase, .building)
        XCTAssertEqual(second.current.phase, .building)
        XCTAssertEqual(third.current.phase, .active)
        XCTAssertEqual(third.current.trends[.suspense], .rising)
        XCTAssertEqual(third.current.revision, 3)
        XCTAssertEqual(third.current.updatedAt, .seconds(2))
        XCTAssertEqual(third.evidence[.suspense]?.value, 0.90)
        XCTAssertTrue(first.events.isEmpty)
        XCTAssertTrue(second.events.isEmpty)
        XCTAssertTrue(third.events.isEmpty)
    }

    func testEventEvidenceIsTransitionLocalAndDoesNotStick() throws {
        let reducer = QualiaSceneReducer()
        let impact = reducer.reduce(
            state: .initial(),
            observation: observation(signals: [.impact: 0.95]),
            at: .zero
        )
        let later = reducer.reduce(
            state: impact.current,
            observation: observation(),
            at: .seconds(1)
        )

        XCTAssertEqual(impact.evidence[.impact]?.value, 0.95)
        XCTAssertEqual(impact.events[.impact]?.value, 0.95)
        XCTAssertNil(impact.current.signals[.impact])
        XCTAssertNil(impact.current.trends[.impact])
        XCTAssertTrue(later.events.isEmpty)
        XCTAssertTrue(later.evidence.isEmpty)
        XCTAssertNil(later.current.signals[.impact])
    }

    func testEventMissingZeroAndLowEvidenceRemainDistinct() throws {
        let reducer = QualiaSceneReducer()
        let missing = reducer.reduce(
            state: .initial(),
            observation: observation(),
            at: .zero
        )
        let zero = reducer.reduce(
            state: .initial(),
            observation: observation(signals: [.impact: 0]),
            at: .zero
        )
        let low = reducer.reduce(
            state: .initial(),
            observation: observation(signals: [.impact: 0.5]),
            at: .zero
        )

        XCTAssertNil(missing.evidence[.impact])
        XCTAssertNil(missing.events[.impact])
        XCTAssertEqual(zero.evidence[.impact]?.value, 0)
        XCTAssertEqual(zero.events[.impact]?.value, 0)
        XCTAssertEqual(low.evidence[.impact]?.value, 0.5)
        XCTAssertEqual(low.events[.impact]?.value, 0.5)
        XCTAssertNotEqual(missing, zero)
        XCTAssertNotEqual(zero, low)
    }

    func testMissingEvidenceRemainsDistinctFromExplicitZero() throws {
        let continuous = try QualiaContinuousSignalConfiguration(
            smoothingHalfLife: .seconds(1),
            missingDataPolicy: .preserve,
            trendEpsilon: 0.01
        )
        let reducer = try reducer(continuous: continuous)
        let initialEvidence = reducer.reduce(
            state: .initial(),
            observation: observation(signals: [.suspense: 1]),
            at: .zero
        ).current

        let missing = reducer.reduce(
            state: initialEvidence,
            observation: observation(),
            at: .seconds(1)
        ).current
        let explicitZero = reducer.reduce(
            state: initialEvidence,
            observation: observation(signals: [.suspense: 0]),
            at: .seconds(1)
        ).current

        XCTAssertEqual(missing.signals[.suspense], 1)
        XCTAssertEqual(missing.trends[.suspense], .stable)
        XCTAssertEqual(explicitZero.signals[.suspense] ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(explicitZero.trends[.suspense], .falling)
    }

    func testMissingContinuousEvidenceUsesConfiguredHalfLife() throws {
        let continuous = try QualiaContinuousSignalConfiguration(
            smoothingHalfLife: .seconds(1),
            missingDataPolicy: .decay(halfLife: .seconds(2), toward: 0),
            trendEpsilon: 0.01
        )
        let reducer = try reducer(continuous: continuous)
        let full = reducer.reduce(
            state: .initial(),
            observation: observation(signals: [.suspense: 1]),
            at: .zero
        ).current
        let decayed = reducer.reduce(
            state: full,
            observation: observation(),
            at: .seconds(2)
        ).current

        XCTAssertEqual(decayed.signals[.suspense] ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(decayed.trends[.suspense], .falling)
        XCTAssertEqual(decayed.phase, .resolving)
    }

    func testContinuousConfidenceRemainsFreshTransitionEvidence() throws {
        let reducer = QualiaSceneReducer()
        let observed = reducer.reduce(
            state: .initial(),
            observation: observation(
                signals: [.suspense: 0.9],
                signalConfidences: [.suspense: 0.82]
            ),
            at: .zero
        )
        let missing = reducer.reduce(
            state: observed.current,
            observation: observation(),
            at: .seconds(1)
        )

        XCTAssertEqual(observed.evidence[.suspense]?.value, 0.9)
        XCTAssertEqual(observed.evidence[.suspense]?.confidence, 0.82)
        XCTAssertEqual(observed.current.signals[.suspense], 0.9)
        XCTAssertNil(missing.evidence[.suspense])
        XCTAssertLessThan(missing.current.signals[.suspense] ?? 1, 0.9)
    }

    func testActiveSceneResolvesAndEventuallyReturnsToIdle() throws {
        let reducer = QualiaSceneReducer()
        let active = reducer.reduce(
            state: .initial(),
            observation: observation(signals: [.suspense: 0.9]),
            at: .zero
        ).current
        let resolving = reducer.reduce(
            state: active,
            observation: observation(),
            at: .seconds(4)
        ).current
        let idle = reducer.reduce(
            state: resolving,
            observation: observation(),
            at: .seconds(20)
        ).current

        XCTAssertEqual(active.phase, .active)
        XCTAssertEqual(resolving.phase, .resolving)
        XCTAssertEqual(idle.phase, .idle)
    }

    func testValenceCanDecayTowardItsNeutralAnchor() throws {
        let valence = try QualiaContinuousSignalConfiguration(
            smoothingHalfLife: .seconds(1),
            missingDataPolicy: .decay(halfLife: .seconds(2), toward: 0.5),
            trendEpsilon: 0.01
        )
        let phase = try QualiaScenePhaseConfiguration(
            signals: [],
            idleThreshold: 0.1,
            buildingThreshold: 0.5,
            activeThreshold: 0.9
        )
        let configuration = try QualiaSceneReducerConfiguration(
            signals: [:],
            valence: valence,
            phase: phase
        )
        let reducer = QualiaSceneReducer(configuration: configuration)
        let observed = reducer.reduce(
            state: .initial(),
            observation: observation(valence: 0.9, confidence: 0.8),
            at: .zero
        )
        let decayed = reducer.reduce(
            state: observed.current,
            observation: observation(),
            at: .seconds(2)
        ).current

        XCTAssertEqual(observed.current.dimensions.valence?.value, 0.9)
        XCTAssertNil(observed.current.dimensions.valence?.confidence)
        XCTAssertEqual(decayed.dimensions.valence?.value ?? -1, 0.7, accuracy: 0.0001)
        XCTAssertNil(decayed.dimensions.valence?.confidence)
        XCTAssertEqual(decayed.phase, .idle)
    }

    func testUnconfiguredCustomSignalUsesNeutralIgnoreDefault() throws {
        let custom = try QualiaSignal(rawValue: "com.example.unconfigured")
        let restoredState = try QualiaSceneState(
            dimensions: .init(),
            signals: [custom: 0.8],
            trends: [custom: .rising],
            phase: .idle,
            revision: 4,
            updatedAt: .zero
        )
        let transition = QualiaSceneReducer().reduce(
            state: restoredState,
            observation: observation(signals: [custom: 1]),
            at: .seconds(1)
        )

        XCTAssertNil(transition.current.signals[custom])
        XCTAssertNil(transition.current.trends[custom])
        XCTAssertNil(transition.events[custom])
        XCTAssertEqual(transition.current.phase, .idle)
        XCTAssertEqual(transition.current.revision, 5)
    }

    func testSameInputsProduceTheSameTransition() throws {
        let reducer = QualiaSceneReducer()
        let state = reducer.reduce(
            state: .initial(),
            observation: observation(signals: [.suspense: 0.4]),
            at: .seconds(1)
        ).current
        let input = observation(signals: [.suspense: 0.8, .impact: 0.9])

        let first = reducer.reduce(state: state, observation: input, at: .seconds(3))
        let second = reducer.reduce(state: state, observation: input, at: .seconds(3))

        XCTAssertEqual(first, second)
    }

    func testInvalidConfigurationIsRejectedBeforeReduction() throws {
        assertConfigurationError(.invalidSmoothingHalfLife) {
            try QualiaContinuousSignalConfiguration(
                smoothingHalfLife: .zero,
                missingDataPolicy: .preserve,
                trendEpsilon: 0.1
            )
        }
        assertConfigurationError(.invalidDecayHalfLife) {
            try QualiaContinuousSignalConfiguration(
                smoothingHalfLife: .seconds(1),
                missingDataPolicy: .decay(halfLife: .seconds(-1), toward: 0),
                trendEpsilon: 0.1
            )
        }
        assertConfigurationError(.invalidDecayTarget) {
            try QualiaContinuousSignalConfiguration(
                smoothingHalfLife: .seconds(1),
                missingDataPolicy: .decay(halfLife: .seconds(1), toward: .nan),
                trendEpsilon: 0.1
            )
        }
        assertConfigurationError(.invalidTrendEpsilon) {
            try QualiaContinuousSignalConfiguration(
                smoothingHalfLife: .seconds(1),
                missingDataPolicy: .preserve,
                trendEpsilon: 1.1
            )
        }
        assertConfigurationError(.invalidPhaseThresholds) {
            try QualiaScenePhaseConfiguration(
                signals: [],
                idleThreshold: 0.5,
                buildingThreshold: 0.5,
                activeThreshold: 0.9
            )
        }

        let invalidPhase = try QualiaScenePhaseConfiguration(
            signals: [.impact],
            idleThreshold: 0.1,
            buildingThreshold: 0.5,
            activeThreshold: 0.9
        )
        assertConfigurationError(.invalidPhaseSignal(.impact)) {
            try QualiaSceneReducerConfiguration(
                signals: [.impact: .event],
                phase: invalidPhase
            )
        }
    }

    func testPublicStateConstructionRejectsInvalidValues() throws {
        assertValidationError(.stateContainsAnalyzerConfidence) {
            try QualiaSceneState(
                dimensions: .init(
                    valence: try QualiaScore(value: 0.5, confidence: 0.8)
                ),
                signals: [:],
                trends: [:],
                phase: .idle,
                revision: 0,
                updatedAt: .zero
            )
        }
        assertValidationError(.invalidStateSignal(.suspense)) {
            try QualiaSceneState(
                dimensions: .init(),
                signals: [.suspense: .nan],
                trends: [:],
                phase: .idle,
                revision: 0,
                updatedAt: .zero
            )
        }
        assertValidationError(.trendWithoutSignal(.suspense)) {
            try QualiaSceneState(
                dimensions: .init(),
                signals: [:],
                trends: [.suspense: .rising],
                phase: .idle,
                revision: 0,
                updatedAt: .zero
            )
        }
    }

    func testPublicTransitionConstructionValidatesRevisionTimeAndEvents() throws {
        let previous = QualiaSceneState.initial(at: .seconds(1))
        let sameRevision = try QualiaSceneState(
            dimensions: .init(),
            signals: [:],
            trends: [:],
            phase: .idle,
            revision: 0,
            updatedAt: .seconds(2)
        )
        assertValidationError(.invalidTransitionRevision) {
            try QualiaSceneTransition(
                previous: previous,
                current: sameRevision,
                evidence: [:],
                events: [:]
            )
        }

        let older = try QualiaSceneState(
            dimensions: .init(),
            signals: [:],
            trends: [:],
            phase: .idle,
            revision: 1,
            updatedAt: .zero
        )
        assertValidationError(.nonMonotonicTransitionTime) {
            try QualiaSceneTransition(
                previous: previous,
                current: older,
                evidence: [:],
                events: [:]
            )
        }

        let current = try QualiaSceneState(
            dimensions: .init(),
            signals: [:],
            trends: [:],
            phase: .idle,
            revision: 1,
            updatedAt: .seconds(2)
        )
        let impact = try QualiaScore(value: 0.5)
        assertValidationError(.invalidEventEvidence(.impact)) {
            try QualiaSceneTransition(
                previous: previous,
                current: current,
                evidence: [:],
                events: [.impact: impact]
            )
        }

        XCTAssertNoThrow(
            try QualiaSceneTransition(
                previous: previous,
                current: current,
                evidence: [.impact: impact],
                events: [.impact: impact]
            )
        )
    }

    func testScenePublicValuesAreSendable() {
        assertSendable(QualiaTrend.self)
        assertSendable(QualiaScenePhase.self)
        assertSendable(QualiaSceneState.self)
        assertSendable(QualiaSceneTransition.self)
        assertSendable(QualiaMissingDataPolicy.self)
        assertSendable(QualiaContinuousSignalConfiguration.self)
        assertSendable(QualiaSignalReduction.self)
        assertSendable(QualiaScenePhaseConfiguration.self)
        assertSendable(QualiaSceneReducerConfiguration.self)
        assertSendable(QualiaSceneReducer.self)
        assertSendable(QualiaSceneConfigurationError.self)
        assertSendable(QualiaSceneValidationError.self)
    }

    private func reducer(
        continuous: QualiaContinuousSignalConfiguration
    ) throws -> QualiaSceneReducer {
        let phase = try QualiaScenePhaseConfiguration(
            signals: [.suspense],
            idleThreshold: 0.1,
            buildingThreshold: 0.35,
            activeThreshold: 0.7
        )
        let configuration = try QualiaSceneReducerConfiguration(
            signals: [.suspense: .continuous(continuous)],
            phase: phase
        )
        return QualiaSceneReducer(configuration: configuration)
    }

    private func observation(
        valence: Float? = nil,
        confidence: Float? = nil,
        signals: [QualiaSignal: Float] = [:],
        signalConfidences: [QualiaSignal: Float] = [:]
    ) -> QualiaObservation {
        QualiaObservation(
            inputID: try! QualiaInputID(rawValue: "scene-fixture"),
            dimensions: QualiaDimensions(
                valence: valence.map { try! QualiaScore(value: $0, confidence: confidence) }
            ),
            signals: Dictionary(uniqueKeysWithValues: signals.map { signal, value in
                (
                    signal,
                    try! QualiaScore(
                        value: value,
                        confidence: signalConfidences[signal]
                    )
                )
            }),
            language: try! QualiaLanguage(rawValue: "en"),
            analyzer: try! QualiaAnalyzerIdentity(
                identifier: "com.example.scene-fixture",
                version: "1"
            )
        )
    }

    private func assertConfigurationError<T>(
        _ expected: QualiaSceneConfigurationError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? QualiaSceneConfigurationError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func assertValidationError<T>(
        _ expected: QualiaSceneValidationError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? QualiaSceneValidationError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func assertSendable<T: Sendable>(_: T.Type) {}
}
