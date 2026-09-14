import Foundation

/// A redaction-safe key/value used to explain a reaction decision.
///
/// Built-in policies only record identifiers, normalized numeric values, and
/// configuration metadata. They never receive or include raw input text.
public struct QualiaDiagnosticFact: Hashable, Sendable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// Local user preferences applied after semantic analysis.
public struct QualiaHapticPreferences: Hashable, Sendable {
    public let enabled: Bool
    public let continuousEffectsEnabled: Bool
    public let intensityScale: Float
    public let maximumContinuousDuration: Duration

    public init(
        enabled: Bool = true,
        continuousEffectsEnabled: Bool = true,
        intensityScale: Float = 1,
        maximumContinuousDuration: Duration = .seconds(30)
    ) throws {
        guard intensityScale.isFinite, (0...1).contains(intensityScale) else {
            throw QualiaReactionConfigurationError.invalidIntensityScale
        }

        guard maximumContinuousDuration > .zero, maximumContinuousDuration <= .seconds(3600) else {
            throw QualiaError.invalidConfiguration(reason: .maximumDuration)
        }
        self.maximumContinuousDuration = maximumContinuousDuration
        self.enabled = enabled
        self.continuousEffectsEnabled = continuousEffectsEnabled
        self.intensityScale = intensityScale
    }

    public static let `default`: Self = {
        do {
            return try Self()
        } catch {
            preconditionFailure("Invalid built-in haptic preferences: \(error)")
        }
    }()

    public static let disabled: Self = {
        do {
            return try Self(enabled: false)
        } catch {
            preconditionFailure("Invalid built-in disabled preferences: \(error)")
        }
    }()
}

/// Validation failures for externally restored reaction state.
public enum QualiaReactionStateError: Error, Hashable, Sendable {
    case invalidNormalizedValue
    case invalidIntensityScale
    case mismatchedEffectID
}

/// The last ambient descriptor successfully applied by a renderer.
///
/// `normalizedValue` is the policy-owned experience value used to create the
/// pattern. It remains separate from semantic scene state so a failed replace
/// can be reconciled against the last physical state.
public struct QualiaAppliedAmbientState: Hashable, Sendable {
    public let effectID: HapticEffectID
    public let normalizedValue: Float
    public let intensityScale: Float
    public let pattern: HapticPattern

    public init(
        effectID: HapticEffectID,
        normalizedValue: Float,
        intensityScale: Float,
        pattern: HapticPattern
    ) throws {
        guard normalizedValue.isFinite, (0...1).contains(normalizedValue) else {
            throw QualiaReactionStateError.invalidNormalizedValue
        }
        guard intensityScale.isFinite, (0...1).contains(intensityScale) else {
            throw QualiaReactionStateError.invalidIntensityScale
        }

        self.effectID = effectID
        self.normalizedValue = normalizedValue
        self.intensityScale = intensityScale
        self.pattern = pattern
    }

    init(
        validatedEffectID effectID: HapticEffectID,
        normalizedValue: Float,
        intensityScale: Float,
        pattern: HapticPattern
    ) {
        self.effectID = effectID
        self.normalizedValue = normalizedValue
        self.intensityScale = intensityScale
        self.pattern = pattern
    }
}

/// Session-owned physical reaction state threaded through pure evaluations.
///
/// A policy never mutates this value. After all renderer commands succeed, the
/// caller commits the plan's `nextState`. If execution throws, the caller uses
/// `QualiaReactionPlan.reconciledStateAfterFailure` with the renderer's
/// post-command `activeEffects` instead of assuming execution was atomic.
public struct QualiaReactionState: Hashable, Sendable {
    public let activeAmbientEffects: [HapticEffectID: QualiaAppliedAmbientState]
    var heartbeats: [HapticEffectID: HeartbeatState] = [:]

    public var activeEffects: Set<HapticEffectID> {
        Set(activeAmbientEffects.keys)
    }

