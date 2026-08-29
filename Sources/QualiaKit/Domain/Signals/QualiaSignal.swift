public struct QualiaSignal: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    /// The exact signal identifier supplied by the caller.
    ///
    /// Equality and hashing are case-sensitive. Custom analyzers should use
    /// reverse-DNS namespacing, but QualiaKit does not enforce a naming scheme.
    /// Model adapters must map raw model labels to semantic identifiers before
    /// constructing product-facing observations; this generic type cannot infer
    /// whether an arbitrary identifier originated as a model label.
    public let rawValue: String

    public init(rawValue: String) throws {
        guard !QualiaDomainValidation.isBlank(rawValue) else {
            throw QualiaError.invalidSignal
        }
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        precondition(
            !QualiaDomainValidation.isBlank(value),
            "QualiaSignal string literals must not be empty or whitespace-only"
        )
        self.rawValue = value
    }

    public static let suspense: Self = "suspense"
    public static let threat: Self = "threat"
    public static let impact: Self = "impact"

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
