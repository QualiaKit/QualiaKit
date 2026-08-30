import CoreML
import CryptoKit
import Foundation
import XCTest

@testable import QualiaBert

final class CurrentModelContractTests: XCTestCase {
    private let labels = (0...4).map { "LABEL_\($0)" }
    private let fixtureDirectory = "Tests/Golden/current/current-russian-fixture-v1"

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func url(_ relativePath: String) -> URL {
        repositoryRoot.appendingPathComponent(relativePath)
    }

    private func json(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: url(relativePath))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func golden(_ name: String) -> String {
        "\(fixtureDirectory)/\(name)"
    }

    private func object(_ value: Any?, _ message: String = "expected object") throws -> [String: Any] {
        try XCTUnwrap(value as? [String: Any], message)
    }

    private func array(_ value: Any?, _ message: String = "expected array") throws -> [[String: Any]] {
        try XCTUnwrap(value as? [[String: Any]], message)
    }

    private func doubles(_ value: Any?) throws -> [String: Double] {
        let raw = try object(value)
        return try Dictionary(uniqueKeysWithValues: raw.map { key, value in
            (key, try XCTUnwrap(value as? NSNumber).doubleValue)
        })
    }

    private func ints(_ value: Any?) throws -> [Int] {
        try XCTUnwrap(value as? [NSNumber]).map(\.intValue)
    }

    private func strings(_ value: Any?) throws -> [String] {
        try XCTUnwrap(value as? [String])
    }

