import Testing
import Foundation
@testable import WanderIQKit

@Suite struct TripExportCSVTests {

    private func sampleTrip() -> Trip {
        let day = TripDay(date: Date(timeIntervalSince1970: 0), city: "SH", title: "")
        let item = ChecklistItem(kind: .packing, label: "Socks, 3 pairs", notes: "warm",
                                 dayID: day.id, isDone: true, sortOrder: 0)
        return Trip(name: "T", startDate: Date(timeIntervalSince1970: 0),
                    endDate: Date(timeIntervalSince1970: 0), days: [day], items: [item])
    }

    @Test func exportCSVStartsWithBOMandHeaderAndQuotesCommas() {
        let csv = TripExportCodec.exportCSV(sampleTrip())
        #expect(csv.hasPrefix("\u{FEFF}"))  // UTF-8 BOM (Excel + 中文)
        #expect(csv.contains("kind,label,notes,day_date,time,owner,is_done,place_name,place_query"))
        #expect(csv.contains("\"Socks, 3 pairs\""))  // comma-containing field quoted
        #expect(csv.contains("packing"))
        #expect(csv.contains("true"))
    }

    @Test func importCSVItemsAddsItemsToTrip() {
        var trip = Trip(name: "T", startDate: Date(timeIntervalSince1970: 0),
                        endDate: Date(timeIntervalSince1970: 0))
        let csv = "\u{FEFF}kind,label,notes,day_date,time,owner,is_done,place_name,place_query\n" +
                  "prep,\"Buy, tickets\",note,,09:30,Mom,false,,\n"
        TripExportCodec.importCSVItems(csv, into: &trip)
        #expect(trip.items.count == 1)
        #expect(trip.items[0].label == "Buy, tickets")
        #expect(trip.items[0].kind == .prep)
        #expect(trip.items[0].time == "09:30")
        #expect(trip.items[0].isDone == false)
    }
}
