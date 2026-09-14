import Foundation
import OSLog

/// Opt-in local OSLog adapter. The entire already-redacted payload is marked
/// private. No queue, file, network transport, or raw-text debug switch is added.
public struct OSLogQualiaDiagnosticsSink: QualiaDiagnosticsSink {
    private let logger = Logger(subsystem: "com.qualiakit.runtime", category: "diagnostics")
    public init() {}
    public func record(_ event: QualiaDiagnosticEvent) {
        logger.debug("Qualia schema=1 event=\(String(describing: event), privacy: .private)")
    }
}
