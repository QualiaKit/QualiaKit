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
    /// The renderer's post-command long-lived state.
    ///
    /// Callers use this snapshot to reconcile policy state when `execute(_:)`
    /// throws after partially changing physical playback.
    var activeEffects: [HapticEffectID: HapticActiveEffect] { get }
    func prepare() throws
    func execute(_ command: HapticCommand) throws
    /// Session envelope. One-shots must retain this owner through completion
    /// and failed rollback so stopEffects(ownedBy:) can clean up every player.
    func execute(_ command: HapticCommand, ownedBy owner: HapticOwnerID) throws
    /// Stops this owner's active effects and any players retained after failed
    /// rollback, even if they are absent from activeEffects. Must throw while
    /// any owned cleanup remains incomplete; must not stop another owner.
    func stopEffects(ownedBy owner: HapticOwnerID) throws
    func suspend() async
    func resume() async throws
}

public extension HapticRendering {
    /// Older custom renderers remain usable for owned ambient commands. They
    /// must implement the envelope before accepting session-owned one-shots.
    func execute(_ command: HapticCommand, ownedBy owner: HapticOwnerID) throws {
        try HapticCommandSemantics.validateOwnership(command, owner: owner)
        if case .play = command { throw HapticError.ownershipConflict }
        try execute(command)
    }
}

/// An explicitly selected no-op renderer. It advertises no physical support
/// and performs no fallback vibration.
@MainActor
public final class NoOpHapticRenderer: HapticRendering {
    public let capabilities: HapticCapabilities = .unavailable
    public let activeEffects: [HapticEffectID: HapticActiveEffect] = [:]

    public init() {}

    public func prepare() throws {}
    public func execute(_ command: HapticCommand) throws {}
    public func execute(_ command: HapticCommand, ownedBy owner: HapticOwnerID) throws {
        try HapticCommandSemantics.validateOwnership(command, owner: owner)
    }
    public func stopEffects(ownedBy owner: HapticOwnerID) throws {}
    public func suspend() async {}
    public func resume() async throws {}
}

package enum HapticCommandSemantics {
    package static func validateOwnership(_ command: HapticCommand, owner: HapticOwnerID) throws {
        switch command {
        case let .start(id, _, _), let .replace(id, _, _), let .stop(id):
            guard id.scope == .owned(owner) else { throw HapticError.ownershipConflict }
        case let .play(_, channel):
            guard channel == .accent else { throw HapticError.ownershipConflict }
        case .stopAll, .stopChannel:
            throw HapticError.ownershipConflict
        }
    }
    package static func effectsRetainedAfterReset(
        _ activeEffects: [HapticEffectID: HapticActiveEffect]
    ) -> [HapticEffectID: HapticActiveEffect] {
        activeEffects.filter { $0.key.scope == .global && $0.value.pattern.playbackDuration == nil }
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
