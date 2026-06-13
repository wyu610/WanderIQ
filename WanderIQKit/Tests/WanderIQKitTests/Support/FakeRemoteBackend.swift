import Foundation
@testable import WanderIQKit

/// In-memory backend for tests and the conformance suite. Stamps a monotonic
/// server time on each send to model `server_updated_at`.
actor FakeRemoteBackend: RemoteSyncBackend {
    private var stored: [EntityKey: (record: SyncRecord, serverAt: Date)] = [:]
    private var clock = Date(timeIntervalSince1970: 0)

    func send(_ records: [SyncRecord]) async throws {
        for r in records {
            clock = clock.addingTimeInterval(1)
            stored[EntityKey(kind: r.kind, id: r.id)] = (r, clock)
        }
    }

    func changes(since cursor: Date) async throws -> ChangePage {
        let fresh = stored.values.filter { $0.serverAt > cursor }
            .sorted { $0.serverAt < $1.serverAt }
        let newCursor = fresh.last?.serverAt ?? cursor
        return ChangePage(records: fresh.map(\.record), cursor: newCursor)
    }
}
