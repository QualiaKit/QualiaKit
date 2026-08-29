/// Standard dimensions currently understood by the domain capability vocabulary.
public enum QualiaDimension: Hashable, Sendable {
    case valence
}

/// Optional standard dimensions produced for one observation.
public struct QualiaDimensions: Hashable, Sendable {
    /// Normalized valence where `0` is negative, `0.5` is neutral, and `1` is
    /// positive. `nil` means missing or unsupported.
    public let valence: QualiaScore?

    public init(valence: QualiaScore? = nil) {
        self.valence = valence
    }
}
