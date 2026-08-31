/// An explicit degradation for narrative planning. The degraded mode only
/// consumes transition-local impact/shock evidence and never invents narrative
/// state from valence or another unrelated signal.
public enum HorrorNarrativeCompatibilityMode: String, Hashable, Sendable {
    case strict
    case transientAccentsOnly = "transient-accents-only"
}

/// Built-in narrative policy for accumulated suspense/threat/urgency and
/// transition-local impact/shock accents.
public struct HorrorNarrativePolicy: QualiaReactionPolicy, Sendable {
    public static let identifier = "qualia.horror-narrative"
    public static let version = "1.0.0-beta.1"

    public let configuration: Configuration

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }
}

public extension HorrorNarrativePolicy {
    /// Validates capabilities once when a policy is installed in a session.
    /// Planning repeats compatible runtime checks because capabilities may be
    /// swapped by a host between otherwise deterministic evaluations.
    func validate(
        analyzerCapabilities: QualiaAnalyzerCapabilities,
        hapticCapabilities: HapticCapabilities
    ) throws {
        switch configuration.compatibilityMode {
        case .strict:
            guard analyzerCapabilities.signals.contains(.suspense) else {
                throw QualiaReactionConfigurationError.missingAnalyzerSignal(.suspense)
            }
            guard hapticCapabilities.supportsHaptics else {
                throw QualiaReactionConfigurationError.hapticsUnavailable
            }
            guard hapticCapabilities.supportsContinuousHaptics else {
                throw QualiaReactionConfigurationError.unsupportedHapticFeature(
                    .continuousHaptics
                )
            }

        case .transientAccentsOnly:
            guard analyzerCapabilities.signals.contains(.impact)
                    || analyzerCapabilities.signals.contains(.shock) else {
                throw QualiaReactionConfigurationError.missingAccentSignal
            }
            guard hapticCapabilities.supportsHaptics else {
                throw QualiaReactionConfigurationError.hapticsUnavailable
            }
        }
    }
}

public extension HorrorNarrativePolicy {
    func plan(
        for transition: QualiaSceneTransition,
        context: QualiaReactionContext
    ) -> QualiaReactionPlan {
        let effectID = makeEffectID(ownerID: context.ownerID)
        let wasActive = context.state.activeEffects.contains(effectID)
        let baseFacts = compatibilityFacts(context: context)

        guard context.preferences.enabled,
              context.preferences.intensityScale > 0 else {
            return suppressAndStopIfNeeded(
                rule: context.preferences.enabled ? "zero-intensity" : "haptics-disabled",
                effectID: effectID,
                wasActive: wasActive,
                facts: baseFacts,
                context: context
            )
        }
        guard context.hapticCapabilities.supportsHaptics else {
            return noOp(
                rule: "haptics-unavailable",
                facts: baseFacts,
                state: context.state.deactivating(effectID)
            )
        }
        if let mismatch = strictRuntimeMismatch(context: context) {
            return suppressAndStopIfNeeded(
                rule: mismatch,
                effectID: effectID,
                wasActive: wasActive,
                facts: baseFacts + [fact("compatibility-result", mismatch)],
                context: context
            )
        }

        let inputs = supportedInputs(for: transition, context: context)
        guard inputs.hasContinuous || inputs.hasAccent || wasActive else {
            return noOp(
                rule: "no-supported-signal",
                facts: baseFacts,
                state: context.state
            )
        }

        var result = HorrorPlanningResult(state: context.state, facts: baseFacts)
        planAmbient(
            transition: transition,
            context: context,
            effectID: effectID,
            wasActive: wasActive,
            result: &result
        )
        planAccent(
            events: transition.events,
            supportedSignals: inputs.accentSignals,
            context: context,
            result: &result
        )

        if result.commands.isEmpty, result.ruleIdentifiers.isEmpty {
            let suppression = result.facts.first { $0.key == "ambient-suppression" }
            let rule = inputs.hasContinuous
                ? suppression?.value ?? "below-threshold"
                : (inputs.hasAccent ? "below-threshold" : "no-op")
            result.ruleIdentifiers.append(rule)
        }

        return makePlan(result: result)
    }
}

private struct HorrorPlanningResult {
    var commands: [HapticCommand] = []
    var state: QualiaReactionState
    var ruleIdentifiers: [String] = []
    var facts: [QualiaDiagnosticFact]
}

