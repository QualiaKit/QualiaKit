import Foundation

@MainActor
package protocol HapticRuntimePlayer: AnyObject, Sendable {
    var completionHandler: (@Sendable () -> Void)? { get set }
    func start() throws
    func stop() throws
}

@MainActor
package protocol HapticRuntimeEngine: AnyObject, Sendable {
    var capabilities: HapticCapabilities { get }
    var stoppedHandler: (@Sendable () -> Void)? { get set }
    var resetHandler: (@Sendable () -> Void)? { get set }

    func start() throws
    func stop() async throws
    func makePlayer(pattern: HapticPattern) throws -> any HapticRuntimePlayer
}

#if canImport(CoreHaptics)
import CoreHaptics

@MainActor
package final class CoreHapticsRuntimeEngine: HapticRuntimeEngine {
    package let capabilities: HapticCapabilities
    package var stoppedHandler: (@Sendable () -> Void)? {
        didSet { installLifecycleHandlers() }
    }
    package var resetHandler: (@Sendable () -> Void)? {
        didSet { installLifecycleHandlers() }
    }

    private var engine: CHHapticEngine?

    package init() {
        let hardware = CHHapticEngine.capabilitiesForHardware()
        let supported = hardware.supportsHaptics
        capabilities = HapticCapabilities(
            supportsHaptics: supported,
            supportsContinuousHaptics: supported,
            supportsParameterCurves: supported
        )
    }

    package func start() throws {
        guard capabilities.supportsHaptics else {
            throw HapticError.hapticsUnavailable
        }

        do {
            if engine == nil {
                let engine = try CHHapticEngine()
                engine.playsHapticsOnly = true
                self.engine = engine
                installLifecycleHandlers()
            }
            guard let engine else {
                throw HapticError.enginePreparationFailed
            }
            try engine.start()
        } catch let error as HapticError {
            throw error
        } catch {
            throw HapticError.enginePreparationFailed
        }
    }

    package func stop() async throws {
        guard let engine else { return }
        let succeeded = await withCheckedContinuation { continuation in
            engine.stop { error in
                continuation.resume(returning: error == nil)
            }
        }
        guard succeeded else {
            throw HapticError.engineStopFailed
        }
    }

    package func makePlayer(pattern: HapticPattern) throws -> any HapticRuntimePlayer {
        guard let engine else {
            throw HapticError.invalidLifecycleState
        }
        let corePattern = try Self.makeCorePattern(pattern)
        do {
            let player = try engine.makeAdvancedPlayer(with: corePattern)
            if case let .loop(period) = pattern.looping {
                player.loopEnabled = true
                player.loopEnd = period.timeInterval
            }
            return CoreHapticsRuntimePlayer(player: player)
        } catch {
            throw HapticError.playerCreationFailed
        }
    }

    private func installLifecycleHandlers() {
        guard let engine else { return }
        let stoppedHandler = stoppedHandler
        let resetHandler = resetHandler
        engine.stoppedHandler = { _ in stoppedHandler?() }
        engine.resetHandler = { resetHandler?() }
    }

    private static func makeCorePattern(_ descriptor: HapticPattern) throws -> CHHapticPattern {
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

@MainActor
private final class CoreHapticsRuntimePlayer: HapticRuntimePlayer {
    var completionHandler: (@Sendable () -> Void)? {
        didSet {
            let completionHandler = completionHandler
            player.completionHandler = { _ in completionHandler?() }
        }
    }

    private let player: CHHapticAdvancedPatternPlayer

    init(player: CHHapticAdvancedPatternPlayer) {
        self.player = player
    }

    func start() throws {
        do {
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            throw HapticError.playerStartFailed
        }
    }

    func stop() throws {
        do {
            try player.stop(atTime: CHHapticTimeImmediate)
        } catch {
            throw HapticError.playerStopFailed
        }
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
package final class CoreHapticsRuntimeEngine: HapticRuntimeEngine {
    package let capabilities: HapticCapabilities = .unavailable
    package var stoppedHandler: (@Sendable () -> Void)?
    package var resetHandler: (@Sendable () -> Void)?

    package init() {}
    package func start() throws { throw HapticError.hapticsUnavailable }
    package func stop() async throws {}
    package func makePlayer(pattern: HapticPattern) throws -> any HapticRuntimePlayer {
        throw HapticError.hapticsUnavailable
    }
}
#endif
