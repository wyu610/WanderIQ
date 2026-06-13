import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SyncTypesTests {

    @Test func pendingChangeKeyIgnoresOpAndTime() {
        let id = UUID()
        let a = PendingChange(kind: .item, id: id, tripID: UUID(), op: .upsert,
                              modifiedAt: Date(timeIntervalSince1970: 1))
        let b = PendingChange(kind: .item, id: id, tripID: UUID(), op: .delete,
                              modifiedAt: Date(timeIntervalSince1970: 2))
        #expect(a.key == b.key)              // same (kind, id) → same coalescing key
    }

    @Test func differentKindSameIdAreDistinctKeys() {
        let id = UUID()
        let day  = PendingChange(kind: .day,  id: id, tripID: UUID(), op: .upsert, modifiedAt: .now)
        let item = PendingChange(kind: .item, id: id, tripID: UUID(), op: .upsert, modifiedAt: .now)
        #expect(day.key != item.key)
    }

    @Test func syncRecordRoundTripsThroughCodable() throws {
        let rec = SyncRecord(kind: .trip, id: UUID(), tripID: UUID(),
                             modifiedAt: Date(timeIntervalSince1970: 100),
                             deleted: false, fields: ["name": "HK"])
        let data = try JSONEncoder().encode(rec)
        let back = try JSONDecoder().decode(SyncRecord.self, from: data)
        #expect(back == rec)
    }
}