private struct HorrorSupportedInputs {
    let accentSignals: Set<QualiaSignal>
    let hasContinuous: Bool
    let hasAccent: Bool
}

private extension HorrorNarrativePolicy {
    func makePlan(result: HorrorPlanningResult) -> QualiaReactionPlan {
        QualiaReactionPlan(
            hapticCommands: result.commands,
            rationale: .make(
                policyIdentifier: Self.identifier,
                policyVersion: Self.version,
                ruleIdentifier: result.ruleIdentifiers.joined(separator: "+"),
                facts: result.facts
            ),
            nextState: result.state
        )
    }

    func strictRuntimeMismatch(context: QualiaReactionContext) -> String? {
        guard configuration.compatibilityMode == .strict else {
            return nil
        }
        if !context.analyzerCapabilities.signals.contains(.suspense) {
            return "missing-required-capability"
        }
        if !context.hapticCapabilities.supportsContinuousHaptics {
            return "continuous-haptics-unavailable"
        }
        return nil
    }

    func supportedInputs(
        for transition: QualiaSceneTransition,
        context: QualiaReactionContext
    ) -> HorrorSupportedInputs {
        let continuous = Self.continuousSignals.intersection(
            context.analyzerCapabilities.signals
        )
        let accent = Self.accentSignals.intersection(
            context.analyzerCapabilities.signals
        )
        return HorrorSupportedInputs(
            accentSignals: accent,
            hasContinuous: continuous.contains { transition.current.signals[$0] != nil },
            hasAccent: accent.contains { transition.events[$0] != nil }
        )
    }

    func planAmbient(
        transition: QualiaSceneTransition,
        context: QualiaReactionContext,
        effectID: HapticEffectID,
        wasActive: Bool,
        result: inout HorrorPlanningResult
    ) {
        if let reason = ambientSuppressionReason(context: context) {
            result.facts.append(fact("ambient-suppression", reason))
            if wasActive {
                result.commands.append(.stop(id: effectID))
                result.state = result.state.deactivating(effectID)
                result.ruleIdentifiers.append("ambient-stop")
            }
            return
        }

        let supportedSignals = context.analyzerCapabilities.signals
        let previousTension = tension(
            signals: transition.previous.signals,
            supportedSignals: supportedSignals
        )
        let currentTension = tension(
            signals: transition.current.signals,
            supportedSignals: supportedSignals
        )
        result.facts.append(fact("previous-tension", previousTension))
        result.facts.append(fact("tension", currentTension))

        if wasActive, currentTension <= configuration.stopThreshold {
            result.commands.append(.stop(id: effectID))
            result.state = result.state.deactivating(effectID)
            result.ruleIdentifiers.append("ambient-stop")
        } else if !wasActive, currentTension >= configuration.startThreshold {
            result.commands.append(
                .start(
                    id: effectID,
                    pattern: makeAmbientPattern(
                        tension: currentTension,
                        intensityScale: context.preferences.intensityScale
                    ),
                    channel: .ambient
                )
            )
            result.state = result.state.activating(effectID)
            result.ruleIdentifiers.append("ambient-start")
        } else if wasActive,
                  abs(currentTension - previousTension) >= configuration.minimumUpdateDelta {
            result.commands.append(
                .replace(
                    id: effectID,
                    pattern: makeAmbientPattern(
                        tension: currentTension,
                        intensityScale: context.preferences.intensityScale
                    ),
                    channel: .ambient
                )
            )
            result.ruleIdentifiers.append("ambient-update")
        } else if wasActive {
            result.ruleIdentifiers.append("ambient-stable")
        }
    }

    func planAccent(
        events: [QualiaSignal: QualiaScore],
        supportedSignals: Set<QualiaSignal>,
        context: QualiaReactionContext,
        result: inout HorrorPlanningResult
    ) {
        guard let accent = qualifyingAccent(
            events: events,
            supportedSignals: supportedSignals
        ) else {
            return
        }

        result.commands.append(
            .play(
                pattern: makeAccentPattern(
                    evidence: accent.score.value,
                    intensityScale: context.preferences.intensityScale
                ),
                channel: .accent
            )
        )
        result.ruleIdentifiers.append("accent-play")
        result.facts.append(fact("accent-signal", accent.signal.rawValue))
        result.facts.append(fact("accent-value", accent.score.value))
        if let confidence = accent.score.confidence {
            result.facts.append(fact("accent-confidence", confidence))
        }
    }

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

