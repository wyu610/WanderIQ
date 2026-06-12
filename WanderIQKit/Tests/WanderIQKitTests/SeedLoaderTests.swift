import Foundation
import Testing
@testable import WanderIQKit

@Suite struct SeedLoaderTests {

    @Test func testSeedLoadsChinaTrip() throws {
        let trip = try SeedLoader.loadChinaTrip2026()
        #expect(trip.name == "2026 暑假中国行")
        #expect(trip.destinations == ["上海", "香港", "广州"])
        #expect(trip.days.count == 21)
        #expect(trip.items.count == 188)
        #expect(trip.items.filter { $0.kind == .prep }.count == 5)
        #expect(trip.items.filter { $0.kind == .hotel }.count == 6)
        #expect(trip.items.filter { $0.kind == .doc }.count == 5)
        #expect(trip.items.filter { $0.kind == .packing }.count == 10)
        #expect(trip.items.filter { $0.kind == .itinerary }.count == 162)
    }

    @Test func testFirstHotelIsBookedAndDayItemsLinkToDays() throws {
        let trip = try SeedLoader.loadChinaTrip2026()
        let hotelItems = trip.items.filter { $0.kind == .hotel }
        let hotels = hotelItems.sorted { $0.sortOrder < $1.sortOrder }
        #expect(hotels[0].isDone == true)
        #expect(hotels[1].isDone == false)

        let day12 = trip.days[1]
        #expect(day12.title == "滴水湖科技探索日")
        let day12Items = trip.items.filter { $0.dayID == day12.id }
        #expect(day12Items.count == 10)

        let dayIDs = Set(trip.days.map { $0.id })
        for item in trip.items where item.kind == .itinerary {
            #expect(item.dayID != nil)
            if let dayID = item.dayID {
                #expect(dayIDs.contains(dayID))
            }
        }
    }
}
