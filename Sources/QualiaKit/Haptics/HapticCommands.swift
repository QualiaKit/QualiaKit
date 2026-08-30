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

/// Stable identity for a long-lived effect.
///
/// A non-nil owner scopes the effect to a session/coordinator. A nil owner is
/// an explicit global scope rather than missing ownership metadata.
public struct HapticEffectID: Hashable, Codable, Sendable {
    public let rawValue: String
    public let owner: HapticOwnerID?

    public init(rawValue: String, owner: HapticOwnerID? = nil) throws {
        guard !rawValue.isBlank else {
            throw HapticError.invalidHapticIdentifier
        }
        self.rawValue = rawValue
        self.owner = owner
    }

    private enum CodingKeys: String, CodingKey {
        case rawValue
        case owner
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            rawValue: container.decode(String.self, forKey: .rawValue),
            owner: container.decodeIfPresent(HapticOwnerID.self, forKey: .owner)
        )
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
