import Foundation
import NaturalLanguage

/// Protocol for pluggable sentiment analysis implementations
///
/// Allows different backends (NLTagger, BERT, custom models) to provide
/// sentiment scores for text analysis.
///
/// ## Example
/// ```swift
/// struct CustomProvider: SentimentProvider {
///     func analyzeSentiment(_ text: String, language: NLLanguage) async throws -> Double {
///         // Custom implementation
///         return 0.0
///     }
/// }
/// ```
public protocol SentimentProvider {
    /// Analyzes sentiment of the given text
    ///
    /// - Parameters:
    ///   - text: Text to analyze
    ///   - language: Detected language of the text
    /// - Returns: Sentiment score from -1.0 (negative) to 1.0 (positive)
    /// - Throws: Analysis errors (model loading, processing failures)
    func analyzeSentiment(_ text: String, language: NLLanguage) async throws -> Double
}