    public init(
        activeAmbientEffects: [HapticEffectID: QualiaAppliedAmbientState] = [:]
    ) throws {
        guard activeAmbientEffects.allSatisfy({ $0.key == $0.value.effectID }) else {
            throw QualiaReactionStateError.mismatchedEffectID
        }
        self.activeAmbientEffects = activeAmbientEffects
    }

    public static let empty = Self(validatedAmbientEffects: [:])

    public func appliedAmbientState(
        for effectID: HapticEffectID
    ) -> QualiaAppliedAmbientState? {
        activeAmbientEffects[effectID]
    }

    public func applying(_ appliedState: QualiaAppliedAmbientState) -> Self {
        var effects = activeAmbientEffects
        effects[appliedState.effectID] = appliedState
        return Self(validatedAmbientEffects: effects, heartbeats: heartbeats)
    }

    public func removingEffect(_ effectID: HapticEffectID) -> Self {
        var effects = activeAmbientEffects
        effects.removeValue(forKey: effectID)
        return Self(validatedAmbientEffects: effects, heartbeats: heartbeats)
    }

    init(
        validatedAmbientEffects: [HapticEffectID: QualiaAppliedAmbientState],
        heartbeats: [HapticEffectID: HeartbeatState] = [:]
    ) {
        self.activeAmbientEffects = validatedAmbientEffects
        self.heartbeats = heartbeats
    }
}

/// Immutable inputs supplied by a session for one policy decision.
public struct QualiaReactionContext: Hashable, Sendable {
    public let analyzerCapabilities: QualiaAnalyzerCapabilities
    public let hapticCapabilities: HapticCapabilities
    public let preferences: QualiaHapticPreferences
    public let instant: Duration
    public let effectScope: HapticEffectScope
    public let state: QualiaReactionState

    public init(
        analyzerCapabilities: QualiaAnalyzerCapabilities,
        hapticCapabilities: HapticCapabilities,
        preferences: QualiaHapticPreferences = .default,
        instant: Duration,
        effectScope: HapticEffectScope,
        state: QualiaReactionState = .empty
    ) {
        self.analyzerCapabilities = analyzerCapabilities
        self.hapticCapabilities = hapticCapabilities
        self.preferences = preferences
        self.instant = instant
        self.effectScope = effectScope
        self.state = state
    }
}

/// A deterministic and redacted explanation of one policy rule result.
public struct QualiaReactionRationale: Hashable, Sendable {
    public let policyIdentifier: String
    public let policyVersion: String
    public let ruleIdentifier: String
    public let facts: [QualiaDiagnosticFact]

    public init(
        policyIdentifier: String,
        policyVersion: String,
        ruleIdentifier: String,
        facts: [QualiaDiagnosticFact] = []
    ) {
        self.policyIdentifier = policyIdentifier
        self.policyVersion = policyVersion
        self.ruleIdentifier = ruleIdentifier
        self.facts = facts
    }
}

/// Ordered declarative commands plus the state to commit after successful
/// planning/execution reconciliation by the owning session.
public struct QualiaReactionPlan: Hashable, Sendable {
    public let hapticCommands: [HapticCommand]
    public let rationale: QualiaReactionRationale?
    public let nextState: QualiaReactionState

    public init(
        hapticCommands: [HapticCommand],
        rationale: QualiaReactionRationale?,
        nextState: QualiaReactionState
    ) {
        self.hapticCommands = hapticCommands
        self.rationale = rationale
        self.nextState = nextState
    }

    /// Convenience for stateless/accent-only custom policies that explicitly
    /// preserve all applied ambient state from the current context.
    public static func preservingState(
        hapticCommands: [HapticCommand],
        rationale: QualiaReactionRationale?,
        from context: QualiaReactionContext
    ) -> Self {
        Self(
            hapticCommands: hapticCommands,
            rationale: rationale,
            nextState: context.state
        )
    }

