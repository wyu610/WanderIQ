import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SupabaseRowMappingTests {
    let at = "2026-06-13T00:00:05Z"
    var atDate: Date { ISO8601DateFormatter().date(from: at)! }

    @Test func itemRowToSyncRecordCarriesFieldsAndDeleted() {
        let row = ItemRow(id: "00000000-0000-0000-0000-0000000000e1",
                          trip_id: "00000000-0000-0000-0000-0000000000f1",
                          kind: "prep", label: "Buy", notes: "n", day_id: nil,
                          time: "09:30", item_owner: "Mom", is_done: true,
                          sort_order: 2, reminder_date: nil,
                          place: PlaceRow(name: "Museum", query: "Museum SH",
                                          latitude: 31.0, longitude: 121.0),
                          modified_at: at, deleted: false)
        let rec = SupabaseRowMapping.syncRecord(item: row)
        #expect(rec.kind == .item)
        #expect(rec.deleted == false)
        #expect(rec.modifiedAt == atDate)
        #expect(rec.fields?["label"] == "Buy")
        #expect(rec.fields?["isDone"] == "true")
        #expect(rec.fields?["placeName"] == "Museum")
        #expect(rec.fields?["placeLat"] == "31.0")
    }

    @Test func syncRecordToItemRowRoundTripsCoreFields() {
        let rec = SyncRecord(kind: .item, id: UUID(), tripID: UUID(),
                             modifiedAt: atDate, deleted: false,
                             fields: ["kind": "packing", "label": "Socks",
                                      "notes": "", "isDone": "false", "sortOrder": "1"])
        let row = SupabaseRowMapping.itemRow(from: rec)
        #expect(row.kind == "packing")
        #expect(row.label == "Socks")
        #expect(row.is_done == false)
        #expect(row.sort_order == 1)
        #expect(row.modified_at == at)
        #expect(row.deleted == false)
    }

    @Test func tripTombstoneRecordMapsToDeletedRow() {
        let id = UUID(); let trip = id
        let rec = SyncRecord(kind: .trip, id: id, tripID: trip,
                             modifiedAt: atDate, deleted: true)
        let row = SupabaseRowMapping.tripRow(from: rec)
        #expect(row.deleted == true)
        #expect(row.modified_at == at)
    }
}
