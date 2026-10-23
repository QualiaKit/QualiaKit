import Foundation
import XCTest

final class ReleaseAndAdoptionTests: XCTestCase {
    func testReleaseGatesRejectIncompleteOrStaleEvidence() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-m", "unittest", "discover", "-s", "Tools/Release", "-p", "test_*.py"]
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let message = String(decoding: output, as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, message)
        let regex = try NSRegularExpression(pattern: "Ran ([0-9]+) tests?")
        let match = try XCTUnwrap(regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)), message)
        let range = try XCTUnwrap(Range(match.range(at: 1), in: message))
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(Int(message[range])), 23, message)
    }
}
