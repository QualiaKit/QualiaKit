import CoreML
import Foundation
import XCTest
import QualiaKit
@testable import QualiaCoreML

final class BertRuntimeTests: XCTestCase {
    struct Golden: Decodable {
        let id: String
        let text: String
        let context: [String]
        let ids: [Int]
        let mask: [Int]
        let types: [Int]
        let scores: [Double]
    }
    func directory(_ name: String = "uncased-pair") -> URL {
        let root = Bundle.module.resourceURL ?? Bundle.module.bundleURL
        let direct = root.appendingPathComponent("Bert/" + name)
        return FileManager.default.fileExists(atPath: direct.path) ? direct : root.appendingPathComponent("Resources/Bert/" + name)
    }
    func manifest(_ directory: URL) throws -> BertModelManifest {
        let manifest = try BertModelManifest.decode(Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        try manifest.validate()
        return manifest
    }
    func tokenizer(_ directory: URL, _ manifest: BertModelManifest) throws -> BertWordPieceTokenizer {
        try BertWordPieceTokenizer(configuration: manifest.tokenizer,
            data: Data(contentsOf: directory.appendingPathComponent(manifest.tokenizer.vocabulary)))
    }
    func input(_ row: Golden) throws -> QualiaInput {
        try .init(id: .init(rawValue: row.id), text: row.text,
                  context: row.context.enumerated().map { try .init(id: .init(rawValue: "context-\($0.offset)"), text: $0.element) },
                  language: .init(rawValue: "en"))
    }
    func copyFixture(_ name: String = "uncased-pair") throws -> URL {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: directory(name), to: destination)
        addTeardownBlock { try? FileManager.default.removeItem(at: destination) }
        return destination
    }
    func edit(_ directory: URL, _ change: (inout [String: Any]) -> Void) throws {
        let file = directory.appendingPathComponent("manifest.json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        change(&object)
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: file)
    }

    func testDifferentModelsUseTheSameAnalyzerAndMatchHuggingFaceAndArithmetic() async throws {
        for name in ["uncased-pair", "cased-single", "uncased-package"] {
            let folder = directory(name)
            let contract = try manifest(folder)
            let tokenizer = try tokenizer(folder, contract)
            let analyzer = try await BertQualiaAnalyzer(source: FileQualiaModelSource(directory: folder))
            XCTAssertEqual(analyzer.capabilities.acceptsContext, name.hasPrefix("uncased"))
            let rows = try JSONDecoder().decode([Golden].self, from: Data(contentsOf: folder.appendingPathComponent("golden.json")))
            for row in rows {
                let prepared = try tokenizer.prepare(text: row.text, context: row.context, sequence: contract.sequence)
                XCTAssertEqual(prepared.ids, row.ids, "\(name)/\(row.id)")
                XCTAssertEqual(prepared.mask, row.mask, "\(name)/\(row.id)")
                XCTAssertEqual(prepared.types, row.types, "\(name)/\(row.id)")
                let observation = try await analyzer.analyze(input(row))
                XCTAssertEqual(observation.inputID.rawValue, row.id)
                XCTAssertEqual(observation.analyzer, analyzer.identity)
                for (label, expected) in zip(contract.output.labels, row.scores) {
                    let score = try XCTUnwrap(observation.signals[try .init(rawValue: label.signal)])
                    XCTAssertEqual(Double(score.value), expected, accuracy: 1e-6)
                    XCTAssertNil(score.confidence)
                }
            }
        }
    }

