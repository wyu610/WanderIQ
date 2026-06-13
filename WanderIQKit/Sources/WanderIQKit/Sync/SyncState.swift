import Foundation

/// Durable sync bookkeeping: the pull cursor and live tombstones.
/// `tombstones[id] = deletedAt`. Persisted by the app between launches.
public struct SyncState: Equatable, Codable, Sendable {
    public var cursor: Date
    public var tombstones: [UUID: Date]

    public init(cursor: Date = .distantPast, tombstones: [UUID: Date] = [:]) {
        self.cursor = cursor
        self.tombstones = tombstones
    }
}
