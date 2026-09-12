import NaturalLanguage

/// On-device detection with a fresh recognizer per call. Only current text is
/// examined; no history, hints, or constraints can force an allowed language.
public struct AppleLanguageDetector: QualiaLanguageDetecting {
    public init() {}

    public func detectLanguage(in text: String) -> QualiaLanguageDetection? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              language != .undetermined,
              let resolved = try? QualiaLanguage(rawValue: language.rawValue) else {
            return nil
        }
        return try? QualiaLanguageDetection(language: resolved, confidence: Float(confidence))
    }
}
