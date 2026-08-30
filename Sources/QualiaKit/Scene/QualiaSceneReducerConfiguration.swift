/// Typed validation failures for scene reducer configuration.
public enum QualiaSceneConfigurationError: Error, Hashable, Sendable {
    case invalidSmoothingHalfLife
    case invalidDecayHalfLife
    case invalidDecayTarget
    case invalidTrendEpsilon
    case invalidEventThreshold
    case invalidPhaseThresholds
    case invalidPhaseSignal(QualiaSignal)
}

/// The meaning of an absent continuous signal in a later observation.
///
/// Missing evidence remains distinct from an explicitly observed score of
/// zero. A missing value can either retain the previous state or decay toward
/// a configured neutral baseline.
public enum QualiaMissingDataPolicy: Hashable, Sendable {
    case preserve
    case decay(halfLife: Duration, toward: Float)
}

/// Time-aware behavior for one continuous scene value.
public struct QualiaContinuousSignalConfiguration: Hashable, Sendable {
    public let smoothingHalfLife: Duration
    public let missingDataPolicy: QualiaMissingDataPolicy
    public let trendEpsilon: Float

    public init(
        smoothingHalfLife: Duration,
        missingDataPolicy: QualiaMissingDataPolicy,
        trendEpsilon: Float
    ) throws {
        guard smoothingHalfLife.isStrictlyPositive else {
            throw QualiaSceneConfigurationError.invalidSmoothingHalfLife
        }
        guard trendEpsilon.isFinite, (0...1).contains(trendEpsilon) else {
            throw QualiaSceneConfigurationError.invalidTrendEpsilon
        }
        if case let .decay(halfLife, target) = missingDataPolicy {
            guard halfLife.isStrictlyPositive else {
                throw QualiaSceneConfigurationError.invalidDecayHalfLife
            }
            guard target.isFinite, (0...1).contains(target) else {
                throw QualiaSceneConfigurationError.invalidDecayTarget
            }
        }

        self.smoothingHalfLife = smoothingHalfLife
        self.missingDataPolicy = missingDataPolicy
        self.trendEpsilon = trendEpsilon
    }
}

/// Transition-local behavior for event-like evidence.
public struct QualiaEventSignalConfiguration: Hashable, Sendable {
    public let threshold: Float

    public init(threshold: Float) throws {
        guard threshold.isFinite, (0...1).contains(threshold) else {
            throw QualiaSceneConfigurationError.invalidEventThreshold
        }
        self.threshold = threshold
    }
}

/// Selects whether an observed signal accumulates in scene state or is emitted
/// only on the current transition.
public enum QualiaSignalReduction: Hashable, Sendable {
    case continuous(QualiaContinuousSignalConfiguration)
    case event(QualiaEventSignalConfiguration)
}

/// Thresholds and driving signals for deterministic phase calculation.
public struct QualiaScenePhaseConfiguration: Hashable, Sendable {
    public let signals: Set<QualiaSignal>
    public let idleThreshold: Float
    public let buildingThreshold: Float
    public let activeThreshold: Float

    public init(
        signals: Set<QualiaSignal>,
        idleThreshold: Float,
        buildingThreshold: Float,
        activeThreshold: Float
    ) throws {
        let thresholds = [idleThreshold, buildingThreshold, activeThreshold]
        guard thresholds.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              idleThreshold < buildingThreshold,
              buildingThreshold < activeThreshold else {
            throw QualiaSceneConfigurationError.invalidPhaseThresholds
        }

        self.signals = signals
        self.idleThreshold = idleThreshold
        self.buildingThreshold = buildingThreshold
        self.activeThreshold = activeThreshold
    }
}

/// Immutable, validated configuration for `QualiaSceneReducer`.
///
/// Signals absent from `signals` use the neutral default: they are ignored and
/// neither stored nor emitted as events.
public struct QualiaSceneReducerConfiguration: Sendable {
    public let signals: [QualiaSignal: QualiaSignalReduction]
    public let valence: QualiaContinuousSignalConfiguration?
    public let phase: QualiaScenePhaseConfiguration

    public init(
        signals: [QualiaSignal: QualiaSignalReduction],
        valence: QualiaContinuousSignalConfiguration? = nil,
        phase: QualiaScenePhaseConfiguration
    ) throws {
        for signal in phase.signals {
            guard case .continuous? = signals[signal] else {
                throw QualiaSceneConfigurationError.invalidPhaseSignal(signal)
            }
        }

        self.signals = signals
        self.valence = valence
        self.phase = phase
    }

    /// Built-in configuration for the flagship narrative path.
    ///
    /// Suspense and threat accumulate and decay over time. Impact remains a
    /// transition-local event. Unconfigured custom signals are ignored.
    public static let narrative: Self = {
        let continuous = try! QualiaContinuousSignalConfiguration(
            smoothingHalfLife: .seconds(1),
            missingDataPolicy: .decay(halfLife: .seconds(4), toward: 0),
            trendEpsilon: 0.025
        )
        let impact = try! QualiaEventSignalConfiguration(threshold: 0.6)
        let phase = try! QualiaScenePhaseConfiguration(
            signals: [.suspense, .threat],
            idleThreshold: 0.1,
            buildingThreshold: 0.35,
            activeThreshold: 0.7
        )
        return try! Self(
            signals: [
                .suspense: .continuous(continuous),
                .threat: .continuous(continuous),
                .impact: .event(impact),
            ],
            phase: phase
        )
    }()
}

public extension QualiaSignal {
    /// Standard narrative convenience. Custom signal identifiers remain fully
    /// supported through `QualiaSignal`'s open string-backed representation.
    static let suspense: Self = "suspense"
    static let threat: Self = "threat"
    static let impact: Self = "impact"
}

extension Duration {
    fileprivate var isStrictlyPositive: Bool {
        self > .zero
    }
}
