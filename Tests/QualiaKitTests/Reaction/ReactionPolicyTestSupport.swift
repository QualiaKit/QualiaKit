import QualiaKit

extension ReactionPolicyTests {
    // Preserve the spec-0007 low-threshold scenarios explicitly. Production
    // candidate defaults are exercised in HeartbeatEffectTests.
    func narrativePolicy() -> HorrorNarrativePolicy {
        do {
            return HorrorNarrativePolicy(configuration: try .init(heartbeat: .init(
                startThreshold: 0.7, stopThreshold: 0.4, minimumBPMDelta: 2
            )))
        } catch { preconditionFailure("Invalid test policy: \(error)") }
    }

    func context(
        signals: Set<QualiaSignal> = [],
        dimensions: Set<QualiaDimension> = [],
        haptics: HapticCapabilities = .full,
        preferences: QualiaHapticPreferences = .default,
        instant: Duration? = nil,
        state: QualiaReactionState = .empty,
        effectScope: HapticEffectScope = .global
    ) -> QualiaReactionContext {
        QualiaReactionContext(
            analyzerCapabilities: capabilities(signals: signals, dimensions: dimensions),
            hapticCapabilities: haptics,
            preferences: preferences,
            instant: instant ?? (state.activeEffects.isEmpty ? .zero : .seconds(1)),
            effectScope: effectScope,
            state: state
        )
    }

    func activeState(
        policy: HorrorNarrativePolicy? = nil,
        tension: Float,
        intensityScale: Float = 1,
        effectScope: HapticEffectScope = .global
    ) throws -> QualiaReactionState {
        let preferences = try QualiaHapticPreferences(intensityScale: intensityScale)
        return (policy ?? narrativePolicy()).plan(
            for: try transition(
                currentSignals: [.suspense: tension],
                currentPhase: .active
            ),
            context: context(
                signals: [.suspense],
                preferences: preferences,
                effectScope: effectScope
            )
        ).nextState
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
        evidence: [QualiaSignal: QualiaScore]? = nil,
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
            evidence: try evidence ?? currentSignals.mapValues { try QualiaScore(value: $0, confidence: 0.9) }.merging(events) { _, event in event },
            events: events
        )
    }
}
