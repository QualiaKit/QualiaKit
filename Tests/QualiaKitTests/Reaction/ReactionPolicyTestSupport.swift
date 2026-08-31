import QualiaKit

extension ReactionPolicyTests {
    func context(
        signals: Set<QualiaSignal> = [],
        dimensions: Set<QualiaDimension> = [],
        haptics: HapticCapabilities = .full,
        preferences: QualiaHapticPreferences = .default,
        instant: Duration = .zero,
        state: QualiaReactionState = .empty,
        ownerID: HapticOwnerID? = nil
    ) -> QualiaReactionContext {
        QualiaReactionContext(
            analyzerCapabilities: capabilities(signals: signals, dimensions: dimensions),
            hapticCapabilities: haptics,
            preferences: preferences,
            instant: instant,
            state: state,
            ownerID: ownerID
        )
    }

    func capabilities(
        signals: Set<QualiaSignal> = [],
        dimensions: Set<QualiaDimension> = []
    ) -> QualiaAnalyzerCapabilities {
        QualiaAnalyzerCapabilities(
            languages: [],
            dimensions: dimensions,
            signals: signals,
            acceptsContext: false,
            execution: .onDevice
        )
    }

    func transition(
        previousSignals: [QualiaSignal: Float] = [:],
        currentSignals: [QualiaSignal: Float] = [:],
        previousPhase: QualiaScenePhase = .idle,
        currentPhase: QualiaScenePhase = .idle,
        currentValence: Float? = nil,
        evidence: [QualiaSignal: QualiaScore] = [:],
        events: [QualiaSignal: QualiaScore] = [:]
    ) throws -> QualiaSceneTransition {
        let previous = try QualiaSceneState(
            dimensions: .init(),
            signals: previousSignals,
            trends: previousSignals.mapValues { _ in .stable },
            phase: previousPhase,
            revision: 0,
            updatedAt: .zero
        )
        let currentDimensions = try currentValence.map {
            QualiaDimensions(valence: try QualiaScore(value: $0))
        } ?? .init()
        let current = try QualiaSceneState(
            dimensions: currentDimensions,
            signals: currentSignals,
            trends: currentSignals.mapValues { signal in
                signal > (previousSignals.first?.value ?? 0) ? .rising : .stable
            },
            phase: currentPhase,
            revision: 1,
            updatedAt: .seconds(1)
        )
        return try QualiaSceneTransition(
            previous: previous,
            current: current,
            evidence: evidence,
            events: events
        )
    }
}
