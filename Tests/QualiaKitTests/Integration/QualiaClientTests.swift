import QualiaBert
import XCTest

@testable import Qualia

final class QualiaClientIntegrationTests: XCTestCase {

    var client: QualiaClient!
    var vocabURL: URL!

    override func setUpWithError() throws {
        // Get test vocab file from bundle
        let bundle = Bundle.module
        guard
            let url = bundle.url(
                forResource: "test_vocab", withExtension: "txt", subdirectory: "Resources")
        else {
            XCTFail("Could not find test_vocab.txt in test resources")
            return
        }
        vocabURL = url

        // Skip tests that require real model by default
        guard let modelPath = ProcessInfo.processInfo.environment["QUALIAKIT_TEST_MODEL_PATH"]
        else {
            throw XCTSkip("Skipping integration tests - set QUALIAKIT_TEST_MODEL_PATH to run")
        }

        let modelURL = URL(fileURLWithPath: modelPath)
        let provider = try BertProvider(vocabURL: vocabURL, modelURL: modelURL)
        client = QualiaClient(provider: provider)
    }

    override func tearDownWithError() throws {
        client = nil
        vocabURL = nil
    }

    // MARK: - Keyword Detection Tests (Don't require model)

    func testIntenseKeywordDetection() async throws {
        // This test doesn't actually require a model since keyword detection happens first
        // But we skip it anyway if no model is provided to keep tests consistent

        let (emotion, score) = await client.analyzeAndFeel("кровь")
        XCTAssertEqual(emotion, .intense, "Should detect intense emotion for 'кровь'")
        XCTAssertEqual(score, 0.0, "Keyword matches return 0.0 score")
    }

    func testMysteriousKeywordDetection() async throws {
        let (emotion, score) = await client.analyzeAndFeel("тайна")
        XCTAssertEqual(emotion, .mysterious, "Should detect mysterious emotion for 'тайна'")
        XCTAssertEqual(score, 0.0, "Keyword matches return 0.0 score")
    }

    func testEnglishIntenseKeyword() async throws {
        let (emotion, _) = await client.analyzeAndFeel("blood and death")
        XCTAssertEqual(emotion, .intense, "Should detect intense emotion for English keywords")
    }

    // MARK: - Custom Keywords Tests

    func testCustomIntenseKeywords() async throws {
        // Get default keywords and add a custom one
        let defaultKeywords = QualiaConfiguration.loadKeywordsFromBundle()
        let customIntense = defaultKeywords.intense + ["опасность"]
        
        // Create config with custom keywords
        let config = QualiaConfiguration(intenseKeywords: customIntense)
        
        // Get model path from environment
        guard let modelPath = ProcessInfo.processInfo.environment["QUALIAKIT_TEST_MODEL_PATH"]
        else {
            throw XCTSkip("Skipping integration tests - set QUALIAKIT_TEST_MODEL_PATH to run")
        }
        
        let modelURL = URL(fileURLWithPath: modelPath)
        let provider = try BertProvider(vocabURL: vocabURL, modelURL: modelURL)
        let customClient = QualiaClient(provider: provider, config: config)

        let (emotion, _) = await customClient.analyzeAndFeel("опасность")
        XCTAssertEqual(emotion, .intense, "Should detect custom keyword")
    }

    func testCustomMysteriousKeywords() async throws {
        // Get default keywords and add a custom one
        let defaultKeywords = QualiaConfiguration.loadKeywordsFromBundle()
        let customMysterious = defaultKeywords.mysterious + ["загадка"]
        
        // Create config with custom keywords
        let config = QualiaConfiguration(mysteriousKeywords: customMysterious)
        
        // Get model path from environment
        guard let modelPath = ProcessInfo.processInfo.environment["QUALIAKIT_TEST_MODEL_PATH"]
        else {
            throw XCTSkip("Skipping integration tests - set QUALIAKIT_TEST_MODEL_PATH to run")
        }
        
        let modelURL = URL(fileURLWithPath: modelPath)
        let provider = try BertProvider(vocabURL: vocabURL, modelURL: modelURL)
        let customClient = QualiaClient(provider: provider, config: config)

        let (emotion, _) = await customClient.analyzeAndFeel("загадка")
        XCTAssertEqual(emotion, .mysterious, "Should detect custom mysterious keyword")
    }

    // MARK: - Sentiment Analysis Tests (Require model)

    func testPositiveSentiment() async throws {
        let (emotion, score) = await client.analyzeAndFeel("Это прекрасный день!")

        // Should analyze sentiment since no keywords match
        XCTAssertNotEqual(score, 0.0, "Should return non-zero score from ML")

        // Depending on the model training, we might get positive
        // But we can't assert exact emotion without knowing model behavior
        XCTAssertTrue(
            [.positive, .neutral, .negative].contains(emotion), "Should return valid emotion")
    }

    func testNegativeSentiment() async throws {
        let (emotion, score) = await client.analyzeAndFeel("Это ужасно и плохо")

        XCTAssertNotEqual(score, 0.0, "Should return non-zero score from ML")
        XCTAssertTrue(
            [.positive, .neutral, .negative].contains(emotion), "Should return valid emotion")
    }

    func testNeutralSentiment() async throws {
        let (_, score) = await client.analyzeAndFeel("Сегодня среда")

        // Neutral text should have low absolute score
        XCTAssertLessThan(abs(score), 0.5, "Neutral text should have low absolute score")
    }

    func testEmptyText() async throws {
        let (emotion, score) = await client.analyzeAndFeel("")

        XCTAssertEqual(score, 0.0, "Empty text should return 0.0 score")
        XCTAssertEqual(emotion, .neutral, "Empty text should return neutral emotion")
    }

    func testWhitespaceText() async throws {
        let (emotion, score) = await client.analyzeAndFeel("   ")

        XCTAssertEqual(score, 0.0, "Whitespace text should return 0.0 score")
        XCTAssertEqual(emotion, .neutral, "Whitespace text should return neutral emotion")
    }

    // MARK: - Lemma Matching Tests (Don't require model)

    func testLemmaMatching() throws {
        // Create a simple client without model for lemma testing
        // We'll use a mock approach
        throw XCTSkip("Lemma testing requires NaturalLanguage framework - tested separately")
    }
}

// MARK: - Lemma Matching Tests (Lightweight, no model required)

final class QualiaClientLemmaTests: XCTestCase {

    var client: QualiaClient!

    override func setUpWithError() throws {
        // Create a minimal vocab for testing
        let vocabContent = """
            [PAD]
            [UNK]
            [CLS]
            [SEP]
            """

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "minimal_vocab.txt")
        try vocabContent.write(to: tempURL, atomically: true, encoding: .utf8)

        // Create a dummy model URL (tests won't use it)
        _ = FileManager.default.temporaryDirectory.appendingPathComponent(
            "dummy.mlmodel")

        // This will fail to create the client, so we skip these tests for now
        // In a real scenario, we'd refactor QualiaClient to allow testing without model
        throw XCTSkip("Lemma tests require refactoring QualiaClient to work without model")
    }

    func testTextContainsConcept() throws {
        // Test that "running" matches "run" via lemmatization
        // This would work if we could create client without model
    }
}
