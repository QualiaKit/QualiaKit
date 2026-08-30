#if canImport(CoreHaptics)
import CoreHaptics
import Foundation

/// Core Haptics-backed renderer with independent long-lived and one-shot
/// player ownership. It is injected like any other renderer and has no global
/// singleton or semantic signal mapping.
@MainActor
public final class CoreHapticRenderer: HapticRendering {
    public let capabilities: HapticCapabilities
    public private(set) var activeEffects: [HapticEffectID: HapticActiveEffect] = [:]
    public private(set) var isPrepared = false
    public private(set) var isSuspended = false
    public private(set) var lastLifecycleError: HapticError?

    /// Core Haptics player references never leave MainActor isolation. The
    /// unchecked conformance only allows the actor-isolated renderer reference
    /// to be weakly captured by Core Haptics' sendable completion callback.
    private struct OneShotPlayer: @unchecked Sendable {
        let channel: HapticChannel
        let player: CHHapticAdvancedPatternPlayer
    }

    private var engine: CHHapticEngine?
    private var activePlayers: [HapticEffectID: CHHapticAdvancedPatternPlayer] = [:]
    private var oneShotPlayers: [UInt64: OneShotPlayer] = [:]
    private var nextOneShotID: UInt64 = 0

    public init() {
        let hardware = CHHapticEngine.capabilitiesForHardware()
        let supported = hardware.supportsHaptics
        self.capabilities = HapticCapabilities(
            supportsHaptics: supported,
            supportsContinuousHaptics: supported,
            supportsParameterCurves: supported
        )
    }

    public func prepare() throws {
        guard capabilities.supportsHaptics else {
            throw HapticError.hapticsUnavailable
        }
        guard !isSuspended else {
            throw HapticError.invalidLifecycleState
        }
        if isPrepared {
            return
        }

        do {
            if engine == nil {
                let engine = try CHHapticEngine()
                engine.playsHapticsOnly = true
                installLifecycleHandlers(on: engine)
                self.engine = engine
            }
            try engine?.start()
            isPrepared = true
            lastLifecycleError = nil
        } catch {
            isPrepared = false
            lastLifecycleError = .enginePreparationFailed
            throw HapticError.enginePreparationFailed
        }
    }

    public func execute(_ command: HapticCommand) throws {
        guard isPrepared, !isSuspended, engine != nil else {
            throw HapticError.invalidLifecycleState
        }

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
                // Repeated start is explicitly idempotent. A changed pattern
                // must use replace so no duplicate player is created.
                activeEffects = nextEffects
                return
            }
            activePlayers[id] = try makeAndStartPlayer(pattern: pattern)

        case let .replace(id, pattern, _):
            guard let previous = activePlayers[id] else {
                throw HapticError.invalidLifecycleState
            }
            let replacement = try makeAndStartPlayer(pattern: pattern)
            do {
                try previous.stop(atTime: CHHapticTimeImmediate)
                activePlayers[id] = replacement
            } catch {
                try? replacement.stop(atTime: CHHapticTimeImmediate)
                throw HapticError.playerStopFailed
            }

        case let .stop(id):
            try stopEffect(id)

        case let .stopChannel(channel):
            try stopChannel(channel)

