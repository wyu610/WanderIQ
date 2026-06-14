import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SupabaseRowsTests {
    @Test func tripRowDecodesSnakeCaseJSON() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-0000000000a1",
         "owner_id":"00000000-0000-0000-0000-0000000000b2",
         "name":"China","start_date":"2026-07-11","end_date":"2026-07-31",
         "destinations":["Shanghai","HK"],"schema_version":1,
         "modified_at":"2026-06-13T00:00:05Z","deleted":false}
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(TripRow.self, from: json)
        #expect(row.name == "China")
        #expect(row.destinations == ["Shanghai", "HK"])
        #expect(row.modified_at == "2026-06-13T00:00:05Z")
        #expect(row.deleted == false)
    }

    @Test func itemRowEncodesWithSnakeCaseKeys() throws {
        let row = ItemRow(id: "i1", trip_id: "t1", kind: "prep", label: "X",
                          notes: "", day_id: nil, time: nil, item_owner: nil,
                          is_done: true, sort_order: 0, reminder_date: nil,
                          place: nil, modified_at: "2026-06-13T00:00:05Z", deleted: false)
        let data = try JSONEncoder().encode(row)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains("\"is_done\":true"))
        #expect(s.contains("\"sort_order\":0"))
    }
}
