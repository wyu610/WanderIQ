import Testing
import Foundation
@testable import WanderIQKit

@Suite struct FakeRemoteBackendTests {
    let trip = UUID()

    @Test func pushThenPullReturnsRecordsAfterCursor() async throws {
        let backend = FakeRemoteBackend()
        let rec = SyncRecord(kind: .item, id: UUID(), tripID: trip,
                             modifiedAt: Date(timeIntervalSince1970: 5),
                             deleted: false, fields: ["label": "X"])
        try await backend.send([rec])
        let page = try await backend.changes(since: .distantPast)
        #expect(page.records.count == 1)
        #expect(page.cursor > Date.distantPast)
        // A pull at the new cursor sees nothing new.
        let empty = try await backend.changes(since: page.cursor)
        #expect(empty.records.isEmpty)
    }
}
