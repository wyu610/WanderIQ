import Testing
import Foundation
@testable import WanderIQKit

@Suite struct TripExportJSONTests {

    @Test func importThenExportRoundTripsTheSharedFixture() throws {
        let url = Bundle.module.url(forResource: "trip-export-sample", withExtension: "json",
                                    subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        let trip = try TripExportCodec.importJSON(data)

        // Fresh ids + remap.
        #expect(trip.name == "Sample Trip")
        #expect(trip.days.count == 2)
        #expect(trip.items.count == 2)
        // Item 2 referenced dayIndex 1 → its dayID must equal the 2nd day's id.
        let museum = trip.items.first { $0.label == "Astronomy Museum" }!
        #expect(museum.dayID == trip.days[1].id)
        #expect(museum.place?.name == "Shanghai Astronomy Museum")
        let passport = trip.items.first { $0.label == "Passport" }!
        #expect(passport.dayID == nil)
        #expect(passport.isDone == true)

        // Re-export and re-import: structure is stable (item count, day links).
        let reData = try TripExportCodec.exportJSON(trip)
        let trip2 = try TripExportCodec.importJSON(reData)
        #expect(trip2.items.count == 2)
        #expect(trip2.days.count == 2)
        #expect(trip2.id != trip.id)  // import always makes a new trip id
    }
}
