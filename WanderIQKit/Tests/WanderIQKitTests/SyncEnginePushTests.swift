import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SyncEnginePushTests {
    let tripID = UUID()

    @Test func pushSendsRecordsBuiltFromStoreAndClearsOutbox() async throws {
        let item = ChecklistItem(id: UUID(), kind: .prep, label: "Buy",
                                 modifiedAt: Date(timeIntervalSince1970: 3))
        let trip = Trip(id: tripID, name: "T", startDate: Date(timeIntervalSince1970: 0),
                        endDate: Date(timeIntervalSince1970: 0), items: [item],
                        modifiedAt: Date(timeIntervalSince1970: 1))
        let store = TripStore(trips: [trip])
        var box = Outbox()
        box.enqueue(PendingChange(kind: .item, id: item.id, tripID: tripID,
                                  op: .upsert, modifiedAt: item.modifiedAt))
        let backend = FakeRemoteBackend()

        try await SyncEngine.push(outbox: &box, store: store, backend: backend)

        #expect(box.isEmpty)
        let page = try await backend.changes(since: .distantPast)
        #expect(page.records.first?.fields?["label"] == "Buy")
    }

    @Test func pushSendsTombstoneForDeleteEntries() async throws {
        let store = TripStore(trips: [])
        var box = Outbox()
        let goneID = UUID()
        box.enqueue(PendingChange(kind: .item, id: goneID, tripID: tripID,
                                  op: .delete, modifiedAt: Date(timeIntervalSince1970: 4)))
        let backend = FakeRemoteBackend()

        try await SyncEngine.push(outbox: &box, store: store, backend: backend)

        let page = try await backend.changes(since: .distantPast)
        #expect(page.records.first?.deleted == true)
        #expect(page.records.first?.id == goneID)
        #expect(box.isEmpty)
    }
}
