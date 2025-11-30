import QualiaBert
import XCTest

@testable import Qualia

/// Tests for QualiaConfiguration and its integration with QualiaClient
@available(macOS 11.0, iOS 14.0, *)
final class QualiaClientConfigTests: XCTestCase {

    var vocabURL: URL!
    var mockModelURL: URL!

    override func setUpWithError() throws {
        // Create temporary vocab file for testing
        vocabURL = try createTestVocabFile()

        // Create temporary model URL (won't be used for happy path config tests)
        let tempDir = FileManager.default.temporaryDirectory
        mockModelURL = tempDir.appendingPathComponent("mock_model.mlpackage")
    }

    override func tearDownWithError() throws {
        // Clean up temp files
        if FileManager.default.fileExists(atPath: vocabURL.path) {
            try? FileManager.default.removeItem(at: vocabURL)
        }
    }

    // MARK: - Configuration Preset Tests

    func testConfigurationPresets() {
        // Test standard configuration
        let standard = QualiaConfiguration.standard
        XCTAssertTrue(standard.autoPlayHaptics, "Standard should enable auto-haptics")
        XCTAssertTrue(standard.enableHeartbeat, "Standard should enable heartbeat")
        XCTAssertEqual(standard.hapticIntensity, 1.0, "Standard should use full intensity")
        XCTAssertEqual(standard.hapticDelay, 0.0, "Standard should have no delay")

        // Test silent configuration
        let silent = QualiaConfiguration.silent
        XCTAssertFalse(silent.autoPlayHaptics, "Silent should disable auto-haptics")
        XCTAssertFalse(silent.enableHeartbeat, "Silent should disable heartbeat")

        // Test testing configuration
        let testing = QualiaConfiguration.testing
        XCTAssertFalse(testing.autoPlayHaptics, "Testing should disable auto-haptics")
        XCTAssertFalse(testing.enableHeartbeat, "Testing should disable heartbeat")

        // Test accessibility configuration
        let accessibility = QualiaConfiguration.accessibility
        XCTAssertEqual(
            accessibility.hapticIntensity, 0.5, "Accessibility should use reduced intensity")
        XCTAssertTrue(
            accessibility.autoPlayHaptics, "Accessibility should still enable auto-haptics")
    }

    func testCustomConfiguration() {
        let config = QualiaConfiguration(
            autoPlayHaptics: false,
            enableHeartbeat: true,
            hapticIntensity: 0.7,
            hapticDelay: 0.5
        )

        XCTAssertFalse(config.autoPlayHaptics)
        XCTAssertTrue(config.enableHeartbeat)
        XCTAssertEqual(config.hapticIntensity, 0.7)
        XCTAssertEqual(config.hapticDelay, 0.5)
    }

    // MARK: - Client Configuration Tests

    func testClientInitWithDefaultConfig() throws {
        // Test with default lightweight NLTagger provider
        let client = QualiaClient()
        XCTAssertNotNil(client, "Client creates with default NLTagger provider")
    }

    func testClientInitWithCustomConfig() throws {
        let config = QualiaConfiguration.silent
        let client = QualiaClient(config: config)
        XCTAssertNotNil(client, "Client accepts custom configuration")
    }

    // MARK: - API Method Tests

    func testAnalyzeMethodExists() throws {
        // Verify the new analyze() method exists and is callable
        let client = QualiaClient(config: .testing)

        // This test just verifies the method signature exists
        Task {
            _ = await client.analyze("test")
        }
        XCTAssertTrue(true, "analyze() method exists")
    }

    func testFeelMethodExists() throws {
        // Verify the new feel() method exists and is callable
        let client = QualiaClient(config: .testing)

        // This test just verifies the method signature exists
        Task { @MainActor in
            client.feel(.positive)
        }
        XCTAssertTrue(true, "feel() method exists")
    }

    // MARK: - Helper Methods

    private func createTestVocabFile() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let vocabURL = tempDir.appendingPathComponent("test_vocab_\(UUID().uuidString).txt")

        let testVocab = """
            [PAD]
            [UNK]
            [CLS]
            [SEP]
            the
            a
            test
            """

        try testVocab.write(to: vocabURL, atomically: true, encoding: .utf8)
        return vocabURL
    }
}