    func testOverflowAndUnsupportedContextAreExplicit() async throws {
        for name in ["uncased-pair", "cased-single"] {
            let folder = directory(name)
            let contract = try manifest(folder)
            let tokenizer = try tokenizer(folder, contract)
            XCTAssertThrowsError(try tokenizer.prepare(text: "", context: [], sequence: contract.sequence))
            XCTAssertThrowsError(try tokenizer.prepare(text: Array(repeating: "hello", count: contract.sequence.maximumLength).joined(separator: " "),
                                                       context: [], sequence: contract.sequence)) {
                XCTAssertEqual($0 as? CoreMLRuntimeError, .inputPreparationFailed)
            }
        }
        let analyzer = try await BertQualiaAnalyzer(source: FileQualiaModelSource(directory: directory("cased-single")))
        let request = try QualiaInput(id: .init(rawValue: "context"), text: "hello",
                                     context: [.init(id: .init(rawValue: "previous"), text: "world")], language: .init(rawValue: "en"))
        do { _ = try await analyzer.analyze(request); XCTFail("Expected unsupported context") }
        catch { XCTAssertEqual(error as? QualiaError, .unsupportedContext) }
    }

    func testWrongMetadataAndCorruptAssetsFailBeforePrediction() async throws {
        for mutation in 0..<7 {
            let folder = try copyFixture()
            try edit(folder) { value in
                switch mutation {
                case 0: var t = value["tokenizer"] as! [String: Any]; t["type"] = "sentencepiece"; value["tokenizer"] = t
                case 1: var o = value["output"] as! [String: Any]; o["shape"] = [1, 16, 3]; value["output"] = o
                case 2: var o = value["output"] as! [String: Any]; o["feature"] = "missing"; value["output"] = o
                case 3: var t = value["tokenizer"] as! [String: Any]; t["vocabulary"] = "../vocab.txt"; value["tokenizer"] = t
                case 4: var o = value["output"] as! [String: Any]; o["classification"] = "regression"; value["output"] = o
                case 5: value["schemaVersion"] = 99
                default: var m = value["model"] as! [String: Any]; m["sha256"] = String(repeating: "0", count: 64); value["model"] = m
                }
            }
            do { _ = try await BertQualiaAnalyzer(source: FileQualiaModelSource(directory: folder)); XCTFail("Expected rejection \(mutation)") }
            catch { XCTAssertTrue(error is CoreMLRuntimeError) }
        }
        let folder = try copyFixture()
        try Data("changed".utf8).write(to: folder.appendingPathComponent("vocab.txt"))
        do { _ = try await BertQualiaAnalyzer(source: FileQualiaModelSource(directory: folder)); XCTFail("Expected checksum rejection") }
        catch { XCTAssertEqual(error as? CoreMLRuntimeError, .checksumMismatch) }
    }

    @MainActor
    func testConcurrentCallsAndSnapshotLifetime() async throws {
        let folder = try copyFixture()
        let probe = BertProbe()
        let analyzer = try await BertQualiaAnalyzer(source: FileQualiaModelSource(directory: folder), configuration: .init(diagnostics: { probe.record($0) }))
        try FileManager.default.removeItem(at: folder)
        let results = try await withThrowingTaskGroup(of: QualiaObservation.self) { group in
            for index in 0..<20 {
                let request = try QualiaInput(id: .init(rawValue: "call-\(index)"), text: "hello", language: .init(rawValue: "en"))
                group.addTask { try await analyzer.analyze(request) }
            }
            var results: [QualiaObservation] = []
            for try await result in group { results.append(result) }
            return results
        }
        XCTAssertEqual(Set(results.map(\.inputID)).count, 20)
        let snapshot = probe.snapshot()
        XCTAssertFalse(snapshot.mainThread)
        XCTAssertEqual(snapshot.maximum, 1)
        XCTAssertEqual(snapshot.completed, 20)
    }

    func testCancellationAtEachExecutionBoundary() async throws {
        for stage: CoreMLRuntimeEvent.Stage in [.loaded, .tokenized, .prepared, .predictionStarted, .predicted, .transformed] {
            let directory = directory()
            let task = Task {
                let analyzer = try await BertQualiaAnalyzer(source: FileQualiaModelSource(directory: directory), configuration: .init(diagnostics: {
                    if $0.stage == stage { withUnsafeCurrentTask { $0?.cancel() } }
                }))
                return try await analyzer.analyze(.init(id: .init(rawValue: "cancel"), text: "hello", language: .init(rawValue: "en")))
            }
            do { _ = try await task.value; XCTFail("Expected cancellation at \(stage)") }
            catch { XCTAssertTrue(error is CancellationError) }
        }
    }

