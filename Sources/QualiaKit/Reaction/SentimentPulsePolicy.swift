/// A deliberately named baseline preview of the standard valence dimension.
/// It is not a narrative or emotion policy.
public struct SentimentPulsePolicy: QualiaReactionPolicy, Sendable {
    public static let identifier = "qualia.sentiment-pulse-preview"
    public static let version = "1.0.0"

    public struct Configuration: Hashable, Sendable {
        public let minimumDistanceFromNeutral: Float
        public let minimumIntensity: Float
        public let maximumIntensity: Float
        public let patternDuration: Duration

        public init(
            minimumDistanceFromNeutral: Float = 0.15,
            minimumIntensity: Float = 0.2,
            maximumIntensity: Float = 0.8,
            patternDuration: Duration = .milliseconds(80)
        ) throws {
            let values = [minimumDistanceFromNeutral, minimumIntensity, maximumIntensity]
            guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                  minimumDistanceFromNeutral < 0.5,
                  minimumIntensity <= maximumIntensity else {
                throw QualiaReactionConfigurationError.invalidRange
            }
            guard patternDuration > .zero else {
                throw QualiaReactionConfigurationError.invalidDuration
            }

            self.minimumDistanceFromNeutral = minimumDistanceFromNeutral
            self.minimumIntensity = minimumIntensity
            self.maximumIntensity = maximumIntensity
            self.patternDuration = patternDuration
        }

        public static let `default`: Self = {
            do {
                return try Self()
            } catch {
                preconditionFailure("Invalid built-in sentiment policy: \(error)")
            }
        }()
    }

    public let configuration: Configuration

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    public func validate(
        analyzerCapabilities: QualiaAnalyzerCapabilities,
        hapticCapabilities: HapticCapabilities
    ) throws {
        guard analyzerCapabilities.dimensions.contains(.valence) else {
            throw QualiaReactionConfigurationError.missingAnalyzerDimension(.valence)
        }
        guard hapticCapabilities.supportsHaptics else {
            throw QualiaReactionConfigurationError.hapticsUnavailable
        }
    }

    public func plan(
        for transition: QualiaSceneTransition,
        context: QualiaReactionContext
    ) -> QualiaReactionPlan {
        let baseFacts = [
            fact("compatibility", "sentiment-preview"),
            fact("intensity-scale", context.preferences.intensityScale),
        ]

        guard context.analyzerCapabilities.dimensions.contains(.valence) else {
            return noOp("missing-required-capability", facts: baseFacts, context: context)
        }
        guard context.preferences.enabled else {
            return noOp("haptics-disabled", facts: baseFacts, context: context)
        }
        guard context.preferences.intensityScale > 0 else {
            return noOp("zero-intensity", facts: baseFacts, context: context)
        }
        guard context.hapticCapabilities.supportsHaptics else {
            return noOp("haptics-unavailable", facts: baseFacts, context: context)
        }
        guard let valence = transition.current.dimensions.valence?.value else {
            return noOp("no-supported-signal", facts: baseFacts, context: context)
        }

        let distance = abs(valence - 0.5)
        guard distance >= configuration.minimumDistanceFromNeutral else {
            return noOp(
                "below-threshold",
                facts: baseFacts + [
                    fact("distance-from-neutral", distance),
                    fact("threshold", configuration.minimumDistanceFromNeutral),
                ],
                context: context
            )
        }

        let normalized = min(1, distance / 0.5)
        let configuredIntensity = configuration.minimumIntensity
            + (configuration.maximumIntensity - configuration.minimumIntensity) * normalized
        let intensity = configuredIntensity * context.preferences.intensityScale
        let sharpness: Float = valence >= 0.5 ? 0.7 : 0.3
        let pattern = makePulse(intensity: intensity, sharpness: sharpness)

        return QualiaReactionPlan(
            hapticCommands: [.play(pattern: pattern, channel: .accent)],
            rationale: .make(
                policyIdentifier: Self.identifier,
                policyVersion: Self.version,
                ruleIdentifier: valence >= 0.5 ? "positive-valence-pulse" : "negative-valence-pulse",
                facts: baseFacts + [
                    fact("distance-from-neutral", distance),
                    fact("haptic-intensity", intensity),
                    fact("valence", valence),
                ]
            ),
            nextState: context.state
        )
    }

    private func makePulse(intensity: Float, sharpness: Float) -> HapticPattern {
        do {
            return try HapticPattern(
                duration: configuration.patternDuration,
                events: [
                    .transient(
                        at: .zero,
                        intensity: HapticValue(intensity),
                        sharpness: HapticValue(sharpness)
                    )
                ]
            )
        } catch {
            preconditionFailure("Validated SentimentPulsePolicy produced an invalid pattern: \(error)")
        }
    }

    private func noOp(
        _ rule: String,
        facts: [QualiaDiagnosticFact],
        context: QualiaReactionContext
    ) -> QualiaReactionPlan {
        QualiaReactionPlan(
            hapticCommands: [],
            rationale: .make(
                policyIdentifier: Self.identifier,
                policyVersion: Self.version,
                ruleIdentifier: rule,
                facts: facts
            ),
            nextState: context.state
        )
    }

    private func fact(_ key: String, _ value: String) -> QualiaDiagnosticFact {
        QualiaDiagnosticFact(key: key, value: value)
    }

    private func fact(_ key: String, _ value: Float) -> QualiaDiagnosticFact {
        fact(key, value.reactionFactValue)
    }
}
