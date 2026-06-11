import Foundation

public enum ItemKind: String, Codable, CaseIterable, Sendable {
    case prep, hotel, doc, itinerary, packing
}

public struct Place: Codable, Equatable, Sendable {
    public var name: String
    public var query: String
    public var latitude: Double?
    public var longitude: Double?

    public init(name: String, query: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.name = name
        self.query = query
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct ChecklistItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ItemKind
    public var label: String
    public var notes: String
    public var dayID: UUID?
    public var time: String?      // "HH:mm", itinerary items only
    public var owner: String?
    public var isDone: Bool
    public var sortOrder: Int
    public var reminderDate: Date?
    public var place: Place?
    public var modifiedAt: Date

    public init(id: UUID = UUID(), kind: ItemKind, label: String, notes: String = "",
                dayID: UUID? = nil, time: String? = nil, owner: String? = nil,
                isDone: Bool = false, sortOrder: Int = 0, reminderDate: Date? = nil,
                place: Place? = nil, modifiedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.id = id
        self.kind = kind
        self.label = label
        self.notes = notes
        self.dayID = dayID
        self.time = time
        self.owner = owner
        self.isDone = isDone
        self.sortOrder = sortOrder
        self.reminderDate = reminderDate
        self.place = place
        self.modifiedAt = modifiedAt
    }
}

public struct TripDay: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var city: String
    public var title: String

    public init(id: UUID = UUID(), date: Date, city: String, title: String) {
        self.id = id
        self.date = date
        self.city = city
        self.title = title
    }
}

public struct Trip: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var startDate: Date
    public var endDate: Date
    public var destinations: [String]
    public var days: [TripDay]
    public var items: [ChecklistItem]
    public var schemaVersion: Int

    public init(id: UUID = UUID(), name: String, startDate: Date, endDate: Date,
                destinations: [String] = [], days: [TripDay] = [],
                items: [ChecklistItem] = [], schemaVersion: Int = 1) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.destinations = destinations
        self.days = days
        self.items = items
        self.schemaVersion = schemaVersion
    }
}

/// Port of the web app's sortDayItems(): timed items first in time order,
/// then untimed items in their original order.
public enum ItinerarySort {
    public static func daySorted(_ items: [ChecklistItem]) -> [ChecklistItem] {
        items.enumerated().sorted { a, b in
            let ta = a.element.time ?? ""
            let tb = b.element.time ?? ""
            switch (!ta.isEmpty, !tb.isEmpty) {
            case (true, true):
                if ta != tb { return ta < tb }
                return a.offset < b.offset
            case (true, false): return true
            case (false, true): return false
            case (false, false): return a.offset < b.offset
            }
        }.map(\.element)
    }
}
