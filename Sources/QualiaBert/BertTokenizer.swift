import Foundation

public final class BertTokenizer {
    private var vocab: [String: Int] = [:]

    private let unkToken = "[UNK]"
    private let clsToken = "[CLS]"
    private let sepToken = "[SEP]"
    private let padToken = "[PAD]"
    private let wordPiecePrefix = "##"

    private let maxSequenceLength: Int

    private var unknownTokenId: Int = 100
    private var padTokenId: Int = 0

    public init(vocabURL: URL, maxSequenceLength: Int = 128) throws {
        self.maxSequenceLength = maxSequenceLength
        try loadVocabulary(from: vocabURL)
    }

    private func loadVocabulary(from url: URL) throws {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            guard !line.isEmpty else { continue }
            vocab[line] = index
        }

        if let unk = vocab[unkToken] { self.unknownTokenId = unk }
        if let pad = vocab[padToken] { self.padTokenId = pad }

        print("✅ SenseKit: Vocab loaded with \(vocab.count) tokens.")
    }

    private func wordPieceTokenize(word: String) -> [String] {
        if vocab[word] != nil { return [word] }

        var tokens: [String] = []
        var currentWordPart = word

        while !currentWordPart.isEmpty {
            var foundToken: String?
            for i in (1...currentWordPart.count).reversed() {
                let prefix = String(currentWordPart.prefix(i))
                let tokenToFind = tokens.isEmpty ? prefix : "\(wordPiecePrefix)\(prefix)"

                if vocab[tokenToFind] != nil {
                    foundToken = tokenToFind
                    let remainderIndex = currentWordPart.index(
                        currentWordPart.startIndex, offsetBy: i)
                    currentWordPart = String(currentWordPart[remainderIndex...])
                    break
                }
            }

            if let token = foundToken {
                tokens.append(token)
            } else {
                return [unkToken]
            }
        }
        return tokens
    }

    public func tokenize(text: String) -> (inputIds: [Int], attentionMask: [Int]) {
        let normalizedText = text.lowercased()
        let words = normalizedText.components(
            separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        )
        .filter { !$0.isEmpty }

        var inputTokenStrings: [String] = [clsToken]

        for word in words {
            inputTokenStrings.append(contentsOf: wordPieceTokenize(word: word))
        }
        inputTokenStrings.append(sepToken)

        if inputTokenStrings.count > maxSequenceLength {
            inputTokenStrings = Array(inputTokenStrings.prefix(maxSequenceLength - 1))
            inputTokenStrings.append(sepToken)
        }

        var tokens: [Int] = inputTokenStrings.map { vocab[$0] ?? unknownTokenId }
        let tokenCount = tokens.count

        if tokenCount < maxSequenceLength {
            tokens.append(
                contentsOf: Array(repeating: padTokenId, count: maxSequenceLength - tokenCount))
        }

        let attentionMask = (0..<maxSequenceLength).map { $0 < tokenCount ? 1 : 0 }

        return (tokens, attentionMask)
    }
}
