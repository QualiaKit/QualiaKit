/// An owner for session-scoped long-lived effects.
public struct HapticOwnerID: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) throws {
        guard !rawValue.isBlank else {
            throw HapticError.invalidHapticIdentifier
        }
        self.rawValue = rawValue
    }

    private enum CodingKeys: String, CodingKey {
        case rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(rawValue: container.decode(String.self, forKey: .rawValue))
    }
}

/// Mandatory ownership scope for a long-lived effect.
public enum HapticEffectScope: Hashable, Codable, Sendable {
    case owned(HapticOwnerID)
    case global
}

/// Stable identity for a long-lived effect. Callers must deliberately choose
/// either a session/coordinator owner or the explicit global scope.
public struct HapticEffectID: Hashable, Codable, Sendable {
    public let rawValue: String
    public let scope: HapticEffectScope

    public init(rawValue: String, scope: HapticEffectScope) throws {
        guard !rawValue.isBlank else {
            throw HapticError.invalidHapticIdentifier
        }
        self.rawValue = rawValue
        self.scope = scope
    }

    private enum CodingKeys: String, CodingKey {
        case rawValue
        case scope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            rawValue: container.decode(String.self, forKey: .rawValue),
            scope: container.decode(HapticEffectScope.self, forKey: .scope)
        )
    }

    package var orderingKey: (scope: Int, owner: String, rawValue: String) {
        switch scope {
        case let .owned(owner):
            return (1, owner.rawValue, rawValue)
        case .global:
            return (0, "", rawValue)
        }
    }
}

public enum HapticChannel: Hashable, Codable, Sendable {
    case ambient
    case accent
}

/// Declarative physical playback commands with no semantic signal knowledge.
public enum HapticCommand: Hashable, Sendable {
    case play(pattern: HapticPattern, channel: HapticChannel)
    case start(id: HapticEffectID, pattern: HapticPattern, channel: HapticChannel)
    case replace(id: HapticEffectID, pattern: HapticPattern, channel: HapticChannel)
    case stop(id: HapticEffectID)
    case stopChannel(HapticChannel)
    case stopAll
}

/// One currently active long-lived effect.
public struct HapticActiveEffect: Hashable, Sendable {
    public let id: HapticEffectID
    public let pattern: HapticPattern
    public let channel: HapticChannel

    public init(id: HapticEffectID, pattern: HapticPattern, channel: HapticChannel) {
        self.id = id
        self.pattern = pattern
        self.channel = channel
    }
}

private extension String {
    var isBlank: Bool {
        isEmpty || allSatisfy(\.isWhitespace)
    }
}
