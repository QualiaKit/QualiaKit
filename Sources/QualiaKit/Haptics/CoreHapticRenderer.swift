/// Observable lifecycle for the Core Haptics renderer.
public enum HapticRendererLifecycleState: Hashable, Sendable {
    case idle
    case preparing
    case ready
    case suspending
    case suspended
    case recovering
}

/// Core Haptics-backed renderer with independent long-lived and one-shot
/// player ownership. It is injected like any other renderer and has no global
/// singleton or semantic signal mapping.
@MainActor
public final class CoreHapticRenderer: HapticRendering {
    public let capabilities: HapticCapabilities
    public private(set) var activeEffects: [HapticEffectID: HapticActiveEffect] = [:]
    public private(set) var lifecycleState: HapticRendererLifecycleState = .idle
    public private(set) var lastLifecycleError: HapticError?

    public var isPrepared: Bool { lifecycleState == .ready }
    public var isSuspended: Bool {
        lifecycleState == .suspending || lifecycleState == .suspended
    }

    package var activeLongLivedPlayerCount: Int { activePlayers.count }
    package var activeOneShotPlayerCount: Int { oneShotPlayers.count }
    package var pendingCleanupPlayerCount: Int { pendingCleanupPlayers.count }
    package var suspensionWaiterCount: Int { suspensionWaiters.count }

    private enum DesiredLifecycleState {
        case ready
        case suspended
    }

    private struct OneShotPlayer: Sendable {
        let channel: HapticChannel
        let player: any HapticRuntimePlayer
    }

    private let backend: any HapticRuntimeEngine
    private var activePlayers: [HapticEffectID: any HapticRuntimePlayer] = [:]
    private var oneShotPlayers: [UInt64: OneShotPlayer] = [:]
    private var pendingCleanupPlayers: [UInt64: any HapticRuntimePlayer] = [:]
    private var nextOneShotID: UInt64 = 0
    private var nextCleanupID: UInt64 = 0
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private var lifecycleRequestGeneration: UInt64 = 0
    private var desiredLifecycleState: DesiredLifecycleState = .ready

    public convenience init() {
        self.init(backend: CoreHapticsRuntimeEngine())
    }

    package init(backend: any HapticRuntimeEngine) {
        self.backend = backend
        capabilities = backend.capabilities
        installLifecycleHandlers()
    }

    public func prepare() throws {
        guard capabilities.supportsHaptics else {
            throw HapticError.hapticsUnavailable
        }

        switch lifecycleState {
        case .ready:
            try requireCompletedPendingCleanup()
            return
        case .idle:
            try requireCompletedPendingCleanup()
        case .preparing, .suspending, .suspended, .recovering:
            throw HapticError.invalidLifecycleState
        }

        lifecycleState = .preparing
        do {
            try backend.start()
            lifecycleState = .ready
            desiredLifecycleState = .ready
            lastLifecycleError = nil
        } catch {
            lifecycleState = .idle
            let error = typed(error, fallback: .enginePreparationFailed)
            lastLifecycleError = error
            throw error
        }
    }

    public func execute(_ command: HapticCommand) throws {
        guard lifecycleState == .ready else {
            throw HapticError.invalidLifecycleState
        }
        try requireCompletedPendingCleanup()

        let nextEffects = try HapticCommandSemantics.nextActiveEffects(
            after: command,
            current: activeEffects,
            capabilities: capabilities
        )

        switch command {
        case let .play(pattern, channel):
            try playOneShot(pattern: pattern, channel: channel)

        case let .start(id, pattern, _):
            guard activePlayers[id] == nil else {
                activeEffects = nextEffects
                return
            }
            activePlayers[id] = try makeAndStartPlayer(pattern: pattern)
            activeEffects = nextEffects

        case let .replace(id, pattern, _):
            guard let previous = activePlayers[id] else {
                throw HapticError.invalidLifecycleState
            }
            let replacement = try makePlayer(pattern: pattern)
            do {
                try previous.stop()
            } catch {
                throw typed(error, fallback: .playerStopFailed)
            }
            activePlayers.removeValue(forKey: id)
            activeEffects.removeValue(forKey: id)
            do {
                try replacement.start()
            } catch {
                throw cleanupAfterFailedStart(replacement, startError: error)
            }
            activePlayers[id] = replacement
            activeEffects = nextEffects

        case let .stop(id):
            try stopEffect(id)

        case let .stopChannel(channel):
            try stopChannel(channel)

        case .stopAll:
            try stopAllPlayers()
        }
    }

