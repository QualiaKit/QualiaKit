public struct HapticCapabilities: Hashable, Sendable {
    public let supportsHaptics: Bool
    public let supportsContinuousHaptics: Bool
    public let supportsParameterCurves: Bool

    public init(
        supportsHaptics: Bool,
        supportsContinuousHaptics: Bool,
        supportsParameterCurves: Bool
    ) {
        self.supportsHaptics = supportsHaptics
        self.supportsContinuousHaptics = supportsContinuousHaptics
        self.supportsParameterCurves = supportsParameterCurves
    }

    public static let unavailable = Self(
        supportsHaptics: false,
        supportsContinuousHaptics: false,
        supportsParameterCurves: false
    )

    public static let full = Self(
        supportsHaptics: true,
        supportsContinuousHaptics: true,
        supportsParameterCurves: true
    )
}

@MainActor
public protocol HapticRendering: AnyObject {
    var capabilities: HapticCapabilities { get }
    func prepare() throws
    func execute(_ command: HapticCommand) throws
    func suspend() async
    func resume() async throws
}

/// An explicitly selected no-op renderer. It advertises no physical support
/// and performs no fallback vibration.
@MainActor
public final class NoOpHapticRenderer: HapticRendering {
    public let capabilities: HapticCapabilities = .unavailable

    public init() {}

    public func prepare() throws {}
    public func execute(_ command: HapticCommand) throws {}
    public func suspend() async {}
    public func resume() async throws {}
}

package enum HapticCommandSemantics {
    package static func effectsRetainedAfterReset(
        _ activeEffects: [HapticEffectID: HapticActiveEffect]
    ) -> [HapticEffectID: HapticActiveEffect] {
        activeEffects.filter { $0.key.scope == .global }
    }

    package static func nextActiveEffects(
        after command: HapticCommand,
        current: [HapticEffectID: HapticActiveEffect],
        capabilities: HapticCapabilities
    ) throws -> [HapticEffectID: HapticActiveEffect] {
        var active = current

        switch command {
        case let .play(pattern, channel):
            try validate(pattern: pattern, capabilities: capabilities)
            guard case .none = pattern.looping else {
                throw HapticError.invalidCommand
            }
            _ = channel

        case let .start(id, pattern, channel):
            try validateLongLived(pattern: pattern, channel: channel, capabilities: capabilities)
            if active[id] == nil {
                active[id] = HapticActiveEffect(id: id, pattern: pattern, channel: channel)
            }

        case let .replace(id, pattern, channel):
            try validateLongLived(pattern: pattern, channel: channel, capabilities: capabilities)
            guard active[id] != nil else {
                throw HapticError.invalidLifecycleState
            }
            active[id] = HapticActiveEffect(id: id, pattern: pattern, channel: channel)

        case let .stop(id):
            active.removeValue(forKey: id)

        case let .stopChannel(channel):
            active = active.filter { $0.value.channel != channel }

        case .stopAll:
            active.removeAll(keepingCapacity: true)
        }

        return active
    }

    package static func validate(
        pattern: HapticPattern,
        capabilities: HapticCapabilities
    ) throws {
        guard capabilities.supportsHaptics else {
            throw HapticError.hapticsUnavailable
        }
        if pattern.requiresContinuousHaptics,
           !capabilities.supportsContinuousHaptics {
            throw HapticError.unsupportedFeature(.continuousHaptics)
        }
        if !pattern.curves.isEmpty,
           !capabilities.supportsParameterCurves {
            throw HapticError.unsupportedFeature(.parameterCurves)
        }
    }

    private static func validateLongLived(
        pattern: HapticPattern,
        channel: HapticChannel,
        capabilities: HapticCapabilities
    ) throws {
        try validate(pattern: pattern, capabilities: capabilities)
        guard channel == .ambient,
              case .loop = pattern.looping else {
            throw HapticError.invalidCommand
        }
    }
}
