extension HorrorNarrativePolicy {
    static let continuousSignals: Set<QualiaSignal> = [
        .suspense,
        .threat,
        .urgency,
    ]

    static let accentSignals: Set<QualiaSignal> = [
        .impact,
        .shock,
    ]

    func ambientSuppressionReason(context: QualiaReactionContext) -> String? {
        if configuration.compatibilityMode == .transientAccentsOnly {
            return "compatibility-mode"
        }
        if !context.preferences.continuousEffectsEnabled {
            return "continuous-effects-disabled"
        }
        if !context.hapticCapabilities.supportsContinuousHaptics {
            return "continuous-haptics-unavailable"
        }
        if !context.analyzerCapabilities.signals.contains(.suspense) {
            return "missing-suspense-capability"
        }
        return nil
    }

    func tension(
        signals: [QualiaSignal: Float],
        supportedSignals: Set<QualiaSignal>
    ) -> Float {
        max(
            supportedSignals.contains(.suspense) ? signals[.suspense] ?? 0 : 0,
            supportedSignals.contains(.threat) ? (signals[.threat] ?? 0) * 0.8 : 0,
            supportedSignals.contains(.urgency) ? (signals[.urgency] ?? 0) * 0.6 : 0
        )
    }

    func qualifyingAccent(
        events: [QualiaSignal: QualiaScore],
        supportedSignals: Set<QualiaSignal>
    ) -> (signal: QualiaSignal, score: QualiaScore)? {
        supportedSignals
            .compactMap { signal -> (QualiaSignal, QualiaScore)? in
                guard let score = events[signal],
                      score.value >= configuration.accentThreshold else {
                    return nil
                }
                if let requiredConfidence = configuration.minimumAccentConfidence {
                    guard let confidence = score.confidence,
                          confidence >= requiredConfidence else {
                        return nil
                    }
                }
                return (signal, score)
            }
            .max { left, right in
                if left.1.value == right.1.value {
                    return left.0.rawValue > right.0.rawValue
                }
                return left.1.value < right.1.value
            }
    }

    func makeAccentPattern(
        evidence: Float,
        intensityScale: Float
    ) -> HapticPattern {
        let normalized = (evidence - configuration.accentThreshold)
            / max(0.0001, 1 - configuration.accentThreshold)
        let intensity = (0.55 + 0.45 * normalized) * intensityScale

        do {
            return try HapticPattern(
                duration: configuration.accentPatternDuration,
                events: [
                    .transient(
                        at: .zero,
                        intensity: HapticValue(intensity),
                        sharpness: HapticValue(0.85)
                    )
                ]
            )
        } catch {
            preconditionFailure(
                "Validated HorrorNarrativePolicy produced an invalid accent pattern: \(error)"
            )
        }
    }

    func makeAppliedState(
        effectID: HapticEffectID,
        tension: Float,
        intensityScale: Float,
        pattern: HapticPattern
    ) -> QualiaAppliedAmbientState {
        QualiaAppliedAmbientState(
            validatedEffectID: effectID,
            normalizedValue: tension,
            intensityScale: intensityScale,
            pattern: pattern
        )
    }

    func makeEffectID(scope: HapticEffectScope) -> HapticEffectID {
        do {
            return try HapticEffectID(
                rawValue: configuration.effectName,
                scope: scope
            )
        } catch {
            preconditionFailure(
                "Validated HorrorNarrativePolicy produced an invalid effect ID: \(error)"
            )
        }
    }

    func compatibilityFacts(
        context: QualiaReactionContext
    ) -> [QualiaDiagnosticFact] {
        [
            fact("compatibility-mode", configuration.compatibilityMode.rawValue),
            fact("continuous-effects-enabled", context.preferences.continuousEffectsEnabled),
            fact("intensity-scale", context.preferences.intensityScale),
            fact("threshold-curve-version", "horror-tension-v1"),
            fact("heartbeat-version", HeartbeatPolicyConfiguration.version),
        ]
    }

    func fact(_ key: String, _ value: String) -> QualiaDiagnosticFact {
        QualiaDiagnosticFact(key: key, value: value)
    }

    func fact(_ key: String, _ value: Bool) -> QualiaDiagnosticFact {
        fact(key, value ? "true" : "false")
    }

    func fact(_ key: String, _ value: Float) -> QualiaDiagnosticFact {
        fact(key, value.reactionFactValue)
    }
}