    public func suspend() async {
        let requestGeneration = beginLifecycleRequest(.suspended)

        while isCurrentLifecycleRequest(requestGeneration, desired: .suspended) {
            switch lifecycleState {
            case .suspended:
                return
            case .suspending:
                await waitForSuspension()
                continue
            case .idle, .ready, .preparing, .recovering:
                break
            }

            lifecycleState = .suspending
            lastLifecycleError = nil

            var stopFailure: HapticError?
            do {
                try stopAllPlayers()
            } catch {
                stopFailure = typed(error, fallback: .playerStopFailed)
            }

            do {
                try await backend.stop()
            } catch {
                if stopFailure == nil {
                    stopFailure = typed(error, fallback: .engineStopFailed)
                }
            }

            // Completion means the explicit engine stop has finished. Every
            // old player is invalid at this boundary, including players whose
            // individual or deferred cleanup stop reported an error.
            clearPlayerState()
            if let stopFailure {
                lastLifecycleError = stopFailure
            }
            finishSuspension()
            return
        }
    }

    public func resume() async throws {
        let requestGeneration = beginLifecycleRequest(.ready)
        if lifecycleState == .suspending {
            await waitForSuspension()
        }
        try Task.checkCancellation()
        guard isCurrentLifecycleRequest(requestGeneration, desired: .ready) else {
            return
        }

        switch lifecycleState {
        case .ready:
            return
        case .idle:
            try prepare()
        case .suspended:
            lifecycleState = .idle
            do {
                try prepare()
            } catch {
                lifecycleState = .suspended
                throw error
            }
        case .preparing, .suspending, .recovering:
            throw HapticError.invalidLifecycleState
        }
    }

