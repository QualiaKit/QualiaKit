import XCTest

@testable import Qualia
import QualiaBert

final class HapticEngineTests: XCTestCase {

    var mockProvider: MockHapticProvider!

    private let tapPattern = HapticPattern(events: [
        HapticEvent(delay: 0.0, intensity: 0.7, sharpness: 0.8)
    ])

    private let thudPattern = HapticPattern(events: [
        HapticEvent(delay: 0.0, intensity: 0.9, sharpness: 1.0)
    ])

    private let loopingPattern = HapticPattern(
        events: [HapticEvent(delay: 0.0, intensity: 0.6, sharpness: 1.0)],
        looping: true,
        loopDuration: 1.5
    )

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

    func testPlayPattern() {
        mockProvider.play(pattern: tapPattern, baseIntensity: 1.0)

        XCTAssertEqual(mockProvider.playedPatterns.count, 1, "Should have one played pattern")
        XCTAssertEqual(mockProvider.playedIntensities.first, 1.0, "Should record intensity")
    }

    func testPlayMultiplePatterns() {
        mockProvider.play(pattern: tapPattern, baseIntensity: 1.0)
        mockProvider.play(pattern: thudPattern, baseIntensity: 0.5)
        mockProvider.play(pattern: loopingPattern, baseIntensity: 0.8)

        XCTAssertEqual(mockProvider.playedPatterns.count, 3, "Should have three played patterns")
        XCTAssertEqual(mockProvider.playedIntensities, [1.0, 0.5, 0.8], "Should maintain order")
    }

    // MARK: - Looping Tests

    func testLoopingFlagSetByPattern() {
        XCTAssertFalse(mockProvider.isLooping, "Should not be looping initially")

        mockProvider.play(pattern: loopingPattern, baseIntensity: 1.0)
        XCTAssertTrue(mockProvider.isLooping, "Looping pattern should set isLooping = true")
    }

    func testNonLoopingPatternClearsLooping() {
        mockProvider.play(pattern: loopingPattern, baseIntensity: 1.0)
        XCTAssertTrue(mockProvider.isLooping)

        mockProvider.play(pattern: tapPattern, baseIntensity: 1.0)
        XCTAssertFalse(mockProvider.isLooping, "Non-looping pattern should clear isLooping")
    }

    func testStopLooping() {
        mockProvider.play(pattern: loopingPattern, baseIntensity: 1.0)
        XCTAssertTrue(mockProvider.isLooping)

        mockProvider.stopLooping()
        XCTAssertFalse(mockProvider.isLooping, "stopLooping() should clear isLooping")
    }

    // MARK: - Reset Tests

    func testReset() {
        mockProvider.prepare()
        mockProvider.play(pattern: tapPattern, baseIntensity: 1.0)
        mockProvider.play(pattern: loopingPattern, baseIntensity: 1.0)

        mockProvider.reset()

        XCTAssertEqual(mockProvider.playedPatterns.count, 0, "Should clear played patterns")
        XCTAssertEqual(mockProvider.playedIntensities.count, 0, "Should clear intensities")
        XCTAssertFalse(mockProvider.prepareCalled, "Should reset prepare flag")
        XCTAssertFalse(mockProvider.isLooping, "Should clear looping flag")
    }

    // MARK: - Thread Safety Tests

    func testConcurrentPlays() {
        let expectation = self.expectation(description: "Concurrent plays complete")
        expectation.expectedFulfillmentCount = 100

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            mockProvider.play(pattern: tapPattern, baseIntensity: 1.0)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0)

        XCTAssertEqual(mockProvider.playedPatterns.count, 100, "Should record all 100 plays")
    }
}
