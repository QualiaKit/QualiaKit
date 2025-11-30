import Foundation
import NaturalLanguage

/// Lightweight sentiment provider using iOS built-in NLTagger
///
/// This is the default provider for Qualia, requiring zero additional
/// dependencies or model files. Works with all languages supported by
/// Apple's Natural Language framework.
///
/// ## Performance
/// - Bundle size: 0 bytes additional
/// - Accuracy: Good for English, acceptable for other languages
/// - Languages: 50+ languages supported
public struct NLTaggerProvider: SentimentProvider {
    /// Creates a new NLTagger-based sentiment provider
    public init() {}

    /// Analyzes sentiment using Apple's NLTagger
    ///
    /// - Parameters:
    ///   - text: Text to analyze
    ///   - language: Detected language (used for logging, not selection)
    /// - Returns: Sentiment score from -1.0 (negative) to 1.0 (positive)
    public func analyzeSentiment(_ text: String, language: NLLanguage) async throws -> Double {
        // WORKAROUND: Preprocess text to fix NLTagger bugs
        let processedText = preprocessText(text, language: language)

        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = processedText

        // WORKAROUND: Explicitly set language for short phrases
        // NLTagger's language detection fails on phrases < 10 words
        if language == .english || text.split(separator: " ").count < 10 {
            tagger.setLanguage(.english, range: processedText.startIndex..<processedText.endIndex)
        }

        let (sentiment, _) = tagger.tag(
            at: processedText.startIndex,
            unit: .paragraph,
            scheme: .sentimentScore
        )

        let rawScore = Double(sentiment?.rawValue ?? "0.0") ?? 0.0

        // Apply tanh to normalize extreme values
        return tanh(rawScore * 1.5)
    }

    /// Preprocesses text to work around NLTagger bugs
    ///
    /// ## Workarounds Applied
    /// 1. **Short text fix**: Adds period to texts < 15 chars without punctuation
    ///    - NLTagger expects sentence-like structure for accurate analysis
    ///    - Example: "good" → "good." improves score from 0.0 to 0.8
    ///
    /// - Parameters:
    ///   - text: Original text to preprocess
    ///   - language: Detected language
    /// - Returns: Preprocessed text ready for NLTagger
    private func preprocessText(_ text: String, language: NLLanguage) -> String {
        var processed = text.trimmingCharacters(in: .whitespaces)

        // WORKAROUND: Add period to short texts without punctuation
        // NLTagger produces inaccurate scores for short phrases without sentence structure
        let hasPunctuation = processed.last.map { "!?.,:;".contains($0) } ?? false

        if !hasPunctuation && processed.count < 15 {
            processed += "."
        }

        return processed
    }
}
