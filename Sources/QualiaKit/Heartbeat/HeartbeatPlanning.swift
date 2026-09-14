extension HorrorNarrativePolicy {
    func heartbeatDecision(
        transition: QualiaSceneTransition,
        context: QualiaReactionContext,
        effectID: HapticEffectID
    ) -> QualiaReactionPlan {
        var planner = HeartbeatPlanner(policy: self, transition: transition, context: context, effectID: effectID)
        return planner.plan()
    }
}

private struct HeartbeatPlanner {
    let policy: HorrorNarrativePolicy
    let transition: QualiaSceneTransition
    let context: QualiaReactionContext
    let effectID: HapticEffectID
    let config: HeartbeatPolicyConfiguration
    let tension: Float
    let scale: Float
    var state: QualiaReactionState
    var heartbeat: HeartbeatState
    var commands: [HapticCommand] = []
    var facts: [QualiaDiagnosticFact]

    init(
        policy: HorrorNarrativePolicy,
        transition: QualiaSceneTransition,
        context: QualiaReactionContext,
        effectID: HapticEffectID
    ) {
        self.policy = policy
        self.transition = transition
        self.context = context
        self.effectID = effectID
        config = policy.configuration.heartbeat
        state = context.state
        heartbeat = state.heartbeats[effectID] ?? HeartbeatState()
        tension = policy.tension(signals: transition.current.signals, supportedSignals: context.analyzerCapabilities.signals)
        scale = context.preferences.intensityScale * config.userIntensityScale
        facts = [policy.fact("tension", tension), policy.fact("heartbeat-state-before", heartbeat.phase.rawValue)]
    }

    mutating func plan() -> QualiaReactionPlan {
        if state.activeEffects.contains(effectID), state.heartbeats[effectID] == nil {
            stop()
            heartbeat.phase = .failed
            return finish("missing-heartbeat-lifecycle")
        }
        if scale == 0 {
            stop()
            heartbeat = HeartbeatState()
            return finish("zero-heartbeat-intensity")
        }
        if heartbeat.phase == .failed { return finish("heartbeat-execution-failed") }
        if heartbeat.phase != .idle, context.instant < heartbeat.lastUpdate {
            return finish("non-monotonic-time")
        }
        if heartbeat.phase == .running || heartbeat.phase == .resolving {
            if context.instant >= heartbeat.deadline {
                stop()
                let wasResolving = heartbeat.phase == .resolving
                heartbeat.phase = .cooldown
                heartbeat.cooldownUntil = heartbeat.deadline + config.cooldown
                let completionRule = wasResolving ? "heartbeat-resolved" : "heartbeat-maximum-duration"
                facts.append(policy.fact("heartbeat-completion", completionRule))
                if context.instant < heartbeat.cooldownUntil { return finish(completionRule) }
                // A single observation may arrive after both deadlines. Fall
                // through to idle and qualify it as a new segment now.
            }
        }
        if heartbeat.phase == .cooldown {
            guard context.instant >= heartbeat.cooldownUntil else { return finish("heartbeat-cooldown") }
            heartbeat = HeartbeatState()
        }
        if heartbeat.phase == .resolving { return finish("heartbeat-resolving") }
        if heartbeat.phase == .idle { return startIfQualified() }

        if tension <= config.stopThreshold {
            heartbeat.phase = .resolving
            heartbeat.deadline = min(heartbeat.deadline, context.instant + config.resolvingDuration)
            // A brief, weaker double beat resolves without requiring curves.
            // It is physically bounded even if no further observation arrives.
            apply(parameters: heartbeatParameters(tension: 0, scale: scale * 0.3), starting: false)
            return finish("heartbeat-resolving")
        }
        let parameters = heartbeatParameters(tension: tension, scale: scale)
        guard let applied = heartbeat.parameters else { return finish("ambient-stable") }
        let significant = abs(parameters.beatsPerMinute - applied.beatsPerMinute) >= config.minimumBPMDelta
            || abs(parameters.intensity.rawValue - applied.intensity.rawValue) >= config.minimumIntensityDelta
            || state.appliedAmbientState(for: effectID)?.intensityScale != scale
        guard significant else { return finish("ambient-stable") }
        guard context.instant - heartbeat.lastUpdate >= config.minimumUpdateInterval else {
            return finish("heartbeat-update-throttled")
        }
        apply(parameters: parameters, starting: false)
        return finish("ambient-update")
    }

