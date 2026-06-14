import Foundation

/// Pure mapping between Postgres row types and the engine's SyncRecord. Dates
/// use ISO-8601 strings. `fields` keys match SyncMapping (sub-project 2).
public enum SupabaseRowMapping {
    static let iso: ISO8601DateFormatter = ISO8601DateFormatter()

    private static func date(_ s: String?) -> Date {
        guard let s, let d = iso.date(from: s) else { return Date(timeIntervalSince1970: 0) }
        return d
    }
    private static func str(_ d: Date) -> String { iso.string(from: d) }

    // MARK: Pull (row → SyncRecord)

    public static func syncRecord(trip row: TripRow) -> SyncRecord {
        SyncRecord(kind: .trip, id: UUID(uuidString: row.id) ?? UUID(),
                   tripID: UUID(uuidString: row.id) ?? UUID(),
                   modifiedAt: date(row.modified_at), deleted: row.deleted,
                   fields: row.deleted ? nil : [
                    "name": row.name,
                    "startDate": row.start_date ?? "",
                    "endDate": row.end_date ?? "",
                    "destinations": row.destinations.joined(separator: "\u{1f}"),
                    "schemaVersion": String(row.schema_version)])
    }

    public static func syncRecord(day row: DayRow) -> SyncRecord {
        SyncRecord(kind: .day, id: UUID(uuidString: row.id) ?? UUID(),
                   tripID: UUID(uuidString: row.trip_id) ?? UUID(),
                   modifiedAt: date(row.modified_at), deleted: row.deleted,
                   fields: row.deleted ? nil : [
                    "date": row.date ?? "", "city": row.city, "title": row.title])
    }

    public static func syncRecord(item row: ItemRow) -> SyncRecord {
        var f: [String: String] = [
            "kind": row.kind, "label": row.label, "notes": row.notes,
            "isDone": row.is_done ? "true" : "false",
            "sortOrder": String(row.sort_order)]
        if let v = row.day_id { f["dayID"] = v }
        if let v = row.time { f["time"] = v }
        if let v = row.item_owner { f["owner"] = v }
        if let v = row.reminder_date { f["reminderDate"] = v }
        if let p = row.place {
            f["placeName"] = p.name; f["placeQuery"] = p.query
            if let lat = p.latitude { f["placeLat"] = String(lat) }
            if let lon = p.longitude { f["placeLon"] = String(lon) }
        }
        return SyncRecord(kind: .item, id: UUID(uuidString: row.id) ?? UUID(),
                          tripID: UUID(uuidString: row.trip_id) ?? UUID(),
                          modifiedAt: date(row.modified_at), deleted: row.deleted,
                          fields: row.deleted ? nil : f)
    }

    // MARK: Push (SyncRecord → row)

    public static func tripRow(from rec: SyncRecord) -> TripRow {
        let f = rec.fields ?? [:]
        return TripRow(id: rec.id.uuidString.lowercased(), owner_id: nil,
                       name: f["name"] ?? "",
                       start_date: (f["startDate"]).flatMap { $0.isEmpty ? nil : $0 },
                       end_date: (f["endDate"]).flatMap { $0.isEmpty ? nil : $0 },
                       destinations: (f["destinations"]).map { $0.isEmpty ? [] : $0.components(separatedBy: "\u{1f}") } ?? [],
                       schema_version: Int(f["schemaVersion"] ?? "1") ?? 1,
                       modified_at: str(rec.modifiedAt), deleted: rec.deleted)
    }

    public static func dayRow(from rec: SyncRecord) -> DayRow {
        let f = rec.fields ?? [:]
        return DayRow(id: rec.id.uuidString.lowercased(),
                      trip_id: rec.tripID.uuidString.lowercased(),
                      date: (f["date"]).flatMap { $0.isEmpty ? nil : $0 },
                      city: f["city"] ?? "", title: f["title"] ?? "",
                      modified_at: str(rec.modifiedAt), deleted: rec.deleted)
    }

    public static func itemRow(from rec: SyncRecord) -> ItemRow {
        let f = rec.fields ?? [:]
        var place: PlaceRow?
        if let name = f["placeName"] {
            place = PlaceRow(name: name, query: f["placeQuery"] ?? "",
                             latitude: f["placeLat"].flatMap(Double.init),
                             longitude: f["placeLon"].flatMap(Double.init))
        }
        return ItemRow(id: rec.id.uuidString.lowercased(),
                       trip_id: rec.tripID.uuidString.lowercased(),
                       kind: f["kind"] ?? "prep", label: f["label"] ?? "",
                       notes: f["notes"] ?? "", day_id: f["dayID"], time: f["time"],
                       item_owner: f["owner"], is_done: f["isDone"] == "true",
                       sort_order: Int(f["sortOrder"] ?? "0") ?? 0,
                       reminder_date: f["reminderDate"], place: place,
                       modified_at: str(rec.modifiedAt), deleted: rec.deleted)
    }
}
