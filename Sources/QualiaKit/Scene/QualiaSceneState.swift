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

/// Typed validation failures for externally constructed scene values.
public enum QualiaSceneValidationError: Error, Hashable, Sendable {
    case invalidStateSignal(QualiaSignal)
    case trendWithoutSignal(QualiaSignal)
    case stateContainsAnalyzerConfidence
    case invalidTransitionRevision
    case nonMonotonicTransitionTime
    case invalidEventEvidence(QualiaSignal)
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
    /// Signal values must be finite and normalized to `0...1`, every trend
    /// must refer to a stored signal, and reducer-derived dimensions must not
    /// carry analyzer confidence. Invalid restored or custom state is rejected
    /// with a typed error rather than trapping the host process.
    public init(
        dimensions: QualiaDimensions,
        signals: [QualiaSignal: Float],
        trends: [QualiaSignal: QualiaTrend],
        phase: QualiaScenePhase,
        revision: UInt64,
        updatedAt: Duration
    ) throws {
        guard dimensions.valence?.confidence == nil else {
            throw QualiaSceneValidationError.stateContainsAnalyzerConfidence
        }
        if let invalid = signals.first(where: {
            !$0.value.isFinite || !(0...1).contains($0.value)
        }) {
            throw QualiaSceneValidationError.invalidStateSignal(invalid.key)
        }
        if let orphaned = trends.keys.first(where: { signals[$0] == nil }) {
            throw QualiaSceneValidationError.trendWithoutSignal(orphaned)
        }

        self.init(
            validatedDimensions: dimensions,
            signals: signals,
            trends: trends,
            phase: phase,
            revision: revision,
            updatedAt: updatedAt
        )
    }

    init(
        validatedDimensions dimensions: QualiaDimensions,
        signals: [QualiaSignal: Float],
        trends: [QualiaSignal: QualiaTrend],
        phase: QualiaScenePhase,
        revision: UInt64,
        updatedAt: Duration
    ) {
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
            validatedDimensions: .init(),
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
    /// Fresh scores from the current observation for configured signals.
    /// Missing evidence remains absent, while explicit zero and confidence are
    /// preserved for downstream reaction policies.
    public let evidence: [QualiaSignal: QualiaScore]
    /// The transition-local subset of `evidence` configured as event-like.
    public let events: [QualiaSignal: QualiaScore]

    /// Creates a transition from externally constructed state and evidence.
    /// Revision, monotonic-time, and event-subset invariants are validated.
    public init(
        previous: QualiaSceneState,
        current: QualiaSceneState,
        evidence: [QualiaSignal: QualiaScore],
        events: [QualiaSignal: QualiaScore]
    ) throws {
        guard previous.revision < .max,
              current.revision == previous.revision + 1 else {
            throw QualiaSceneValidationError.invalidTransitionRevision
        }
        guard current.updatedAt >= previous.updatedAt else {
            throw QualiaSceneValidationError.nonMonotonicTransitionTime
        }
        if let invalid = events.first(where: { evidence[$0.key] != $0.value }) {
            throw QualiaSceneValidationError.invalidEventEvidence(invalid.key)
        }

        self.init(
            validatedPrevious: previous,
            current: current,
            evidence: evidence,
            events: events
        )
    }

    init(
        validatedPrevious previous: QualiaSceneState,
        current: QualiaSceneState,
        evidence: [QualiaSignal: QualiaScore],
        events: [QualiaSignal: QualiaScore]
    ) {
        self.previous = previous
        self.current = current
        self.evidence = evidence
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