    private func sha256(_ fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var digest = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            digest.update(data: data)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func runReferenceTool(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3", url("Tools/ModelContract/reference_inference.py").path,
        ] + arguments
        process.currentDirectoryURL = repositoryRoot
        process.environment = ProcessInfo.processInfo.environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, output)
    }

    private func manifestValidationErrors(_ manifest: [String: Any]) -> [String] {
        var errors: [String] = []
        if (manifest["schemaVersion"] as? NSNumber)?.intValue != 1 { errors.append("schemaVersion") }
        if manifest["contractVersion"] as? String != "current-russian-v1" { errors.append("contractVersion") }
        guard let model = manifest["model"] as? [String: Any] else { return errors + ["model"] }
        if model["identifier"] as? String != "rub-sentiment-coreml-local-audit" { errors.append("model.identifier") }
        if model["version"] as? String != "sha256-f7ac2156e756a2aa" { errors.append("model.version") }
        guard let fixture = manifest["fixture"] as? [String: Any] else { return errors + ["fixture"] }
        if fixture["version"] as? String != "current-russian-fixture-v1" { errors.append("fixture.version") }
        guard let outputs = manifest["outputs"] as? [String: Any],
              let outputLabels = outputs["labels"] as? [[String: Any]] else { return errors + ["outputs.labels"] }
        if outputLabels.compactMap({ $0["name"] as? String }) != labels { errors.append("outputs.labels") }
        return errors
    }

    func testReferenceTokenizerKnownVectorsAndCorpusCoverage() throws {
        let corpus = try json(golden("corpus-v1.json"))
        let golden = try json(golden("fixture-v1.json"))
        let corpusCases = try array(corpus["cases"])
        let goldenCases = try array(golden["cases"])
        XCTAssertGreaterThanOrEqual(corpusCases.count, 100)
        XCTAssertEqual((corpus["caseCount"] as? NSNumber)?.intValue, corpusCases.count)

        let required = Set(try strings(corpus["requiredCoverage"]))
        XCTAssertEqual(required, Set([
            "yo_e", "dash_variants", "quote_variants", "ellipses", "emoji", "mixed_scripts",
            "negation", "hard_negative", "casing", "unknown_words", "truncation",
        ]))
        let observed = Set(try corpusCases.flatMap { try strings($0["categories"]) })
        XCTAssertTrue(required.isSubset(of: observed))

        let byID = Dictionary(uniqueKeysWithValues: goldenCases.compactMap { item -> (String, [String: Any])? in
            guard let id = item["id"] as? String else { return nil }
            return (id, item)
        })
        let empty = try XCTUnwrap(byID["edge-empty"])
        XCTAssertEqual(Array(try ints(empty["inputIds"]).prefix(4)), [101, 102, 0, 0])
        XCTAssertEqual(Array(try ints(empty["attentionMask"]).prefix(4)), [1, 1, 0, 0])
        XCTAssertEqual(Array(try strings(empty["tokens"]).prefix(4)), ["[CLS]", "[SEP]", "[PAD]", "[PAD]"])

        for id in ["case-lower", "case-title", "case-upper"] {
            let item = try XCTUnwrap(byID[id])
            XCTAssertEqual(Array(try ints(item["inputIds"]).prefix(5)), [101, 3998, 4564, 12918, 102])
        }
        let exactBoundary = try XCTUnwrap(byID["truncation-126"])
        XCTAssertFalse(try XCTUnwrap(exactBoundary["wasTruncated"] as? Bool))
        XCTAssertEqual(try ints(exactBoundary["inputIds"]).last, 102)
        XCTAssertTrue(try ints(exactBoundary["attentionMask"]).allSatisfy { $0 == 1 })
        let truncated = try XCTUnwrap(byID["truncation-127"])
        XCTAssertTrue(try XCTUnwrap(truncated["wasTruncated"] as? Bool))
        XCTAssertEqual(try ints(truncated["inputIds"]).last, 102)
        XCTAssertTrue(try ints(truncated["attentionMask"]).allSatisfy { $0 == 1 })
    }

    func testSchemaIdentityAndVersionCompatibility() throws {
        let schema = try json("Models/current/manifest.schema.json")
        let manifest = try json("Models/current/manifest.json")
        XCTAssertEqual(schema["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")
        XCTAssertTrue(manifestValidationErrors(manifest).isEmpty)
        let schemaSelfTest = try runReferenceTool(["--schema-self-test"])
        XCTAssertEqual(schemaSelfTest.status, 0, schemaSelfTest.output)
        XCTAssertTrue(schemaSelfTest.output.contains("compatible-resolved-evidence"))

        var unsupported = manifest
        unsupported["schemaVersion"] = 2
        XCTAssertTrue(manifestValidationErrors(unsupported).contains("schemaVersion"))
        var missing = manifest
        missing.removeValue(forKey: "model")
        XCTAssertTrue(manifestValidationErrors(missing).contains("model"))
        var wrongType = manifest
        wrongType["schemaVersion"] = "1"
        XCTAssertTrue(manifestValidationErrors(wrongType).contains("schemaVersion"))
        var mismatchedIdentity = manifest
        var model = try object(mismatchedIdentity["model"])
        model["identifier"] = "different-model"
        mismatchedIdentity["model"] = model
        XCTAssertTrue(manifestValidationErrors(mismatchedIdentity).contains("model.identifier"))

        let fixture = try json(golden("fixture-v1.json"))
        for item in try array(fixture["cases"]) {
            XCTAssertEqual(item["contractVersion"] as? String, manifest["contractVersion"] as? String)
            XCTAssertEqual(item["fixtureVersion"] as? String, try object(manifest["fixture"])["version"] as? String)
            XCTAssertEqual(item["modelIdentifier"] as? String, try object(manifest["model"])["identifier"] as? String)
            XCTAssertEqual(item["modelVersion"] as? String, try object(manifest["model"])["version"] as? String)
        }
    }

    func testChecksumClosureAndFixtureImmutability() throws {
        let inventory = try json("Models/current/checksums.json")
        XCTAssertEqual(inventory["algorithm"] as? String, "SHA-256")
        let files = try doublesOrStrings(try object(inventory["files"]))
        XCTAssertGreaterThanOrEqual(files.count, 11)
        for (relative, expected) in files {
            XCTAssertEqual(try sha256(url(relative)), expected, relative)
        }
        let index = try json(golden("index.json"))
        let indexedFiles = try doublesOrStrings(try object(index["files"]))
        XCTAssertEqual(
            Set(indexedFiles.keys),
            Set(["manifest.json", "corpus-v1.json", "fixture-v1.json", "calibration-v1.json", "run-report-v1.json"])
        )
        for (name, expected) in indexedFiles {
            XCTAssertEqual(try sha256(url(golden(name))), expected, name)
        }
        XCTAssertEqual(
            try Data(contentsOf: url(golden("manifest.json"))),
            try Data(contentsOf: url("Models/current/manifest.json")),
            "Versioned manifest snapshot must match the normative manifest"
        )

        let environment = ProcessInfo.processInfo.environment
        if let modelPath = environment["QUALIAKIT_TEST_MODEL_PATH"] {
            let expected = [
                "Manifest.json": "a655c85265418a3c567fc48869e4bab5271b2340e33b7b67bdc395f3874bb302",
                "Data/com.apple.CoreML/model.mlmodel": "f7ac2156e756a2aacd1cca8cc3f3aded5e7b143147270ea0aea374747a609a42",
                "Data/com.apple.CoreML/weights/weight.bin": "26c028484b4df267933afbfa3ef9ca421dc7450d48bd02c720146bd4444da2f2",
            ]
            for (relative, checksum) in expected {
                XCTAssertEqual(try sha256(URL(fileURLWithPath: modelPath).appendingPathComponent(relative)), checksum)
            }
        }
        if let vocabPath = environment["QUALIAKIT_TEST_VOCAB_PATH"] {
            XCTAssertEqual(try sha256(URL(fileURLWithPath: vocabPath)), "78106a3d3ae8600d1ba573b967b9bb731d2c2282957cbc6e26ab20935c3da02b")
        }

        let fixtureURL = url(golden("fixture-v1.json"))
        let before = try sha256(fixtureURL)
        _ = try json(golden("fixture-v1.json"))
        XCTAssertEqual(try sha256(fixtureURL), before, "verification reads rather than overwrites immutable fixtures")

        let controlled = Data("immutable-fixture".utf8)
        let original = SHA256.hash(data: controlled).map { String(format: "%02x", $0) }.joined()
        var corrupted = controlled
        corrupted[0] ^= 0x01
        let changed = SHA256.hash(data: corrupted).map { String(format: "%02x", $0) }.joined()
        XCTAssertNotEqual(original, changed, "one-byte corruption must fail exact SHA-256 comparison")
        let comparatorSelfTest = try runReferenceTool(["--comparator-self-test"])
        XCTAssertEqual(comparatorSelfTest.status, 0, comparatorSelfTest.output)
        for scenario in [
            "discrete-mismatch-rejected",
            "float-at-tolerance-accepted",
            "float-over-tolerance-rejected",
        ] {
            XCTAssertTrue(comparatorSelfTest.output.contains(scenario), scenario)
        }
    }

    private func doublesOrStrings(_ value: [String: Any]) throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: value.map { key, item in
            (key, try XCTUnwrap(item as? String))
        })
    }

    func testSwiftTokenizerAndFinalMappingMatchIndependentGoldenCorpus() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let vocabPath = environment["QUALIAKIT_TEST_VOCAB_PATH"] else {
            throw XCTSkip("asset-backed parity requires QUALIAKIT_TEST_VOCAB_PATH")
        }
        let tokenizer = try BertTokenizer(vocabURL: URL(fileURLWithPath: vocabPath))
        let corpus = try json(golden("corpus-v1.json"))
        let fixture = try json(golden("fixture-v1.json"))
        let corpusCases = try array(corpus["cases"])
        let fixtureCases = try array(fixture["cases"])
        XCTAssertEqual(corpusCases.count, fixtureCases.count)

        for (source, expected) in zip(corpusCases, fixtureCases) {
            let id = try XCTUnwrap(source["id"] as? String)
            XCTAssertEqual(id, expected["id"] as? String)
            let text = try XCTUnwrap(source["text"] as? String)
            let actual = tokenizer.tokenize(text: text)
            XCTAssertEqual(actual.inputIds, try ints(expected["inputIds"]), "input IDs: \(id)")
            XCTAssertEqual(actual.attentionMask, try ints(expected["attentionMask"]), "attention mask: \(id)")
            XCTAssertEqual(actual.inputIds.count, 128)
            XCTAssertEqual(actual.attentionMask.count, 128)
            XCTAssertTrue(try ints(expected["tokenTypeIds"]).allSatisfy { $0 == 0 })
        }

        guard let modelPath = environment["QUALIAKIT_TEST_MODEL_PATH"] else {
            throw XCTSkip("raw model parity requires QUALIAKIT_TEST_MODEL_PATH")
        }
        let sourceModelURL = URL(fileURLWithPath: modelPath)
        let compiledModelURL = sourceModelURL.lastPathComponent.hasSuffix(".mlmodelc")
            ? sourceModelURL
            : try MLModel.compileModel(at: sourceModelURL)
        let wrapper = try BertModelWrapper(modelURL: compiledModelURL)
        let rawOutputOracle = try MLModel(contentsOf: compiledModelURL)
        for (source, expected) in zip(corpusCases, fixtureCases) {
            let text = try XCTUnwrap(source["text"] as? String)
            let tensors = tokenizer.tokenize(text: text)
            let actual = try wrapper.predictSentiment(inputIds: tensors.inputIds, attentionMask: tensors.attentionMask)
            let output = try rawOutputOracle.prediction(from: modelInput(
                inputIds: tensors.inputIds,
                attentionMask: tensors.attentionMask
            ))
            let rawScores = try XCTUnwrap(
                output.featureValue(for: "classLabel_probs")?.dictionaryValue as? [String: Double]
            )
            let orderedScores = try labels.map { try XCTUnwrap(rawScores[$0]) }
            let maximum = try XCTUnwrap(orderedScores.max())
            let exponentials = orderedScores.map { exp($0 - maximum) }
            let denominator = exponentials.reduce(0, +)
            let expectedValue = exponentials[2] / denominator - exponentials[0] / denominator
            XCTAssertEqual(actual, expectedValue, accuracy: 0,
                           "same-backend current Swift transform: \(expected["id"] as? String ?? "unknown")")
            XCTAssertTrue(actual.isFinite)
            XCTAssertTrue((-1.0...1.0).contains(actual))
        }
    }

    private func modelInput(inputIds: [Int], attentionMask: [Int]) throws -> MLFeatureProvider {
        let shape = [1, NSNumber(value: inputIds.count)] as [NSNumber]
        let inputIDs = try MLMultiArray(shape: shape, dataType: .int32)
        let mask = try MLMultiArray(shape: shape, dataType: .int32)
        let tokenTypes = try MLMultiArray(shape: shape, dataType: .int32)
        for index in inputIds.indices {
            let position = [0, index] as [NSNumber]
            inputIDs[position] = NSNumber(value: inputIds[index])
            mask[position] = NSNumber(value: attentionMask[index])
            tokenTypes[position] = 0
        }
        return try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIDs),
            "attention_mask": MLFeatureValue(multiArray: mask),
            "token_type_ids": MLFeatureValue(multiArray: tokenTypes),
        ])
    }

    func testCoreMLOutputContractAndTransforms() throws {
        let manifest = try json("Models/current/manifest.json")
        let inputs = try object(manifest["inputs"])
        XCTAssertEqual(Set(inputs.keys), Set(["input_ids", "attention_mask", "token_type_ids"]))
        for name in inputs.keys {
            let input = try object(inputs[name])
            XCTAssertEqual(input["dataType"] as? String, "Int32")
            XCTAssertEqual(try ints(input["shape"]), [1, 128])
            XCTAssertEqual(input["required"] as? Bool, true)
        }
        let outputs = try object(manifest["outputs"])
        XCTAssertEqual(try array(outputs["labels"]).compactMap { $0["name"] as? String }, labels)
        XCTAssertEqual(try object(outputs["kind"])["value"] as? String, "classifier_logits")

        let graph = try json("Models/current/graph-evidence.json")
        XCTAssertEqual(graph["classifierSoftmaxBetweenLinearAndClassify"] as? Bool, false)
        XCTAssertEqual((graph["encoderSoftmaxOperationCount"] as? NSNumber)?.intValue, 12)
        XCTAssertEqual(try strings(graph["labels"]), labels)

        let fixture = try json(golden("fixture-v1.json"))
        var observedNonProbabilityDictionary = false
        for item in try array(fixture["cases"]) {
            let raw = try doubles(item["rawOutputs"])
            XCTAssertEqual(Set(raw.keys), Set(labels))
            XCTAssertTrue(raw.values.allSatisfy(\.isFinite))
            if raw.values.contains(where: { $0 < 0 }) || abs(raw.values.reduce(0, +) - 1.0) > 0.01 {
                observedNonProbabilityDictionary = true
            }
            let stable = softmax(raw)
            let serialized = try doubles(try object(item["transformedScores"])["stableSoftmax"])
            for label in labels {
                XCTAssertEqual(try XCTUnwrap(serialized[label]), try XCTUnwrap(stable[label]), accuracy: 1e-15)
            }
            XCTAssertEqual(stable.values.reduce(0, +), 1.0, accuracy: 1e-12)
            let argmax = try XCTUnwrap(labels.max { raw[$0, default: -.infinity] < raw[$1, default: -.infinity] })
            XCTAssertEqual(item["predictedLabel"] as? String, argmax)
            let current = try XCTUnwrap(try object(item["currentSwiftTransform"])["value"] as? NSNumber).doubleValue
            XCTAssertEqual(current, stable["LABEL_2", default: 0] - stable["LABEL_0", default: 0], accuracy: 1e-15)
        }
        XCTAssertTrue(observedNonProbabilityDictionary)
    }

    private func softmax(_ raw: [String: Double]) -> [String: Double] {
        let maximum = raw.values.max() ?? 0
        let exponentials = Dictionary(uniqueKeysWithValues: labels.map { ($0, exp(raw[$0, default: 0] - maximum)) })
        let sum = exponentials.values.reduce(0, +)
        return Dictionary(uniqueKeysWithValues: labels.map { ($0, exponentials[$0, default: 0] / sum) })
    }

    func testUnknownsReleaseRisksMismatchInventoryAndM0Gate() throws {
        let manifest = try json("Models/current/manifest.json")
        let outputs = try object(manifest["outputs"])
        for label in try array(outputs["labels"]) {
            let semantic = try object(label["semanticMeaning"])
            XCTAssertEqual(semantic["status"] as? String, "unknown")
            XCTAssertFalse((semantic["owner"] as? String ?? "").isEmpty)
            XCTAssertFalse((semantic["proofPlan"] as? String ?? "").isEmpty)
            XCTAssertTrue(label.keys.contains("productSignal"))
            XCTAssertTrue(label["productSignal"] is NSNull)
        }
        let tokenizer = try object(manifest["tokenizer"])
        XCTAssertEqual(try object(tokenizer["contextPairSupport"])["status"] as? String, "unknown")
        let provenance = try object(manifest["provenance"])
        for field in ["source", "dataset", "domain", "classBalance", "trainingConfiguration"] {
            XCTAssertEqual(try object(provenance[field])["status"] as? String, "unknown")
        }
        let model = try object(manifest["model"])
        XCTAssertEqual(try object(model["license"])["status"] as? String, "unknown")
        XCTAssertEqual(try object(model["redistribution"])["status"] as? String, "blocked")
        let risks = try array(manifest["releaseRisks"])
        XCTAssertTrue(Set(risks.compactMap { $0["field"] as? String }).isSuperset(of: [
            "source", "dataset", "license", "domain", "classBalance", "redistributionRights",
        ]))

        let card = try String(contentsOf: url("Models/current/MODEL_CARD.md"), encoding: .utf8)
        for requiredMismatch in [
            "Unicode normalization", "second stable softmax", "Missing dictionary labels",
            "neutral-like behavior", "all-zero `token_type_ids`", "repository MIT license",
            "reference verifier pins CPU-only",
        ] {
            XCTAssertTrue(card.localizedCaseInsensitiveContains(requiredMismatch), requiredMismatch)
        }
        let benchmark = try String(contentsOf: url("Benchmarks/Models/current-baseline.md"), encoding: .utf8)
        XCTAssertTrue(benchmark.contains("pending consolidated release gate HG-0015-002"))
        XCTAssertTrue(benchmark.localizedCaseInsensitiveContains("do not log source text"))

        let gateFields = ["labelSemantics", "outputKind", "tokenizerTrainingParity", "provenance"]
        for unresolvedField in gateFields {
            var conditions = Dictionary(uniqueKeysWithValues: gateFields.map { ($0, "resolved") })
            conditions[unresolvedField] = "unresolved"
            XCTAssertEqual(gateStatus(conditions), "blocked", unresolvedField)
        }
        XCTAssertEqual(gateStatus(Dictionary(uniqueKeysWithValues: gateFields.map { ($0, "resolved") })), "open")
        let declaredGate = try object(manifest["runtimeRefactorGate"])
        XCTAssertEqual(gateStatus(try doublesOrStrings(try object(declaredGate["conditions"]))), "blocked")
    }

    private func gateStatus(_ conditions: [String: String]) -> String {
        conditions.values.contains("unresolved") ? "blocked" : "open"
    }

    func testVerifierRejectsInvalidInputsWithoutLeakingText() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", url("Tools/ModelContract/reference_inference.py").path, "--verify"]
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "QUALIAKIT_TEST_MODEL_PATH")
        environment.removeValue(forKey: "QUALIAKIT_TEST_VOCAB_PATH")
        process.environment = environment
        let errorPipe = Pipe()
        let outputPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = outputPipe
        try process.run()
        process.waitUntilExit()
        let diagnostic = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertTrue(diagnostic.contains("contract-error[environment:QUALIAKIT_TEST_MODEL_PATH]"))
        XCTAssertFalse(diagnostic.contains("На лестнице"), "errors must not leak curated or private text")

        guard let modelPath = ProcessInfo.processInfo.environment["QUALIAKIT_TEST_MODEL_PATH"],
              let vocabPath = ProcessInfo.processInfo.environment["QUALIAKIT_TEST_VOCAB_PATH"] else {
            return
        }
        for probe in ["missing-model-component", "vocabulary-checksum", "unsupported-schema",
                      "incomplete-fixture", "checksum-inventory", "holdout-overrun",
                      "published-overwrite"] {
            let mutation = Process()
            mutation.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            mutation.arguments = [
                "python3", url("Tools/ModelContract/reference_inference.py").path,
                "--probe-error", probe, "--model-path", modelPath, "--vocab-path", vocabPath,
            ]
            mutation.environment = ProcessInfo.processInfo.environment
            let mutationError = Pipe()
            mutation.standardError = mutationError
            mutation.standardOutput = Pipe()
            try mutation.run()
            mutation.waitUntilExit()
            let mutationDiagnostic = String(
                decoding: mutationError.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
            )
            XCTAssertNotEqual(mutation.terminationStatus, 0, probe)
            XCTAssertTrue(mutationDiagnostic.contains("contract-error["), probe)
            XCTAssertFalse(mutationDiagnostic.contains("На лестнице"), probe)
        }
    }

    func testPinnedEnvironmentAndFreshProcessCalibrationEvidence() throws {
        let lock = try String(contentsOf: url("Tools/ModelContract/requirements.lock"), encoding: .utf8)
        for pin in ["python==3.14.0", "python-dependencies==standard-library-only", "swift==6.3.3",
                    "xcode==26.6", "coremlcompiler==3520.5.1", "coreml-compute-units==cpuOnly",
                    "network-access==disabled"] {
            XCTAssertTrue(lock.contains(pin), pin)
        }

        let calibration = try json(golden("calibration-v1.json"))
        let calibrationRuns = try array(calibration["calibrationRuns"])
        let holdoutRuns = try array(calibration["holdoutRuns"])
        XCTAssertGreaterThanOrEqual(calibrationRuns.count, 10)
        XCTAssertGreaterThanOrEqual(holdoutRuns.count, 5)
        let allRuns = calibrationRuns + holdoutRuns
        let sequences = try allRuns.map { try XCTUnwrap($0["processSequence"] as? NSNumber).intValue }
        let processIdentifiers = try allRuns.map { try XCTUnwrap($0["processIdentifier"] as? NSNumber).intValue }
        XCTAssertEqual(Set(sequences).count, sequences.count)
        XCTAssertEqual(Set(processIdentifiers).count, processIdentifiers.count)
        XCTAssertEqual(sequences, sequences.sorted())
        XCTAssertTrue(allRuns.allSatisfy { $0["freshOSProcess"] as? Bool == true })
        XCTAssertTrue(allRuns.allSatisfy { $0["computeUnits"] as? String == "cpuOnly" })
        XCTAssertTrue(allRuns.allSatisfy {
            ($0["helperSourceSha256"] as? String)?.count == 64
                && ($0["helperExecutableSha256"] as? String)?.count == 64
                && ($0["privateCompilationDirectory"] as? Bool) == true
                && ($0["privateCompilationIdentifier"] as? String)?.count == 32
        })
        let compilationIdentifiers = try allRuns.map {
            try XCTUnwrap($0["privateCompilationIdentifier"] as? String)
        }
        XCTAssertEqual(Set(compilationIdentifiers).count, compilationIdentifiers.count)
        for (earlier, later) in zip(allRuns, allRuns.dropFirst()) {
            let ended = try XCTUnwrap(earlier["endedMonotonicSeconds"] as? NSNumber).doubleValue
            let started = try XCTUnwrap(later["startedMonotonicSeconds"] as? NSNumber).doubleValue
            XCTAssertLessThanOrEqual(ended, started, "fresh process runs must not overlap")
        }
        let protocolObject = try object(calibration["protocol"])
        XCTAssertEqual(protocolObject["sequentialProcesses"] as? Bool, true)
        XCTAssertEqual(protocolObject["modelReloadedEachProcess"] as? Bool, true)
        XCTAssertEqual(protocolObject["modelRecompiledEachProcess"] as? Bool, true)
        XCTAssertEqual(protocolObject["privateCompilationPerProcess"] as? Bool, true)
        XCTAssertEqual(protocolObject["corpusScope"] as? String, "full")
        let environment = try object(calibration["environment"])
        XCTAssertEqual(environment["backend"] as? String, "CoreML")
        XCTAssertEqual(environment["computeUnits"] as? String, "cpuOnly")
        XCTAssertEqual((environment["networkDependencies"] as? [Any])?.count, 0)

        let referenceCases = try array(calibration["referenceCases"])
        let baseline = Dictionary(uniqueKeysWithValues: try referenceCases.map { item in
            (try XCTUnwrap(item["id"] as? String), try doubles(item["floatingValues"]))
        })
        var accumulated: [String: [Double]] = [:]
        for run in calibrationRuns {
            for item in try array(run["cases"]) {
                let id = try XCTUnwrap(item["id"] as? String)
                let expected = try XCTUnwrap(baseline[id])
                let actual = try floatingFields(item)
                for field in expected.keys {
                    accumulated[field, default: []].append(abs(actual[field, default: 0] - expected[field, default: 0]))
                }
            }
        }
        let storedDistributions = try object(calibration["distributions"])
        let tolerances = try doubles(calibration["absoluteToleranceByField"])
        for (field, values) in accumulated {
            let ordered = values.sorted()
            let stored = try object(storedDistributions[field])
            XCTAssertEqual((stored["count"] as? NSNumber)?.intValue, ordered.count)
            XCTAssertEqual(try XCTUnwrap(stored["min"] as? NSNumber).doubleValue, try XCTUnwrap(ordered.first), accuracy: 0, field)
            XCTAssertEqual(try XCTUnwrap(stored["p50"] as? NSNumber).doubleValue, percentile(ordered, 0.50), accuracy: 1e-15)
            XCTAssertEqual(try XCTUnwrap(stored["p95"] as? NSNumber).doubleValue, percentile(ordered, 0.95), accuracy: 1e-15)
            XCTAssertEqual(try XCTUnwrap(stored["p99"] as? NSNumber).doubleValue, percentile(ordered, 0.99), accuracy: 1e-15)
            XCTAssertEqual(try XCTUnwrap(stored["max"] as? NSNumber).doubleValue, try XCTUnwrap(ordered.last), accuracy: 0, field)
            XCTAssertEqual(try XCTUnwrap(tolerances[field]), try XCTUnwrap(ordered.last), accuracy: 0, field)
        }
        for run in holdoutRuns {
            XCTAssertEqual(run["withinFixedTolerance"] as? Bool, true)
            let maxima = try doubles(run["maximumDeltaByField"])
            for field in tolerances.keys {
                XCTAssertLessThanOrEqual(maxima[field, default: .infinity], tolerances[field, default: 0])
            }
        }
    }

    private func floatingFields(_ item: [String: Any]) throws -> [String: Double] {
        if let stored = item["floatingValues"] {
            return try doubles(stored)
        }
        let raw = try doubles(item["rawOutputs"])
        let stable = softmax(raw)
        var result = Dictionary(uniqueKeysWithValues: labels.map { ("rawOutputs.\($0)", raw[$0, default: 0]) })
        result.merge(Dictionary(uniqueKeysWithValues: labels.map { ("stableSoftmax.\($0)", stable[$0, default: 0]) })) { _, new in new }
        if let currentSwiftValue = (item["currentSwiftTransformValue"] as? NSNumber)?.doubleValue {
            result["currentSwiftTransform.value"] = currentSwiftValue
        } else if let transformed = item["transformedScores"] as? [String: Any] {
            let referenceStable = try doubles(transformed["stableSoftmax"])
            result["currentSwiftTransform.value"] =
                referenceStable["LABEL_2", default: 0] - referenceStable["LABEL_0", default: 0]
        } else {
            result["currentSwiftTransform.value"] = stable["LABEL_2", default: 0] - stable["LABEL_0", default: 0]
        }
        return result
    }

    private func percentile(_ ordered: [Double], _ probability: Double) -> Double {
        guard !ordered.isEmpty else { return 0 }
        let rank = Double(ordered.count - 1) * probability
        let lower = Int(floor(rank))
        let upper = Int(ceil(rank))
        if lower == upper { return ordered[lower] }
        let fraction = rank - Double(lower)
        return ordered[lower] * (1 - fraction) + ordered[upper] * fraction
    }
}
