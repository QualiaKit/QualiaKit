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
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text

        let (sentiment, _) = tagger.tag(
            at: text.startIndex,
            unit: .paragraph,
            scheme: .sentimentScore
        )

        let rawScore = Double(sentiment?.rawValue ?? "0.0") ?? 0.0

        // Apply tanh to normalize extreme values
        return tanh(rawScore * 1.5)
    }
}