        case .stopAll:
            try stopAllPlayers()
        }

        activeEffects = nextEffects
    }

    public func suspend() {
        isSuspended = true
        lastLifecycleError = nil
        do {
            try stopChannel(.ambient)
        } catch let error as HapticError {
            lastLifecycleError = error
        } catch {
            lastLifecycleError = .playerStopFailed
        }
        activeEffects = activeEffects.filter { $0.value.channel != .ambient }
        engine?.stop(completionHandler: nil)
        isPrepared = false
    }

    public func resume() throws {
        isSuspended = false
        do {
            try prepare()
        } catch {
            isSuspended = true
            throw error
        }
    }

    private func installLifecycleHandlers(on engine: CHHapticEngine) {
        engine.stoppedHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleInterruption()
            }
        }
        engine.resetHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleReset()
            }
        }
    }

    private func handleInterruption() {
        activePlayers.removeAll(keepingCapacity: true)
        oneShotPlayers.removeAll(keepingCapacity: true)
        activeEffects.removeAll(keepingCapacity: true)
        isPrepared = false
        guard !isSuspended else { return }
        lastLifecycleError = .engineInterrupted
    }

    private func handleReset() {
        let retainedEffects = HapticCommandSemantics.effectsRetainedAfterReset(activeEffects)
        let effectsToRestore = Array(retainedEffects.values)
        activePlayers.removeAll(keepingCapacity: true)
        oneShotPlayers.removeAll(keepingCapacity: true)
        activeEffects = retainedEffects
        isPrepared = false
        lastLifecycleError = .engineReset

        do {
            try engine?.start()
            isPrepared = true
            for effect in effectsToRestore {
                activePlayers[effect.id] = try makeAndStartPlayer(pattern: effect.pattern)
            }
            lastLifecycleError = nil
        } catch {
            for player in activePlayers.values {
                try? player.stop(atTime: CHHapticTimeImmediate)
            }
            activePlayers.removeAll(keepingCapacity: true)
            activeEffects.removeAll(keepingCapacity: true)
            isPrepared = false
            lastLifecycleError = .enginePreparationFailed
        }
    }

    private func playOneShot(pattern: HapticPattern, channel: HapticChannel) throws {
        let player = try makePlayer(pattern: pattern)
        precondition(nextOneShotID < .max, "CoreHapticRenderer one-shot ID overflow")
        nextOneShotID += 1
        let identifier = nextOneShotID
        player.completionHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.oneShotPlayers.removeValue(forKey: identifier)
            }
        }
        oneShotPlayers[identifier] = OneShotPlayer(channel: channel, player: player)
        do {
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            oneShotPlayers.removeValue(forKey: identifier)
            throw HapticError.playerStartFailed
        }
    }

    private func makeAndStartPlayer(
        pattern descriptor: HapticPattern
    ) throws -> CHHapticAdvancedPatternPlayer {
        let player = try makePlayer(pattern: descriptor)
        do {
            try player.start(atTime: CHHapticTimeImmediate)
            return player
        } catch {
            throw HapticError.playerStartFailed
        }
    }

    private func makePlayer(
        pattern descriptor: HapticPattern
    ) throws -> CHHapticAdvancedPatternPlayer {
        guard let engine else {
            throw HapticError.invalidLifecycleState
        }

        let pattern = try makeCorePattern(descriptor)
        let player: CHHapticAdvancedPatternPlayer
        do {
            player = try engine.makeAdvancedPlayer(with: pattern)
        } catch {
            throw HapticError.playerCreationFailed
        }

        if case let .loop(period) = descriptor.looping {
            player.loopEnabled = true
            player.loopEnd = period.timeInterval
        }
        return player
    }

    private func stopEffect(_ id: HapticEffectID) throws {
        guard let player = activePlayers[id] else {
            return
        }
        do {
            try player.stop(atTime: CHHapticTimeImmediate)
            activePlayers.removeValue(forKey: id)
        } catch {
            throw HapticError.playerStopFailed
        }
    }

    private func stopChannel(_ channel: HapticChannel) throws {
        let effectIDs = activeEffects.values
            .filter { $0.channel == channel }
            .map(\.id)
        for id in effectIDs {
            try stopEffect(id)
        }

        let oneShotIDs = oneShotPlayers
            .filter { $0.value.channel == channel }
            .map(\.key)
        for id in oneShotIDs {
            guard let record = oneShotPlayers[id] else { continue }
            do {
                try record.player.stop(atTime: CHHapticTimeImmediate)
                oneShotPlayers.removeValue(forKey: id)
            } catch {
                throw HapticError.playerStopFailed
            }
        }
    }

    private func stopAllPlayers() throws {
        for id in Array(activePlayers.keys) {
            try stopEffect(id)
        }
        for id in Array(oneShotPlayers.keys) {
            guard let record = oneShotPlayers[id] else { continue }
            do {
                try record.player.stop(atTime: CHHapticTimeImmediate)
                oneShotPlayers.removeValue(forKey: id)
            } catch {
                throw HapticError.playerStopFailed
            }
        }
    }

    private func makeCorePattern(_ descriptor: HapticPattern) throws -> CHHapticPattern {
        let events = descriptor.events.map { event -> CHHapticEvent in
            let parameters: [CHHapticEventParameter]
            let eventType: CHHapticEvent.EventType
            let relativeTime: TimeInterval
            let duration: TimeInterval

            switch event {
            case let .transient(at, intensity, sharpness):
                eventType = .hapticTransient
                relativeTime = at.timeInterval
                duration = 0
                parameters = Self.parameters(intensity: intensity, sharpness: sharpness)

            case let .continuous(at, eventDuration, intensity, sharpness):
                eventType = .hapticContinuous
                relativeTime = at.timeInterval
                duration = eventDuration.timeInterval
                parameters = Self.parameters(intensity: intensity, sharpness: sharpness)
            }

            return CHHapticEvent(
                eventType: eventType,
                parameters: parameters,
                relativeTime: relativeTime,
                duration: duration
            )
        }

        let curves = descriptor.curves.map { curve -> CHHapticParameterCurve in
            let parameterID: CHHapticDynamicParameter.ID
            switch curve.parameter {
            case .intensity:
                parameterID = .hapticIntensityControl
            case .sharpness:
                parameterID = .hapticSharpnessControl
            }
            let points = curve.controlPoints.map {
                CHHapticParameterCurve.ControlPoint(
                    relativeTime: $0.at.timeInterval,
                    value: $0.value.rawValue
                )
            }
            return CHHapticParameterCurve(
                parameterID: parameterID,
                controlPoints: points,
                relativeTime: 0
            )
        }

        do {
            return try CHHapticPattern(events: events, parameterCurves: curves)
        } catch {
            throw HapticError.playerCreationFailed
        }
    }

    private static func parameters(
        intensity: HapticValue,
        sharpness: HapticValue
    ) -> [CHHapticEventParameter] {
        [
            CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: intensity.rawValue
            ),
            CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: sharpness.rawValue
            ),
        ]
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}
#else
@MainActor
public final class CoreHapticRenderer: HapticRendering {
    public let capabilities: HapticCapabilities = .unavailable

    public init() {}
    public func prepare() throws { throw HapticError.hapticsUnavailable }
    public func execute(_ command: HapticCommand) throws {
        throw HapticError.hapticsUnavailable
    }
    public func suspend() {}
    public func resume() throws { throw HapticError.hapticsUnavailable }
}
#endif
