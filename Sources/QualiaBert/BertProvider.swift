import Foundation
import NaturalLanguage
import Qualia

/// High-accuracy sentiment provider using CoreML BERT model
///
/// This provider implements the `SentimentProvider` protocol using a
/// fine-tuned BERT model for Russian sentiment analysis. For non-Russian
/// languages, it falls back to NLTagger.
///
/// ## Usage
/// ```swift
/// import Qualia
/// import QualiaBert
///
/// let provider = try BertProvider(
///     vocabURL: Bundle.main.url(forResource: "vocab", withExtension: "txt")!,
///     modelURL: Bundle.main.url(forResource: "rusentiment", withExtension: "mlmodelc")!
/// )
/// let client = QualiaClient(provider: provider)
/// ```
///
/// ## Performance
/// - Bundle size: ~100MB (model + vocabulary)
/// - Accuracy: Excellent for Russian, good for other languages (via NLTagger fallback)
/// - Languages: Optimized for Russian, supports all NLTagger languages
public struct BertProvider: SentimentProvider {
    private let tokenizer: BertTokenizer
    private let modelWrapper: BertModelWrapper
    private let fallback: NLTaggerProvider

    /// Creates a new BERT-based sentiment provider
    ///
    /// - Parameters:
    ///   - vocabURL: URL to BERT vocabulary file
    ///   - modelURL: URL to CoreML model file (.mlmodel or .mlmodelc)
    /// - Throws: Initialization errors from tokenizer or model loading
    public init(vocabURL: URL, modelURL: URL) throws {
        self.tokenizer = try BertTokenizer(vocabURL: vocabURL)
        self.modelWrapper = try BertModelWrapper(modelURL: modelURL)
        self.fallback = NLTaggerProvider()
    }

    /// Analyzes sentiment using BERT for Russian, NLTagger for other languages
    ///
    /// - Parameters:
    ///   - text: Text to analyze
    ///   - language: Detected language
    /// - Returns: Sentiment score from -1.0 (negative) to 1.0 (positive)
    public func analyzeSentiment(_ text: String, language: NLLanguage) async throws -> Double {
        // Use BERT for Russian, fallback for other languages
        if language == .russian {
            let (ids, mask) = tokenizer.tokenize(text: text)
            return try modelWrapper.predictSentiment(inputIds: ids, attentionMask: mask)
        } else {
            return try await fallback.analyzeSentiment(text, language: language)
        }
    }
}
