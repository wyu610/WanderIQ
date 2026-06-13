import Foundation

/// One page of pulled changes plus the advanced cursor.
public struct ChangePage: Equatable, Sendable {
    public let records: [SyncRecord]
    public let cursor: Date
    public init(records: [SyncRecord], cursor: Date) {
        self.records = records; self.cursor = cursor
    }
}

/// Transport abstraction. Sub-project 3 implements this with supabase-swift
/// (PostgREST upserts + cursor query + Realtime). The engine depends only on
/// this protocol, so it is fully testable with a fake.
public protocol RemoteSyncBackend: Sendable {
    /// Upsert records (tombstones included) to the server.
    func send(_ records: [SyncRecord]) async throws
    /// Fetch records with server_updated_at strictly greater than `cursor`,
    /// and the new cursor (max server_updated_at seen, else `cursor`).
    func changes(since cursor: Date) async throws -> ChangePage
}