    /// Reconciles the previous and proposed reaction snapshots with physical
    /// renderer state after any command throws.
    ///
    /// A command may fail before changing playback, after successfully
    /// applying a state change, or midway through a destructive replacement.
    /// Only a descriptor that exactly matches the renderer is retained. The
    /// method never adopts effects outside the previous/next policy state, so
    /// effects owned by other sessions remain isolated.
    public func reconciledStateAfterFailure(
        from previousState: QualiaReactionState,
        rendererActiveEffects: [HapticEffectID: HapticActiveEffect]
    ) -> QualiaReactionState {
        let candidateIDs = previousState.activeEffects.union(nextState.activeEffects)
        var reconciled: [HapticEffectID: QualiaAppliedAmbientState] = [:]

        for effectID in candidateIDs {
            guard let rendererEffect = rendererActiveEffects[effectID],
                  rendererEffect.id == effectID,
                  rendererEffect.channel == .ambient else {
                continue
            }

            if let proposed = nextState.appliedAmbientState(for: effectID),
               proposed.pattern == rendererEffect.pattern {
                reconciled[effectID] = proposed
            } else if let previous = previousState.appliedAmbientState(for: effectID),
                      previous.pattern == rendererEffect.pattern {
                reconciled[effectID] = previous
            }
        }

        var heartbeats = nextState.heartbeats
        for (id, previous) in previousState.heartbeats where heartbeats[id] == nil {
            heartbeats[id] = previous
        }
        for id in heartbeats.keys {
            // An unrelated accent failure after a successful ambient command
            // preserves the proposed lifecycle. A missing/unchanged failed
            // ambient command suppresses retries until the owner resets.
            let proposed = nextState.activeAmbientEffects[id]
            let applied = reconciled[id]
            if proposed != applied || (proposed == nil && heartbeats[id]?.phase == .running) {
                heartbeats[id]?.phase = .failed
            }
        }
        return QualiaReactionState(validatedAmbientEffects: reconciled, heartbeats: heartbeats)
    }
}

/// A pure mapping from a validated scene transition to declarative reactions.
/// Implementations must not retain or invoke a haptic renderer.
public protocol QualiaReactionPolicy: Sendable {
    var diagnosticIdentity: QualiaDiagnosticIdentity? { get }
    /// Validates installation-time analyzer and renderer compatibility.
    /// Policies without required capabilities may use the default no-op.
    func validate(
        analyzerCapabilities: QualiaAnalyzerCapabilities,
        hapticCapabilities: HapticCapabilities
    ) throws

    func plan(
        for transition: QualiaSceneTransition,
        context: QualiaReactionContext
    ) -> QualiaReactionPlan
}

public extension QualiaReactionPolicy {
    var diagnosticIdentity: QualiaDiagnosticIdentity? { nil }
    func validate(
        analyzerCapabilities: QualiaAnalyzerCapabilities,
        hapticCapabilities: HapticCapabilities
    ) throws {
        _ = analyzerCapabilities
        _ = hapticCapabilities
    }
}

/// Typed setup failures for reaction policies and preferences.
public enum QualiaReactionConfigurationError: Error, Hashable, Sendable {
    case invalidThresholds
    case invalidRange
    case invalidDuration
    case invalidIntensityScale
    case missingAnalyzerDimension(QualiaDimension)
    case missingAnalyzerSignal(QualiaSignal)
    case missingAccentSignal
    case hapticsUnavailable
    case unsupportedHapticFeature(HapticFeature)
}

extension QualiaReactionRationale {
    static func make(
        policyIdentifier: String,
        policyVersion: String,
        ruleIdentifier: String,
        facts: [QualiaDiagnosticFact] = []
    ) -> Self {
        Self(
            policyIdentifier: policyIdentifier,
            policyVersion: policyVersion,
            ruleIdentifier: ruleIdentifier,
            facts: facts.sorted { left, right in
                if left.key == right.key {
                    return left.value < right.value
                }
                return left.key < right.key
            }
        )
    }
}

extension Float {
    var reactionFactValue: String {
        String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), self)
    }
}

extension QualiaReactionConfigurationError: QualiaErrorConvertible {
    public var qualiaError: QualiaError {
        switch self {
        case .hapticsUnavailable, .unsupportedHapticFeature: return .hapticsUnavailable
        default: return .invalidConfiguration(reason: .configuration)
        }
    }
}
