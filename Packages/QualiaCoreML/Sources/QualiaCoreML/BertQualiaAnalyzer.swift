import CoreML
import Foundation
import QualiaKit

/// A reusable BERT WordPiece sequence-classification adapter. Applications supply
/// a local manifest, vocabulary and Core ML model; no app-specific Swift adapter
/// or bundled weights are required. See docs/reference/BertRuntime.md.
public struct BertQualiaAnalyzer: QualiaAnalyzing {
    public let capabilities: QualiaAnalyzerCapabilities
    public let identity: QualiaAnalyzerIdentity
    public var diagnosticIdentity: QualiaDiagnosticIdentity? {
        .init(identifier: identity.identifier, version: identity.version)
    }
    private let worker: BertWorker

    public init(source: any QualiaModelSource, configuration: CoreMLAnalyzerConfiguration = .init()) async throws {
        try Task.checkCancellation()
        let resolved: QualiaResolvedModel
        do { resolved = try await source.resolve() }
        catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            throw (error as? CoreMLRuntimeError) ?? .missingAsset
        }
        let worker = BertWorker(source: resolved, configuration: configuration)
        let manifest = try await worker.load()
        try Task.checkCancellation()
        self.worker = worker
        capabilities = try manifest.capabilities()
        identity = try manifest.identity()
    }

    public func analyze(_ input: QualiaInput) async throws -> QualiaObservation {
        try Task.checkCancellation()
        guard let language = input.language else { throw QualiaError.languageUndetermined }
        guard capabilities.languages.contains(language) else { throw QualiaError.unsupportedLanguage(language) }
        guard capabilities.acceptsContext || input.context.isEmpty else { throw QualiaError.unsupportedContext }
        let result = try await worker.analyze(input)
        try Task.checkCancellation()
        return result
    }
}

