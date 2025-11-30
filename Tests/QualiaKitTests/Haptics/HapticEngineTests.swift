import XCTest

@testable import Qualia
import QualiaBert

final class HapticEngineTests: XCTestCase {

    var mockProvider: MockHapticProvider!

    override func setUpWithError() throws {
        mockProvider = MockHapticProvider()
    }

    override func tearDownWithError() throws {
        mockProvider = nil
    }

    // MARK: - Basic Functionality Tests

    func testPrepare() {
        mockProvider.prepare()
        XCTAssertTrue(mockProvider.prepareCalled, "Prepare should be called")
    }

    func testPlayEmotion() {
        mockProvider.play(.positive, intensity: 1.0)

        XCTAssertEqual(mockProvider.playedEmotions.count, 1, "Should have one played emotion")
        XCTAssertEqual(mockProvider.playedEmotions.first, .positive, "Should play positive emotion")
    }

    func testPlayMultipleEmotions() {
        mockProvider.play(.positive, intensity: 1.0)
        mockProvider.play(.negative, intensity: 1.0)
        mockProvider.play(.intense, intensity: 1.0)

        XCTAssertEqual(mockProvider.playedEmotions.count, 3, "Should have three played emotions")
        XCTAssertEqual(
            mockProvider.playedEmotions, [.positive, .negative, .intense], "Should maintain order")
    }

    func testEmotionCounts() {
        mockProvider.play(.positive, intensity: 1.0)
        mockProvider.play(.positive, intensity: 1.0)
        mockProvider.play(.negative, intensity: 1.0)
        mockProvider.play(.positive, intensity: 1.0)

        let counts = mockProvider.emotionCounts
        XCTAssertEqual(counts[.positive], 3, "Should count 3 positive emotions")
        XCTAssertEqual(counts[.negative], 1, "Should count 1 negative emotion")
        XCTAssertNil(counts[.intense], "Should not count unplayed emotions")
    }

    // MARK: - Heartbeat Tests

    func testStartHeartbeat() {
        XCTAssertFalse(mockProvider.isHeartbeatPlaying, "Heartbeat should not be playing initially")

        mockProvider.startHeartbeat()
        XCTAssertTrue(mockProvider.isHeartbeatPlaying, "Heartbeat should be playing")
    }

    func testStopHeartbeat() {
        mockProvider.startHeartbeat()
        XCTAssertTrue(mockProvider.isHeartbeatPlaying, "Heartbeat should be playing")

        mockProvider.stopHeartbeat()
        XCTAssertFalse(mockProvider.isHeartbeatPlaying, "Heartbeat should stop")
    }

    func testHeartbeatToggle() {
        mockProvider.startHeartbeat()
        XCTAssertTrue(mockProvider.isHeartbeatPlaying)

        mockProvider.stopHeartbeat()
        XCTAssertFalse(mockProvider.isHeartbeatPlaying)

        mockProvider.startHeartbeat()
        XCTAssertTrue(mockProvider.isHeartbeatPlaying)
    }

    // MARK: - Reset Tests

    func testReset() {
        mockProvider.prepare()
        mockProvider.play(.positive, intensity: 1.0)
        mockProvider.play(.negative, intensity: 1.0)
        mockProvider.startHeartbeat()

        mockProvider.reset()

        XCTAssertEqual(mockProvider.playedEmotions.count, 0, "Should clear played emotions")
        XCTAssertFalse(mockProvider.prepareCalled, "Should reset prepare flag")
        XCTAssertFalse(mockProvider.isHeartbeatPlaying, "Should stop heartbeat")
    }

    // MARK: - Thread Safety Tests

    func testConcurrentPlays() {
        let expectation = self.expectation(description: "Concurrent plays complete")
        expectation.expectedFulfillmentCount = 100

        DispatchQueue.concurrentPerform(iterations: 100) { index in
            let emotion: SenseEmotion = index % 2 == 0 ? .positive : .negative
            mockProvider.play(emotion, intensity: 1.0)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0)

        XCTAssertEqual(mockProvider.playedEmotions.count, 100, "Should record all 100 plays")
        XCTAssertEqual(
            mockProvider.emotionCounts[.positive]! + mockProvider.emotionCounts[.negative]!, 100,
            "Should count all emotions")
    }
}
