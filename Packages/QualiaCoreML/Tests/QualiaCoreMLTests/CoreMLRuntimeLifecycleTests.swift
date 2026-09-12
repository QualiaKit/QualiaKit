import CoreML
import Foundation
import XCTest
import QualiaKit
@testable import QualiaCoreML

extension CoreMLRuntimeTests {
    @MainActor
    func testLoadingAndConcurrentPredictionsStayOffMainActorAndSerialize() async throws {
        let probe = RuntimeProbe(delayPredictions: true)
        let analyzer = try await CoreMLQualiaAnalyzer(
            source: FileQualiaModelSource(directory: directory()), configuration: .init(diagnostics: { probe.record($0) })
        )
        let requests = try (0..<24).map { try input($0.isMultiple(of: 2) ? "quiet" : "storm rises", id: "call-\($0)") }
        let results = try await withThrowingTaskGroup(of: QualiaObservation.self) { group in
            for request in requests { group.addTask { try await analyzer.analyze(request) } }
            var results: [QualiaObservation] = []
            for try await result in group { results.append(result) }
            return results
        }
        XCTAssertEqual(Set(results.map(\.inputID)), Set(requests.map(\.id)))
        let references = try golden("exclusive-logits-v2")
        for result in results {
            let index = Int(result.inputID.rawValue.dropFirst(5))!
            let expected = references[index.isMultiple(of: 2) ? 0 : 1]
            XCTAssertEqual(Double(result.signals["com.qualiakit.fixture.component0"]!.value), expected.scores[0], accuracy: 1e-6)
        }
        let state = probe.snapshot()
        XCTAssertEqual(state.maximum, 1)
        XCTAssertEqual(state.active, 0)
        XCTAssertEqual(state.predictions, 24)
        XCTAssertFalse(state.sawMainThread)
        XCTAssertTrue(state.stages.contains(.loaded))
    }

