import Foundation

/// A scoped execution boundary used by QualiaSession and by hosts that provide
/// their own orchestration. Capture a request token before asynchronous
/// analysis, then submit its successful transition. Lifecycle invalidation
/// and command dispatch are serialized on MainActor without suspension points.
@MainActor
public final class QualiaReactionExecutor {
    public struct Request: Hashable, Sendable {
        fileprivate let executor: UUID
        fileprivate let generation: UInt64
    }

    public let owner: HapticOwnerID
    public private(set) var state: QualiaReactionState = .empty
    public private(set) var preferences: QualiaHapticPreferences
    public private(set) var isSuspended = false
    private let renderer: any HapticRendering
    private let identity = UUID()
    private var generation: UInt64 = 0
    private var playbackFailed = false
    private var cleanupRequired = false
    private var effectDeadlines: [HapticEffectID: Duration] = [:]

    public init(
        renderer: any HapticRendering,
        owner: HapticOwnerID,
        preferences: QualiaHapticPreferences = .default
    ) {
        self.renderer = renderer
        self.owner = owner
        self.preferences = preferences
    }

    /// A newer request invalidates older analysis results. An analyzer failure
    /// does not submit a transition and therefore leaves reaction state intact.
    public func beginRequest() -> Request {
        invalidateRequests()
        return Request(executor: identity, generation: generation)
    }

    /// Returns nil for a stale, consumed, foreign, or suspended request.
    /// The injected instant must be monotonic and sampled at dispatch time.
    @discardableResult
    public func execute(
        for transition: QualiaSceneTransition,
        policy: any QualiaReactionPolicy,
        analyzerCapabilities: QualiaAnalyzerCapabilities,
        at instant: Duration,
        request: Request
    ) throws -> QualiaReactionPlan? {
        guard let result = try executeRecording(for: transition, policy: policy,
            analyzerCapabilities: analyzerCapabilities, at: instant, request: request) else { return nil }
        if let failure = result.underlyingFailure { throw failure }
        return result.plan
    }

