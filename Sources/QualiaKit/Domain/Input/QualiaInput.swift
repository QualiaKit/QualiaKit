public struct QualiaInputID: Hashable, Codable, Sendable {
    /// The exact caller-provided identifier.
    ///
    /// QualiaKit does not trim, case-fold, or Unicode-normalize this value.
    /// Equality and hashing are exact and case-sensitive.
    public let rawValue: String

    public init(rawValue: String) throws {
        guard !QualiaDomainValidation.isBlank(rawValue) else {
            throw QualiaError.invalidInputID
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

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawValue, forKey: .rawValue)
    }
}

public struct QualiaContextFragment: Hashable, Codable, Sendable {
    public let id: QualiaInputID
    /// Sensitive caller text. Its explicit `Codable` conformance must not be
    /// treated as permission to persist or log it without a privacy review.
    public let text: String

    public init(id: QualiaInputID, text: String) {
        self.id = id
        self.text = text
    }
}

public struct QualiaInput: Sendable {
    public let id: QualiaInputID
    public let text: String
    public let context: [QualiaContextFragment]
    public let language: QualiaLanguage?

    public init(
        id: QualiaInputID,
        text: String,
        context: [QualiaContextFragment] = [],
        language: QualiaLanguage? = nil
    ) throws {
        guard !QualiaDomainValidation.isBlank(text) else {
            throw QualiaError.emptyInput
        }
        self.id = id
        self.text = text
        self.context = context
        self.language = language
    }
}
