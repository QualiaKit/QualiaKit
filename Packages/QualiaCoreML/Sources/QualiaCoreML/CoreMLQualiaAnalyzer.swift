import CoreML
import Foundation
import QualiaKit

public struct CoreMLAnalyzerConfiguration: Sendable {
    public enum ComputeUnits: String, Sendable {
        case cpuOnly, cpuAndGPU, all

        var coreML: MLComputeUnits {
            switch self {
            case .cpuOnly: return .cpuOnly
            case .cpuAndGPU: return .cpuAndGPU
            case .all: return .all
            }
        }
    }

    public let computeUnits: ComputeUnits
    /// Called synchronously on the worker. Keep this callback short; it never receives text or token IDs.
    public let diagnostics: (@Sendable (CoreMLRuntimeEvent) -> Void)?

    public init(computeUnits: ComputeUnits = .cpuOnly, diagnostics: (@Sendable (CoreMLRuntimeEvent) -> Void)? = nil) {
        self.computeUnits = computeUnits
        self.diagnostics = diagnostics
    }
}

public struct CoreMLRuntimeEvent: Sendable {
    public enum Stage: String, Sendable {
        case compiled, loaded, tokenized, prepared, predictionStarted, predicted, transformed
    }

    public let stage: Stage
    public let modelIdentifier: String
    public let modelVersion: String
    public let contractVersion: String
    public let sourceKind: QualiaResolvedModel.SourceKind
    public let computeUnits: CoreMLAnalyzerConfiguration.ComputeUnits
    public let durationSeconds: Double
    public let tokenCount: Int?
    public let truncatedTokenCount: Int?
}

/// A local, manifest-selected text classifier. The first execution profile is documented in
/// `Documentation/CoreMLRuntime.md`; unsupported contracts fail at initialization.
public struct CoreMLQualiaAnalyzer: QualiaAnalyzing {
    public let capabilities: QualiaAnalyzerCapabilities
    public let identity: QualiaAnalyzerIdentity
    public let modelVersion: String
    public let contractVersion: String
    private let worker: CoreMLWorker

    public init(source: any QualiaModelSource, configuration: CoreMLAnalyzerConfiguration = .init()) async throws {
        try Task.checkCancellation()
        let resolved: QualiaResolvedModel
        do { resolved = try await source.resolve() }
        catch {
            try Task.checkCancellation()
            if error is CancellationError { throw CancellationError() }
            throw (error as? CoreMLRuntimeError) ?? .missingAsset
        }
        try Task.checkCancellation()
        let worker = CoreMLWorker(source: resolved, configuration: configuration)
        let contract = try await worker.load()
        try Task.checkCancellation()
        self.worker = worker
        capabilities = contract.capabilities
        identity = contract.identity
        modelVersion = contract.manifest.model.version
        contractVersion = contract.manifest.contractVersion
    }

    public func analyze(_ input: QualiaInput) async throws -> QualiaObservation {
        try Task.checkCancellation()
        guard let language = input.language else { throw QualiaError.languageUndetermined }
        guard capabilities.languages.contains(language) else { throw QualiaError.unsupportedLanguage(language) }
        guard input.context.isEmpty else { throw QualiaError.unsupportedContext }
        let observation = try await worker.analyze(input)
        try Task.checkCancellation()
        return observation
    }
}

