import CryptoKit
import Foundation

public protocol QualiaModelSource: Sendable {
    func resolve() async throws -> QualiaResolvedModel
}

/// Local source locations. Validation and I/O occur on the runtime worker.
public struct QualiaResolvedModel: Sendable {
    public let directory: URL
    public let manifestName: String
    public let sourceKind: SourceKind

    public enum SourceKind: String, Sendable { case file, bundle }

    public init(directory: URL, manifestName: String = "manifest.json", sourceKind: SourceKind = .file) {
        self.directory = directory
        self.manifestName = manifestName
        self.sourceKind = sourceKind
    }
}

/// Resolves `.mlmodel` or locally pinned `.mlmodelc` assets relative to a manifest.
public struct FileQualiaModelSource: QualiaModelSource {
    private let resolved: QualiaResolvedModel

    public init(directory: URL, manifestName: String = "manifest.json") {
        resolved = .init(directory: directory, manifestName: manifestName)
    }

    public func resolve() async throws -> QualiaResolvedModel {
        try Task.checkCancellation()
        return resolved
    }
}

public struct BundledQualiaModelSource: QualiaModelSource {
    private let resolved: QualiaResolvedModel

    public init(bundle: Bundle, subdirectory: String, manifestName: String = "manifest.json") throws {
        guard let root = bundle.resourceURL else { throw CoreMLRuntimeError.missingAsset }
        resolved = .init(directory: try LocalAssets.child(subdirectory, of: root),
                         manifestName: manifestName, sourceKind: .bundle)
    }

    public func resolve() async throws -> QualiaResolvedModel {
        try Task.checkCancellation()
        return resolved
    }
}

enum LocalAssets {
    static func removeSnapshot(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Component checks and symlink rejection also apply to intermediate directories.
    static func child(_ relative: String, of root: URL) throws -> URL {
        guard root.isFileURL, !relative.isEmpty, !relative.contains("\\"), !relative.contains(":"),
              !relative.utf8.contains(0) else { throw CoreMLRuntimeError.invalidAssetPath }
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw CoreMLRuntimeError.invalidAssetPath
        }
        var url = root.standardizedFileURL.resolvingSymlinksInPath()
        for part in parts {
            url.appendPathComponent(String(part))
            if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true {
                throw CoreMLRuntimeError.invalidAssetPath
            }
        }
        return url
    }

    static func read(_ url: URL, sha256: String? = nil) throws -> Data {
        try Task.checkCancellation()
        guard url.isFileURL,
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw CoreMLRuntimeError.missingAsset
        }
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw CoreMLRuntimeError.missingAsset }
        if let sha256 {
            guard isSHA256(sha256) else { throw CoreMLRuntimeError.invalidManifest }
            guard digest(data) == sha256 else { throw CoreMLRuntimeError.checksumMismatch }
        }
        try Task.checkCancellation()
        return data
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// Snapshot verified bytes before Core ML uses them. No unverified original path is loaded.
    static func snapshotModel(_ contract: ValidatedContract, root: URL, into snapshot: URL) throws -> URL {
        let asset = contract.execution.model
        switch asset.format {
        case "mlmodel":
            guard contract.execution.compiledFrom == nil else { throw CoreMLRuntimeError.invalidManifest }
            return try snapshotFile(asset, root: root, into: snapshot, contract: contract)
        case "mlmodelc":
            guard asset.sha256 == nil, let files = asset.files, !files.isEmpty,
                  let origin = contract.execution.compiledFrom,
                  !origin.compiler.isBlank, !origin.evidence.isBlank else {
                throw CoreMLRuntimeError.invalidManifest
            }
            // Verify the source artifact as well. This records a declared compiler relationship;
            // it does not claim cross-toolchain reproducibility or cryptographic build provenance.
            _ = try snapshotFile(origin.source, root: root, into: snapshot, contract: contract)
            let source = try child(asset.path, of: root)
            guard source.pathExtension == "mlmodelc" else { throw CoreMLRuntimeError.invalidAssetPath }
            let actual = try fileInventory(in: source)
            guard actual == Set(files.keys) else { throw CoreMLRuntimeError.checksumMismatch }
            let destination = snapshot.appendingPathComponent("model.mlmodelc", isDirectory: true)
            for name in files.keys.sorted() {
                let data = try read(child(name, of: source), sha256: files[name])
                let target = try child(name, of: destination)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target)
            }
            return destination
        default:
            throw CoreMLRuntimeError.unsupportedExecutionContract
        }
    }

    private static func snapshotFile(
        _ asset: QualiaModelManifest.Asset, root: URL, into snapshot: URL, contract: ValidatedContract
    ) throws -> URL {
        guard asset.format == "mlmodel", let sha = asset.sha256, asset.files == nil,
              contract.manifest.model.componentSha256 == [asset.path: sha] else {
            throw CoreMLRuntimeError.invalidManifest
        }
        let source = try child(asset.path, of: root)
        guard source.pathExtension == "mlmodel" else { throw CoreMLRuntimeError.invalidAssetPath }
        let bytes = try read(source, sha256: sha)
        let destination = snapshot.appendingPathComponent("source.mlmodel")
        try bytes.write(to: destination)
        return destination
    }

    static func fileInventory(in directory: URL) throws -> Set<String> {
        let directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw CoreMLRuntimeError.missingAsset
        }
        var failed = false
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey],
            errorHandler: { _, _ in failed = true; return false }
        ) else { throw CoreMLRuntimeError.missingAsset }
        var names: Set<String> = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            guard values.isSymbolicLink != true else { throw CoreMLRuntimeError.invalidAssetPath }
            if values.isRegularFile == true {
                let path = url.standardizedFileURL.resolvingSymlinksInPath().path
                guard path.hasPrefix(directory.path + "/") else { throw CoreMLRuntimeError.invalidAssetPath }
                names.insert(String(path.dropFirst(directory.path.count + 1)))
            } else if values.isDirectory != true {
                throw CoreMLRuntimeError.invalidAssetPath
            }
        }
        guard !failed else { throw CoreMLRuntimeError.missingAsset }
        return names
    }
}
