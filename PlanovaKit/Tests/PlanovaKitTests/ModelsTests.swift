import Foundation
import Testing
@testable import PlanovaKit

@Suite struct ModelsTests {

    @Test func testTripCodableRoundTrip() throws {
        let day = TripDay(id: UUID(), date: Date(timeIntervalSince1970: 1_780_000_000), city: "上海", title: "抵达上海")
        let item = ChecklistItem(kind: .itinerary, label: "酒店早餐", dayID: day.id, time: "08:00", owner: "全家", sortOrder: 3)
        let trip = Trip(id: UUID(), name: "Test", startDate: Date(timeIntervalSince1970: 0),
                        endDate: Date(timeIntervalSince1970: 86_400), destinations: ["上海"],
                        days: [day], items: [item], schemaVersion: 1)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Trip.self, from: encoder.encode(trip))
        #expect(decoded == trip)
    }

    @Test func testChecklistItemDefaults() {
        let item = ChecklistItem(kind: .packing, label: "护照")
        #expect(item.isDone == false)
        #expect(item.dayID == nil)
        #expect(item.reminderDate == nil)
        #expect(item.notes == "")
    }

    @Test func testDaySortedPutsTimedItemsFirstInTimeOrder() {
        let a = ChecklistItem(kind: .itinerary, label: "a", sortOrder: 0)
        let b = ChecklistItem(kind: .itinerary, label: "b", time: "14:00", sortOrder: 1)
        let c = ChecklistItem(kind: .itinerary, label: "c", time: "09:30", sortOrder: 2)
        let d = ChecklistItem(kind: .itinerary, label: "d", sortOrder: 3)
        let sorted = ItinerarySort.daySorted([a, b, c, d])
        #expect(sorted.map(\.label) == ["c", "b", "a", "d"])
    }
}
