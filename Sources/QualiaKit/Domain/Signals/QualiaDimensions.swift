/// Standard dimensions currently understood by the domain capability vocabulary.
public enum QualiaDimension: Hashable, Sendable {
    case valence
}

/// Optional standard dimensions produced for one observation.
public struct QualiaDimensions: Hashable, Sendable {
    /// Normalized valence:
    /// - `0.0`: maximally negative
    /// - `0.5`: neutral
    /// - `1.0`: maximally positive
    /// - `nil`: unsupported or not produced
    public let valence: QualiaScore?

    public init(valence: QualiaScore? = nil) {
        self.valence = valence
    }
}
