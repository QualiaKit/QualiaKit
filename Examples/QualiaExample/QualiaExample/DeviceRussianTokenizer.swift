#if QUALIA_DEVICE_EVALUATION
import Foundation

/// Lab-only implementation of the recovered Hugging Face BertTokenizer settings.
/// Unicode scalars (Python code points), BasicTokenizer, then greedy WordPiece.
struct DeviceRussianTokenizer: Sendable {
    struct Encoding: Sendable {
        let inputIds: [Int]
        let attentionMask: [Int]
        let tokenTypeIds: [Int]
        let truncated: Bool
    }
    private let vocabulary: [String: Int]
    private static let specials = ["[UNK]", "[SEP]", "[PAD]", "[CLS]", "[MASK]"]
    init(vocabURL: URL) throws {
        let text = try String(contentsOf: vocabURL, encoding: .utf8)
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        guard lines.count == 119547, Set(lines).count == lines.count,
              lines[0] == "[PAD]", lines[100] == "[UNK]", lines[101] == "[CLS]",
              lines[102] == "[SEP]", lines[103] == "[MASK]" else { throw TokenizerError.vocabulary }
        vocabulary = Dictionary(uniqueKeysWithValues: lines.enumerated().map { ($1, $0) })
    }
    enum TokenizerError: Error { case vocabulary, inputTooLong }

    func encode(_ text: String) throws -> Encoding {
        guard text.utf8.count <= 65536 else { throw TokenizerError.inputTooLong }
        var pieces: [String] = []
        // The source tokenizer isolates literal special tokens before basic tokenization.
        var remainder = text[...]
        while !remainder.isEmpty {
            let next = Self.specials.compactMap { token in remainder.range(of: token).map { ($0, token) } }
                .min { $0.0.lowerBound < $1.0.lowerBound }
            if let (range, token) = next {
                pieces += basic(String(remainder[..<range.lowerBound])).flatMap(wordPiece)
                pieces.append(token)
                remainder = remainder[range.upperBound...]
            } else {
                pieces += basic(String(remainder)).flatMap(wordPiece)
                break
            }
        }
        let truncated = pieces.count > 126
        let content = Array(pieces.prefix(126)).map { vocabulary[$0] ?? 100 }
        var ids = [101] + content + [102]
        let count = ids.count
        ids += Array(repeating: 0, count: 128 - count)
        return Encoding(inputIds: ids, attentionMask: (0..<128).map { $0 < count ? 1 : 0 },
                        tokenTypeIds: Array(repeating: 0, count: 128), truncated: truncated)
    }
    private func basic(_ text: String) -> [String] {
        var clean = String.UnicodeScalarView()
        for s in text.unicodeScalars {
            if s.value == 0 || s.value == 0xfffd { continue }
            if Self.whitespace(s) { clean.append(" "); continue }
            if [.control, .format].contains(s.properties.generalCategory) { continue }
            if Self.chinese(s.value) { clean.append(" "); clean.append(s); clean.append(" ") }
            else { clean.append(s) }
        }
        let normalized = String(clean).precomposedStringWithCanonicalMapping
        var output: [String] = []
        for word in normalized.split(whereSeparator: { $0.isWhitespace }) {
            let lower = String(word).lowercased().decomposedStringWithCanonicalMapping
            var buffer = ""
            for scalar in lower.unicodeScalars where scalar.properties.generalCategory != .nonspacingMark {
                if Self.punctuation(scalar) {
                    if !buffer.isEmpty { output.append(buffer); buffer = "" }
                    output.append(String(scalar))
                } else { buffer.unicodeScalars.append(scalar) }
            }
            if !buffer.isEmpty { output.append(buffer) }
        }
        return output
    }
    private func wordPiece(_ word: String) -> [String] {
        let scalars = Array(word.unicodeScalars)
        guard scalars.count <= 100 else { return ["[UNK]"] }
        var output: [String] = []; var start = 0
        while start < scalars.count {
            var end = scalars.count; var match: String?
            while end > start {
                let token = (start > 0 ? "##" : "") + String(String.UnicodeScalarView(scalars[start..<end]))
                if vocabulary[token] != nil { match = token; break }
                end -= 1
            }
            guard let match else { return ["[UNK]"] }
            output.append(match); start = end
        }
        return output
    }
    private static func whitespace(_ s: Unicode.Scalar) -> Bool {
        [9, 10, 13, 32].contains(s.value) || s.properties.generalCategory == .spaceSeparator
    }
    private static func punctuation(_ s: Unicode.Scalar) -> Bool {
        let n = s.value
        return (33...47).contains(n) || (58...64).contains(n) || (91...96).contains(n) || (123...126).contains(n)
            || [.connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                .initialPunctuation, .finalPunctuation, .otherPunctuation].contains(s.properties.generalCategory)
    }
    private static func chinese(_ n: UInt32) -> Bool {
        [(0x4e00,0x9fff),(0x3400,0x4dbf),(0x20000,0x2a6df),(0x2a700,0x2b73f),
         (0x2b740,0x2b81f),(0x2b820,0x2ceaf),(0xf900,0xfaff),(0x2f800,0x2fa1f)].contains { n >= $0.0 && n <= $0.1 }
    }
}
#endif
