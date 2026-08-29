/// An opaque, already-resolved language identifier.
///
/// Language identifiers use case-insensitive canonical semantics. QualiaKit
/// lowercases valid values without trimming or Unicode normalization, so `ru`
/// and `RU` compare and hash equally. Other language resolution occurs before
/// construction.
public struct QualiaLanguage: Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) throws {
        guard !QualiaDomainValidation.isBlank(rawValue) else {
            throw QualiaError.invalidLanguage
        }
        self.rawValue = rawValue.lowercased()
    }
}
