// snippet:start custom-policy
import QualiaKit

/// A host-specific one-shot rule; the session applies safety and ownership.
public struct AuthoredAccentPolicy: QualiaReactionPolicy {
    private let pattern: HapticPattern
    public init() throws {
        pattern = try HapticPattern(duration: .milliseconds(100), events: [
            .transient(at: .zero, intensity: HapticValue(0.4), sharpness: HapticValue(0.3))
        ])
    }
    public func validate(analyzerCapabilities: QualiaAnalyzerCapabilities,
                         hapticCapabilities: HapticCapabilities) throws {
        guard analyzerCapabilities.signals.contains(.impact) else {
            throw QualiaReactionConfigurationError.missingAnalyzerSignal(.impact)
        }
        guard hapticCapabilities.supportsHaptics else { throw QualiaReactionConfigurationError.hapticsUnavailable }
    }
    public func plan(for transition: QualiaSceneTransition, context: QualiaReactionContext) -> QualiaReactionPlan {
        let commands: [HapticCommand] = (transition.events[.impact]?.value ?? 0) >= 0.8
            ? [.play(pattern: pattern, channel: .accent)] : []
        return .preservingState(hapticCommands: commands,
            rationale: .init(policyIdentifier: "example.authored-accent", policyVersion: "1",
                             ruleIdentifier: commands.isEmpty ? "below-threshold" : "authored-impact"),
            from: context)
    }
}
// snippet:end custom-policy