    private mutating func startIfQualified() -> QualiaReactionPlan {
        guard tension >= config.startThreshold else { return finish("below-threshold") }
        // Confidence belongs to a currently driving signal, not a stale
        // dominant state value or unrelated high-confidence observation.
        let weights: [(QualiaSignal, Float)] = [(.suspense, 1), (.threat, 0.8), (.urgency, 0.6)]
        let driver = weights.first { signal, weight in
            guard context.analyzerCapabilities.signals.contains(signal),
                  let value = transition.current.signals[signal] else { return false }
            return value * weight == tension
        }?.0
        if let driver { facts.append(policy.fact("driving-signal", driver.rawValue)) }
        guard let driver, let evidence = transition.evidence[driver] else {
            return finish("missing-heartbeat-evidence")
        }
        facts.append(policy.fact("driving-evidence", evidence.value))
        guard let confidence = evidence.confidence else { return finish("missing-heartbeat-confidence") }
        facts.append(policy.fact("driving-confidence", confidence))
        guard evidence.value > 0, confidence >= config.minimumSignalConfidence else {
            return finish("insufficient-heartbeat-confidence")
        }
        heartbeat.phase = .running
        heartbeat.startedAt = context.instant
        heartbeat.deadline = context.instant + min(config.maximumDuration, context.preferences.maximumContinuousDuration)
        apply(parameters: heartbeatParameters(tension: tension, scale: scale), starting: true)
        return finish("ambient-start")
    }

    mutating func finish(_ rule: String) -> QualiaReactionPlan {
        if heartbeat.phase == .idle {
            state.heartbeats.removeValue(forKey: effectID)
        } else {
            state.heartbeats[effectID] = heartbeat
        }
        facts.append(policy.fact("heartbeat-state", heartbeat.phase.rawValue))
        if let parameters = heartbeat.parameters {
            facts += [
                policy.fact("bpm", String(parameters.beatsPerMinute)),
                policy.fact("intensity", parameters.intensity.rawValue),
                policy.fact("sharpness", parameters.sharpness.rawValue),
                policy.fact("second-beat-ratio", String(parameters.secondBeatRatio)),
            ]
        }
        return QualiaReactionPlan(
            hapticCommands: commands,
            rationale: .make(policyIdentifier: HorrorNarrativePolicy.identifier, policyVersion: HorrorNarrativePolicy.version,
                             ruleIdentifier: rule, facts: facts),
            nextState: state
        )
    }

    mutating func stop() {
        if state.activeEffects.contains(effectID) { commands.append(.stop(id: effectID)) }
        state = state.removingEffect(effectID)
    }

    mutating func apply(parameters: HeartbeatParameters, starting: Bool) {
        do {
            let pattern = try HeartbeatPatternFactory().makePattern(
                parameters: parameters, maximumDuration: heartbeat.deadline - context.instant
            )
            commands.append(starting ? .start(id: effectID, pattern: pattern, channel: .ambient)
                                     : .replace(id: effectID, pattern: pattern, channel: .ambient))
            state = state.applying(policy.makeAppliedState(
                effectID: effectID,
                tension: tension,
                intensityScale: scale,
                pattern: pattern
            ))
            heartbeat.parameters = parameters
            heartbeat.lastUpdate = context.instant
        } catch {
            preconditionFailure("Validated heartbeat produced an invalid pattern: \(error)")
        }
    }
    private func heartbeatParameters(tension: Float, scale: Float) -> HeartbeatParameters {
        let smooth = Double(tension) * Double(tension) * (3 - 2 * Double(tension))
        do {
            return try HeartbeatParameters(
                beatsPerMinute: config.minimumBPM + (config.maximumBPM - config.minimumBPM) * smooth,
                intensity: HapticValue(Float(0.15 + 0.5 * smooth) * scale),
                sharpness: HapticValue(0.2)
            )
        } catch { preconditionFailure("Invalid heartbeat mapping: \(error)") }
    }
}
