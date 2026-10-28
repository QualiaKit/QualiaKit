import Foundation

struct BertPreparedText: Sendable, Equatable {
    let ids: [Int]
    let mask: [Int]
    let types: [Int]
    let tokenCount: Int
}

/// Standard BERT BasicTokenizer + greedy WordPiece. Settings and special IDs
/// come from the external model contract, never from a particular application.
struct BertWordPieceTokenizer: Sendable {
    let configuration: BertTokenizerConfiguration
    private let vocabulary: [Data: Int]
    private let special: [(scalars: [Unicode.Scalar], id: Int)]

    init(configuration: BertTokenizerConfiguration, data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else { throw CoreMLRuntimeError.invalidVocabulary }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let keys = lines.map { Data($0.utf8) }
        guard keys.count == configuration.vocabularyLineCount, Set(keys).count == keys.count,
              !lines.contains(where: { $0.isEmpty || $0.contains("\r") }),
              Set(configuration.specialTokens.values.map(\.id)).count == configuration.specialTokens.count else {
            throw CoreMLRuntimeError.invalidVocabulary
        }
        for token in configuration.specialTokens.values {
            guard keys.indices.contains(token.id), keys[token.id] == Data(token.token.utf8) else {
                throw CoreMLRuntimeError.invalidVocabulary
            }
        }
        self.configuration = configuration
        vocabulary = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($1, $0) })
        special = configuration.specialTokens.values.map { (Array($0.token.unicodeScalars), $0.id) }
            .sorted { $0.0.count > $1.0.count }
    }

    func prepare(text: String, context: [String], sequence: BertModelManifest.Sequence) throws -> BertPreparedText {
        try Task.checkCancellation()
        guard !text.isBlank, let cls = configuration.specialTokens["cls"]?.id,
              let sep = configuration.specialTokens["sep"]?.id,
              let pad = configuration.specialTokens["pad"]?.id else { throw CoreMLRuntimeError.inputPreparationFailed }
        let pair = sequence.template == "contextThenText"
        guard pair || context.isEmpty else { throw CoreMLRuntimeError.inputPreparationFailed }
        let first = try encode(pair ? context.joined(separator: sequence.contextSeparator) : text)
        var ids = [cls] + first + [sep]
        var types = Array(repeating: 0, count: ids.count)
        if pair {
            let second = try encode(text)
            ids += second + [sep]
            types += Array(repeating: 1, count: second.count + 1)
        }
        guard ids.count <= sequence.maximumLength else { throw CoreMLRuntimeError.inputPreparationFailed }
        let count = ids.count
        let padding = sequence.maximumLength - count
        ids += Array(repeating: pad, count: padding)
        types += Array(repeating: 0, count: padding)
        return BertPreparedText(ids: ids, mask: Array(repeating: 1, count: count) + Array(repeating: 0, count: padding),
                                types: types, tokenCount: count)
    }

    func encode(_ text: String) throws -> [Int] {
        // Added special tokens are recognized before normalization, including
        // adjacent tokens. Matching scalar bytes avoids canonical equivalence.
        let scalars = Array(text.unicodeScalars)
        var plain: [Unicode.Scalar] = []
        var result: [Int] = []
        var offset = 0
        while offset < scalars.count {
            try Task.checkCancellation()
            if let token = special.first(where: {
                offset + $0.scalars.count <= scalars.count &&
                    scalars[offset..<(offset + $0.scalars.count)].elementsEqual($0.scalars)
            }) {
                result += try encodePlain(plain)
                plain.removeAll(keepingCapacity: true)
                result.append(token.id)
                offset += token.scalars.count
            } else {
                plain.append(scalars[offset])
                offset += 1
            }
        }
        result += try encodePlain(plain)
        return result
    }

    private func encodePlain(_ source: [Unicode.Scalar]) throws -> [Int] {
        var cleaned: [Unicode.Scalar] = []
        for scalar in source {
            if configuration.cleanText {
                if scalar.value == 0 || scalar.value == 0xfffd || Self.isControl(scalar) { continue }
                if Self.isBertWhitespace(scalar) { cleaned.append(" "); continue }
            }
            if configuration.tokenizeChineseCharacters && Self.isChinese(scalar) {
                cleaned += [" ", scalar, " "]
            } else { cleaned.append(scalar) }
        }
        var normalized = String(String.UnicodeScalarView(cleaned))
        if configuration.lowercase {
            // Hugging Face's BERT normalizer lowercases each scalar; whole-string
            // lowercasing can instead apply contextual Greek final-sigma rules.
            normalized = normalized.unicodeScalars.map { String($0).lowercased() }.joined()
        }
        if configuration.stripAccents {
            normalized = String(String.UnicodeScalarView(normalized.decomposedStringWithCanonicalMapping.unicodeScalars.filter {
                $0.properties.generalCategory != .nonspacingMark
            }))
        }
        var words: [[Unicode.Scalar]] = []
        var word: [Unicode.Scalar] = []
        for scalar in normalized.unicodeScalars {
            if scalar.properties.isWhitespace || Self.isPunctuation(scalar) {
                if !word.isEmpty { words.append(word); word.removeAll(keepingCapacity: true) }
                if !scalar.properties.isWhitespace { words.append([scalar]) }
            } else { word.append(scalar) }
        }
        if !word.isEmpty { words.append(word) }
        guard let unk = configuration.specialTokens["unk"]?.id else { throw CoreMLRuntimeError.invalidVocabulary }
        var result: [Int] = []
        for word in words {
            try Task.checkCancellation()
            guard word.count <= configuration.maximumWordCharacters else { result.append(unk); continue }
            var pieces: [Int] = []
            var start = 0
            while start < word.count {
                var end = word.count
                var found: Int?
                while end > start {
                    let piece = (start == 0 ? "" : configuration.continuingSubwordPrefix) +
                        String(String.UnicodeScalarView(word[start..<end]))
                    if let id = vocabulary[Data(piece.utf8)] { found = id; break }
                    end -= 1
                }
                guard let found else { pieces = [unk]; break }
                pieces.append(found)
                start = end
            }
            result += pieces
        }
        return result
    }

    private static func isBertWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace
    }
    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        if [9, 10, 13].contains(scalar.value) { return false }
        switch scalar.properties.generalCategory {
        case .control, .format, .privateUse, .surrogate: return true
        default: return false
        }
    }
    private static func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        let n = scalar.value
        if (33...47).contains(n) || (58...64).contains(n) || (91...96).contains(n) || (123...126).contains(n) { return true }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation: return true
        default: return false
        }
    }
    private static func isChinese(_ scalar: Unicode.Scalar) -> Bool {
        let n = scalar.value
        return (0x4e00...0x9fff).contains(n) || (0x3400...0x4dbf).contains(n) ||
            (0x20000...0x2a6df).contains(n) || (0x2a700...0x2b73f).contains(n) ||
            (0x2b740...0x2b81f).contains(n) || (0x2b820...0x2ceaf).contains(n) ||
            (0xf900...0xfaff).contains(n) || (0x2f800...0x2fa1f).contains(n)
    }
}
