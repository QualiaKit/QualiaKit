public extension HorrorNarrativePolicy {
    struct Configuration: Hashable, Sendable {
        public let heartbeat: HeartbeatPolicyConfiguration
        public let accentThreshold: Float
        public let minimumAccentConfidence: Float?
        public let accentPatternDuration: Duration
        public let compatibilityMode: HorrorNarrativeCompatibilityMode
        public let effectName: String

        public init(
            heartbeat: HeartbeatPolicyConfiguration = .default,
            accentThreshold: Float = 0.75,
            minimumAccentConfidence: Float? = 0.7,
            accentPatternDuration: Duration = .milliseconds(120),
            compatibilityMode: HorrorNarrativeCompatibilityMode = .strict,
            effectName: String = "qualia.horror-narrative.heartbeat"
        ) throws {
            guard accentThreshold.isFinite, (0...1).contains(accentThreshold) else {
                throw QualiaReactionConfigurationError.invalidThresholds
            }
            if let minimumAccentConfidence {
                guard minimumAccentConfidence.isFinite,
                      (0...1).contains(minimumAccentConfidence) else {
                    throw QualiaReactionConfigurationError.invalidThresholds
                }
            }
            guard accentPatternDuration > .zero else {
                throw QualiaReactionConfigurationError.invalidDuration
            }
            guard effectName.contains(where: { !$0.isWhitespace }) else {
                throw QualiaReactionConfigurationError.invalidRange
            }
            self.heartbeat = heartbeat
            self.accentThreshold = accentThreshold
            self.minimumAccentConfidence = minimumAccentConfidence
            self.accentPatternDuration = accentPatternDuration
            self.compatibilityMode = compatibilityMode
            self.effectName = effectName
        }

        public static let `default`: Self = {
            do { return try Self() } catch { preconditionFailure("Invalid built-in horror policy: \(error)") }
        }()
    }
}
