import QualiaKit

public enum HapticRecordingResult: Hashable, Sendable {
    case success
    case failure(HapticError)
}

public struct HapticRecordingEntry: Hashable, Sendable {
    public let sequence: UInt64
    public let timestamp: Duration
    public let command: HapticCommand
    public let result: HapticRecordingResult
    public let activeEffects: [HapticActiveEffect]
    public let owner: HapticOwnerID?

    public init(
        sequence: UInt64,
        timestamp: Duration,
        command: HapticCommand,
        result: HapticRecordingResult,
        activeEffects: [HapticActiveEffect] = [],
        owner: HapticOwnerID? = nil
    ) {
        self.sequence = sequence
        self.timestamp = timestamp
        self.command = command
        self.result = result
        self.activeEffects = activeEffects
        self.owner = owner
    }
}

public enum HapticResetRecoveryResult: Hashable, Sendable {
    case success
    case failure(HapticError)
    case ignoredWhileIdle
    case suppressedWhileSuspended
}

public enum HapticRecordingLifecycleEvent: Hashable, Sendable {
    case prepare
    case suspend
    case stopOwnedEffects(HapticOwnerID)
    case resume
    case engineInterruption
    case engineReset(HapticResetRecoveryResult)
}

/// A deterministic renderer for policy/session tests. It implements the same
/// command and capability semantics as the production renderer without using
/// Core Haptics or a physical device.
@MainActor
public final class RecordingHapticRenderer: HapticRendering {
    public let capabilities: HapticCapabilities
    public private(set) var history: [HapticRecordingEntry] = []
    public private(set) var lifecycleHistory: [HapticRecordingLifecycleEvent] = []
    public private(set) var activeEffects: [HapticEffectID: HapticActiveEffect] = [:]
    public private(set) var lifecycleState: HapticRendererLifecycleState = .idle
    public private(set) var lastLifecycleError: HapticError?

    public var isPrepared: Bool { lifecycleState == .ready }
    public var isSuspended: Bool {
        lifecycleState == .suspending || lifecycleState == .suspended
    }

    public var commands: [HapticCommand] {
        history.map(\.command)
    }

    public var activeEffectHistory: [[HapticActiveEffect]] {
        history.map(\.activeEffects)
    }

    private let now: @MainActor () -> Duration
    private var nextFailure: HapticError?
    private var sequence: UInt64 = 0
    private var deadlines: [HapticEffectID: Duration] = [:]
    private var recordingOwner: HapticOwnerID?

    public init(
        capabilities: HapticCapabilities = .full,
        now: @escaping @MainActor () -> Duration = { .zero }
    ) {
        self.capabilities = capabilities
        self.now = now
    }

    public func prepare() throws {
        lifecycleHistory.append(.prepare)
        guard capabilities.supportsHaptics else {
            throw HapticError.hapticsUnavailable
        }

        switch lifecycleState {
        case .ready:
            return
        case .idle:
            break
        case .preparing, .suspending, .suspended, .recovering:
            throw HapticError.invalidLifecycleState
        }

        try transitionToReady()
    }

    public func execute(_ command: HapticCommand) throws {
        let timestamp = now()
        expireEffects()
        guard lifecycleState == .ready else {
            let error = HapticError.invalidLifecycleState
            record(command, at: timestamp, result: .failure(error))
            throw error
        }
        if let failure = consumeFailure() {
            record(command, at: timestamp, result: .failure(failure))
            throw failure
        }

        do {
            let previous = activeEffects
            activeEffects = try HapticCommandSemantics.nextActiveEffects(
                after: command,
                current: activeEffects,
                capabilities: capabilities
            )
            switch command {
            case let .start(id, pattern, _) where previous[id] == nil,
                 let .replace(id, pattern, _):
                deadlines[id] = pattern.playbackDuration.map { timestamp + $0 }
            default: break
            }
            deadlines = deadlines.filter { activeEffects[$0.key] != nil }
            record(command, at: timestamp, result: .success)
        } catch let error as HapticError {
            record(command, at: timestamp, result: .failure(error))
            throw error
        }
    }

    public func execute(_ command: HapticCommand, ownedBy owner: HapticOwnerID) throws {
        try HapticCommandSemantics.validateOwnership(command, owner: owner)
        recordingOwner = owner
        defer { recordingOwner = nil }
        try execute(command)
    }

    public func stopEffects(ownedBy owner: HapticOwnerID) throws {
        lifecycleHistory.append(.stopOwnedEffects(owner))
        expireEffects()
        let ids = activeEffects.keys.filter { $0.scope == .owned(owner) }
            .sorted { $0.orderingKey < $1.orderingKey }
        var firstFailure: Error?
        for id in ids {
            do { try execute(.stop(id: id)) } catch {
                if firstFailure == nil { firstFailure = error }
            }
        }
        if let firstFailure { throw firstFailure }
    }

