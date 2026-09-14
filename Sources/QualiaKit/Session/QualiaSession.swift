import Foundation

/// One accepted-fragment sequence. Latest request wins; previous analysis is
/// cancelled and also guarded against cancellation-ignoring implementations.
/// Call reset/suspend explicitly when leaving a room; deinit is not lifecycle.
public actor QualiaSession {
    public nonisolated let diagnosticID = UUID()
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
        dependencies.diagnostics.emit(.correlated(session: diagnosticID, generation: 0, event: .installed(
            analyzer: dependencies.analyzer.diagnosticIdentity, policy: dependencies.reactionPolicy.diagnosticIdentity,
            runtime: .init(identifier: "com.qualiakit.runtime", version: QualiaDiagnosticEvent.runtimeVersion))))
        if dependencies.diagnostics.isEnabled {
            let capabilities = await renderer.capabilities
            dependencies.diagnostics.emit(.correlated(session: diagnosticID, generation: 0,
                event: .capability(capabilities)))
        }
        do {
            executor = try await renderer.makeExecutor(owner: owner, dependencies: dependencies, preferences: preferences)
        } catch {
            dependencies.diagnostics.emit(.correlated(session: diagnosticID, generation: 0,
                event: .failure(stage: .dispatch, error: .redacted(error, stage: .dispatch))))
            // Preserve closed configuration categories for existing policy clients.
            if let error = error as? QualiaReactionConfigurationError {
                if case .missingAnalyzerSignal = error { throw QualiaError.invalidConfiguration(reason: .configuration) }
                throw error
            }
            throw redactedRuntimeError(error, stage: .dispatch)
        }
        dependencies.diagnostics.emit(.lifecycle(.created))
        dependencies.diagnostics.emit(.correlated(session: diagnosticID, generation: 0, event: .lifecycle(.created)))
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
        dependencies.diagnostics.emit(.started(generation: generation))
        emit(.started, generation: generation)
        let diagnosticID = self.diagnosticID
        let worker = Task.detached {
            try await Self.prepareAndAnalyze(fullInput, dependencies: dependencies, generation: generation, diagnosticID: diagnosticID)
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
                dependencies.diagnostics.emit(.completed(
                    generation: generation, revision: response.transition.current.revision,
                    attemptedCommands: response.execution.commands.count, rendererFailure: response.execution.failure
                ))
                emit(.completed(revision: response.transition.current.revision,
                    attemptedCommands: response.execution.commands.count, rendererFailure: response.execution.failure),
                    generation: generation)
                recordResponse(response, generation: generation)
                // Cancellation after the atomic commit cannot undo accepted
                // state/playback; return the committed response in that case.
                return response
            } catch {
                absorb(gate.takeReceipt())
                finishWork(generation)
                if !gate.isCurrent(generation) || error is CancellationError || error is AnalysisCancellation {
                    let stage: QualiaDiagnosticEvent.Stage = (error as? AnalysisCancellation)?.stage
                        ?? (reachedDispatch ? .dispatch : .analysis)
                    let cancelled = Task.isCancelled || gate.isCurrent(generation)
                    dependencies.diagnostics.emit(cancelled
                        ? .cancelled(generation: generation, stage: stage)
                        : .discarded(generation: generation, stage: stage))
                    emit(cancelled ? .cancelled(stage) : .discarded(stage), generation: generation)
                    throw CancellationError()
                }
                if reachedDispatch {
                    dependencies.diagnostics.emit(.failed(generation: generation, stage: .dispatch))
                    emit(.failure(stage: .dispatch, error: .redacted(error, stage: .dispatch)), generation: generation)
                }
                throw redactedRuntimeError(error, stage: reachedDispatch ? .dispatch : .analysis)
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
            dependencies.diagnostics.emit(.lifecycle(.reset))
            emit(.lifecycle(.reset), generation: generation)
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
            dependencies.diagnostics.emit(.lifecycle(.suspended))
            emit(.lifecycle(.suspended), generation: generation)
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
            dependencies.diagnostics.emit(.lifecycle(.resumed))
            emit(.lifecycle(.resumed), generation: generation)
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
        dependencies.diagnostics.emit(.lifecycle(.cleanupFailed))
        emit(.lifecycle(.cleanupFailed), generation: generation)
        emit(.failure(stage: .dispatch, error: .redacted(error, stage: .dispatch)), generation: generation)
        throw redactedRuntimeError(error, stage: .dispatch)
    }

    /// Applies an immutable snapshot and invalidates pending analysis. Any change
    /// stops owned playback immediately; fresh input is needed to start again.
    /// Semantic state/history and suspension are preserved. Failed cleanup blocks
    /// processing until an explicit lifecycle recovery succeeds.
    public func updateHapticPreferences(_ preferences: QualiaHapticPreferences) async throws {
        let generation = beginLifecycle()
        do {
            try await renderer.updatePreferences(preferences, generation: generation, gate: gate, executor: executor,
                                                 resumePlayback: !suspended)
            try completeLifecycle(generation)
            let reason: QualiaDiagnosticEvent.Suppression?
            if !preferences.enabled { reason = .disabled }
            else if preferences.intensityScale == 0 { reason = .zeroIntensity }
            else if !preferences.continuousEffectsEnabled { reason = .continuousDisabled }
            else { reason = nil }
            if let reason { emit(.suppressed(reason), generation: generation) }
        } catch { try failLifecycle(generation, error: error) }
    }

    public var hapticCapabilities: HapticCapabilities { get async { await renderer.capabilities } }

    private func emit(_ event: @autoclosure () -> QualiaDiagnosticEvent.CorrelatedEvent, generation: UInt64) {
        dependencies.diagnostics.emit(.correlated(session: diagnosticID, generation: generation, event: event()))
    }

    private func recordResponse(_ response: QualiaResponse, generation: UInt64) {
        guard dependencies.diagnostics.isEnabled else { return }
        emit(.analyzer(.init(identifier: response.observation.analyzer.identifier,
                             version: response.observation.analyzer.version)), generation: generation)
        emit(.observation(signalCount: response.observation.signals.count,
                          hasValence: response.observation.dimensions.valence != nil), generation: generation)
        emit(.transition(previous: response.transition.previous.revision,
                         current: response.transition.current.revision), generation: generation)
        if let rationale = response.reaction.rationale {
            emit(.policy(identity: .init(identifier: rationale.policyIdentifier, version: rationale.policyVersion),
                         rule: .init(metadata: rationale.ruleIdentifier),
                         commandCount: response.reaction.hapticCommands.count), generation: generation)
        }
        for entry in response.execution.commands {
            let failure: HapticError?
            if case .failed(let error) = entry.outcome { failure = error } else { failure = nil }
            emit(.command(entry.command.diagnosticKind, failure: failure), generation: generation)
        }
        for reason in response.execution.suppressions { emit(.suppressed(reason), generation: generation) }
        if let timing = response.execution.timing {
            emit(.timing(.stateAndPolicy, timing.stateAndPolicy), generation: generation)
            emit(.timing(.dispatch, timing.dispatch), generation: generation)
        }
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

    private struct AnalysisCancellation: Error, Sendable {
        let stage: QualiaDiagnosticEvent.Stage
    }

    private struct PreparedAnalysis: Sendable {
        let observation: QualiaObservation
        let context: SessionContext?
    }

    private static func prepareAndAnalyze(
        _ input: QualiaInput, dependencies: QualiaSessionDependencies, generation: UInt64, diagnosticID: UUID
    ) async throws -> PreparedAnalysis {
        var stage: QualiaSessionDiagnostic.Stage = .preparation
        let clock = ContinuousClock()
        let start = dependencies.diagnostics.isEnabled ? clock.now : nil
        do {
            let recordPreparation: (@Sendable (QualiaPreparationDiagnostic) -> Void)?
            if dependencies.diagnostics.isEnabled {
                recordPreparation = { event in
                    dependencies.diagnostics.emit(.preparation(event))
                    dependencies.diagnostics.emit(.correlated(session: diagnosticID, generation: generation,
                        event: .preparation(event)))
                }
            } else { recordPreparation = nil }
            let preparer = QualiaInputPreparer(
                languageResolver: dependencies.languageResolver,
                contextWindow: dependencies.contextWindow.recordingDiagnostics(recordPreparation),
                diagnostics: recordPreparation
            )
            let prepared = try await preparer.prepare(input, for: dependencies.analyzer.capabilities)
            let analysisStart = start.map { _ in clock.now }
            if let start, let analysisStart {
                dependencies.diagnostics.emit(.correlated(session: diagnosticID, generation: generation,
                    event: .timing(.preparation, start.duration(to: analysisStart))))
                if let language = prepared.language {
                    dependencies.diagnostics.emit(.correlated(session: diagnosticID, generation: generation,
                        event: .language(.init(metadata: language.rawValue))))
                }
            }
            stage = .analysis
            let observation = try await QualiaAnalyzerContract.analyze(dependencies.analyzer, input: prepared)
            if let analysisStart {
                dependencies.diagnostics.emit(.correlated(session: diagnosticID, generation: generation,
                    event: .timing(.inference, analysisStart.duration(to: clock.now))))
            }
            let fragments = Array((prepared.context + [QualiaContextFragment(id: prepared.id, text: prepared.text)])
                .suffix(dependencies.contextWindow.configuration.maximumFragments))
            return PreparedAnalysis(observation: observation, context: fragments.isEmpty ? nil : SessionContext(fragments))
        } catch {
            if error is CancellationError { throw AnalysisCancellation(stage: stage) }
            let safe = QualiaError.redacted(error, stage: stage)
            dependencies.diagnostics.emit(.failed(generation: generation, stage: stage))
            dependencies.diagnostics.emit(.correlated(session: diagnosticID, generation: generation,
                event: .failure(stage: stage, error: .redacted(safe, stage: stage))))
            throw safe
        }
    }
}