/// Synchronous isolated methods serialize model access without actor reentrancy.
private actor BertWorker {
    let source: QualiaResolvedModel
    let configuration: CoreMLAnalyzerConfiguration
    let snapshot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    var state: State?
    struct State {
        let manifest: BertModelManifest
        let tokenizer: BertWordPieceTokenizer
        let model: MLModel
    }
    init(source: QualiaResolvedModel, configuration: CoreMLAnalyzerConfiguration) {
        self.source = source
        self.configuration = configuration
    }
    deinit { LocalAssets.removeSnapshot(snapshot) }

    func load() throws -> BertModelManifest {
        try Task.checkCancellation()
        var retained = false
        defer { if !retained { LocalAssets.removeSnapshot(snapshot) } }
        do {
            let manifest = try BertModelManifest.decode(LocalAssets.read(LocalAssets.child(source.manifestName, of: source.directory)))
            try manifest.validate()
            let bytes = try LocalAssets.read(LocalAssets.child(manifest.tokenizer.vocabulary, of: source.directory),
                                            sha256: manifest.tokenizer.vocabularySha256)
            let tokenizer = try BertWordPieceTokenizer(configuration: manifest.tokenizer, data: bytes)
            try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
            let url = try snapshotAsset(manifest.model)
            let compiled: URL
            let compilationStarted = ContinuousClock.now
            do {
                let temporary = try MLModel.compileModel(at: url)
                defer { LocalAssets.removeSnapshot(temporary) }
                compiled = snapshot.appendingPathComponent("compiled.mlmodelc", isDirectory: true)
                try FileManager.default.moveItem(at: temporary, to: compiled)
            } catch {
                try Task.checkCancellation()
                throw CoreMLRuntimeError.compilationFailed
            }
            emit(.compiled, manifest: manifest, since: compilationStarted)
            try Task.checkCancellation()
            let started = ContinuousClock.now
            let config = MLModelConfiguration()
            config.computeUnits = configuration.computeUnits.coreML
            let model: MLModel
            do { model = try MLModel(contentsOf: compiled, configuration: config) }
            catch { throw CoreMLRuntimeError.modelLoadFailed }
            try BertTensorAdapter.validate(model.modelDescription, manifest: manifest)
            emit(.loaded, manifest: manifest, since: started)
            try Task.checkCancellation()
            state = State(manifest: manifest, tokenizer: tokenizer, model: model)
            retained = true
            return manifest
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            throw (error as? CoreMLRuntimeError) ?? .invalidManifest
        }
    }

    func analyze(_ input: QualiaInput) throws -> QualiaObservation {
        try Task.checkCancellation()
        guard let state, let language = input.language else { throw CoreMLRuntimeError.modelLoadFailed }
        let manifest = state.manifest
        let tokenization = ContinuousClock.now
        let text = try state.tokenizer.prepare(text: input.text, context: input.context.map(\.text), sequence: manifest.sequence)
        emit(.tokenized, manifest: manifest, since: tokenization, count: text.tokenCount)
        try Task.checkCancellation()
        let preparation = ContinuousClock.now
        let features: MLDictionaryFeatureProvider
        do { features = try BertTensorAdapter.inputs(text, manifest: manifest) }
        catch {
            try Task.checkCancellation()
            throw CoreMLRuntimeError.inputPreparationFailed
        }
        emit(.prepared, manifest: manifest, since: preparation, count: text.tokenCount)
        try Task.checkCancellation()
        let started = ContinuousClock.now
        emit(.predictionStarted, manifest: manifest, since: started)
        try Task.checkCancellation()
        let output: any MLFeatureProvider
        do { output = try state.model.prediction(from: features, options: MLPredictionOptions()) }
        catch {
            try Task.checkCancellation()
            throw CoreMLRuntimeError.predictionFailed
        }
        emit(.predicted, manifest: manifest, since: started)
        try Task.checkCancellation()
        let transformation = ContinuousClock.now
        let scores = try BertTensorAdapter.scores(output, manifest: manifest)
        let result = QualiaObservation(inputID: input.id, signals: scores, language: language, analyzer: try manifest.identity())
        emit(.transformed, manifest: manifest, since: transformation)
        try Task.checkCancellation()
        return result
    }

    private func snapshotAsset(_ asset: QualiaModelManifest.Asset) throws -> URL {
        let sourceURL = try LocalAssets.child(asset.path, of: source.directory)
        let target = snapshot.appendingPathComponent("source." + asset.format)
        if asset.format == "mlmodel" {
            guard let sha = asset.sha256, asset.files == nil else { throw CoreMLRuntimeError.invalidManifest }
            try LocalAssets.read(sourceURL, sha256: sha).write(to: target)
        } else {
            guard asset.sha256 == nil, let files = asset.files, !files.isEmpty else { throw CoreMLRuntimeError.invalidManifest }
            guard try LocalAssets.fileInventory(in: sourceURL) == Set(files.keys) else { throw CoreMLRuntimeError.checksumMismatch }
            for name in files.keys.sorted() {
                let bytes = try LocalAssets.read(LocalAssets.child(name, of: sourceURL), sha256: files[name])
                let destination = try LocalAssets.child(name, of: target)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: destination)
            }
        }
        try Task.checkCancellation()
        return target
    }

    private func emit(_ stage: CoreMLRuntimeEvent.Stage, manifest: BertModelManifest,
                      since start: ContinuousClock.Instant, count: Int? = nil) {
        guard configuration.diagnostics != nil || configuration.diagnosticsSink.isEnabled else { return }
        let elapsed = start.duration(to: .now)
        configuration.diagnostics?(.init(stage: stage, modelIdentifier: .init(metadata: manifest.identifier),
            modelVersion: .init(metadata: manifest.version), contractVersion: .init(metadata: manifest.version),
            sourceKind: source.sourceKind, computeUnits: configuration.computeUnits,
            durationSeconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
            tokenCount: count, truncatedTokenCount: count == nil ? nil : 0))
        let sharedStage: QualiaDiagnosticEvent.ModelStage
        switch stage {
        case .compiled: sharedStage = .compiled
        case .loaded: sharedStage = .loaded
        case .tokenized: sharedStage = .tokenized
        case .prepared: sharedStage = .prepared
        case .predictionStarted: sharedStage = .predictionStarted
        case .predicted: sharedStage = .predicted
        case .transformed: sharedStage = .transformed
        }
        configuration.diagnosticsSink.emit(.model(stage: sharedStage,
            identity: .init(identifier: manifest.identifier, version: manifest.version),
            contract: .init(metadata: manifest.version), duration: elapsed,
            tokenCount: count, truncatedTokenCount: count == nil ? nil : 0))
    }
}

