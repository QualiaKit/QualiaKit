import Foundation
import XCTest
import QualiaKit
@testable import QualiaCoreML

extension CoreMLRuntimeTests {
    func testSharedDiagnosticsRedactManifestMetadataAndTraceTruncation() async throws {
        let fixture = try copyFixture()
        let secret = "PRIVATE_MANIFEST_/Users/person/story"
        try edit(fixture) { document in
            var model = document["model"] as! [String: Any]
            model["identifier"] = secret
            model["version"] = secret
            document["model"] = model
            document["contractVersion"] = secret
        }
        let sink = CoreMLDiagnosticRecorder()
        let analyzer = try await CoreMLQualiaAnalyzer(source: FileQualiaModelSource(directory: fixture),
            configuration: .init(diagnostics: { sink.legacy($0) }, diagnosticsSink: sink))
        _ = try await analyzer.analyze(input(String(repeating: "quiet ", count: 100)))
        let events = sink.events
        XCTAssertTrue(events.contains { if case .model(.loaded, _, _, _, _, _) = $0 { return true }; return false })
        XCTAssertTrue(events.contains { event in
            if case let .model(.tokenized, identity, contract, _, _, truncated) = event {
                return identity == .init(identifier: secret, version: secret)
                    && contract == .init(metadata: secret) && (truncated ?? 0) > 0
            }
            return false
        })
        XCTAssertFalse(String(reflecting: events).contains(secret))
        XCTAssertFalse(String(reflecting: events).contains("quiet"))
        XCTAssertFalse(sink.legacyDescriptions.contains(secret))
        XCTAssertEqual(CoreMLRuntimeError.predictionFailed.qualiaError, .inferenceFailed(reason: .adapterFailure))
        XCTAssertEqual(CoreMLRuntimeError.invalidNumericOutput.qualiaError, .invalidModelOutput(reason: .modelOutput))
    }
}

private final class CoreMLDiagnosticRecorder: QualiaDiagnosticsSink, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [QualiaDiagnosticEvent] = []
    private var legacyStorage = ""
    var events: [QualiaDiagnosticEvent] { lock.lock(); defer { lock.unlock() }; return storage }
    var legacyDescriptions: String { lock.lock(); defer { lock.unlock() }; return legacyStorage }
    func record(_ event: QualiaDiagnosticEvent) { lock.lock(); defer { lock.unlock() }; storage.append(event) }
    func legacy(_ event: CoreMLRuntimeEvent) {
        lock.lock(); defer { lock.unlock() }; legacyStorage += String(reflecting: event)
    }
}
