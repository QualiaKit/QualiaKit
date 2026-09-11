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
    public static let version = "1.0.0-beta.3"

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
            return suppressAndStopIfNeeded(
                rule: "haptics-unavailable", effectID: effectID,
                wasActive: wasActive, facts: baseFacts, context: context
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
        guard inputs.hasContinuous || inputs.hasAccent || wasActive
                || context.state.heartbeats[effectID] != nil else {
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
        if let reason = ambientSuppressionReason(context: context) {
            result.facts.append(fact("ambient-suppression", reason))
            if appliedState != nil {
                result.commands.append(.stop(id: effectID))
                result.ruleIdentifiers.append("ambient-stop")
            }
            result.state = result.state.removingEffect(effectID)
            result.state.heartbeats.removeValue(forKey: effectID)
            return
        }
        let decision = heartbeatDecision(transition: transition, context: context, effectID: effectID)
        result.commands.append(contentsOf: decision.hapticCommands)
        result.state = decision.nextState
        result.facts.append(contentsOf: decision.rationale?.facts ?? [])
        if let rule = decision.rationale?.ruleIdentifier { result.ruleIdentifiers.append(rule) }
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
        var state = context.state.removingEffect(effectID)
        state.heartbeats.removeValue(forKey: effectID)
        return QualiaReactionPlan(
            hapticCommands: wasActive ? [.stop(id: effectID)] : [],
            rationale: .make(
                policyIdentifier: Self.identifier,
                policyVersion: Self.version,
                ruleIdentifier: rule,
                facts: facts
            ),
            nextState: state
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
