/// Final safety boundary for built-in and host policies. Built-ins scale their
/// mapping proportionally; this boundary also caps custom descriptors at the
/// user's intensity ceiling and bounds long-lived physical playback.
enum QualiaHapticSafety {
    struct Result {
        let plan: QualiaReactionPlan
        let suppressions: [QualiaDiagnosticEvent.Suppression]
        let deadlines: [HapticEffectID: Duration]
    }

    static func apply(_ plan: QualiaReactionPlan, preferences: QualiaHapticPreferences,
                      capabilities: HapticCapabilities, at instant: Duration,
                      deadlines: [HapticEffectID: Duration], playbackFailed: Bool, previous: QualiaReactionState) throws -> Result {
        var commands: [HapticCommand] = []
        var state = plan.nextState
        var limits = deadlines
        var reasons: [QualiaDiagnosticEvent.Suppression] = []
        func note(_ reason: QualiaDiagnosticEvent.Suppression) {
            if !reasons.contains(reason) { reasons.append(reason) }
        }
        let suppressed: QualiaDiagnosticEvent.Suppression?
        if playbackFailed { suppressed = .rendererFailure }
        else if !preferences.enabled { suppressed = .disabled }
        else if preferences.intensityScale == 0 { suppressed = .zeroIntensity }
        else if !capabilities.supportsHaptics { suppressed = .hardwareUnavailable }
        else { suppressed = nil }
        if let suppressed { note(suppressed) }
        for command in plan.hapticCommands {
            switch command {
            case let .play(pattern, channel):
                if suppressed != nil { continue }
                if !preferences.continuousEffectsEnabled && pattern.requiresContinuousHaptics {
                    note(.continuousDisabled)
                    continue
                }
                commands.append(.play(pattern: try bounded(pattern, preferences: preferences,
                    maximumDuration: preferences.maximumContinuousDuration), channel: channel))
            case let .start(id, pattern, channel), let .replace(id, pattern, channel):
                if suppressed != nil || !preferences.continuousEffectsEnabled {
                    if suppressed == nil { note(.continuousDisabled) }
                    if let applied = previous.appliedAmbientState(for: id) {
                        state = state.applying(applied)
                        state.heartbeats[id] = previous.heartbeats[id]
                    } else {
                        state = state.removingEffect(id)
                        state.heartbeats.removeValue(forKey: id)
                    }
                    continue
                }
                let deadline = min(limits[id] ?? (instant + preferences.maximumContinuousDuration),
                                   instant + preferences.maximumContinuousDuration)
                let remaining = deadline - instant
                guard remaining > .zero else {
                    note(.durationLimit)
                    commands.append(.stop(id: id))
                    state = state.removingEffect(id)
                    state.heartbeats[id]?.phase = .failed
                    continue
                }
                let boundedPattern = try bounded(pattern, preferences: preferences, maximumDuration: remaining)
                limits[id] = min(deadline, instant + (boundedPattern.playbackDuration ?? remaining))
                if case .start = command { commands.append(.start(id: id, pattern: boundedPattern, channel: channel)) }
                else { commands.append(.replace(id: id, pattern: boundedPattern, channel: channel)) }
                if let applied = state.appliedAmbientState(for: id) {
                    state = state.applying(QualiaAppliedAmbientState(validatedEffectID: id,
                        normalizedValue: applied.normalizedValue, intensityScale: applied.intensityScale,
                        pattern: boundedPattern))
                }
            case let .stop(id):
                commands.append(command)
                limits.removeValue(forKey: id)
            case .stopAll, .stopChannel:
                // Ownership validation rejects these before reaching safety.
                throw HapticError.ownershipConflict
            }
        }
        return Result(plan: .init(hapticCommands: commands, rationale: plan.rationale, nextState: state),
                      suppressions: reasons, deadlines: limits)
    }

    private static func bounded(_ pattern: HapticPattern, preferences: QualiaHapticPreferences,
                                maximumDuration: Duration) throws -> HapticPattern {
        let longLived: Bool
        if case .loop = pattern.looping { longLived = true } else { longLived = pattern.requiresContinuousHaptics }
        let limit = longLived ? min(pattern.playbackDuration ?? maximumDuration, maximumDuration) : pattern.playbackDuration
        if preferences.intensityScale == 1, limit == pattern.playbackDuration { return pattern }
        func intensity(_ value: HapticValue) throws -> HapticValue {
            try HapticValue(min(value.rawValue, preferences.intensityScale))
        }
        let events = try pattern.events.map { event -> HapticEvent in
            switch event {
            case let .transient(at, value, sharpness):
                return .transient(at: at, intensity: try intensity(value), sharpness: sharpness)
            case let .continuous(at, duration, value, sharpness):
                return .continuous(at: at, duration: duration, intensity: try intensity(value), sharpness: sharpness)
            }
        }
        let curves = try pattern.curves.map { curve in
            try HapticParameterCurve(parameter: curve.parameter, controlPoints: curve.controlPoints.map { point in
                try HapticCurveControlPoint(at: point.at,
                    value: curve.parameter == .intensity ? intensity(point.value) : point.value)
            })
        }
        return try HapticPattern(duration: pattern.duration, events: events, curves: curves,
                                 looping: pattern.looping, playbackDuration: limit)
    }
}