    /// Session uses the same planning/reconciliation path while retaining a
    /// semantic response when a renderer command fails.
    package func executeRecording(
        for transition: QualiaSceneTransition,
        policy: any QualiaReactionPolicy,
        analyzerCapabilities: QualiaAnalyzerCapabilities,
        at instant: Duration,
        request: Request,
        measureTiming: Bool = false,
        reductionDuration: Duration = .zero,
        executeCommand: (@MainActor (HapticCommand) throws -> Void)? = nil
    ) throws -> (plan: QualiaReactionPlan, execution: QualiaExecutionSummary, underlyingFailure: Error?)? {
        guard request.executor == identity, request.generation == generation,
              !isSuspended else { return nil }
        guard !cleanupRequired else { throw HapticError.invalidLifecycleState }
        invalidateRequests()
        // Detect interruption or natural completion before planning. The
        // policy deadline handles natural expiry; unexpected loss latches
        // suppression instead of replaying an effect after renderer recovery.
        for (id, heartbeat) in state.heartbeats {
            if state.activeEffects.contains(id), renderer.activeEffects[id] == nil,
               instant < heartbeat.deadline {
                state = state.removingEffect(id)
                state.heartbeats[id]?.phase = .failed
            }
        }
        // A custom policy may only track applied ambient state, with no
        // heartbeat lifecycle. Remove a physically completed segment before
        // planning, while its deadline still distinguishes expiry from loss.
        // Heartbeat expiry/cooldown remains owned by its specialized policy.
        for (id, deadline) in effectDeadlines {
            if renderer.activeEffects[id] == nil, state.heartbeats[id] == nil,
               instant >= deadline {
                state = state.removingEffect(id)
            }
        }
        effectDeadlines = effectDeadlines.filter { renderer.activeEffects[$0.key] != nil }
        let clock = ContinuousClock()
        let planningStarted = measureTiming ? clock.now : nil
        let proposed = policy.plan(for: transition, context: QualiaReactionContext(
            analyzerCapabilities: analyzerCapabilities,
            hapticCapabilities: renderer.capabilities,
            preferences: preferences,
            instant: instant,
            effectScope: .owned(owner),
            state: state
        ))
        // This executor is scoped even when given a custom policy.
        guard proposed.hapticCommands.allSatisfy(isOwned),
              proposed.nextState.activeEffects.allSatisfy({ $0.scope == .owned(owner) }) else {
            throw HapticError.ownershipConflict
        }
        let safe = try QualiaHapticSafety.apply(proposed, preferences: preferences,
            capabilities: renderer.capabilities, at: instant, deadlines: effectDeadlines,
            playbackFailed: playbackFailed, previous: state)
        let plan = safe.plan
        let dispatchStarted = planningStarted.map { _ in clock.now }
        func summary(_ entries: [QualiaCommandExecution]) -> QualiaExecutionSummary {
            var result = QualiaExecutionSummary(plannedCommandCount: plan.hapticCommands.count,
                                                commands: entries, reactionState: state)
            result.suppressions = safe.suppressions
            if let planningStarted, let dispatchStarted {
                result.timing = .init(stateAndPolicy: reductionDuration + planningStarted.duration(to: dispatchStarted),
                                     dispatch: dispatchStarted.duration(to: clock.now))
            }
            return result
        }
        var entries: [QualiaCommandExecution] = []
        for command in plan.hapticCommands {
            do {
                if let executeCommand { try executeCommand(command) }
                else { try renderer.execute(command, ownedBy: owner) }
                entries.append(QualiaCommandExecution(command: command, outcome: .succeeded))
                switch command {
                case let .start(id, _, _), let .replace(id, _, _): effectDeadlines[id] = safe.deadlines[id]
                case let .stop(id): effectDeadlines.removeValue(forKey: id)
                default: break
                }
            } catch {
                playbackFailed = true
                let failure = error as? HapticError ?? .invalidCommand
                entries.append(QualiaCommandExecution(command: command, outcome: .failed(failure)))
                state = plan.reconciledStateAfterFailure(from: state, rendererActiveEffects: renderer.activeEffects)
                return (plan, summary(entries), failure)
            }
        }
        state = plan.nextState
        return (plan, summary(entries), nil)
    }

    /// Invalidates queued work and stops only this owner's effects. Call for
    /// scene reset and renderer interruption/reset, before accepting new work.
    public func reset() throws {
        invalidateRequests()
        do {
            try renderer.stopEffects(ownedBy: owner)
        } catch {
            cleanupRequired = true
            playbackFailed = true
            for id in state.heartbeats.keys { state.heartbeats[id]?.phase = .failed }
            throw redactedRuntimeError(error, stage: .dispatch)
        }
        state = .empty
        playbackFailed = false
        cleanupRequired = false
        effectDeadlines.removeAll(keepingCapacity: true)
    }

    /// Host background/interruption hook. Other owners may share the renderer.
    public func suspend() throws {
        isSuspended = true
        try reset()
    }

    /// Explicit host recovery; it does not restart any previous effect.
    public func resume() {
        invalidateRequests()
        isSuspended = false
    }

    /// Disabling effects takes effect without requiring another observation.
    public func updatePreferences(_ preferences: QualiaHapticPreferences) throws {
        self.preferences = preferences
        invalidateRequests()
        // Stop on every update, including intensity/duration reductions. Leaving
        // an already-playing descriptor unchanged would violate the new snapshot.
        try reset()
    }

    private func invalidateRequests() {
        precondition(generation < .max, "Reaction request generation overflow")
        generation += 1
    }

    private func isOwned(_ command: HapticCommand) -> Bool {
        switch command {
        case let .start(id, _, _), let .replace(id, _, _), let .stop(id):
            return id.scope == .owned(owner)
        case let .play(_, channel):
            return channel == .accent
        case .stopAll, .stopChannel:
            return false
        }
    }
}
