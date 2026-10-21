import XCTest
import QualiaKit
import QualiaTesting

// Hosted in the existing test target to preserve the checksum-bound model audit manifest.
final class TestingPrimitivesTests: XCTestCase {
    func testClockReleasesOnlyDueSleepersAndRejectsBackwardsTime() async throws {
        let clock = TestQualiaClock()
        let first = Task { try await clock.sleep(for: .seconds(1)) }
        let second = Task { try await clock.sleep(for: .seconds(2)) }
        try await clock.waitUntilSleeping(count: 2)
        try clock.advance(by: .milliseconds(999))
        XCTAssertEqual(clock.pendingSleepCount, 2)
        try clock.advance(by: .milliseconds(1))
        try await first.value
        XCTAssertEqual(clock.pendingSleepCount, 1)
        XCTAssertThrowsError(try clock.advance(to: .zero))
        XCTAssertThrowsError(try clock.advance(by: .seconds(-1)))
        XCTAssertEqual(clock.now, .seconds(1))
        try clock.advance(to: .seconds(2))
        try await second.value
        XCTAssertEqual(clock.pendingSleepCount, 0)
    }

    func testClockCancellationBeforeAndAfterRegistrationAndTeardown() async throws {
        let clock = TestQualiaClock()
        let sleeper = Task { try await clock.sleep(for: .seconds(1)) }
        try await clock.waitUntilSleeping()
        sleeper.cancel()
        await cancelled(sleeper)
        XCTAssertEqual(clock.pendingSleepCount, 0)
        let early = Task { try await clock.sleep(for: .seconds(10)) }
        early.cancel()
        await cancelled(early)
        let observer = Task { try await clock.waitUntilSleeping(count: 2) }
        observer.cancel()
        await cancelled(observer)
        let last = Task { try await clock.sleep(for: .seconds(5)) }
        try await clock.waitUntilSleeping()
        clock.cancelAll()
        await cancelled(last)
        try clock.advance(to: .seconds(10))
        XCTAssertEqual(clock.pendingSleepCount, 0)
        try await clock.sleep(for: .zero)
    }

    func testControlledAnalyzerDistinguishesRepeatedIDsAndCompletesOutOfOrder() async throws {
        let analyzer = try controlled(.ignore)
        let input = try input()
        let first = Task { try await analyzer.analyze(input) }
        let a = try await analyzer.waitForRequest(number: 1)
        let second = Task { try await analyzer.analyze(input) }
        let b = try await analyzer.waitForRequest(number: 2)
        XCTAssertEqual(a.input.id, b.input.id)
        XCTAssertNotEqual(a.number, b.number)
        first.cancel()
        try await analyzer.complete(b.number, signals: [.suspense: .init(value: 1)])
        let latest = try await second.value
        XCTAssertEqual(latest.signals[.suspense]?.value, 1)
        try await analyzer.complete(a.number, signals: [.suspense: .init(value: 0)])
        let older = try await first.value
        XCTAssertEqual(older.signals[.suspense]?.value, 0)
        do { try await analyzer.complete(a.number); XCTFail("Double completion must fail") }
        catch { XCTAssertEqual(error as? QualiaTestingError, .unknownRequest(a.number)) }
        await analyzer.clearHistory()
        do { _ = try await analyzer.waitForRequest(number: 1); XCTFail("Cleared request must fail") }
        catch { XCTAssertEqual(error as? QualiaTestingError, .unknownRequest(1)) }
    }

    func testControlledAnalyzerCancellationAndExplicitCleanupReleaseWaiters() async throws {
        let analyzer = try controlled(.respect)
        let input = try input()
        let request = Task { try await analyzer.analyze(input) }
        _ = try await analyzer.waitForRequest(number: 1)
        request.cancel()
        await cancelled(request)
        let early = Task { try await analyzer.analyze(input) }
        early.cancel()
        await cancelled(early)
        let observer = Task { try await analyzer.waitForRequest(number: 10) }
        observer.cancel()
        await cancelled(observer)
        let ignoring = try controlled(.ignore)
        let pending = Task { try await ignoring.analyze(input) }
        _ = try await ignoring.waitForRequest(number: 1)
        await ignoring.cancelAll()
        await cancelled(pending)
    }

    func testImmutableFixturesFailOnMissingAndDuplicateIDs() async throws {
        let analyzer = try controlled(.respect)
        let input = try input()
        let observation = QualiaObservation(inputID: input.id, signals: [.suspense: try .init(value: 0.8)],
                                           language: try .init(rawValue: "en"), analyzer: analyzer.identity)
        XCTAssertThrowsError(try FixtureAnalyzer(capabilities: analyzer.capabilities, observations: [observation, observation]))
        let fixture = try FixtureAnalyzer(capabilities: analyzer.capabilities, observations: [observation])
        let actual = try await fixture.analyze(input)
        XCTAssertEqual(actual.signals, observation.signals)
        let missing = try QualiaInput(id: .init(rawValue: "missing"), text: "synthetic")
        do { _ = try await fixture.analyze(missing); XCTFail("Missing fixture must fail") }
        catch { XCTAssertEqual(error as? QualiaTestingError, .missingFixture(missing.id)) }
    }

    private func controlled(_ behavior: ControlledAnalyzer.CancellationBehavior) throws -> ControlledAnalyzer {
        try ControlledAnalyzer(capabilities: .init(languages: [.init(rawValue: "en")], dimensions: [],
            signals: [.suspense], acceptsContext: true, execution: .onDevice),
            identity: .init(identifier: "synthetic", version: "1"), cancellationBehavior: behavior)
    }

    private func input() throws -> QualiaInput {
        try .init(id: .init(rawValue: "same-id"), text: "synthetic", language: .init(rawValue: "en"))
    }

    private func cancelled<T>(_ task: Task<T, Error>, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await task.value; XCTFail("Expected cancellation", file: file, line: line) }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
    }
}
