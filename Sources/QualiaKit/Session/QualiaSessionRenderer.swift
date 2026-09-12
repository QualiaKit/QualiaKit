/// Share one coordinator when sessions target the same physical renderer.
/// Independent owners may coexist; this is not a guarantee of perceptual mixing.
public enum QualiaRendererArbitration: Hashable, Sendable {
    case independentOwners
    /// Reject a new ambient start/replace while another owner/global effect is
    /// active. Never preempt the other session or invoke global stop.
    case exclusiveAmbient
}

@MainActor
public final class QualiaSessionRenderer {
    public let arbitration: QualiaRendererArbitration
    private let renderer: any HapticRendering
    private let beforeDispatch: (@Sendable (UInt64) async -> Void)?
    private let afterDispatch: (@Sendable (UInt64) async -> Void)?

    public init(renderer: any HapticRendering, arbitration: QualiaRendererArbitration) {
        self.renderer = renderer
        self.arbitration = arbitration
        beforeDispatch = nil
        afterDispatch = nil
    }

    // Deterministic scheduling seam: delay after hopping to MainActor, before
    // acquiring the final gate. Production has no suspension inside dispatch.
    init(renderer: any HapticRendering, arbitration: QualiaRendererArbitration,
         beforeDispatch: (@Sendable (UInt64) async -> Void)? = nil,
         afterDispatch: (@Sendable (UInt64) async -> Void)?) {
        self.renderer = renderer
        self.arbitration = arbitration
        self.beforeDispatch = beforeDispatch
        self.afterDispatch = afterDispatch
    }

    func makeExecutor(owner: HapticOwnerID, dependencies: QualiaSessionDependencies,
                      preferences: QualiaHapticPreferences) throws -> QualiaReactionExecutor {
        guard dependencies.analyzer.capabilities.acceptsContext
            || dependencies.contextWindow.configuration.maximumFragments == 0 else {
            throw QualiaError.unsupportedContext
        }
        try dependencies.reactionPolicy.validate(analyzerCapabilities: dependencies.analyzer.capabilities,
                                                hapticCapabilities: renderer.capabilities)
        try renderer.prepare()
        return QualiaReactionExecutor(renderer: renderer, owner: owner, preferences: preferences)
    }

    func dispatch(
        generation: UInt64, gate: SessionCommitGate, previous: QualiaSceneState,
        observation: QualiaObservation, context: SessionContext?, acceptedID: QualiaInputID,
        dependencies: QualiaSessionDependencies, executor: QualiaReactionExecutor
    ) async throws -> QualiaResponse {
        if let beforeDispatch { await beforeDispatch(generation) }
        let response = try gate.commit(generation) {
            let instant = dependencies.clock.now
            guard instant >= previous.updatedAt else { throw QualiaSessionError.nonMonotonicClock }
            guard previous.revision < .max else { throw QualiaSessionError.invalidReducerOutput }
            let transition = dependencies.stateReducer.reduce(state: previous, observation: observation, at: instant)
            guard transition.previous == previous, transition.current.updatedAt == instant else {
                throw QualiaSessionError.invalidReducerOutput
            }
            let result = try executor.executeRecording(
                for: transition, policy: dependencies.reactionPolicy,
                analyzerCapabilities: dependencies.analyzer.capabilities,
                at: instant, request: executor.beginRequest(),
                executeCommand: { command in
                    if self.arbitration == .exclusiveAmbient {
                        switch command {
                        case .start, .replace:
                            guard !self.renderer.activeEffects.values.contains(where: {
                                $0.channel == .ambient && $0.id.scope != .owned(executor.owner)
                            }) else { throw HapticError.ownershipConflict }
                        default: break
                        }
                    }
                    try self.renderer.execute(command, ownedBy: executor.owner)
                }
            )
            guard let result else { throw CancellationError() }
            return SessionCommit(
                response: QualiaResponse(observation: observation, transition: transition,
                                        reaction: result.plan, execution: result.execution),
                context: context, acceptedID: acceptedID
            )
        }
        if let afterDispatch { await afterDispatch(generation) }
        return response
    }

    func stop(generation: UInt64, gate: SessionCommitGate, executor: QualiaReactionExecutor) throws {
        try gate.lifecycle(generation) { try executor.suspend() }
    }

    func resume(generation: UInt64, gate: SessionCommitGate, executor: QualiaReactionExecutor) throws {
        try gate.lifecycle(generation) {
            // Retry incomplete owned cleanup before allowing any new playback.
            try executor.reset()
            try renderer.prepare()
            executor.resume()
        }
    }

    func enable(generation: UInt64, gate: SessionCommitGate, executor: QualiaReactionExecutor) throws {
        try gate.lifecycle(generation) { executor.resume() }
    }
}