    public func suspend() async {
        lifecycleHistory.append(.suspend)
        guard lifecycleState != .suspended else { return }
        lifecycleState = .suspending
        lastLifecycleError = nil
        deadlines.removeAll(keepingCapacity: true)
        activeEffects.removeAll(keepingCapacity: true)
        lifecycleState = .suspended
    }

    public func resume() async throws {
        lifecycleHistory.append(.resume)
        try Task.checkCancellation()

        switch lifecycleState {
        case .ready:
            return
        case .idle:
            try transitionToReady()
        case .suspended:
            lifecycleState = .idle
            do {
                try transitionToReady()
            } catch {
                lifecycleState = .suspended
                throw error
            }
        case .preparing, .suspending, .recovering:
            throw HapticError.invalidLifecycleState
        }
    }

    public func simulateEngineInterruption() {
        lifecycleHistory.append(.engineInterruption)
        deadlines.removeAll(keepingCapacity: true)
        activeEffects.removeAll(keepingCapacity: true)
        lastLifecycleError = .engineInterrupted
        switch lifecycleState {
        case .suspending, .suspended:
            break
        case .idle, .preparing, .ready, .recovering:
            lifecycleState = .idle
        }
    }

    public func simulateEngineReset() {
        guard lifecycleState != .suspending,
              lifecycleState != .suspended else {
            deadlines.removeAll(keepingCapacity: true)
            activeEffects.removeAll(keepingCapacity: true)
            lastLifecycleError = .engineReset
            lifecycleHistory.append(.engineReset(.suppressedWhileSuspended))
            return
        }

        guard lifecycleState == .ready else {
            deadlines.removeAll(keepingCapacity: true)
            activeEffects.removeAll(keepingCapacity: true)
            lifecycleState = .idle
            lastLifecycleError = .engineReset
            lifecycleHistory.append(.engineReset(.ignoredWhileIdle))
            return
        }

        let retainedEffects = HapticCommandSemantics.effectsRetainedAfterReset(activeEffects)
        activeEffects = retainedEffects
        deadlines = deadlines.filter { activeEffects[$0.key] != nil }
        lifecycleState = .recovering
        lastLifecycleError = .engineReset
        let failure = consumeFailure()
            ?? (capabilities.supportsHaptics ? nil : .hapticsUnavailable)

        guard let failure else {
            lifecycleState = .ready
            lastLifecycleError = nil
            lifecycleHistory.append(.engineReset(.success))
            return
        }

        deadlines.removeAll(keepingCapacity: true)
        activeEffects.removeAll(keepingCapacity: true)
        lifecycleState = .idle
        lastLifecycleError = failure
        lifecycleHistory.append(.engineReset(.failure(failure)))
    }

    /// Advances deterministic physical completion using the injected clock,
    /// without manufacturing a policy command or a new observation.
    public func expireEffects() {
        let instant = now()
        for (id, deadline) in deadlines where instant >= deadline {
            activeEffects.removeValue(forKey: id)
            deadlines.removeValue(forKey: id)
        }
    }

    public func failNext(with error: HapticError = .injectedFailure) {
        nextFailure = error
    }

    public func resetHistory() {
        history.removeAll(keepingCapacity: true)
        lifecycleHistory.removeAll(keepingCapacity: true)
        sequence = 0
    }

    private func consumeFailure() -> HapticError? {
        defer { nextFailure = nil }
        return nextFailure
    }

    private func transitionToReady() throws {
        guard capabilities.supportsHaptics else {
            throw HapticError.hapticsUnavailable
        }
        lifecycleState = .preparing
        if let failure = consumeFailure() {
            lifecycleState = .idle
            lastLifecycleError = failure
            throw failure
        }
        lifecycleState = .ready
        lastLifecycleError = nil
    }

    private func record(
        _ command: HapticCommand,
        at timestamp: Duration,
        result: HapticRecordingResult
    ) {
        precondition(sequence < .max, "RecordingHapticRenderer sequence overflow")
        sequence += 1
        history.append(
            HapticRecordingEntry(
                sequence: sequence,
                timestamp: timestamp,
                command: command,
                result: result,
                activeEffects: activeEffects.values.sorted(by: Self.effectOrder),
                owner: recordingOwner
            )
        )
    }

    private static func effectOrder(
        _ left: HapticActiveEffect,
        _ right: HapticActiveEffect
    ) -> Bool {
        left.id.orderingKey < right.id.orderingKey
    }
}
