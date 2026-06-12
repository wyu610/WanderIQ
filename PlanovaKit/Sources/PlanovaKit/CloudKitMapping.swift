import Foundation
import CloudKit

/// Pure Trip ⇄ CKRecord mapping. One zone per trip; one record per entity.
/// Record types: TripMeta (singleton "trip-meta" per zone), TripDay, ChecklistItem
/// (recordName == entity UUID string).
public enum CloudKitMapping {

    public static let tripMetaRecordName = "trip-meta"
    private static let zonePrefix = "trip-"

    // MARK: Zone / record IDs

    /// `owner` defaults to the current user (private database). Callers
    /// working with a SHARED zone must pass the zone's ownerName — the
    /// default silently targets the wrong zone for shared trips.
    public static func zoneID(forTripID id: UUID, owner: String = CKCurrentUserDefaultName) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zonePrefix + id.uuidString, ownerName: owner)
    }

    public static func tripID(fromZoneName name: String) -> UUID? {
        guard name.hasPrefix(zonePrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(zonePrefix.count)))
    }

    public static func tripMetaRecordID(tripID: UUID, owner: String = CKCurrentUserDefaultName) -> CKRecord.ID {
        CKRecord.ID(recordName: tripMetaRecordName, zoneID: zoneID(forTripID: tripID, owner: owner))
    }

    public static func dayRecordID(_ dayID: UUID, tripID: UUID, owner: String = CKCurrentUserDefaultName) -> CKRecord.ID {
        CKRecord.ID(recordName: dayID.uuidString, zoneID: zoneID(forTripID: tripID, owner: owner))
    }

    public static func itemRecordID(_ itemID: UUID, tripID: UUID, owner: String = CKCurrentUserDefaultName) -> CKRecord.ID {
        CKRecord.ID(recordName: itemID.uuidString, zoneID: zoneID(forTripID: tripID, owner: owner))
    }

    // MARK: Trip meta

    public static func tripMetaRecord(for trip: Trip, owner: String = CKCurrentUserDefaultName) -> CKRecord {
        let record = CKRecord(recordType: "TripMeta", recordID: tripMetaRecordID(tripID: trip.id, owner: owner))
        record["name"] = trip.name
        record["startDate"] = trip.startDate
        record["endDate"] = trip.endDate
        record["destinations"] = trip.destinations
        record["schemaVersion"] = trip.schemaVersion
        return record
    }

    public static func applyTripMeta(_ record: CKRecord, to trip: inout Trip) {
        if let v = record["name"] as? String { trip.name = v }
        if let v = record["startDate"] as? Date { trip.startDate = v }
        if let v = record["endDate"] as? Date { trip.endDate = v }
        // TripMeta always writes destinations; CloudKit drops empty arrays on
        // the server, so a missing key means "cleared", not "absent".
        trip.destinations = record["destinations"] as? [String] ?? []
        if let v = (record["schemaVersion"] as? NSNumber)?.intValue { trip.schemaVersion = v }
    }

    // MARK: TripDay

    public static func dayRecord(for day: TripDay, tripID: UUID, owner: String = CKCurrentUserDefaultName) -> CKRecord {
        let record = CKRecord(recordType: "TripDay", recordID: dayRecordID(day.id, tripID: tripID, owner: owner))
        record["date"] = day.date
        record["city"] = day.city
        record["title"] = day.title
        return record
    }

    public static func day(from record: CKRecord) -> TripDay? {
        guard record.recordType == "TripDay",
              let id = UUID(uuidString: record.recordID.recordName),
              let date = record["date"] as? Date else { return nil }
        return TripDay(id: id, date: date,
                       city: record["city"] as? String ?? "",
                       title: record["title"] as? String ?? "")
    }

    // MARK: ChecklistItem

    public static func itemRecord(for item: ChecklistItem, tripID: UUID, owner: String = CKCurrentUserDefaultName) -> CKRecord {
        let record = CKRecord(recordType: "ChecklistItem", recordID: itemRecordID(item.id, tripID: tripID, owner: owner))
        record["kind"] = item.kind.rawValue
        record["label"] = item.label
        record["notes"] = item.notes
        record["dayID"] = item.dayID?.uuidString
        record["time"] = item.time
        record["owner"] = item.owner
        record["isDone"] = item.isDone ? 1 : 0
        record["sortOrder"] = item.sortOrder
        record["reminderDate"] = item.reminderDate
        record["modifiedAt"] = item.modifiedAt
        record["placeName"] = item.place?.name
        record["placeQuery"] = item.place?.query
        record["placeLat"] = item.place?.latitude
        record["placeLon"] = item.place?.longitude
        return record
    }

    public static func item(from record: CKRecord) -> ChecklistItem? {
        guard record.recordType == "ChecklistItem",
              let id = UUID(uuidString: record.recordID.recordName),
              let kindRaw = record["kind"] as? String,
              let kind = ItemKind(rawValue: kindRaw),
              let label = record["label"] as? String else { return nil }
        var place: Place?
        // placeName alone identifies a place; query may be empty/dropped.
        if let name = record["placeName"] as? String {
            place = Place(name: name, query: record["placeQuery"] as? String ?? "",
                          latitude: (record["placeLat"] as? NSNumber)?.doubleValue,
                          longitude: (record["placeLon"] as? NSNumber)?.doubleValue)
        }
        return ChecklistItem(
            id: id, kind: kind, label: label,
            notes: record["notes"] as? String ?? "",
            dayID: (record["dayID"] as? String).flatMap(UUID.init(uuidString:)),
            time: record["time"] as? String,
            owner: record["owner"] as? String,
            // NSNumber path: server-decoded records bridge integers as Int64.
            isDone: ((record["isDone"] as? NSNumber)?.intValue ?? 0) != 0,
            sortOrder: (record["sortOrder"] as? NSNumber)?.intValue ?? 0,
            reminderDate: record["reminderDate"] as? Date,
            place: place,
            modifiedAt: record["modifiedAt"] as? Date ?? Date(timeIntervalSince1970: 0))
    }
}
