import Foundation

/// The default deterministic implementation of temporal scene reduction.
public struct QualiaSceneReducer: QualiaSceneReducing, Sendable {
    public let configuration: QualiaSceneReducerConfiguration

    public init(configuration: QualiaSceneReducerConfiguration = .narrative) {
        self.configuration = configuration
    }

    public func reduce(
        state: QualiaSceneState,
        observation: QualiaObservation,
        at instant: Duration
    ) -> QualiaSceneTransition {
        precondition(
            instant >= state.updatedAt,
            "QualiaSceneReducer requires a monotonic instant"
        )
        precondition(
            state.revision < .max,
            "QualiaSceneState revision overflow"
        )

        let elapsed = instant - state.updatedAt
        let dimensions = reduceDimensions(
            previous: state.dimensions,
            observed: observation.dimensions,
            elapsed: elapsed
        )

        // Rebuild the bounded state vocabulary from configured continuous
        // signals. This also prevents restored event or unknown values from
        // becoming accidentally sticky after a configuration change.
        var signals: [QualiaSignal: Float] = [:]
        var trends: [QualiaSignal: QualiaTrend] = [:]
        var evidence: [QualiaSignal: QualiaScore] = [:]
        var events: [QualiaSignal: QualiaScore] = [:]

        for (signal, reduction) in configuration.signals {
            let observedScore = observation.signals[signal]
            if let observedScore {
                evidence[signal] = observedScore
            }

            switch reduction {
            case let .continuous(policy):
                let previous = state.signals[signal]
                let current = reduceContinuousValue(
                    previous: previous,
                    observed: observedScore?.value,
                    elapsed: elapsed,
                    configuration: policy
                )

                if let current {
                    signals[signal] = current
                    trends[signal] = trend(
                        previous: previous,
                        current: current,
                        epsilon: policy.trendEpsilon
                    )
                } else {
                    signals.removeValue(forKey: signal)
                    trends.removeValue(forKey: signal)
                }

            case .event:
                // Event-like evidence has independent, immediate decay: it is
                // emitted only for this transition and never copied into state.
                signals.removeValue(forKey: signal)
                trends.removeValue(forKey: signal)
                if let score = observedScore {
                    events[signal] = score
                }
            }
        }

        let phase = reducePhase(
            previous: state.phase,
            signals: signals,
            trends: trends
        )
        let current = QualiaSceneState(
            validatedDimensions: dimensions,
            signals: signals,
            trends: trends,
            phase: phase,
            revision: state.revision + 1,
            updatedAt: instant
        )

        return QualiaSceneTransition(
            validatedPrevious: state,
            current: current,
            evidence: evidence,
            events: events
        )
    }

    private func reduceDimensions(
        previous: QualiaDimensions,
        observed: QualiaDimensions,
        elapsed: Duration
    ) -> QualiaDimensions {
        guard let policy = configuration.valence else {
            return previous
        }

        let value = reduceContinuousValue(
            previous: previous.valence?.value,
            observed: observed.valence?.value,
            elapsed: elapsed,
            configuration: policy
        )
        guard let value else {
            return .init()
        }

        return QualiaDimensions(
            // Analyzer confidence describes fresh evidence, not a smoothed or
            // decayed state value. Never attach it to accumulated state.
            valence: validatedScore(value: value)
        )
    }

    private func reduceContinuousValue(
        previous: Float?,
        observed: Float?,
        elapsed: Duration,
        configuration: QualiaContinuousSignalConfiguration
    ) -> Float? {
        if let observed {
            guard let previous else {
                return observed
            }
            return interpolate(
                from: previous,
                toward: observed,
                elapsed: elapsed,
                halfLife: configuration.smoothingHalfLife
            )
        }

        guard let previous else {
            return nil
        }
        switch configuration.missingDataPolicy {
        case .preserve:
            return previous
        case let .decay(halfLife, target):
            return interpolate(
                from: previous,
                toward: target,
                elapsed: elapsed,
                halfLife: halfLife
            )
        }
    }

    private func interpolate(
        from previous: Float,
        toward target: Float,
        elapsed: Duration,
        halfLife: Duration
    ) -> Float {
        let ratio = elapsed.secondsValue / halfLife.secondsValue
        let retained = Foundation.pow(0.5, ratio)
        let value = Double(target) + (Double(previous) - Double(target)) * retained

        precondition(
            value.isFinite && (0...1).contains(value),
            "QualiaSceneReducer produced an invalid continuous value"
        )
        return Float(value)
    }

    private func trend(
        previous: Float?,
        current: Float,
        epsilon: Float
    ) -> QualiaTrend {
        guard let previous else {
            return current > epsilon ? .rising : .stable
        }
        let difference = current - previous
        if difference > epsilon {
            return .rising
        }
        if difference < -epsilon {
            return .falling
        }
        return .stable
    }

    private func reducePhase(
        previous: QualiaScenePhase,
        signals: [QualiaSignal: Float],
        trends: [QualiaSignal: QualiaTrend]
    ) -> QualiaScenePhase {
        let phaseConfiguration = configuration.phase
        let intensity = phaseConfiguration.signals.compactMap { signals[$0] }.max() ?? 0

        if intensity >= phaseConfiguration.activeThreshold {
            return .active
        }
        if intensity >= phaseConfiguration.buildingThreshold {
            switch previous {
            case .active:
                return .resolving
            case .resolving:
                let rising = phaseConfiguration.signals.contains { signal in
                    signals[signal] == intensity && trends[signal] == .rising
                }
                return rising ? .building : .resolving
            case .idle, .building:
                return .building
            }
        }
        if intensity > phaseConfiguration.idleThreshold {
            return previous == .idle ? .idle : .resolving
        }
        return .idle
    }

    private func validatedScore(value: Float) -> QualiaScore {
        do {
            return try QualiaScore(value: value)
        } catch {
            preconditionFailure("QualiaSceneReducer produced an invalid dimension score")
        }
    }
}

extension Duration {
    fileprivate var secondsValue: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}