    func testPackageInventoryRejectsMissingChangedExtraAndSymlinkedFiles() async throws {
        for mode in 0..<4 {
            let folder = try copyFixture("uncased-package")
            let contract = try manifest(folder)
            let package = folder.appendingPathComponent(contract.model.path)
            let name = try XCTUnwrap(contract.model.files?.keys.sorted().first)
            let file = package.appendingPathComponent(name)
            switch mode {
            case 0: try FileManager.default.removeItem(at: file)
            case 1: try Data("changed".utf8).write(to: file)
            case 2: try Data("extra".utf8).write(to: package.appendingPathComponent("unlisted.bin"))
            default:
                try FileManager.default.removeItem(at: file)
                try FileManager.default.createSymbolicLink(at: file, withDestinationURL: directory("uncased-package").appendingPathComponent(contract.model.path).appendingPathComponent(name))
            }
            do { _ = try await BertQualiaAnalyzer(source: FileQualiaModelSource(directory: folder)); XCTFail("Expected invalid inventory") }
            catch { XCTAssertTrue(error is CoreMLRuntimeError) }
        }
    }

    /// Optional local acceptance uses the same public API. No private model,
    /// vocabulary or text is required by, or copied into, the repository tests.
    func testOptionalPrivateModelAcceptance() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUALIA_BERT_PRIVATE_DIRECTORY"] else {
            throw XCTSkip("Set QUALIA_BERT_PRIVATE_DIRECTORY to an external prepared model with validation.json")
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let contract = try manifest(folder)
        let tokenizer = try tokenizer(folder, contract)
        let analyzer = try await BertQualiaAnalyzer(source: FileQualiaModelSource(directory: folder))
        let rows = try JSONDecoder().decode([Golden].self, from: Data(contentsOf: folder.appendingPathComponent("validation.json")))
        XCTAssertFalse(rows.isEmpty)
        var maximumScoreDifference = 0.0
        var predictions = 0
        for row in rows {
            let prepared = try tokenizer.prepare(text: row.text, context: row.context, sequence: contract.sequence)
            XCTAssertEqual(prepared.ids, row.ids, row.id)
            XCTAssertEqual(prepared.mask, row.mask, row.id)
            XCTAssertEqual(prepared.types, row.types, row.id)
            if row.scores.isEmpty { continue }
            XCTAssertEqual(row.scores.count, contract.output.labels.count)
            let observation = try await analyzer.analyze(input(row))
            predictions += 1
            for (label, expected) in zip(contract.output.labels, row.scores) {
                let actual = Double(try XCTUnwrap(observation.signals[try .init(rawValue: label.signal)]).value)
                XCTAssertEqual(actual, expected, accuracy: 0.001, row.id)
                XCTAssertEqual(actual >= 0.5, expected >= 0.5, row.id)
                maximumScoreDifference = max(maximumScoreDifference, abs(actual - expected))
            }
        }
        print("External BERT acceptance: \(rows.count) tokenization cases, \(predictions) predictions, maximum score difference \(maximumScoreDifference)")
    }
}

private final class BertProbe: @unchecked Sendable {
    struct Snapshot { var mainThread = false; var maximum = 0; var active = 0; var completed = 0 }
    private let lock = NSLock()
    private var state = Snapshot()
    func record(_ event: CoreMLRuntimeEvent) {
        lock.lock()
        defer { lock.unlock() }
        state.mainThread = state.mainThread || Thread.isMainThread
        if event.stage == .predictionStarted { state.active += 1; state.maximum = max(state.maximum, state.active) }
        if event.stage == .predicted { state.active -= 1; state.completed += 1 }
    }
    func snapshot() -> Snapshot { lock.lock(); defer { lock.unlock() }; return state }
}