/// MLModel and all per-call Core ML objects stay on this actor. Both isolated entry points
/// are synchronous: there is no suspension from preparation through synchronous prediction.
/// Consequently at most one prediction can execute per instance, even under concurrent callers.
private actor CoreMLWorker {
    let source: QualiaResolvedModel
    let configuration: CoreMLAnalyzerConfiguration
    var state: LoadedState?
    let snapshot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

    struct LoadedState {
        let contract: ValidatedContract
        let tokenizer: RuntimeTokenizer
        let model: MLModel
    }

    init(source: QualiaResolvedModel, configuration: CoreMLAnalyzerConfiguration) {
        self.source = source
        self.configuration = configuration
    }

    deinit {
        LocalAssets.removeSnapshot(snapshot)
    }

    func load() throws -> ValidatedContract {
        try Task.checkCancellation()
        let started = ProcessInfo.processInfo.systemUptime
        var retained = false
        defer { if !retained { LocalAssets.removeSnapshot(snapshot) } }
        do {
            let manifest = try QualiaModelManifest.decode(LocalAssets.read(LocalAssets.child(source.manifestName, of: source.directory)))
            let contract = try manifest.validateForExecution()
            let tokenizerData = try LocalAssets.read(LocalAssets.child(manifest.tokenizer.vocabulary, of: source.directory),
                                                     sha256: manifest.tokenizer.vocabularySha256)
            let tokenizer = try RuntimeTokenizer(configuration: manifest.tokenizer, data: tokenizerData)
            try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
            let modelURL = try LocalAssets.snapshotModel(contract, root: source.directory, into: snapshot)
            try Task.checkCancellation()
            let compiledURL: URL
            if contract.execution.model.format == "mlmodel" {
                let compilationStarted = ProcessInfo.processInfo.systemUptime
                do {
                    let temporary = try MLModel.compileModel(at: modelURL)
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    compiledURL = snapshot.appendingPathComponent("compiled.mlmodelc", isDirectory: true)
                    try FileManager.default.moveItem(at: temporary, to: compiledURL)
                }
                catch {
                    try Task.checkCancellation()
                    throw CoreMLRuntimeError.compilationFailed
                }
                emit(.compiled, contract: contract, since: compilationStarted)
            } else { compiledURL = modelURL }
            try Task.checkCancellation()
            let modelConfiguration = MLModelConfiguration()
            modelConfiguration.computeUnits = configuration.computeUnits.coreML
            let model: MLModel
            do { model = try MLModel(contentsOf: compiledURL, configuration: modelConfiguration) }
            catch {
                try Task.checkCancellation()
                throw CoreMLRuntimeError.modelLoadFailed
            }
            try RuntimeModelValidation.validate(model.modelDescription, contract: contract)
            emit(.loaded, contract: contract, since: started)
            try Task.checkCancellation()
            state = LoadedState(contract: contract, tokenizer: tokenizer, model: model)
            retained = true
            return contract
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw CancellationError() }
            throw (error as? CoreMLRuntimeError) ?? .modelLoadFailed
        }
    }

    func analyze(_ input: QualiaInput) throws -> QualiaObservation {
        try Task.checkCancellation()
        guard let state, let language = input.language else { throw CoreMLRuntimeError.modelLoadFailed }
        let contract = state.contract
        do {
            let tokenizationStarted = ProcessInfo.processInfo.systemUptime
            let prepared = try state.tokenizer.prepare(input.text)
            emit(.tokenized, contract: contract, since: tokenizationStarted, text: prepared)
            try Task.checkCancellation()
            let preparationStarted = ProcessInfo.processInfo.systemUptime
            let features: MLDictionaryFeatureProvider
            do { features = try RuntimeInputBuilder.build(prepared, contract: contract) }
            catch { throw CoreMLRuntimeError.inputPreparationFailed }
            emit(.prepared, contract: contract, since: preparationStarted, text: prepared)
            try Task.checkCancellation()
            let predictionStarted = ProcessInfo.processInfo.systemUptime
            emit(.predictionStarted, contract: contract, since: predictionStarted)
            try Task.checkCancellation()
            let output: any MLFeatureProvider
            do {
                // Selects the synchronous Core ML API, not the reentrant async overload.
                output = try state.model.prediction(from: features, options: MLPredictionOptions())
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw CancellationError() }
                throw CoreMLRuntimeError.predictionFailed
            }
            emit(.predicted, contract: contract, since: predictionStarted)
            try Task.checkCancellation()
            let transformationStarted = ProcessInfo.processInfo.systemUptime
            let raw = try RuntimeOutputAdapter.extract(output, contract: contract)
            let scores = try RuntimeOutputAdapter.scores(raw, contract: contract)
            let observation = QualiaObservation(inputID: input.id, signals: scores, language: language, analyzer: contract.identity)
            emit(.transformed, contract: contract, since: transformationStarted)
            try Task.checkCancellation()
            return observation
        } catch {
            try Task.checkCancellation()
            throw error
        }
    }

    private func emit(_ stage: CoreMLRuntimeEvent.Stage, contract: ValidatedContract, since start: Double, text: PreparedText? = nil) {
        configuration.diagnostics?(.init(
            stage: stage, modelIdentifier: contract.manifest.model.identifier,
            modelVersion: contract.manifest.model.version, contractVersion: contract.manifest.contractVersion,
            sourceKind: source.sourceKind, computeUnits: configuration.computeUnits,
            durationSeconds: ProcessInfo.processInfo.systemUptime - start,
            tokenCount: text?.tokenCount, truncatedTokenCount: text?.truncatedCount
        ))
    }
}
