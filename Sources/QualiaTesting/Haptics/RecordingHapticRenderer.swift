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

    public init(
        sequence: UInt64,
        timestamp: Duration,
        command: HapticCommand,
        result: HapticRecordingResult,
        activeEffects: [HapticActiveEffect] = []
    ) {
        self.sequence = sequence
        self.timestamp = timestamp
        self.command = command
        self.result = result
        self.activeEffects = activeEffects
    }
}

public enum HapticResetRecoveryResult: Hashable, Sendable {
    case success
    case failure(HapticError)
    case suppressedWhileSuspended
}

public enum HapticRecordingLifecycleEvent: Hashable, Sendable {
    case prepare
    case suspend
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
    public private(set) var isPrepared = false
    public private(set) var isSuspended = false
    public private(set) var lastLifecycleError: HapticError?

    public var commands: [HapticCommand] {
        history.map(\.command)
    }

    public var activeEffectHistory: [[HapticActiveEffect]] {
        history.map(\.activeEffects)
    }

    private let now: @MainActor () -> Duration
    private var nextFailure: HapticError?
    private var sequence: UInt64 = 0

    public init(
        capabilities: HapticCapabilities = .full,
        now: @escaping @MainActor () -> Duration = { .zero }
    ) {
        self.capabilities = capabilities
        self.now = now
    }

    public func prepare() throws {
        lifecycleHistory.append(.prepare)
        if let failure = consumeFailure() {
            lastLifecycleError = failure
            throw failure
        }
        guard capabilities.supportsHaptics else {
            lastLifecycleError = .hapticsUnavailable
            throw HapticError.hapticsUnavailable
        }
        isPrepared = true
        isSuspended = false
        lastLifecycleError = nil
    }

    public func execute(_ command: HapticCommand) throws {
        let timestamp = now()
        if let failure = consumeFailure() {
            record(command, at: timestamp, result: .failure(failure))
            throw failure
        }
        guard isPrepared, !isSuspended else {
            let error = HapticError.invalidLifecycleState
            record(command, at: timestamp, result: .failure(error))
            throw error
        }

        do {
            activeEffects = try HapticCommandSemantics.nextActiveEffects(
                after: command,
                current: activeEffects,
                capabilities: capabilities
            )
            record(command, at: timestamp, result: .success)
        } catch let error as HapticError {
            record(command, at: timestamp, result: .failure(error))
            throw error
        }
    }

    public func suspend() async {
        lifecycleHistory.append(.suspend)
        activeEffects = activeEffects.filter { $0.value.channel != .ambient }
        isPrepared = false
        isSuspended = true
    }

    public func resume() async throws {
        lifecycleHistory.append(.resume)
        if let failure = consumeFailure() {
            lastLifecycleError = failure
            throw failure
        }
        guard capabilities.supportsHaptics else {
            lastLifecycleError = .hapticsUnavailable
            throw HapticError.hapticsUnavailable
        }
        isPrepared = true
        isSuspended = false
        lastLifecycleError = nil
    }

    public func simulateEngineInterruption() {
        lifecycleHistory.append(.engineInterruption)
        activeEffects.removeAll(keepingCapacity: true)
        isPrepared = false
        lastLifecycleError = .engineInterrupted
    }

    public func simulateEngineReset() {
        guard !isSuspended else {
            activeEffects.removeAll(keepingCapacity: true)
            isPrepared = false
            lastLifecycleError = .engineReset
            lifecycleHistory.append(.engineReset(.suppressedWhileSuspended))
            return
        }

        let retainedEffects = HapticCommandSemantics.effectsRetainedAfterReset(activeEffects)
        let failure = consumeFailure()
            ?? (capabilities.supportsHaptics ? nil : .hapticsUnavailable)

        guard let failure else {
            activeEffects = retainedEffects
            isPrepared = true
            lastLifecycleError = nil
            lifecycleHistory.append(.engineReset(.success))
            return
        }

        activeEffects.removeAll(keepingCapacity: true)
        isPrepared = false
        lastLifecycleError = failure
        lifecycleHistory.append(.engineReset(.failure(failure)))
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
                activeEffects: activeEffects.values.sorted(by: Self.effectOrder)
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
