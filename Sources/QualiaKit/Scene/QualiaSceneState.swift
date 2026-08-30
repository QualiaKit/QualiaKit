/// The direction of change for one continuous scene signal.
public enum QualiaTrend: Hashable, Sendable {
    case rising
    case stable
    case falling
}

/// A deterministic, coarse interpretation of accumulated scene intensity.
///
/// A phase is reducer state, not an analyzer or ML prediction.
public enum QualiaScenePhase: Hashable, Sendable {
    case idle
    case building
    case active
    case resolving
}

/// Immutable temporal state accumulated from accepted observations.
///
/// `signals` contains only configured continuous signals. Event-like evidence
/// belongs to `QualiaSceneTransition.events` and is not retained here.
public struct QualiaSceneState: Equatable, Sendable {
    public let dimensions: QualiaDimensions
    public let signals: [QualiaSignal: Float]
    public let trends: [QualiaSignal: QualiaTrend]
    public let phase: QualiaScenePhase
    public let revision: UInt64
    public let updatedAt: Duration

    /// Creates state for a custom reducer or a restored host-owned scene.
    ///
    /// Signal values must be finite and normalized to `0...1`, and every trend
    /// must refer to a stored signal.
    public init(
        dimensions: QualiaDimensions,
        signals: [QualiaSignal: Float],
        trends: [QualiaSignal: QualiaTrend],
        phase: QualiaScenePhase,
        revision: UInt64,
        updatedAt: Duration
    ) {
        precondition(
            signals.values.allSatisfy { $0.isFinite && (0...1).contains($0) },
            "QualiaSceneState signal values must be finite and within 0...1"
        )
        precondition(
            Set(trends.keys).isSubset(of: Set(signals.keys)),
            "QualiaSceneState trends must refer to stored signals"
        )
        self.dimensions = dimensions
        self.signals = signals
        self.trends = trends
        self.phase = phase
        self.revision = revision
        self.updatedAt = updatedAt
    }

    /// The documented empty state used for a new scene or an explicit reset.
    public static func initial(at instant: Duration = .zero) -> Self {
        Self(
            dimensions: .init(),
            signals: [:],
            trends: [:],
            phase: .idle,
            revision: 0,
            updatedAt: instant
        )
    }
}

/// The result of one successful scene reduction.
public struct QualiaSceneTransition: Equatable, Sendable {
    public let previous: QualiaSceneState
    public let current: QualiaSceneState
    public let events: [QualiaSignal: QualiaScore]

    /// Creates a transition from two validated immutable states.
    public init(
        previous: QualiaSceneState,
        current: QualiaSceneState,
        events: [QualiaSignal: QualiaScore]
    ) {
        self.previous = previous
        self.current = current
        self.events = events
    }
}

/// A pure scene reducer. Time is supplied by the caller so implementations do
/// not need a clock or any shared mutable state.
public protocol QualiaSceneReducing: Sendable {
    func reduce(
        state: QualiaSceneState,
        observation: QualiaObservation,
        at instant: Duration
    ) -> QualiaSceneTransition
}

public extension QualiaSceneReducing {
    /// Produces the same deterministic empty state for session reset without
    /// inspecting or mutating the reducer.
    func reset(at instant: Duration = .zero) -> QualiaSceneState {
        .initial(at: instant)
    }
}
