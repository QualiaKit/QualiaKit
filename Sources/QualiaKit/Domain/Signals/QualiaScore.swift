public struct QualiaScore: Hashable, Codable, Sendable {
    /// A finite normalized value in the closed range `0...1`.
    public let value: Float
    /// Analyzer-specific confidence that is not assumed to be calibrated or
    /// directly comparable across analyzer implementations. When present, it
    /// is finite and in the closed range `0...1`.
    public let confidence: Float?

    public init(value: Float, confidence: Float? = nil) throws {
        guard value.isFinite, (0...1).contains(value) else {
            throw QualiaError.invalidScore
        }
        if let confidence {
            guard confidence.isFinite, (0...1).contains(confidence) else {
                throw QualiaError.invalidConfidence
            }
        }
        self.value = value
        self.confidence = confidence
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case confidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            value: container.decode(Float.self, forKey: .value),
            confidence: container.decodeIfPresent(Float.self, forKey: .confidence)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encodeIfPresent(confidence, forKey: .confidence)
    }
}
