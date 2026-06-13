import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SyncEngineCaptureTests {
    let tripID = UUID()

    @Test func localUpsertEnqueuesUpsert() {
        var box = Outbox()
        let item = ChecklistItem(id: UUID(), kind: .prep, label: "X",
                                 modifiedAt: Date(timeIntervalSince1970: 3))
        SyncEngine.captureUpsert(kind: .item, id: item.id, tripID: tripID,
                                 modifiedAt: item.modifiedAt, into: &box)
        #expect(box.pending.count == 1)
        #expect(box.pending.first?.op == .upsert)
        #expect(box.pending.first?.modifiedAt == Date(timeIntervalSince1970: 3))
    }

    @Test func localDeleteEnqueuesDeleteAndRecordsTombstone() {
        var box = Outbox(); var state = SyncState()
        let id = UUID(); let at = Date(timeIntervalSince1970: 4)
        SyncEngine.captureDelete(kind: .item, id: id, tripID: tripID,
                                 deletedAt: at, into: &box, state: &state)
        #expect(box.pending.first?.op == .delete)
        #expect(state.tombstones[id] == at)
    }
}
