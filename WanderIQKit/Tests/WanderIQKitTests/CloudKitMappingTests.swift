import Testing
import CloudKit
@testable import WanderIQKit

@Suite struct CloudKitMappingTests {

    private func sampleTrip() -> Trip {
        let day = TripDay(date: Date(timeIntervalSince1970: 1_700_000_000), city: "上海", title: "抵达上海")
        let item = ChecklistItem(kind: .itinerary, label: "酒店早餐", notes: "n",
                                 dayID: day.id, time: "08:00", owner: "全家",
                                 isDone: true, sortOrder: 7,
                                 reminderDate: Date(timeIntervalSince1970: 1_700_100_000),
                                 place: Place(name: "P", query: "Q", latitude: 31.2, longitude: 121.5),
                                 modifiedAt: Date(timeIntervalSince1970: 1_700_000_500))
        return Trip(name: "T", startDate: Date(timeIntervalSince1970: 0),
                    endDate: Date(timeIntervalSince1970: 86_400),
                    destinations: ["上海", "香港"], days: [day], items: [item])
    }

    @Test func zoneIDEncodesTripID() {
        let trip = sampleTrip()
        let zone = CloudKitMapping.zoneID(forTripID: trip.id)
        #expect(zone.zoneName == "trip-\(trip.id.uuidString)")
        #expect(CloudKitMapping.tripID(fromZoneName: zone.zoneName) == trip.id)
        #expect(CloudKitMapping.tripID(fromZoneName: "garbage") == nil)
    }

    @Test func tripMetaRoundTrip() {
        let trip = sampleTrip()
        let record = CloudKitMapping.tripMetaRecord(for: trip)
        #expect(record.recordType == "TripMeta")
        #expect(record.recordID.recordName == "trip-meta")
        var shell = Trip(name: "", startDate: Date(), endDate: Date())
        CloudKitMapping.applyTripMeta(record, to: &shell)
        #expect(shell.name == trip.name)
        #expect(shell.startDate == trip.startDate)
        #expect(shell.endDate == trip.endDate)
        #expect(shell.destinations == trip.destinations)
        #expect(shell.schemaVersion == trip.schemaVersion)
    }

    @Test func dayRoundTrip() {
        let trip = sampleTrip()
        let record = CloudKitMapping.dayRecord(for: trip.days[0], tripID: trip.id)
        #expect(record.recordType == "TripDay")
        let parsed = CloudKitMapping.day(from: record)
        #expect(parsed == trip.days[0])
    }

    @Test func itemRoundTripIncludingPlaceAndNils() {
        let trip = sampleTrip()
        let full = CloudKitMapping.itemRecord(for: trip.items[0], tripID: trip.id)
        #expect(full.recordType == "ChecklistItem")
        #expect(CloudKitMapping.item(from: full) == trip.items[0])

        let bare = ChecklistItem(kind: .packing, label: "护照")
        let bareRecord = CloudKitMapping.itemRecord(for: bare, tripID: trip.id)
        let parsedBare = CloudKitMapping.item(from: bareRecord)
        #expect(parsedBare == bare)
        #expect(parsedBare?.place == nil)
        #expect(parsedBare?.dayID == nil)
    }

    @Test func unknownKindParsesAsNil() {
        let trip = sampleTrip()
        let record = CloudKitMapping.itemRecord(for: trip.items[0], tripID: trip.id)
        record["kind"] = "future-kind"
        #expect(CloudKitMapping.item(from: record) == nil)
    }

    /// Server-decoded records bridge integers as Int64-backed NSNumber, not
    /// Int — the decoders must read through NSNumber.
    @Test func itemParsesServerShapedInt64Numbers() {
        let trip = sampleTrip()
        let record = CloudKitMapping.itemRecord(for: trip.items[0], tripID: trip.id)
        record["isDone"] = NSNumber(value: Int64(1))
        record["sortOrder"] = NSNumber(value: Int64(7))
        record["placeLat"] = NSNumber(value: 31.2)
        let parsed = CloudKitMapping.item(from: record)
        #expect(parsed?.isDone == true)
        #expect(parsed?.sortOrder == 7)
        #expect(parsed?.place?.latitude == 31.2)
    }

    /// CloudKit drops empty arrays server-side: a TripMeta record with no
    /// destinations key means the field was CLEARED, not absent.
    @Test func missingDestinationsKeyMeansCleared() {
        let trip = sampleTrip()
        let record = CloudKitMapping.tripMetaRecord(for: trip)
        record["destinations"] = nil
        var target = trip
        CloudKitMapping.applyTripMeta(record, to: &target)
        #expect(target.destinations.isEmpty)
        #expect(target.name == trip.name)
    }

    /// TripMeta and TripDay carry modifiedAt so last-writer-wins conflict
    /// resolution works for every record type, not just items.
    @Test func metaAndDayModifiedAtRoundTrip() {
        let stamp = Date(timeIntervalSince1970: 1_700_000_777)
        var trip = sampleTrip()
        trip.modifiedAt = stamp
        trip.days[0].modifiedAt = stamp

        let meta = CloudKitMapping.tripMetaRecord(for: trip)
        #expect(meta["modifiedAt"] as? Date == stamp)
        var shell = Trip(name: "", startDate: Date(), endDate: Date())
        CloudKitMapping.applyTripMeta(meta, to: &shell)
        #expect(shell.modifiedAt == stamp)

        let dayRecord = CloudKitMapping.dayRecord(for: trip.days[0], tripID: trip.id)
        #expect(CloudKitMapping.day(from: dayRecord)?.modifiedAt == stamp)

        // nil stamps stay nil through the round trip (legacy data).
        let bareDay = TripDay(date: stamp, city: "c", title: "t")
        let bareRecord = CloudKitMapping.dayRecord(for: bareDay, tripID: trip.id)
        #expect(CloudKitMapping.day(from: bareRecord)?.modifiedAt == nil)
    }

    /// A place with a name but a dropped/empty query must still decode.
    @Test func placeSurvivesMissingQuery() {
        let trip = sampleTrip()
        let record = CloudKitMapping.itemRecord(for: trip.items[0], tripID: trip.id)
        record["placeQuery"] = nil
        let parsed = CloudKitMapping.item(from: record)
        #expect(parsed?.place?.name == "P")
        #expect(parsed?.place?.query == "")
    }
}