    func testCancellationBeforePreparationBeforePredictionAndBeforeReturn() async throws {
        for cancellationStage: CoreMLRuntimeEvent.Stage in [.tokenized, .prepared, .predictionStarted, .predicted, .transformed] {
            let probe = RuntimeProbe(cancelAt: cancellationStage)
            let analyzer = try await CoreMLQualiaAnalyzer(
                source: FileQualiaModelSource(directory: directory()), configuration: .init(diagnostics: { probe.record($0) })
            )
            let request = try input()
            let task = Task { try await analyzer.analyze(request) }
            do { _ = try await task.value; XCTFail("Cancellation must remain cancellation") }
            catch { XCTAssertTrue(error is CancellationError, "\(cancellationStage): \(error)") }
            let stages = probe.snapshot().stages
            if [.tokenized, .prepared, .predictionStarted].contains(cancellationStage) {
                XCTAssertFalse(stages.contains(.predicted))
            }
        }
        let probe = RuntimeProbe()
        let analyzer = try await CoreMLQualiaAnalyzer(source: FileQualiaModelSource(directory: directory()), configuration: .init(diagnostics: { probe.record($0) }))
        let request = try input()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await analyzer.analyze(request)
        }
        do { _ = try await task.value; XCTFail("Expected cancellation before preparation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(probe.snapshot().stages.contains(.tokenized))
    }

    func testInitializationCancellationIsPreserved() async throws {
        let source = FileQualiaModelSource(directory: directory())
        let task = Task {
            try await CoreMLQualiaAnalyzer(source: source, configuration: .init(diagnostics: { event in
                if event.stage == .loaded { withUnsafeCurrentTask { $0?.cancel() } }
            }))
        }
        do { _ = try await task.value; XCTFail("Expected cancellation during load") }
        catch { XCTAssertTrue(error is CancellationError) }
        do { _ = try await CoreMLQualiaAnalyzer(source: CancelledModelSource()); XCTFail("Expected resolver cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testPrecompiledLocalIdentityAndSnapshotLifetime() async throws {
        let fixture = try copyFixture()
        let compiled = try compileFixture(fixture.appendingPathComponent("model.mlmodel"))
        defer { try? FileManager.default.removeItem(at: compiled) }
        let localCompiled = fixture.appendingPathComponent("pinned.mlmodelc")
        try FileManager.default.copyItem(at: compiled, to: localCompiled)
        var files: [String: String] = [:]
        for name in try LocalAssets.fileInventory(in: localCompiled) {
            files[name] = try LocalAssets.digest(Data(contentsOf: localCompiled.appendingPathComponent(name)))
        }
        try edit(fixture) { document in
            var runtime = document["runtime"] as! [String: Any]
            runtime["compiledFrom"] = ["source": runtime["model"]!, "compiler": "local-test-toolchain", "evidence": "Compiled in this test from the checksum-pinned source"]
            runtime["model"] = ["path": "pinned.mlmodelc", "format": "mlmodelc", "files": files]
            document["runtime"] = runtime
            document["contractVersion"] = "exclusive-logits-local-compiled-v2"
        }
        let probe = RuntimeProbe()
        let analyzer = try await CoreMLQualiaAnalyzer(source: FileQualiaModelSource(directory: fixture), configuration: .init(diagnostics: { probe.record($0) }))
        XCTAssertFalse(probe.snapshot().stages.contains(.compiled))
        let original = try await analyzer.analyze(input())
        try Data("unlisted".utf8).write(to: localCompiled.appendingPathComponent("unexpected.bin"))
        await assertSetupError(.checksumMismatch, at: fixture)
        try FileManager.default.removeItem(at: localCompiled.appendingPathComponent("unexpected.bin"))
        let first = try XCTUnwrap(files.keys.sorted().first)
        let firstURL = localCompiled.appendingPathComponent(first)
        let bytes = try Data(contentsOf: firstURL)
        try Data("changed".utf8).write(to: firstURL)
        await assertSetupError(.checksumMismatch, at: fixture)
        try bytes.write(to: firstURL)
        try FileManager.default.removeItem(at: firstURL)
        await assertSetupError(.checksumMismatch, at: fixture)
        try FileManager.default.removeItem(at: fixture)
        // Core ML retains its private verified snapshot, even after all source files disappear.
        let afterRemoval = try await analyzer.analyze(input())
        XCTAssertEqual(afterRemoval.signals, original.signals)
    }

    func testPrecompiledSourceRelationshipIsRequiredAndVerified() async throws {
        let fixture = try copyFixture()
        try edit(fixture) { document in
            var runtime = document["runtime"] as! [String: Any]
            runtime["model"] = ["path": "pinned.mlmodelc", "format": "mlmodelc", "files": ["data": String(repeating: "a", count: 64)]]
            document["runtime"] = runtime
        }
        await assertSetupError(.invalidManifest, at: fixture)
    }
}

private struct CancelledModelSource: QualiaModelSource {
    func resolve() async throws -> QualiaResolvedModel { throw CancellationError() }
}

/// Lock protects test instrumentation only. The production model still calls the real Core ML API.
private final class RuntimeProbe: @unchecked Sendable {
    struct Snapshot {
        var active = 0
        var maximum = 0
        var predictions = 0
        var sawMainThread = false
        var stages: [CoreMLRuntimeEvent.Stage] = []
    }
    private let lock = NSLock()
    private var state = Snapshot()
    private let delayPredictions: Bool
    private let cancelAt: CoreMLRuntimeEvent.Stage?

    init(delayPredictions: Bool = false, cancelAt: CoreMLRuntimeEvent.Stage? = nil) {
        self.delayPredictions = delayPredictions
        self.cancelAt = cancelAt
    }

    func record(_ event: CoreMLRuntimeEvent) {
        lock.lock()
        state.sawMainThread = state.sawMainThread || Thread.isMainThread
        state.stages.append(event.stage)
        if event.stage == .predictionStarted {
            state.active += 1
            state.maximum = max(state.maximum, state.active)
            state.predictions += 1
        }
        if event.stage == .predicted { state.active -= 1 }
        lock.unlock()
        if delayPredictions && event.stage == .predictionStarted { Thread.sleep(forTimeInterval: 0.005) }
        if event.stage == cancelAt { withUnsafeCurrentTask { $0?.cancel() } }
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return state
    }
}

private func compileFixture(_ url: URL) throws -> URL { try MLModel.compileModel(at: url) }
