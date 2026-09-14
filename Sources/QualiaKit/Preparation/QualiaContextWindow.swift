public struct QualiaContextConfiguration: Hashable, Sendable {
    /// Maximum historical fragments, excluding current text. Zero disables history.
    public let maximumFragments: Int
    /// Sum of Swift Character (extended grapheme cluster) counts across current
    /// text and retained fragments, counted separately without joining them.
    public let maximumCharacters: Int
    /// Sum of exact UTF-8 byte counts, including current text. Nil disables this bound.
    public let maximumUTF8Bytes: Int?

    public init(maximumFragments: Int, maximumCharacters: Int, maximumUTF8Bytes: Int? = nil) throws {
        guard maximumFragments >= 0, maximumCharacters > 0,
              maximumUTF8Bytes.map({ $0 > 0 }) ?? true else {
            throw QualiaError.invalidContextConfiguration
        }
        self.maximumFragments = maximumFragments
        self.maximumCharacters = maximumCharacters
        self.maximumUTF8Bytes = maximumUTF8Bytes
    }
}

public protocol QualiaContextWindowing: Sendable {
    /// Context must be supplied oldest to newest. Preserve current text and IDs.
    func window(_ input: QualiaInput) throws -> QualiaInput
}

/// Stateless, whole-fragment eviction. Retains a contiguous newest suffix of
/// history, never normalizes/slices text, and never approximates model tokens.
public struct QualiaContextWindow: QualiaContextWindowing {
    public let configuration: QualiaContextConfiguration
    private let diagnostics: (@Sendable (QualiaPreparationDiagnostic) -> Void)?

    public init(
        configuration: QualiaContextConfiguration,
        diagnostics: (@Sendable (QualiaPreparationDiagnostic) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.diagnostics = diagnostics
    }

    /// Session adds its sink without discarding a caller's existing callback.
    func recordingDiagnostics(_ additional: (@Sendable (QualiaPreparationDiagnostic) -> Void)?) -> Self {
        guard let additional else { return self }
        return Self(configuration: configuration, diagnostics: { event in
            diagnostics?(event)
            additional(event)
        })
    }

    public func window(_ input: QualiaInput) throws -> QualiaInput {
        let currentCharacters = input.text.count
        let currentBytes = input.text.utf8.count
        var characters = currentCharacters
        var bytes = currentBytes
        let sizes = try input.context.map { fragment in
            let size = (characters: fragment.text.count, bytes: fragment.text.utf8.count)
            characters = try adding(characters, size.characters)
            bytes = try adding(bytes, size.bytes)
            return size
        }
        let before = QualiaPreparationDiagnostic.Counts(
            fragments: input.context.count, characters: characters, utf8Bytes: bytes
        )
        guard fits(characters: currentCharacters, bytes: currentBytes) else {
            // No prepared input is produced; report unchanged counts, not a
            // fictitious successful window containing an oversized current text.
            diagnostics?(.context(before: before, after: before, outcome: .currentTextTooLarge))
            throw QualiaError.currentTextExceedsContextBounds
        }

        var start = 0
        while input.context.count - start > configuration.maximumFragments
            || !fits(characters: characters, bytes: bytes) {
            characters -= sizes[start].characters
            bytes -= sizes[start].bytes
            start += 1
        }
        let result = try QualiaInput(
            id: input.id, text: input.text,
            context: Array(input.context.dropFirst(start)), language: input.language
        )
        diagnostics?(.context(
            before: before,
            after: .init(fragments: result.context.count, characters: characters, utf8Bytes: bytes),
            outcome: start == 0 ? .unchanged : .trimmed
        ))
        return result
    }

    private func fits(characters: Int, bytes: Int) -> Bool {
        characters <= configuration.maximumCharacters
            && bytes <= (configuration.maximumUTF8Bytes ?? Int.max)
    }

    private func adding(_ left: Int, _ right: Int) throws -> Int {
        let (sum, overflow) = left.addingReportingOverflow(right)
        guard !overflow else { throw QualiaError.contextSizeOverflow }
        return sum
    }
}