    private static let continuousSignals: Set<QualiaSignal> = [
        .suspense,
        .threat,
        .urgency,
    ]

    private static let accentSignals: Set<QualiaSignal> = [
        .impact,
        .shock,
    ]

    private func tension(
        signals: [QualiaSignal: Float],
        supportedSignals: Set<QualiaSignal>
    ) -> Float {
        max(
            supportedSignals.contains(.suspense) ? signals[.suspense] ?? 0 : 0,
            supportedSignals.contains(.threat) ? (signals[.threat] ?? 0) * 0.8 : 0,
            supportedSignals.contains(.urgency) ? (signals[.urgency] ?? 0) * 0.6 : 0
        )
    }

    private func qualifyingAccent(
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

    private func makeAmbientPattern(
        tension: Float,
        intensityScale: Float
    ) -> HapticPattern {
        let intensity = (
            configuration.minimumAmbientIntensity
                + (configuration.maximumAmbientIntensity
                    - configuration.minimumAmbientIntensity) * tension
        ) * intensityScale

        do {
            return try HapticPattern(
                duration: configuration.ambientCycleDuration,
                events: [
                    .continuous(
                        at: .zero,
                        duration: configuration.ambientCycleDuration,
                        intensity: HapticValue(intensity),
                        sharpness: HapticValue(0.2)
                    )
                ],
                looping: .loop(period: configuration.ambientCycleDuration)
            )
        } catch {
            preconditionFailure("Validated HorrorNarrativePolicy produced an invalid ambient pattern: \(error)")
        }
    }

    private func makeAccentPattern(
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
            preconditionFailure("Validated HorrorNarrativePolicy produced an invalid accent pattern: \(error)")
        }
    }

    private func makeEffectID(ownerID: HapticOwnerID?) -> HapticEffectID {
        do {
            return try HapticEffectID(
                rawValue: configuration.effectName,
                scope: ownerID.map(HapticEffectScope.owned) ?? .global
            )
        } catch {
            preconditionFailure("Validated HorrorNarrativePolicy produced an invalid effect ID: \(error)")
        }
    }

    private func compatibilityFacts(
        context: QualiaReactionContext
    ) -> [QualiaDiagnosticFact] {
        [
            fact("compatibility-mode", configuration.compatibilityMode.rawValue),
            fact("continuous-effects-enabled", context.preferences.continuousEffectsEnabled),
            fact("intensity-scale", context.preferences.intensityScale),
            fact("threshold-curve-version", "horror-tension-v1"),
        ]
    }

    private func suppressAndStopIfNeeded(
        rule: String,
        effectID: HapticEffectID,
        wasActive: Bool,
        facts: [QualiaDiagnosticFact],
        context: QualiaReactionContext
    ) -> QualiaReactionPlan {
        QualiaReactionPlan(
            hapticCommands: wasActive ? [.stop(id: effectID)] : [],
            rationale: .make(
                policyIdentifier: Self.identifier,
                policyVersion: Self.version,
                ruleIdentifier: rule,
                facts: facts
            ),
            nextState: context.state.deactivating(effectID)
        )
    }

    private func noOp(
        rule: String,
        facts: [QualiaDiagnosticFact],
        state: QualiaReactionState
    ) -> QualiaReactionPlan {
        QualiaReactionPlan(
            hapticCommands: [],
            rationale: .make(
                policyIdentifier: Self.identifier,
                policyVersion: Self.version,
                ruleIdentifier: rule,
                facts: facts
            ),
            nextState: state
        )
    }

    private func fact(_ key: String, _ value: String) -> QualiaDiagnosticFact {
        QualiaDiagnosticFact(key: key, value: value)
    }

    private func fact(_ key: String, _ value: Bool) -> QualiaDiagnosticFact {
        fact(key, value ? "true" : "false")
    }

    private func fact(_ key: String, _ value: Float) -> QualiaDiagnosticFact {
        fact(key, value.reactionFactValue)
    }
}

public extension QualiaSignal {
    static let urgency: Self = "urgency"
    static let shock: Self = "shock"
}
