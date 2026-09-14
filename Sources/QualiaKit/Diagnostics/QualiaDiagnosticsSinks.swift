import Foundation
import OSLog

/// Opt-in local OSLog adapter. The entire already-redacted payload is marked
/// private. No queue, file, network transport, or raw-text debug switch is added.
public struct OSLogQualiaDiagnosticsSink: QualiaDiagnosticsSink {
    public init() {}
    public func record(_ event: QualiaDiagnosticEvent) {
        // Logger is not Sendable in the minimum supported SDK (Xcode 15.2).
        // Keep it local so this sink has no non-Sendable stored state.
        let logger = Logger(subsystem: "com.qualiakit.runtime", category: "diagnostics")
        logger.debug("Qualia schema=1 event=\(String(describing: event), privacy: .private)")
    }
}
