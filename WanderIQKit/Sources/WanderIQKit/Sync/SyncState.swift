import Foundation

/// Durable sync bookkeeping: the pull cursor and live tombstones.
/// `tombstones[id] = deletedAt`. Persisted by the app between launches.
///
/// Pruning is deliberately deferred to sub-project 3 (the real backend). A
/// tombstone may be dropped only once its delete has round-tripped — i.e. we
/// observe our own tombstone echoed back from the server. Pruning by comparing
/// `tombstones[id]` against `cursor` is INVALID: the tombstone value is a
/// client `deletedAt` clock while `cursor` is the server's `server_updated_at`
/// clock. Until then tombstones only grow by one per deletion (family scale),
/// and retaining them is correct: they make last-writer-wins reject stale
/// upserts for already-deleted ids.
public struct SyncState: Equatable, Codable, Sendable {
    public var cursor: Date
    public var tombstones: [UUID: Date]

    public init(cursor: Date = .distantPast, tombstones: [UUID: Date] = [:]) {
        self.cursor = cursor
        self.tombstones = tombstones
    }
}