enum BertTensorAdapter {
    static func dtype(_ name: String) throws -> MLMultiArrayDataType {
        if name == "Float16" { return .float16 }
        return try RuntimeInputBuilder.dataType(name)
    }

    static func validate(_ model: MLModelDescription, manifest: BertModelManifest) throws {
        guard Set(model.inputDescriptionsByName.keys) == Set(manifest.inputs.keys),
              Set(model.outputDescriptionsByName.keys) == [manifest.output.feature] else {
            throw CoreMLRuntimeError.incompatibleModel
        }
        for (name, tensor) in manifest.inputs {
            try validateTensor(model.inputDescriptionsByName[name], shape: tensor.shape, dataType: tensor.dataType)
        }
        try validateTensor(model.outputDescriptionsByName[manifest.output.feature], shape: manifest.output.shape,
                           dataType: manifest.output.dataType)
    }

    private static func validateTensor(_ feature: MLFeatureDescription?, shape: [Int], dataType: String) throws {
        guard let feature, feature.type == .multiArray, !feature.isOptional,
              let tensor = feature.multiArrayConstraint, tensor.shape.map(\.intValue) == shape,
              tensor.dataType == (try dtype(dataType)), RuntimeModelValidation.isFixed(tensor.shapeConstraint, shape: shape) else {
            throw CoreMLRuntimeError.incompatibleModel
        }
    }

    static func inputs(_ text: BertPreparedText, manifest: BertModelManifest) throws -> MLDictionaryFeatureProvider {
        var features: [String: MLFeatureValue] = [:]
        for (name, tensor) in manifest.inputs {
            let values: [Int]
            switch tensor.role {
            case "tokenIDs": values = text.ids
            case "attentionMask": values = text.mask
            case "tokenTypeIDs": values = text.types
            case "positionIDs": values = Array(text.ids.indices)
            default: throw CoreMLRuntimeError.inputPreparationFailed
            }
            let array = try MLMultiArray(shape: tensor.shape.map(NSNumber.init), dataType: dtype(tensor.dataType))
            for (i, value) in values.enumerated() { array[i] = NSNumber(value: value) }
            features[name] = MLFeatureValue(multiArray: array)
        }
        return try MLDictionaryFeatureProvider(dictionary: features)
    }

    static func scores(_ output: any MLFeatureProvider, manifest: BertModelManifest) throws -> [QualiaSignal: QualiaScore] {
        guard let feature = output.featureValue(for: manifest.output.feature), !feature.isUndefined,
              let tensor = feature.multiArrayValue, tensor.shape.map(\.intValue) == manifest.output.shape,
              tensor.dataType == (try dtype(manifest.output.dataType)) else { throw CoreMLRuntimeError.missingOutput }
        let values = (0..<tensor.count).map { tensor[$0].doubleValue }
        let probabilities = try RuntimeOutputAdapter.probabilities(values, classification: manifest.output.classification,
                                                                   transform: manifest.output.transform)
        return try Dictionary(uniqueKeysWithValues: zip(manifest.output.labels, probabilities).map {
            (try QualiaSignal(rawValue: $0.signal), try QualiaScore(value: Float($1), confidence: nil))
        })
    }
}
