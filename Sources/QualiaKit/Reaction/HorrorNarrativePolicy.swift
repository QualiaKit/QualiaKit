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
    public static let version = "1.0.0-beta.2"

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
        let effectID = makeEffectID(scope: context.effectScope)
        let appliedAmbient = context.state.appliedAmbientState(for: effectID)
        let wasActive = appliedAmbient != nil
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
                state: context.state
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
            appliedState: appliedAmbient,
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
        appliedState: QualiaAppliedAmbientState?,
        result: inout HorrorPlanningResult
    ) {
        let wasActive = appliedState != nil
        if let reason = ambientSuppressionReason(context: context) {
            result.facts.append(fact("ambient-suppression", reason))
            if wasActive {
                result.commands.append(.stop(id: effectID))
                result.state = result.state.removingEffect(effectID)
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
        if let appliedState {
            result.facts.append(fact("applied-tension", appliedState.normalizedValue))
            result.facts.append(
                fact("applied-intensity-scale", appliedState.intensityScale)
            )
        }

        if wasActive, currentTension <= configuration.stopThreshold {
            stopAmbient(effectID: effectID, result: &result)
        } else if !wasActive, currentTension >= configuration.startThreshold {
            startAmbient(
                effectID: effectID,
                tension: currentTension,
                intensityScale: context.preferences.intensityScale,
                result: &result
            )
        } else if let appliedState,
                  shouldReplace(
                    appliedState: appliedState,
                    tension: currentTension,
                    intensityScale: context.preferences.intensityScale
                  ) {
            updateAmbient(
                effectID: effectID,
                tension: currentTension,
                intensityScale: context.preferences.intensityScale,
                result: &result
            )
        } else if wasActive {
            result.ruleIdentifiers.append("ambient-stable")
        }
    }

    func stopAmbient(
        effectID: HapticEffectID,
        result: inout HorrorPlanningResult
    ) {
        result.commands.append(.stop(id: effectID))
        result.state = result.state.removingEffect(effectID)
        result.ruleIdentifiers.append("ambient-stop")
    }

    func startAmbient(
        effectID: HapticEffectID,
        tension: Float,
        intensityScale: Float,
        result: inout HorrorPlanningResult
    ) {
        let pattern = makeAmbientPattern(
            tension: tension,
            intensityScale: intensityScale
        )
        result.commands.append(
            .start(id: effectID, pattern: pattern, channel: .ambient)
        )
        result.state = result.state.applying(
            makeAppliedState(
                effectID: effectID,
                tension: tension,
                intensityScale: intensityScale,
                pattern: pattern
            )
        )
        result.ruleIdentifiers.append("ambient-start")
    }

    func updateAmbient(
        effectID: HapticEffectID,
        tension: Float,
        intensityScale: Float,
        result: inout HorrorPlanningResult
    ) {
        let pattern = makeAmbientPattern(
            tension: tension,
            intensityScale: intensityScale
        )
        result.commands.append(
            .replace(id: effectID, pattern: pattern, channel: .ambient)
        )
        result.state = result.state.applying(
            makeAppliedState(
                effectID: effectID,
                tension: tension,
                intensityScale: intensityScale,
                pattern: pattern
            )
        )
        result.ruleIdentifiers.append("ambient-update")
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
            nextState: context.state.removingEffect(effectID)
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

}

public extension QualiaSignal {
    static let urgency: Self = "urgency"
    static let shock: Self = "shock"
}
