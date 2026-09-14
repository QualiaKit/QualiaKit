public protocol QualiaClock: Sendable {
    /// Monotonic time relative to a stable origin, not wall-clock time.
    var now: Duration { get }
    func sleep(for duration: Duration) async throws
}

public struct QualiaContinuousClock: QualiaClock {
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant
    public init() { origin = clock.now }
    public var now: Duration { origin.duration(to: clock.now) }
    public func sleep(for duration: Duration) async throws { try await clock.sleep(for: duration) }
}

public enum QualiaSessionError: Error, Hashable, Sendable {
    case suspended
    case lifecycleTransitionInProgress
    case cleanupRequired
    case externalContextNotSupported
    case duplicateInput
    case nonMonotonicClock
    case invalidReducerOutput
}

public enum QualiaSessionLifecycle: Hashable, Sendable {
    case active, suspended, transitioning, cleanupRequired
}

public struct QualiaSessionSnapshot: Sendable {
    public let scene: QualiaSceneState
    public let lifecycle: QualiaSessionLifecycle
    public let retainedFragments: Int
    public let retainedCharacters: Int
    public let retainedUTF8Bytes: Int
}

public struct QualiaCommandExecution: Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        case succeeded
        case failed(HapticError)
    }
    public let command: HapticCommand
    public let outcome: Outcome
}

/// Contains attempted commands only, in order. Execution stops at the first
/// failure; plannedCommandCount also accounts for commands that were not tried.
public struct QualiaExecutionSummary: Hashable, Sendable {
    public let plannedCommandCount: Int
    public let commands: [QualiaCommandExecution]
    public let reactionState: QualiaReactionState
    public var suppressions: [QualiaDiagnosticEvent.Suppression] = []
    public var timing: QualiaExecutionTiming? = nil
    public var failure: HapticError? {
        for entry in commands {
            if case .failed(let error) = entry.outcome { return error }
        }
        return nil
    }
}

public struct QualiaResponse: Sendable {
    public let observation: QualiaObservation
    public let transition: QualiaSceneTransition
    public let reaction: QualiaReactionPlan
    public let execution: QualiaExecutionSummary
}

public struct QualiaSessionDependencies: Sendable {
    public let analyzer: any QualiaAnalyzing
    public let languageResolver: any QualiaLanguageResolving
    /// The concrete generic window exposes the same bounds for retained history.
    public let contextWindow: QualiaContextWindow
    public let stateReducer: any QualiaSceneReducing
    public let reactionPolicy: any QualiaReactionPolicy
    public let diagnostics: any QualiaDiagnosticsSink
    public let clock: any QualiaClock

    public init(
        analyzer: any QualiaAnalyzing,
        languageResolver: any QualiaLanguageResolving,
        contextWindow: QualiaContextWindow,
        stateReducer: any QualiaSceneReducing,
        reactionPolicy: any QualiaReactionPolicy,
        diagnostics: any QualiaDiagnosticsSink = NoOpQualiaDiagnosticsSink(),
        clock: any QualiaClock
    ) {
        self.analyzer = analyzer
        self.languageResolver = languageResolver
        self.contextWindow = contextWindow
        self.stateReducer = stateReducer
        self.reactionPolicy = reactionPolicy
        self.diagnostics = diagnostics
        self.clock = clock
    }
}

public struct QualiaExecutionTiming: Hashable, Sendable {
    public let stateAndPolicy: Duration
    public let dispatch: Duration
}

extension HapticCommand {
    var diagnosticKind: QualiaDiagnosticEvent.CommandKind {
        switch self {
        case .play: return .play
        case .start: return .start
        case .replace: return .replace
        case .stop: return .stop
        case .stopAll: return .stopAll
        case .stopChannel: return .stopChannel
        }
    }
}
