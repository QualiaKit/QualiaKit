public extension HorrorNarrativePolicy {
    struct Configuration: Hashable, Sendable {
        public let startThreshold: Float
        public let stopThreshold: Float
        public let minimumUpdateDelta: Float
        public let accentThreshold: Float
        public let minimumAccentConfidence: Float?
        public let minimumAmbientIntensity: Float
        public let maximumAmbientIntensity: Float
        public let ambientCycleDuration: Duration
        public let accentPatternDuration: Duration
        public let compatibilityMode: HorrorNarrativeCompatibilityMode
        public let effectName: String

        public init(
            startThreshold: Float = 0.7,
            stopThreshold: Float = 0.4,
            minimumUpdateDelta: Float = 0.08,
            accentThreshold: Float = 0.75,
            minimumAccentConfidence: Float? = 0.7,
            minimumAmbientIntensity: Float = 0.15,
            maximumAmbientIntensity: Float = 0.65,
            ambientCycleDuration: Duration = .milliseconds(600),
            accentPatternDuration: Duration = .milliseconds(120),
            compatibilityMode: HorrorNarrativeCompatibilityMode = .strict,
            effectName: String = "qualia.horror-narrative.ambient"
        ) throws {
            let thresholds = [
                startThreshold,
                stopThreshold,
                minimumUpdateDelta,
                accentThreshold,
            ]
            guard thresholds.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                  startThreshold > stopThreshold,
                  minimumUpdateDelta > 0 else {
                throw QualiaReactionConfigurationError.invalidThresholds
            }
            if let minimumAccentConfidence {
                guard minimumAccentConfidence.isFinite,
                      (0...1).contains(minimumAccentConfidence) else {
                    throw QualiaReactionConfigurationError.invalidThresholds
                }
            }
            guard minimumAmbientIntensity.isFinite,
                  maximumAmbientIntensity.isFinite,
                  (0...1).contains(minimumAmbientIntensity),
                  (0...1).contains(maximumAmbientIntensity),
                  minimumAmbientIntensity <= maximumAmbientIntensity else {
                throw QualiaReactionConfigurationError.invalidRange
            }
            guard ambientCycleDuration > .zero,
                  accentPatternDuration > .zero else {
                throw QualiaReactionConfigurationError.invalidDuration
            }
            guard !effectName.isEmpty,
                  effectName.contains(where: { !$0.isWhitespace }) else {
                throw QualiaReactionConfigurationError.invalidRange
            }

            self.startThreshold = startThreshold
            self.stopThreshold = stopThreshold
            self.minimumUpdateDelta = minimumUpdateDelta
            self.accentThreshold = accentThreshold
            self.minimumAccentConfidence = minimumAccentConfidence
            self.minimumAmbientIntensity = minimumAmbientIntensity
            self.maximumAmbientIntensity = maximumAmbientIntensity
            self.ambientCycleDuration = ambientCycleDuration
            self.accentPatternDuration = accentPatternDuration
            self.compatibilityMode = compatibilityMode
            self.effectName = effectName
        }

        public static let `default`: Self = {
            do {
                return try Self()
            } catch {
                preconditionFailure("Invalid built-in horror policy: \(error)")
            }
        }()
    }
}