    private func installLifecycleHandlers() {
        backend.stoppedHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleInterruption()
            }
        }
        backend.resetHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleReset()
            }
        }
    }

    private func handleInterruption() {
        clearPlayerState()
        lastLifecycleError = .engineInterrupted

        switch lifecycleState {
        case .suspending, .suspended:
            break
        case .idle, .preparing, .ready, .recovering:
            lifecycleState = .idle
        }
    }

    private func handleReset() {
        guard lifecycleState != .suspending,
              lifecycleState != .suspended else {
            clearPlayerState()
            lastLifecycleError = .engineReset
            return
        }

        guard lifecycleState == .ready else {
            clearPlayerState()
            lifecycleState = .idle
            lastLifecycleError = .engineReset
            return
        }

        let retainedEffects = HapticCommandSemantics.effectsRetainedAfterReset(activeEffects)
        let effectsToRestore = retainedEffects.values.sorted {
            $0.id.orderingKey < $1.id.orderingKey
        }
        activePlayers.removeAll(keepingCapacity: true)
        oneShotPlayers.removeAll(keepingCapacity: true)
        pendingCleanupPlayers.removeAll(keepingCapacity: true)
        activeEffects = retainedEffects
        lifecycleState = .recovering
        lastLifecycleError = .engineReset

        do {
            try backend.start()
            for effect in effectsToRestore {
                activePlayers[effect.id] = try makeAndStartPlayer(pattern: effect.pattern)
            }
            lifecycleState = .ready
            lastLifecycleError = nil
        } catch {
            let recoveryError = typed(error, fallback: .enginePreparationFailed)
            moveTrackedPlayersToPendingCleanup()
            do {
                try stopPendingCleanupPlayers()
            } catch {
                // Failed cleanup players remain in pendingCleanupPlayers and
                // are retried by stopAll/suspend or invalidated by engine stop.
            }
            lifecycleState = .idle
            lastLifecycleError = recoveryError
        }
    }

    private func playOneShot(pattern: HapticPattern, channel: HapticChannel) throws {
        let player = try makePlayer(pattern: pattern)
        precondition(nextOneShotID < .max, "CoreHapticRenderer one-shot ID overflow")
        nextOneShotID += 1
        let identifier = nextOneShotID
        player.completionHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.oneShotPlayers.removeValue(forKey: identifier)
            }
        }
        oneShotPlayers[identifier] = OneShotPlayer(channel: channel, player: player)
        do {
            try player.start()
        } catch {
            oneShotPlayers.removeValue(forKey: identifier)
            throw cleanupAfterFailedStart(player, startError: error)
        }
    }

    private func makeAndStartPlayer(
        pattern: HapticPattern
    ) throws -> any HapticRuntimePlayer {
        let player = try makePlayer(pattern: pattern)
        do {
            try player.start()
            return player
        } catch {
            throw cleanupAfterFailedStart(player, startError: error)
        }
    }

    private func makePlayer(pattern: HapticPattern) throws -> any HapticRuntimePlayer {
        do {
            return try backend.makePlayer(pattern: pattern)
        } catch {
            throw typed(error, fallback: .playerCreationFailed)
        }
    }

    private func stopEffect(_ id: HapticEffectID) throws {
        guard let player = activePlayers[id] else {
            activeEffects.removeValue(forKey: id)
            return
        }
        do {
            try player.stop()
            activePlayers.removeValue(forKey: id)
            activeEffects.removeValue(forKey: id)
        } catch {
            throw typed(error, fallback: .playerStopFailed)
        }
    }

    private func stopChannel(_ channel: HapticChannel) throws {
        let effectIDs = activeEffects.values
            .filter { $0.channel == channel }
            .map(\.id)
            .sorted { $0.orderingKey < $1.orderingKey }
        for id in effectIDs {
            try stopEffect(id)
        }

        let oneShotIDs = oneShotPlayers
            .filter { $0.value.channel == channel }
            .map(\.key)
            .sorted()
        for id in oneShotIDs {
            try stopOneShot(id)
        }
    }

    private func stopAllPlayers() throws {
        var firstFailure: HapticError?
        let effectIDs = Set(activePlayers.keys)
            .union(activeEffects.keys)
            .sorted { $0.orderingKey < $1.orderingKey }
        for id in effectIDs {
            do {
                try stopEffect(id)
            } catch {
                if firstFailure == nil {
                    firstFailure = typed(error, fallback: .playerStopFailed)
                }
            }
        }
        for id in oneShotPlayers.keys.sorted() {
            do {
                try stopOneShot(id)
            } catch {
                if firstFailure == nil {
                    firstFailure = typed(error, fallback: .playerStopFailed)
                }
            }
        }
        do {
            try stopPendingCleanupPlayers()
        } catch {
            if firstFailure == nil {
                firstFailure = typed(error, fallback: .playerStopFailed)
            }
        }
        if let firstFailure {
            throw firstFailure
        }
    }

    private func stopOneShot(_ id: UInt64) throws {
        guard let record = oneShotPlayers[id] else { return }
        do {
            try record.player.stop()
            oneShotPlayers.removeValue(forKey: id)
        } catch {
            throw typed(error, fallback: .playerStopFailed)
        }
    }

    private func clearPlayerState() {
        activePlayers.removeAll(keepingCapacity: true)
        oneShotPlayers.removeAll(keepingCapacity: true)
        pendingCleanupPlayers.removeAll(keepingCapacity: true)
        activeEffects.removeAll(keepingCapacity: true)
    }

    private func retainForCleanup(_ player: any HapticRuntimePlayer) {
        precondition(nextCleanupID < .max, "CoreHapticRenderer cleanup ID overflow")
        nextCleanupID += 1
        pendingCleanupPlayers[nextCleanupID] = player
    }

    private func cleanupAfterFailedStart(
        _ player: any HapticRuntimePlayer,
        startError: Error
    ) -> HapticError {
        do {
            try player.stop()
        } catch {
            retainForCleanup(player)
        }
        return typed(startError, fallback: .playerStartFailed)
    }

    private func requireCompletedPendingCleanup() throws {
        guard !pendingCleanupPlayers.isEmpty else { return }
        do {
            try stopPendingCleanupPlayers()
        } catch {
            let error = typed(error, fallback: .playerStopFailed)
            lastLifecycleError = error
            throw error
        }
        guard pendingCleanupPlayers.isEmpty else {
            lastLifecycleError = .playerStopFailed
            throw HapticError.playerStopFailed
        }
    }

    private func moveTrackedPlayersToPendingCleanup() {
        for player in activePlayers.values {
            retainForCleanup(player)
        }
        for record in oneShotPlayers.values {
            retainForCleanup(record.player)
        }
        activePlayers.removeAll(keepingCapacity: true)
        oneShotPlayers.removeAll(keepingCapacity: true)
        activeEffects.removeAll(keepingCapacity: true)
    }

    private func stopPendingCleanupPlayers() throws {
        var firstFailure: HapticError?
        for id in pendingCleanupPlayers.keys.sorted() {
            guard let player = pendingCleanupPlayers[id] else { continue }
            do {
                try player.stop()
                pendingCleanupPlayers.removeValue(forKey: id)
            } catch {
                if firstFailure == nil {
                    firstFailure = typed(error, fallback: .playerStopFailed)
                }
            }
        }
        if let firstFailure {
            throw firstFailure
        }
    }

    private func waitForSuspension() async {
        guard lifecycleState == .suspending else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    private func finishSuspension() {
        lifecycleState = .suspended
        let waiters = suspensionWaiters
        suspensionWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
    }

    private func beginLifecycleRequest(
        _ desiredState: DesiredLifecycleState
    ) -> UInt64 {
        precondition(
            lifecycleRequestGeneration < .max,
            "CoreHapticRenderer lifecycle generation overflow"
        )
        lifecycleRequestGeneration += 1
        desiredLifecycleState = desiredState
        return lifecycleRequestGeneration
    }

    private func isCurrentLifecycleRequest(
        _ generation: UInt64,
        desired state: DesiredLifecycleState
    ) -> Bool {
        generation == lifecycleRequestGeneration && desiredLifecycleState == state
    }

    private func typed(_ error: Error, fallback: HapticError) -> HapticError {
        error as? HapticError ?? fallback
    }
}
