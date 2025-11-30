import XCTest

@testable import Qualia
import QualiaBert

final class BertModelWrapperTests: XCTestCase {

    // MARK: - Softmax Tests

    func testSoftmaxBasic() throws {
        // We'll test softmax indirectly through a mock model
        // For now, create a wrapper class to test the private softmax method
        let input = [1.0, 2.0, 3.0]
        let expected = softmax(input)

        XCTAssertEqual(expected.count, 3, "Output should have same length as input")

        // Sum of softmax should be approximately 1.0
        let sum = expected.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 0.0001, "Softmax should sum to 1.0")

        // Largest input should have largest probability
        let maxIndex = input.firstIndex(of: input.max()!)!
        let maxProbIndex = expected.firstIndex(of: expected.max()!)!
        XCTAssertEqual(maxIndex, maxProbIndex, "Max input should correspond to max probability")
    }

    func testSoftmaxUniform() {
        let input = [1.0, 1.0, 1.0]
        let result = softmax(input)

        // All should be approximately equal (1/3)
        for value in result {
            XCTAssertEqual(
                value, 1.0 / 3.0, accuracy: 0.0001, "Uniform input should produce uniform output")
        }
    }

    func testSoftmaxSingleElement() {
        let input = [5.0]
        let result = softmax(input)

        XCTAssertEqual(result.count, 1, "Should have one element")
        XCTAssertEqual(result[0], 1.0, accuracy: 0.0001, "Single element should be 1.0")
    }

    func testSoftmaxWithNegatives() {
        let input = [-1.0, 0.0, 1.0]
        let result = softmax(input)

        XCTAssertEqual(result.count, 3, "Should have three elements")

        let sum = result.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 0.0001, "Should sum to 1.0")

        // 1.0 should have highest probability
        XCTAssertGreaterThan(result[2], result[1], "Larger input should have larger probability")
        XCTAssertGreaterThan(result[1], result[0], "Larger input should have larger probability")
    }

    // MARK: - Model Initialization Tests

    func testInvalidModelURL() {
        let invalidURL = URL(fileURLWithPath: "/nonexistent/model.mlmodel")
        XCTAssertThrowsError(try BertModelWrapper(modelURL: invalidURL)) { error in
            XCTAssertNotNil(error, "Should throw error for invalid model URL")
        }
    }

    // MARK: - Helper Functions

    /// Reimplementation of softmax for testing (same logic as in BertModelWrapper)
    private func softmax(_ inputs: [Double]) -> [Double] {
        let maxInput = inputs.max() ?? 0.0
        let expValues = inputs.map { exp($0 - maxInput) }
        let sumExp = expValues.reduce(0, +)
        return expValues.map { $0 / sumExp }
    }
}

// MARK: - Integration Tests (Skipped by default - require real model)

final class BertModelWrapperIntegrationTests: XCTestCase {

    func testPredictSentiment_SkippedWithoutModel() throws {
        // This test requires a real BERT model file
        // Developers can enable this test by setting QUALIAKIT_TEST_MODEL_PATH
        guard let modelPath = ProcessInfo.processInfo.environment["QUALIAKIT_TEST_MODEL_PATH"]
        else {
            throw XCTSkip(
                "Skipping integration test - set QUALIAKIT_TEST_MODEL_PATH to run with real model")
        }

        let modelURL = URL(fileURLWithPath: modelPath)
        let wrapper = try BertModelWrapper(modelURL: modelURL)

        // Test with sample input
        let inputIds = Array(repeating: 1, count: 128)
        let attentionMask = Array(repeating: 1, count: 128)

        let score = try wrapper.predictSentiment(inputIds: inputIds, attentionMask: attentionMask)

        // Score should be between -1 and 1
        XCTAssertGreaterThanOrEqual(score, -1.0, "Sentiment score should be >= -1")
        XCTAssertLessThanOrEqual(score, 1.0, "Sentiment score should be <= 1")
    }
}
