import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SyncEngineDiffCaptureTests {
    let tripID = UUID()

    private func trip(name: String, items: [ChecklistItem] = [], at: Date) -> Trip {
        Trip(id: tripID, name: name, startDate: Date(timeIntervalSince1970: 0),
             endDate: Date(timeIntervalSince1970: 0), items: items, modifiedAt: at)
    }

    @Test func newTripCapturesTripAndItemUpserts() {
        var box = Outbox(); var state = SyncState()
        let item = ChecklistItem(id: UUID(), kind: .prep, label: "X",
                                 modifiedAt: Date(timeIntervalSince1970: 5))
        let new = trip(name: "China", items: [item], at: Date(timeIntervalSince1970: 5))
        SyncEngine.capture(old: nil, new: new, into: &box, state: &state,
                           now: Date(timeIntervalSince1970: 5))
        let kinds = Set(box.pending.map(\.kind))
        #expect(kinds == [.trip, .item])
        #expect(box.pending.allSatisfy { $0.op == .upsert })
    }

    @Test func deletedItemCapturesDeleteAndTombstone() {
        var box = Outbox(); var state = SyncState()
        let item = ChecklistItem(id: UUID(), kind: .prep, label: "X",
                                 modifiedAt: Date(timeIntervalSince1970: 5))
        let old = trip(name: "China", items: [item], at: Date(timeIntervalSince1970: 5))
        let new = trip(name: "China", items: [], at: Date(timeIntervalSince1970: 5))
        SyncEngine.capture(old: old, new: new, into: &box, state: &state,
                           now: Date(timeIntervalSince1970: 7))
        #expect(box.pending.contains { $0.kind == .item && $0.op == .delete })
        #expect(state.tombstones[item.id] == Date(timeIntervalSince1970: 7))
    }
}
