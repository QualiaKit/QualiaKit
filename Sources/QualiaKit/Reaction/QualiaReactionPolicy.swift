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

    public init(
        enabled: Bool = true,
        continuousEffectsEnabled: Bool = true,
        intensityScale: Float = 1
    ) throws {
        guard intensityScale.isFinite, (0...1).contains(intensityScale) else {
            throw QualiaReactionConfigurationError.invalidIntensityScale
        }

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

/// Session-owned state threaded through pure policy evaluations.
///
/// A policy never mutates this value. The caller decides when a returned
/// `nextState` is committed, which keeps renderer failures and stale session
/// results outside policy planning.
public struct QualiaReactionState: Hashable, Sendable {
    public let activeEffects: Set<HapticEffectID>

    public init(activeEffects: Set<HapticEffectID> = []) {
        self.activeEffects = activeEffects
    }

    public static let empty = Self()

    func activating(_ id: HapticEffectID) -> Self {
        var effects = activeEffects
        effects.insert(id)
        return Self(activeEffects: effects)
    }

    func deactivating(_ id: HapticEffectID) -> Self {
        var effects = activeEffects
        effects.remove(id)
        return Self(activeEffects: effects)
    }
}

/// Immutable inputs supplied by a session for one policy decision.
public struct QualiaReactionContext: Hashable, Sendable {
    public let analyzerCapabilities: QualiaAnalyzerCapabilities
    public let hapticCapabilities: HapticCapabilities
    public let preferences: QualiaHapticPreferences
    public let instant: Duration
    public let state: QualiaReactionState
    public let ownerID: HapticOwnerID?

    public init(
        analyzerCapabilities: QualiaAnalyzerCapabilities,
        hapticCapabilities: HapticCapabilities,
        preferences: QualiaHapticPreferences = .default,
        instant: Duration,
        state: QualiaReactionState = .empty,
        ownerID: HapticOwnerID? = nil
    ) {
        self.analyzerCapabilities = analyzerCapabilities
        self.hapticCapabilities = hapticCapabilities
        self.preferences = preferences
        self.instant = instant
        self.state = state
        self.ownerID = ownerID
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
        rationale: QualiaReactionRationale? = nil,
        nextState: QualiaReactionState = .empty
    ) {
        self.hapticCommands = hapticCommands
        self.rationale = rationale
        self.nextState = nextState
    }
}

/// A pure mapping from a validated scene transition to declarative reactions.
/// Implementations must not retain or invoke a haptic renderer.
public protocol QualiaReactionPolicy: Sendable {
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
