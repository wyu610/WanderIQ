import Foundation

/// Maps SyncRecord.fields (string-valued) to/from domain models. The wire
/// format mirrors the Postgres columns from sub-project 1.
public enum SyncMapping {
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); return f
    }()

    /// Apply a non-deleted record into the trip aggregate (trip/day/item).
    public static func apply(_ rec: SyncRecord, to trip: inout Trip) {
        let f = rec.fields ?? [:]
        switch rec.kind {
        case .trip:
            if rec.id == trip.id {
                if let v = f["name"] { trip.name = v }
                if let v = f["startDate"], let d = date(v) { trip.startDate = d }
                if let v = f["endDate"], let d = date(v) { trip.endDate = d }
                trip.destinations = f["destinations"].map(splitList) ?? trip.destinations
                if let v = f["schemaVersion"], let n = Int(v) { trip.schemaVersion = n }
                trip.modifiedAt = rec.modifiedAt
            }
        case .day:
            let day = TripDay(id: rec.id, date: date(f["date"] ?? "") ?? Date(timeIntervalSince1970: 0),
                              city: f["city"] ?? "", title: f["title"] ?? "",
                              modifiedAt: rec.modifiedAt)
            if let i = trip.days.firstIndex(where: { $0.id == rec.id }) { trip.days[i] = day }
            else { trip.days.append(day) }
        case .item:
            var place: Place?
            if let name = f["placeName"] {
                place = Place(name: name, query: f["placeQuery"] ?? "",
                              latitude: f["placeLat"].flatMap(Double.init),
                              longitude: f["placeLon"].flatMap(Double.init))
            }
            let item = ChecklistItem(
                id: rec.id,
                kind: ItemKind(rawValue: f["kind"] ?? "prep") ?? .prep,
                label: f["label"] ?? "", notes: f["notes"] ?? "",
                dayID: f["dayID"].flatMap(UUID.init(uuidString:)),
                time: f["time"], owner: f["owner"],
                isDone: f["isDone"] == "true",
                sortOrder: f["sortOrder"].flatMap(Int.init) ?? 0,
                reminderDate: f["reminderDate"].flatMap(date),
                place: place, modifiedAt: rec.modifiedAt)
            if let i = trip.items.firstIndex(where: { $0.id == rec.id }) { trip.items[i] = item }
            else { trip.items.append(item) }
        }
    }

    private static func date(_ s: String) -> Date? {
        if let t = Double(s) { return Date(timeIntervalSince1970: t) }
        return iso.date(from: s)
    }
    private static func splitList(_ s: String) -> [String] {
        s.isEmpty ? [] : s.components(separatedBy: "\u{1f}")  // unit-separator delimited
    }
}
