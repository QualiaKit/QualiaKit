import Foundation
import NaturalLanguage

public class QualiaClient {
    private let tokenizer: BertTokenizer
    private let modelWrapper: BertModelWrapper
    private let haptics: HapticEngine
    private let languageRecognizer = NLLanguageRecognizer()
    private let appleTagger = NLTagger(tagSchemes: [.sentimentScore])

    public var intenseKeywords: [String] = [
        "кровь", "уби", "смерт", "атак", "выстрел", "беги", "rage", "blood", "kill", "death", "run",
        "shoot", "attack",
    ]
    public var mysteriousKeywords: [String] = [
        "тайна", "шепот", "лес", "внезапно", "темнота", "mystery", "shadow", "secret",
    ]

    public init(vocabURL: URL, modelURL: URL) throws {
        self.tokenizer = try BertTokenizer(vocabURL: vocabURL)
        self.modelWrapper = try BertModelWrapper(modelURL: modelURL)
        self.haptics = HapticEngine.shared
    }

    public func analyzeAndFeel(_ text: String) async -> (SenseEmotion, Double) {
        let lowercased = text.lowercased()

        if intenseKeywords.contains(where: { lowercased.contains($0) }) {
            return (.intense, 0.0)
        }

        if mysteriousKeywords.contains(where: { lowercased.contains($0) }) {
            return (.mysterious, 0.0)
        }

        let score = await calculateSentimentScore(text)

        var emotion: SenseEmotion = .neutral
        if score > 0.2 { emotion = .positive } else if score < -0.2 { emotion = .negative }

        return (emotion, score)
    }

    private func calculateSentimentScore(_ text: String) async -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0.0 }

        languageRecognizer.reset()
        languageRecognizer.processString(trimmed)
        let language = languageRecognizer.dominantLanguage ?? .english

        if language == .russian {
            let (ids, mask) = tokenizer.tokenize(text: trimmed)
            do {
                return try modelWrapper.predictSentiment(inputIds: ids, attentionMask: mask)
            } catch {
                print("SenseKit ML Error: \(error)")
                return 0.0
            }
        } else {
            appleTagger.string = trimmed
            let (sentiment, _) = appleTagger.tag(
                at: trimmed.startIndex, unit: .paragraph, scheme: .sentimentScore)
            let rawScore = Double(sentiment?.rawValue ?? "0.0") ?? 0.0
            return tanh(rawScore * 1.5)
        }
    }

    public func textContainsConcept(_ text: String, keyword: String) -> Bool {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        var found = false
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma) {
            tag, _ in
            if let lemma = tag?.rawValue.lowercased(), lemma == keyword.lowercased() {
                found = true
                return false
            }
            return true
        }
        return found
    }
}
