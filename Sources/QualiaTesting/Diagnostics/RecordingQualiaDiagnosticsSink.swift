import Foundation
import QualiaKit

/// Explicit test/debug opt-in. Fixed-capacity in-memory storage; drop newest
/// when full. Sequence numbers include dropped events. No persistence or I/O.
public final class RecordingQualiaDiagnosticsSink: QualiaDiagnosticsSink, @unchecked Sendable {
    public struct Entry: Sendable {
        public let sequence: UInt64
        public let event: QualiaDiagnosticEvent
    }
    private let lock = NSLock()
    private let capacity: Int
    private var storage: [Entry] = []
    private var sequence: UInt64 = 0
    private var dropped: UInt64 = 0

    public init(capacity: Int = 1024) throws {
        guard (1...65_536).contains(capacity) else {
            throw QualiaError.invalidConfiguration(reason: .configuration)
        }
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }
    public var entries: [Entry] { lock.lock(); defer { lock.unlock() }; return storage }
    public var droppedEventCount: UInt64 { lock.lock(); defer { lock.unlock() }; return dropped }
    public func record(_ event: QualiaDiagnosticEvent) {
        lock.lock()
        defer { lock.unlock() }
        sequence &+= 1
        guard storage.count < capacity else { dropped &+= 1; return }
        storage.append(Entry(sequence: sequence, event: event))
    }
    /// Releases retained events; sequence numbers remain monotonic across drains.
    public func drain() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        let result = storage
        storage.removeAll(keepingCapacity: true)
        return result
    }
}
