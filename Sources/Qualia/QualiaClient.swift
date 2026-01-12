import Foundation
import NaturalLanguage

/// Main client for Qualia sentiment analysis and haptic feedback
///
/// QualiaClient analyzes text for emotional content and optionally triggers haptic feedback.
///
/// ## Usage
/// ```swift
/// // Default (NLTagger):
/// let client = QualiaClient()
///
/// // Custom provider:
/// let client = QualiaClient(provider: CustomProvider())
///
/// // Analysis with automatic haptics
/// let (emotion, score) = await client.analyzeAndFeel("I'm so happy!")
///
/// // Analysis without haptics
/// let (emotion, score) = await client.analyze("I'm so happy!")
///
/// // Explicit haptic triggering
/// await client.feel(.positive)
/// ```
public class QualiaClient {
    private let provider: SentimentProvider
    private let haptics: HapticEngine
    private let languageRecognizer = NLLanguageRecognizer()
    private let config: QualiaConfiguration

    /// Creates a new QualiaClient with default NLTagger provider
    ///
    /// - Parameter config: Configuration for haptic behavior. Default: `.standard`
    public init(config: QualiaConfiguration = .standard) {
        self.provider = NLTaggerProvider()
        self.haptics = HapticEngine.shared
        self.config = config
    }

    /// Creates a new QualiaClient with custom sentiment provider
    ///
    /// Use this initializer to inject heavy-duty providers like BertProvider.
    ///
    /// - Parameters:
    ///   - provider: Custom sentiment analysis provider
    ///   - config: Configuration for haptic behavior. Default: `.standard`
    public init(provider: SentimentProvider, config: QualiaConfiguration = .standard) {
        self.provider = provider
        self.haptics = HapticEngine.shared
        self.config = config
    }

    /// Analyzes text for emotional content without triggering haptics
    ///
    /// Use this method when you want pure sentiment analysis without haptic feedback.
    ///
    /// - Parameter text: Text to analyze
    /// - Returns: Tuple of detected emotion and sentiment score
    public func analyze(_ text: String) async -> (SenseEmotion, Double) {
        return await performAnalysis(text)
    }

    /// Analyzes text and plays haptic feedback if configured
    ///
    /// Performs sentiment analysis and automatically triggers haptic feedback
    /// if `config.autoPlayHaptics` is `true`.
    ///
    /// - Parameter text: Text to analyze
    /// - Returns: Tuple of detected emotion and sentiment score
    public func analyzeAndFeel(_ text: String) async -> (SenseEmotion, Double) {
        let (emotion, score) = await performAnalysis(text)

        // Play haptics if configured
        if config.autoPlayHaptics {
            await playHapticFeedback(for: emotion)
        }

        return (emotion, score)
    }

    /// Explicitly triggers haptic feedback for a given emotion
    ///
    /// Use this method when you want manual control over haptic feedback,
    /// regardless of configuration settings.
    ///
    /// - Parameter emotion: The emotion to play haptic feedback for
    @MainActor
    public func feel(_ emotion: SenseEmotion) {
        playHapticFeedback(for: emotion)
    }

    // MARK: - Private Methods

    /// Performs sentiment analysis on text
    ///
    /// Common logic extracted from `analyze()` and `analyzeAndFeel()`.
    ///
    /// - Parameter text: Text to analyze
    /// - Returns: Tuple of detected emotion and sentiment score
    private func performAnalysis(_ text: String) async -> (SenseEmotion, Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        // WORKAROUND: Stop-words filter
        // NLTagger returns false negative (-0.6) for grammatical words without semantic meaning
        // These should remain neutral until user types something meaningful
        if Self.stopWords.contains(lowercased) {
            return (.neutral, 0.0)
        }

        // WORKAROUND: Double negation filter
        // NLTagger incorrectly classifies phrases like "not bad" as negative
        // Double negations should be interpreted as positive
        if Self.positiveNegations.contains(where: { lowercased.contains($0) }) {
            return (.positive, 0.5)
        }

        // Check for intense keywords
        if config.intenseKeywords.contains(where: { lowercased.contains($0) }) {
            return (.intense, 0.0)
        }

        // Check for mysterious keywords
        if config.mysteriousKeywords.contains(where: { lowercased.contains($0) }) {
            return (.mysterious, 0.0)
        }

        // Calculate sentiment score using provider
        let score = await calculateSentimentScore(text)

        // Map score to emotion
        var emotion: SenseEmotion = .neutral
        if score > 0.2 { emotion = .positive } else if score < -0.2 { emotion = .negative }

        return (emotion, score)
    }

    // MARK: - NLTagger Workarounds

    /// Stop-words that should always return neutral sentiment
    ///
    /// NLTagger incorrectly assigns negative sentiment to grammatical words.
    /// These words have no semantic emotional content and should be neutral.
    private static let stopWords: Set<String> = [
        // Articles
        "a", "an", "the",
        // Demonstratives
        "this", "that", "these", "those",
        // Pronouns
        "it", "its", "i", "me", "my", "you", "your",
        "he", "she", "we", "they",
        // Auxiliary verbs
        "is", "am", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did",
        "will", "would", "should", "could", "may", "might", "can",
        // Prepositions
        "of", "in", "on", "at", "to", "for", "with", "from", "by", "about", "as", "into",
    ]

    /// Double negation phrases that should return positive sentiment
    ///
    /// NLTagger fails to understand double negation logic.
    /// These phrases contain negative words but express positive meaning.
    private static let positiveNegations: [String] = [
        "not bad", "not terrible", "not awful", "not horrible",
        "not wrong", "not poor", "not weak", "not worse",
    ]

    /// Plays haptic feedback for the given emotion
    ///
    /// Respects configuration settings for delay and heartbeat.
    ///
    /// - Parameter emotion: The emotion to play haptic feedback for
    @MainActor
    private func playHapticFeedback(for emotion: SenseEmotion) {
        // Apply intensity from config
        haptics.baseIntensity = config.hapticIntensity

        // Apply delay if configured
        if config.hapticDelay > 0 {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(config.hapticDelay * 1_000_000_000))
                haptics.play(for: emotion)
            }
        } else {
            haptics.play(for: emotion)
        }

        // Handle heartbeat for intense emotions
        if config.enableHeartbeat {
            haptics.updateHeartbeat(shouldPlay: emotion == .intense)
        }
    }

    private func calculateSentimentScore(_ text: String) async -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0.0 }

        languageRecognizer.reset()
        languageRecognizer.processString(trimmed)
        let language = languageRecognizer.dominantLanguage ?? .english

        do {
            return try await provider.analyzeSentiment(trimmed, language: language)
        } catch {
            print("Qualia Sentiment Error: \(error)")
            return 0.0
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
