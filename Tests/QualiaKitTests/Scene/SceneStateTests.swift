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

        XCTAssertEqual(impact.events[.impact]?.value, 0.95)
        XCTAssertNil(impact.current.signals[.impact])
        XCTAssertNil(impact.current.trends[.impact])
        XCTAssertTrue(later.events.isEmpty)
        XCTAssertNil(later.current.signals[.impact])
    }

    func testAnalysisFailureLeavesStoredStateAtRevisionSeven() throws {
        let reducer = QualiaSceneReducer()
        var storedState = QualiaSceneState.initial()
        for revision in 1...7 {
            storedState = reducer.reduce(
                state: storedState,
                observation: observation(signals: [.suspense: 0.5]),
                at: .seconds(revision)
            ).current
        }

        do {
            let acceptedObservation = try failingAnalysis()
            storedState = reducer.reduce(
                state: storedState,
                observation: acceptedObservation,
                at: .seconds(8)
            ).current
        } catch TestFailure.analysisFailed {
            // A failed analysis produces no observation and therefore no
            // reducer invocation or scene-state commit.
        }

        XCTAssertEqual(storedState.revision, 7)
        XCTAssertEqual(storedState.updatedAt, .seconds(7))
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
        ).current
        let decayed = reducer.reduce(
            state: observed,
            observation: observation(),
            at: .seconds(2)
        ).current

        XCTAssertEqual(decayed.dimensions.valence?.value ?? -1, 0.7, accuracy: 0.0001)
        XCTAssertEqual(decayed.dimensions.valence?.confidence, 0.8)
        XCTAssertEqual(decayed.phase, .idle)
    }

    func testUnconfiguredCustomSignalUsesNeutralIgnoreDefault() throws {
        let custom = try QualiaSignal(rawValue: "com.example.unconfigured")
        let restoredState = QualiaSceneState(
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
        assertConfigurationError(.invalidEventThreshold) {
            try QualiaEventSignalConfiguration(threshold: .infinity)
        }
        assertConfigurationError(.invalidPhaseThresholds) {
            try QualiaScenePhaseConfiguration(
                signals: [],
                idleThreshold: 0.5,
                buildingThreshold: 0.5,
                activeThreshold: 0.9
            )
        }

        let event = try QualiaEventSignalConfiguration(threshold: 0.5)
        let invalidPhase = try QualiaScenePhaseConfiguration(
            signals: [.impact],
            idleThreshold: 0.1,
            buildingThreshold: 0.5,
            activeThreshold: 0.9
        )
        assertConfigurationError(.invalidPhaseSignal(.impact)) {
            try QualiaSceneReducerConfiguration(
                signals: [.impact: .event(event)],
                phase: invalidPhase
            )
        }
    }

    func testScenePublicValuesAreSendable() {
        assertSendable(QualiaTrend.self)
        assertSendable(QualiaScenePhase.self)
        assertSendable(QualiaSceneState.self)
        assertSendable(QualiaSceneTransition.self)
        assertSendable(QualiaMissingDataPolicy.self)
        assertSendable(QualiaContinuousSignalConfiguration.self)
        assertSendable(QualiaEventSignalConfiguration.self)
        assertSendable(QualiaSignalReduction.self)
        assertSendable(QualiaScenePhaseConfiguration.self)
        assertSendable(QualiaSceneReducerConfiguration.self)
        assertSendable(QualiaSceneReducer.self)
        assertSendable(QualiaSceneConfigurationError.self)
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
        signals: [QualiaSignal: Float] = [:]
    ) -> QualiaObservation {
        QualiaObservation(
            inputID: try! QualiaInputID(rawValue: "scene-fixture"),
            dimensions: QualiaDimensions(
                valence: valence.map { try! QualiaScore(value: $0, confidence: confidence) }
            ),
            signals: signals.mapValues { try! QualiaScore(value: $0) },
            language: try! QualiaLanguage(rawValue: "en"),
            analyzer: try! QualiaAnalyzerIdentity(
                identifier: "com.example.scene-fixture",
                version: "1"
            )
        )
    }

    private func failingAnalysis() throws -> QualiaObservation {
        throw TestFailure.analysisFailed
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

    private func assertSendable<T: Sendable>(_: T.Type) {}
}

private enum TestFailure: Error {
    case analysisFailed
}
