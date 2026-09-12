import CoreML
import Foundation
import XCTest
import QualiaKit
@testable import QualiaCoreML

final class CoreMLRuntimeTests: XCTestCase {
    let fixtures = ["exclusive-logits-v2", "exclusive-probabilities-v2", "independent-logits-v2"]

    struct Golden: Decodable {
        let id: String
        let text: String
        let ids: [Int]
        let mask: [Int]
        let truncatedCount: Int
        let raw: [Double]
        let scores: [Double]
    }

    func directory(_ name: String = "exclusive-logits-v2") -> URL {
        Bundle.module.bundleURL.appendingPathComponent("Resources/CoreML/" + name)
    }

    func contract(_ name: String = "exclusive-logits-v2") throws -> ValidatedContract {
        try QualiaModelManifest.decode(Data(contentsOf: directory(name).appendingPathComponent("manifest.json"))).validateForExecution()
    }

    func golden(_ name: String) throws -> [Golden] {
        try JSONDecoder().decode([Golden].self, from: Data(contentsOf: directory(name).appendingPathComponent("golden.json")))
    }

    func input(_ text: String = "quiet", id: String = "request") throws -> QualiaInput {
        try QualiaInput(id: .init(rawValue: id), text: text, language: .init(rawValue: "en"))
    }

