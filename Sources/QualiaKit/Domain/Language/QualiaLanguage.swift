/// An opaque, already-resolved language identifier.
///
/// The value is preserved exactly. QualiaKit does not trim, case-fold, or
/// Unicode-normalize it, and equality and hashing are case-sensitive.
public struct QualiaLanguage: Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) throws {
        guard !QualiaDomainValidation.isBlank(rawValue) else {
            throw QualiaError.invalidLanguage
        }
        self.rawValue = rawValue
    }

    init(validatedRawValue rawValue: String) {
        self.rawValue = rawValue
    }
}
