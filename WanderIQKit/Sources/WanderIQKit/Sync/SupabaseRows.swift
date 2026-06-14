import Foundation

/// Codable mirrors of the Postgres tables (snake_case columns). Timestamp/date
/// columns are ISO-8601 strings, parsed in SupabaseRowMapping. `place` is a
/// nested object matching the jsonb column.
public struct PlaceRow: Codable, Equatable, Sendable {
    public var name: String
    public var query: String
    public var latitude: Double?
    public var longitude: Double?
    public init(name: String, query: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.name = name; self.query = query; self.latitude = latitude; self.longitude = longitude
    }
}

public struct TripRow: Codable, Equatable, Sendable {
    public var id: String
    public var owner_id: String?
    public var name: String
    public var start_date: String?
    public var end_date: String?
    public var destinations: [String]
    public var schema_version: Int
    public var modified_at: String
    public var deleted: Bool
    public init(id: String, owner_id: String? = nil, name: String,
                start_date: String?, end_date: String?, destinations: [String],
                schema_version: Int, modified_at: String, deleted: Bool) {
        self.id = id; self.owner_id = owner_id; self.name = name
        self.start_date = start_date; self.end_date = end_date
        self.destinations = destinations; self.schema_version = schema_version
        self.modified_at = modified_at; self.deleted = deleted
    }
}

public struct DayRow: Codable, Equatable, Sendable {
    public var id: String
    public var trip_id: String
    public var date: String?
    public var city: String
    public var title: String
    public var modified_at: String
    public var deleted: Bool
    public init(id: String, trip_id: String, date: String?, city: String,
                title: String, modified_at: String, deleted: Bool) {
        self.id = id; self.trip_id = trip_id; self.date = date
        self.city = city; self.title = title
        self.modified_at = modified_at; self.deleted = deleted
    }
}

public struct ItemRow: Codable, Equatable, Sendable {
    public var id: String
    public var trip_id: String
    public var kind: String
    public var label: String
    public var notes: String
    public var day_id: String?
    public var time: String?
    public var item_owner: String?
    public var is_done: Bool
    public var sort_order: Int
    public var reminder_date: String?
    public var place: PlaceRow?
    public var modified_at: String
    public var deleted: Bool
    public init(id: String, trip_id: String, kind: String, label: String, notes: String,
                day_id: String?, time: String?, item_owner: String?, is_done: Bool,
                sort_order: Int, reminder_date: String?, place: PlaceRow?,
                modified_at: String, deleted: Bool) {
        self.id = id; self.trip_id = trip_id; self.kind = kind; self.label = label
        self.notes = notes; self.day_id = day_id; self.time = time; self.item_owner = item_owner
        self.is_done = is_done; self.sort_order = sort_order; self.reminder_date = reminder_date
        self.place = place; self.modified_at = modified_at; self.deleted = deleted
    }
}
