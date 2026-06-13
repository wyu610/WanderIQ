import Testing
import Foundation
@testable import WanderIQKit

@Suite struct OutboxTests {
    let trip = UUID()

    @Test func enqueueCoalescesByKeyKeepingLatest() {
        var box = Outbox()
        let id = UUID()
        box.enqueue(PendingChange(kind: .item, id: id, tripID: trip, op: .upsert,
                                  modifiedAt: Date(timeIntervalSince1970: 1)))
        box.enqueue(PendingChange(kind: .item, id: id, tripID: trip, op: .delete,
                                  modifiedAt: Date(timeIntervalSince1970: 2)))
        #expect(box.pending.count == 1)
        #expect(box.pending.first?.op == .delete)        // latest wins
    }

    @Test func pendingPreservesInsertionOrderAcrossKeys() {
        var box = Outbox()
        let a = UUID(); let b = UUID()
        box.enqueue(PendingChange(kind: .day,  id: a, tripID: trip, op: .upsert, modifiedAt: .now))
        box.enqueue(PendingChange(kind: .item, id: b, tripID: trip, op: .upsert, modifiedAt: .now))
        #expect(box.pending.map(\.id) == [a, b])
    }

    @Test func acknowledgeRemovesOnlyMatchingKey() {
        var box = Outbox()
        let a = UUID(); let b = UUID()
        box.enqueue(PendingChange(kind: .day, id: a, tripID: trip, op: .upsert, modifiedAt: .now))
        box.enqueue(PendingChange(kind: .day, id: b, tripID: trip, op: .upsert, modifiedAt: .now))
        box.acknowledge(EntityKey(kind: .day, id: a))
        #expect(box.pending.map(\.id) == [b])
    }
}
