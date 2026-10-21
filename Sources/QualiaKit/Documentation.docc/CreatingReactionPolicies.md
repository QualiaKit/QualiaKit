# Creating reaction policies

QualiaReactionPolicy is a Sendable pure mapping from a scene transition and
QualiaReactionContext to QualiaReactionPlan. Validate required analyzer/hardware
capabilities at installation. Planning is synchronous, does no I/O and cannot
retain a renderer. Preserve the current applied ambient state when adding only
an accent. The session enforces ownership, preference scaling and duration limits.

This host-specific rule emits one accent for a strong authored impact event. It
reads transition-local events, not accumulated state, so the event cannot replay
on an unrelated later observation. It does not duplicate the built-in heartbeat
or sentiment rules.

<!-- snippet: Examples/DeveloperExperience/Sources/QualiaExamples/CustomPolicy.swift#custom-policy -->
```swift
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
```

Install it using `QualiaReactionConfiguration.custom` and configure `.impact` as
an event in the reducer (the `.narrative` preset already does so). The external
consumer test pairs it with AnnotatedSceneAnalyzer and asserts the exact accent,
then verifies that an unmarked event emits nothing.

Built-in policies explain no-op decisions through rationale and diagnostics.
Custom rationale strings are host-controlled: never put user text in keys,
identifiers or facts. The public decision report hashes policy/rule identities
and does not interpolate those arbitrary facts. <doc:PrivacyAndDataFlow>
and <doc:BuildingHapticPatterns> cover the remaining boundaries.
