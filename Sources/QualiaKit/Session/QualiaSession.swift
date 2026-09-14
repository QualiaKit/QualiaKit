import Foundation

/// One accepted-fragment sequence. Latest request wins; previous analysis is
/// cancelled and also guarded against cancellation-ignoring implementations.
/// Call reset/suspend explicitly when leaving a room; deinit is not lifecycle.
public actor QualiaSession {
    public nonisolated let owner: HapticOwnerID
    private let dependencies: QualiaSessionDependencies
    private let renderer: QualiaSessionRenderer
    private let executor: QualiaReactionExecutor
    private let gate = SessionCommitGate()
    private var scene: QualiaSceneState
    var contextStorage: SessionContext?
    private var lastAcceptedID: QualiaInputID?
    private var suspended = false
    private var transitioning = false
    private var cleanupRequired = false
    private var currentWork: Task<PreparedAnalysis, Error>?
    private var workGeneration: UInt64?

    public init(dependencies: QualiaSessionDependencies, renderer: QualiaSessionRenderer,
                preferences: QualiaHapticPreferences = .default) async throws {
        let owner = try HapticOwnerID(rawValue: UUID().uuidString)
        self.owner = owner
        self.dependencies = dependencies
        self.renderer = renderer
        scene = .initial(at: dependencies.clock.now)
        executor = try await renderer.makeExecutor(owner: owner, dependencies: dependencies, preferences: preferences)
        dependencies.diagnostics.record(.lifecycle(.created))
    }

    public var snapshot: QualiaSessionSnapshot {
        absorb(gate.takeReceipt())
        let fragments = contextStorage?.fragments ?? []
        return QualiaSessionSnapshot(
            scene: scene,
            lifecycle: transitioning ? .transitioning : cleanupRequired ? .cleanupRequired : suspended ? .suspended : .active,
            retainedFragments: fragments.count,
            retainedCharacters: fragments.reduce(0) { $0 + $1.text.count },
            retainedUTF8Bytes: fragments.reduce(0) { $0 + $1.text.utf8.count }
        )
    }

    public func process(_ input: QualiaInput) async throws -> QualiaResponse {
        try Task.checkCancellation()
        guard !transitioning else { throw QualiaSessionError.lifecycleTransitionInProgress }
        guard !cleanupRequired else { throw QualiaSessionError.cleanupRequired }
        guard !suspended else { throw QualiaSessionError.suspended }
        guard input.context.isEmpty else { throw QualiaSessionError.externalContextNotSupported }
        let request = try gate.begin(accepting: input.id, lastAcceptedID: lastAcceptedID, context: contextStorage)
        absorb(request.receipt)
        currentWork?.cancel()
        currentWork = nil
        workGeneration = nil
        let generation = request.generation
        let fullInput = try QualiaInput(id: input.id, text: input.text,
                                       context: contextStorage?.fragments ?? [], language: input.language)
        let dependencies = self.dependencies
        dependencies.diagnostics.record(.started(generation: generation))
        let worker = Task.detached {
            try await Self.prepareAndAnalyze(fullInput, dependencies: dependencies, generation: generation)
        }
        currentWork = worker
        workGeneration = generation
        let gate = self.gate
        let cancellation = request.cancellation
        return try await withTaskCancellationHandler {
            var reachedDispatch = false
            do {
                let prepared = try await worker.value
                reachedDispatch = true
                guard gate.isCurrent(generation) else { throw CancellationError() }
                let response = try await renderer.dispatch(
                    generation: generation, gate: gate, previous: scene,
                    observation: prepared.observation, context: prepared.context,
                    acceptedID: input.id, dependencies: dependencies, executor: executor
                )
                absorb(gate.takeReceipt())
                finishWork(generation)
                dependencies.diagnostics.record(.completed(
                    generation: generation, revision: response.transition.current.revision,
                    attemptedCommands: response.execution.commands.count, rendererFailure: response.execution.failure
                ))
                // Cancellation after the atomic commit cannot undo accepted
                // state/playback; return the committed response in that case.
                return response
            } catch {
                absorb(gate.takeReceipt())
                finishWork(generation)
                if !gate.isCurrent(generation) || error is CancellationError {
                    if reachedDispatch {
                        dependencies.diagnostics.record(.discarded(generation: generation, stage: .dispatch))
                    }
                    throw CancellationError()
                }
                if reachedDispatch {
                    dependencies.diagnostics.record(.failed(generation: generation, stage: .dispatch))
                }
                throw error
            }
        } onCancel: {
            cancellation.cancel()
            worker.cancel()
        }
    }

    /// Clears semantic state/context immediately, before waiting for MainActor.
    /// Throws until owned cleanup succeeds. A newer lifecycle request supersedes
    /// this one with CancellationError; caller cancellation cannot skip cleanup.
    public func reset() async throws {
        let generation = beginLifecycle()
        scene = .initial(at: dependencies.clock.now)
        contextStorage = nil
        lastAcceptedID = nil
        do {
            try await renderer.stop(generation: generation, gate: gate, executor: executor)
            if !suspended { try await renderer.enable(generation: generation, gate: gate, executor: executor) }
            try completeLifecycle(generation)
            dependencies.diagnostics.record(.lifecycle(.reset))
        } catch { try failLifecycle(generation, error: error) }
    }

    /// Retains bounded semantic context, stops all owned playback, and rejects
    /// processing until resume. It never globally suspends a shared renderer.
    public func suspend() async throws {
        let generation = beginLifecycle()
        suspended = true
        do {
            try await renderer.stop(generation: generation, gate: gate, executor: executor)
            try completeLifecycle(generation)
            dependencies.diagnostics.record(.lifecycle(.suspended))
        } catch { try failLifecycle(generation, error: error) }
    }

    /// Retries owned cleanup/preparation and permits fresh input, without replay.
    public func resume() async throws {
        if !suspended, !cleanupRequired, !transitioning { return }
        let generation = beginLifecycle()
        do {
            try await renderer.resume(generation: generation, gate: gate, executor: executor)
            try completeLifecycle(generation)
            suspended = false
            dependencies.diagnostics.record(.lifecycle(.resumed))
        } catch { try failLifecycle(generation, error: error) }
    }

    private func beginLifecycle() -> UInt64 {
        let request = gate.begin()
        absorb(request.receipt)
        currentWork?.cancel()
        currentWork = nil
        workGeneration = nil
        transitioning = true
        cleanupRequired = true
        return request.generation
    }

    private func completeLifecycle(_ generation: UInt64) throws {
        guard gate.isCurrent(generation) else { throw CancellationError() }
        transitioning = false
        cleanupRequired = false
    }

    private func failLifecycle(_ generation: UInt64, error: Error) throws {
        guard gate.isCurrent(generation) else { throw CancellationError() }
        transitioning = false
        cleanupRequired = true
        dependencies.diagnostics.record(.lifecycle(.cleanupFailed))
        throw error
    }

    private func absorb(_ receipt: SessionCommit?) {
        guard let receipt else { return }
        scene = receipt.response.transition.current
        contextStorage = receipt.context
        lastAcceptedID = receipt.acceptedID
    }

    private func finishWork(_ generation: UInt64) {
        if workGeneration == generation {
            currentWork = nil
            workGeneration = nil
        }
    }

    private struct PreparedAnalysis: Sendable {
        let observation: QualiaObservation
        let context: SessionContext?
    }

    private static func prepareAndAnalyze(
        _ input: QualiaInput, dependencies: QualiaSessionDependencies, generation: UInt64
    ) async throws -> PreparedAnalysis {
        var stage: QualiaSessionDiagnostic.Stage = .preparation
        do {
            let preparer = QualiaInputPreparer(
                languageResolver: dependencies.languageResolver, contextWindow: dependencies.contextWindow,
                diagnostics: { dependencies.diagnostics.record(.preparation($0)) }
            )
            let prepared = try await preparer.prepare(input, for: dependencies.analyzer.capabilities)
            stage = .analysis
            let observation = try await QualiaAnalyzerContract.analyze(dependencies.analyzer, input: prepared)
            let fragments = Array((prepared.context + [QualiaContextFragment(id: prepared.id, text: prepared.text)])
                .suffix(dependencies.contextWindow.configuration.maximumFragments))
            return PreparedAnalysis(observation: observation, context: fragments.isEmpty ? nil : SessionContext(fragments))
        } catch {
            dependencies.diagnostics.record(error is CancellationError
                ? .discarded(generation: generation, stage: stage) : .failed(generation: generation, stage: stage))
            throw error
        }
    }
}