    func copyFixture(_ name: String = "exclusive-logits-v2") throws -> URL {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: directory(name), to: destination)
        addTeardownBlock { try? FileManager.default.removeItem(at: destination) }
        return destination
    }

    func edit(_ directory: URL, _ change: (inout [String: Any]) -> Void) throws {
        let file = directory.appendingPathComponent("manifest.json")
        var document = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        change(&document)
        try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]).write(to: file)
    }

    func assertSetupError(_ expected: CoreMLRuntimeError, at directory: URL, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await CoreMLQualiaAnalyzer(source: FileQualiaModelSource(directory: directory))
            XCTFail("Expected setup error", file: file, line: line)
        } catch { XCTAssertEqual(error as? CoreMLRuntimeError, expected, file: file, line: line) }
    }

    // AC-0004-003/004: three actual model/manifest replacements, no domain/session/haptic changes.
    func testPublicModelsProduceReferenceObservationsEndToEnd() async throws {
        for name in fixtures {
            let analyzer = try await CoreMLQualiaAnalyzer(source: FileQualiaModelSource(directory: directory(name)))
            let expectedContract = try contract(name)
            XCTAssertEqual(analyzer.contractVersion, name)
            XCTAssertEqual(analyzer.identity.version, name)
            XCTAssertEqual(analyzer.modelVersion, expectedContract.manifest.model.version)
            XCTAssertEqual(analyzer.capabilities.signals, Set(expectedContract.mapping.values))
            XCTAssertEqual(analyzer.capabilities.dimensions, [])
            XCTAssertFalse(analyzer.capabilities.acceptsContext)
            XCTAssertEqual(analyzer.capabilities.execution, .onDevice)
            for sample in try golden(name) {
                let observation = try await analyzer.analyze(input(sample.text, id: sample.id))
                XCTAssertEqual(observation.inputID.rawValue, sample.id)
                XCTAssertEqual(observation.analyzer, analyzer.identity)
                XCTAssertEqual(observation.language.rawValue, "en")
                XCTAssertNil(observation.dimensions.valence)
                for (index, expected) in sample.scores.enumerated() {
                    let score = try XCTUnwrap(observation.signals[QualiaSignal(rawValue: "com.qualiakit.fixture.component\(index)")])
                    XCTAssertEqual(Double(score.value), expected, accuracy: 1e-6, "\(name)/\(sample.id)")
                    XCTAssertNil(score.confidence)
                }
                XCTAssertFalse(observation.signals.keys.contains { $0.rawValue.hasPrefix("LABEL_") })
            }
        }
    }

    func testExactTokenizerAndInputTensorsAgainstGolden() throws {
        for name in fixtures {
            let contract = try contract(name)
            let tokenizer = try RuntimeTokenizer(configuration: contract.manifest.tokenizer,
                                                  data: Data(contentsOf: directory(name).appendingPathComponent("vocab.txt")))
            for sample in try golden(name) {
                let prepared = try tokenizer.prepare(sample.text)
                XCTAssertEqual(prepared.ids, sample.ids, sample.id)
                XCTAssertEqual(prepared.mask, sample.mask, sample.id)
                XCTAssertEqual(prepared.truncatedCount, sample.truncatedCount)
                let features = try RuntimeInputBuilder.build(prepared, contract: contract)
                for (featureName, role) in contract.execution.inputRoles {
                    let array = try XCTUnwrap(features.featureValue(for: featureName)?.multiArrayValue)
                    let values = role == "tokenIDs" ? sample.ids : (role == "attentionMask" ? sample.mask : Array(repeating: 0, count: sample.ids.count))
                    XCTAssertEqual((0..<array.count).map { array[$0].intValue }, values)
                    XCTAssertEqual(array.dataType, try RuntimeInputBuilder.dataType(contract.manifest.inputs[featureName]!.dataType))
                }
            }
        }
    }

    // References are stdlib arithmetic, not another invocation of the production transform.
    func testActualCoreMLOutputsMatchIndependentArithmeticReference() throws {
        for name in fixtures {
            let contract = try contract(name)
            let compiled = try MLModel.compileModel(at: directory(name).appendingPathComponent("model.mlmodel"))
            defer { try? FileManager.default.removeItem(at: compiled) }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuOnly
            let model = try MLModel(contentsOf: compiled, configuration: configuration)
            for sample in try golden(name) {
                let prepared = PreparedText(ids: sample.ids, mask: sample.mask, tokenCount: sample.mask.reduce(0, +), truncatedCount: sample.truncatedCount)
                let output = try model.prediction(from: RuntimeInputBuilder.build(prepared, contract: contract))
                let raw = try RuntimeOutputAdapter.extract(output, contract: contract)
                for (index, expected) in sample.raw.enumerated() {
                    XCTAssertEqual(try XCTUnwrap(raw["LABEL_\(index)"]), expected, accuracy: 1e-6, "\(name)/\(sample.id)")
                }
            }
        }
    }

    // AC-0004-001: no user text is needed to discover a missing output.
    func testIncompatibleFeatureContractsFailAtInitialization() async throws {
        let mutations: [(inout [String: Any]) -> Void] = [
            { document in var outputs = document["outputs"] as! [String: Any]; outputs["scores"] = "missing"; document["outputs"] = outputs },
            { document in var runtime = document["runtime"] as! [String: Any]; runtime["classLabelFeature"] = "missing"; document["runtime"] = runtime },
            { document in var inputs = document["inputs"] as! [String: Any]; var ids = inputs["pieces"] as! [String: Any]; ids["dataType"] = "Double"; inputs["pieces"] = ids; document["inputs"] = inputs },
            { document in var inputs = document["inputs"] as! [String: Any]; var ids = inputs["pieces"] as! [String: Any]; ids["shape"] = [1, 8]; inputs["pieces"] = ids; document["inputs"] = inputs },
            { document in var inputs = document["inputs"] as! [String: Any]; var ids = inputs["pieces"] as! [String: Any]; ids["required"] = false; inputs["pieces"] = ids; document["inputs"] = inputs },
            { document in var outputs = document["outputs"] as! [String: Any]; var labels = outputs["labels"] as! [[String: Any]]; labels[0]["name"] = "OTHER"; outputs["labels"] = labels; document["outputs"] = outputs },
            { document in var inputs = document["inputs"] as! [String: Any]; inputs["renamed"] = inputs.removeValue(forKey: "pieces"); document["inputs"] = inputs; var runtime = document["runtime"] as! [String: Any]; var roles = runtime["inputRoles"] as! [String: String]; roles["renamed"] = roles.removeValue(forKey: "pieces"); runtime["inputRoles"] = roles; document["runtime"] = runtime },
        ]
        for mutation in mutations {
            let fixture = try copyFixture()
            try edit(fixture, mutation)
            await assertSetupError(.incompatibleModel, at: fixture)
        }
    }

    func testSchemaAndUnresolvedEvidenceFailBeforeLoadingAssets() async throws {
        let fixture = try copyFixture()
        try FileManager.default.removeItem(at: fixture.appendingPathComponent("model.mlmodel"))
        let original = try Data(contentsOf: fixture.appendingPathComponent("manifest.json"))
        let tests: [(CoreMLRuntimeError, (inout [String: Any]) -> Void)] = [
            (.unsupportedSchemaVersion(2), { $0["schemaVersion"] = 2 }),
            (.unsupportedExecutionContract, { $0.removeValue(forKey: "runtime") }),
            (.invalidManifest, { var outputs = $0["outputs"] as! [String: Any]; outputs["kind"] = "logits"; $0["outputs"] = outputs }),
            (.unresolvedEvidence, { var outputs = $0["outputs"] as! [String: Any]; outputs["kind"] = ["status": "unknown"]; $0["outputs"] = outputs }),
            (.unresolvedEvidence, { var provenance = $0["provenance"] as! [String: Any]; provenance["source"] = ["status": "unknown"]; $0["provenance"] = provenance }),
            (.unresolvedEvidence, { var gate = $0["runtimeRefactorGate"] as! [String: Any]; gate["status"] = "blocked"; $0["runtimeRefactorGate"] = gate }),
            (.unsupportedTemplate, { var tokenizer = $0["tokenizer"] as! [String: Any]; tokenizer["contextPairSupport"] = ["status": "verified", "evidence": "fixture", "value": ["mode": "pair", "template": "pair"]]; $0["tokenizer"] = tokenizer }),
            (.unsupportedTokenizer, { var tokenizer = $0["tokenizer"] as! [String: Any]; tokenizer["type"] = "guessed-wordpiece"; $0["tokenizer"] = tokenizer }),
            (.unresolvedEvidence, { var tokenizer = $0["tokenizer"] as! [String: Any]; tokenizer["trainingIdentity"] = ["status": "unknown"]; $0["tokenizer"] = tokenizer }),
            (.unsupportedExecutionContract, { var runtime = $0["runtime"] as! [String: Any]; runtime["transform"] = "sigmoid"; $0["runtime"] = runtime }),
            (.invalidSemanticMapping, { var runtime = $0["runtime"] as! [String: Any]; runtime["confidence"] = "score"; $0["runtime"] = runtime }),
            (.invalidSemanticMapping, { var outputs = $0["outputs"] as! [String: Any]; var labels = outputs["labels"] as! [[String: Any]]; labels[0]["productSignal"] = "LABEL_0"; outputs["labels"] = labels; $0["outputs"] = outputs }),
        ]
        for (expected, mutate) in tests {
            try original.write(to: fixture.appendingPathComponent("manifest.json"))
            try edit(fixture, mutate)
            await assertSetupError(expected, at: fixture)
        }
    }

    func testCurrentAuditIsNotExecutableAndDoesNotResolveProtectedAssets() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try QualiaModelManifest.decode(Data(contentsOf: repository.appendingPathComponent("Models/current/manifest.json")))
        XCTAssertThrowsError(try manifest.validateForExecution()) {
            XCTAssertEqual($0 as? CoreMLRuntimeError, .unresolvedEvidence)
        }
    }

    func testIndependentProbabilitiesAreNotForcedToSumToOne() throws {
        let fixture = try copyFixture("independent-logits-v2")
        try edit(fixture) { document in
            var runtime = document["runtime"] as! [String: Any]
            runtime["transform"] = "none"
            document["runtime"] = runtime
            var output = document["outputs"] as! [String: Any]
            output["kind"] = ["status": "verified", "value": "independent-probabilities", "evidence": "transform-only test"]
            document["outputs"] = output
        }
        let contract = try QualiaModelManifest.decode(Data(contentsOf: fixture.appendingPathComponent("manifest.json"))).validateForExecution()
        let result = try RuntimeOutputAdapter.scores(["LABEL_0": 0.9, "LABEL_1": 0.8, "LABEL_2": 0.7], contract: contract)
        XCTAssertEqual(result["com.qualiakit.fixture.component0"]?.value, 0.9)
        XCTAssertEqual(result["com.qualiakit.fixture.component1"]?.value, 0.8)
        XCTAssertEqual(result["com.qualiakit.fixture.component2"]?.value, 0.7)
    }

    func testCompatibleOptionalMetadataDoesNotChangeExecution() async throws {
        let fixture = try copyFixture()
        try edit(fixture) { $0["futureDocumentation"] = ["note": "compatible optional v1 addition"] }
        let analyzer = try await CoreMLQualiaAnalyzer(source: FileQualiaModelSource(directory: fixture))
        _ = try await analyzer.analyze(input())
    }

    func testMissingCorruptAndEscapingAssetsFailWithRedactedErrors() async throws {
        for file in ["model.mlmodel", "vocab.txt"] {
            let missing = try copyFixture()
            try FileManager.default.removeItem(at: missing.appendingPathComponent(file))
            await assertSetupError(.missingAsset, at: missing)
            let corrupt = try copyFixture()
            try Data("corrupt".utf8).write(to: corrupt.appendingPathComponent(file))
            await assertSetupError(.checksumMismatch, at: corrupt)
        }
        for path in ["../vocab.txt", "/private/secret", "file:///private/secret", "https://example.org/vocab"] {
            let fixture = try copyFixture()
            try edit(fixture) { var tokenizer = $0["tokenizer"] as! [String: Any]; tokenizer["vocabulary"] = path; $0["tokenizer"] = tokenizer }
            await assertSetupError(.invalidAssetPath, at: fixture)
        }
        let symlink = try copyFixture()
        try FileManager.default.removeItem(at: symlink.appendingPathComponent("vocab.txt"))
        try FileManager.default.createSymbolicLink(at: symlink.appendingPathComponent("vocab.txt"), withDestinationURL: directory().appendingPathComponent("vocab.txt"))
        await assertSetupError(.invalidAssetPath, at: symlink)
        await assertSetupError(.invalidAssetPath, at: URL(string: "https://example.org/model")!)
    }

    func testInvalidVocabularyIsRejectedEvenWithMatchingChecksum() async throws {
        let fixture = try copyFixture()
        let data = Data("[PAD]\n[UNK]\n[CLS]\n[SEP]\nquiet\nquiet\n".utf8)
        try data.write(to: fixture.appendingPathComponent("vocab.txt"))
        try edit(fixture) {
            var tokenizer = $0["tokenizer"] as! [String: Any]
            tokenizer["vocabularySha256"] = LocalAssets.digest(data)
            tokenizer["vocabularyLineCount"] = 6
            $0["tokenizer"] = tokenizer
        }
        await assertSetupError(.invalidVocabulary, at: fixture)
    }

    // AC-0004-002: unchanged probabilities, including endpoints and nonuniform distributions.
    func testTransformsAndInvalidOutputs() throws {
        let probabilities = try contract("exclusive-probabilities-v2")
        for vector: [Double] in [[0, 0.25, 0.75], [1, 0, 0]] {
            let result = try RuntimeOutputAdapter.scores(Dictionary(uniqueKeysWithValues: vector.enumerated().map { ("LABEL_\($0)", $1) }), contract: probabilities)
            for (index, value) in vector.enumerated() {
                XCTAssertEqual(result[QualiaSignal(stringLiteral: "com.qualiakit.fixture.component\(index)")]?.value, Float(value))
            }
        }
        let exclusive = try contract()
        let stable = try RuntimeOutputAdapter.scores(["LABEL_0": 1000, "LABEL_1": 999, "LABEL_2": -1000], contract: exclusive)
        XCTAssertEqual(Double(stable["com.qualiakit.fixture.component0"]!.value), 0.7310585786300049, accuracy: 1e-6)
        XCTAssertEqual(stable["com.qualiakit.fixture.component2"]?.value, 0)
        let independent = try contract("independent-logits-v2")
        let saturated = try RuntimeOutputAdapter.scores(["LABEL_0": 1000, "LABEL_1": -1000, "LABEL_2": 0], contract: independent)
        XCTAssertEqual(saturated["com.qualiakit.fixture.component0"]?.value, 1)
        XCTAssertEqual(saturated["com.qualiakit.fixture.component1"]?.value, 0)
        XCTAssertEqual(saturated["com.qualiakit.fixture.component2"]?.value, 0.5)
        for invalid in [Double.nan, .infinity, -.infinity, -0.1, 1.1] {
            XCTAssertThrowsError(try RuntimeOutputAdapter.scores(["LABEL_0": invalid, "LABEL_1": 0.5, "LABEL_2": 0.5], contract: probabilities)) {
                XCTAssertEqual($0 as? CoreMLRuntimeError, .invalidNumericOutput)
            }
        }
        XCTAssertThrowsError(try RuntimeOutputAdapter.scores(["LABEL_0": 0.2, "LABEL_1": 0.2, "LABEL_2": 0.2], contract: probabilities))
        for raw in [["LABEL_0": 1.0], ["LABEL_0": 0.2, "LABEL_1": 0.3, "UNKNOWN": 0.5]] {
            XCTAssertThrowsError(try RuntimeOutputAdapter.scores(raw, contract: probabilities)) {
                XCTAssertEqual($0 as? CoreMLRuntimeError, .unexpectedLabels)
            }
        }
        let empty = try MLDictionaryFeatureProvider(dictionary: [:])
        XCTAssertThrowsError(try RuntimeOutputAdapter.extract(empty, contract: probabilities)) {
            XCTAssertEqual($0 as? CoreMLRuntimeError, .missingOutput)
        }
    }

    func testBundledSourceAndLanguageContextContract() async throws {
        let source = try BundledQualiaModelSource(bundle: .module, subdirectory: "CoreML/exclusive-logits-v2")
        let analyzer = try await CoreMLQualiaAnalyzer(source: source)
        let requests = [
            try QualiaInput(id: .init(rawValue: "undetermined"), text: "quiet"),
            try QualiaInput(id: .init(rawValue: "language"), text: "quiet", language: .init(rawValue: "ru")),
            try QualiaInput(id: .init(rawValue: "context"), text: "quiet", context: [.init(id: .init(rawValue: "before"), text: "storm")], language: .init(rawValue: "en")),
        ]
        let errors: [QualiaError] = [.languageUndetermined, .unsupportedLanguage(try .init(rawValue: "ru")), .unsupportedContext]
        for (request, expected) in zip(requests, errors) {
            do { _ = try await analyzer.analyze(request); XCTFail("Expected unsupported input") }
            catch { XCTAssertEqual(error as? QualiaError, expected) }
        }
    }
}
