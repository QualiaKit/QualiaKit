import Foundation
import XCTest
@testable import QualiaKit

extension DiagnosticsAndPrivacyTests {
    /// Architecture regression check: linking the products introduces neither
    /// a remote package dependency nor a networking/logging implementation.
    /// Host-defined adapters and sinks are outside this source-level guarantee.
    func testNoBundledTelemetryOrNetworkImplementation() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertFalse(manifest.contains(".package("))
        let coreMLManifest = try String(contentsOf: root.appendingPathComponent("Packages/QualiaCoreML/Package.swift"), encoding: .utf8)
        XCTAssertFalse(coreMLManifest.contains("url:"))
        let directories = ["Sources/QualiaKit", "Sources/QualiaTesting", "Packages/QualiaCoreML/Sources"]
        let prohibited = ["URLSession", "URLRequest", "NWConnection", "import Network", "import WebKit",
                          "UserDefaults", "systemUptime", "mach_absolute_time", "print(", "NSLog("]
        for directory in directories {
            let files = try XCTUnwrap(FileManager.default.enumerator(at: root.appendingPathComponent(directory),
                                                                    includingPropertiesForKeys: nil))
            for case let file as URL in files where file.pathExtension == "swift" {
                let source = try String(contentsOf: file, encoding: .utf8)
                // Ignore comments; audit executable source rather than doc examples.
                let code = source.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
                for token in prohibited {
                    let pattern = "\\b" + NSRegularExpression.escapedPattern(for: token)
                    XCTAssertNil(code.range(of: pattern, options: .regularExpression), "\(file.lastPathComponent): \(token)")
                }
                if directory == "Sources/QualiaKit", file.path.contains("/Diagnostics/") {
                    for token in ["FileManager", "Data(contentsOf:", ".write(to:"] {
                        XCTAssertFalse(code.contains(token), "Diagnostics must not persist data")
                    }
                }
            }
        }
        let privacyURL = root.appendingPathComponent("Examples/QualiaExample/QualiaExample/PrivacyInfo.xcprivacy")
        let privacy = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: privacyURL), format: nil) as? [String: Any])
        XCTAssertEqual(privacy["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((privacy["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
        XCTAssertEqual((privacy["NSPrivacyAccessedAPITypes"] as? [Any])?.count, 0)
    }
}
