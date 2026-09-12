import Foundation

/// A scoped execution boundary for hosts until full analyzer/session
/// orchestration is installed. Capture a request token before asynchronous
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
        guard request.executor == identity, request.generation == generation,
              !isSuspended else { return nil }
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
        let plan = policy.plan(for: transition, context: QualiaReactionContext(
            analyzerCapabilities: analyzerCapabilities,
            hapticCapabilities: renderer.capabilities,
            preferences: preferences,
            instant: instant,
            effectScope: .owned(owner),
            state: state
        ))
        // This executor is scoped even when given a custom policy.
        guard plan.hapticCommands.allSatisfy(isOwned),
              plan.nextState.activeEffects.allSatisfy({ $0.scope == .owned(owner) }) else {
            throw HapticError.ownershipConflict
        }
        do {
            for command in plan.hapticCommands { try renderer.execute(command) }
            state = plan.nextState
        } catch {
            state = plan.reconciledStateAfterFailure(from: state, rendererActiveEffects: renderer.activeEffects)
            throw error
        }
        return plan
    }

    /// Invalidates queued work and stops only this owner's effects. Call for
    /// scene reset and renderer interruption/reset, before accepting new work.
    public func reset() throws {
        invalidateRequests()
        do {
            try renderer.stopEffects(ownedBy: owner)
        } catch {
            for id in state.heartbeats.keys { state.heartbeats[id]?.phase = .failed }
            throw error
        }
        state = .empty
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
        if !preferences.enabled || !preferences.continuousEffectsEnabled || preferences.intensityScale == 0 {
            try reset()
        }
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
