import Foundation

struct SeedFile: Decodable {
    struct SeedItem: Decodable {
        var label: String
        var notes: String?
        var done: Bool?
    }
    struct SeedDay: Decodable {
        var date: String
        var city: String
        var title: String
        var items: [String]
    }
    var name: String
    var start: String
    var end: String
    var destinations: [String]
    var prep: [SeedItem]
    var hotels: [SeedItem]
    var docs: [SeedItem]
    var pack: [String]
    var days: [SeedDay]
}

public enum SeedLoader {

    public static func loadChinaTrip2026() throws -> Trip {
        guard let url = Bundle.module.url(forResource: "seed-china-2026", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let file = try JSONDecoder().decode(SeedFile.self, from: Data(contentsOf: url))
        return try makeTrip(from: file)
    }

    static func makeTrip(from file: SeedFile) throws -> Trip {
        guard let start = parseDay(file.start), let end = parseDay(file.end) else {
            throw CocoaError(.coderInvalidValue)
        }
        var items: [ChecklistItem] = []
        func add(_ seeds: [SeedFile.SeedItem], kind: ItemKind) {
            for (i, s) in seeds.enumerated() {
                items.append(ChecklistItem(kind: kind, label: s.label, notes: s.notes ?? "",
                                           isDone: s.done ?? false, sortOrder: i))
            }
        }
        add(file.prep, kind: .prep)
        add(file.hotels, kind: .hotel)
        add(file.docs, kind: .doc)
        for (i, label) in file.pack.enumerated() {
            items.append(ChecklistItem(kind: .packing, label: label, sortOrder: i))
        }
        var days: [TripDay] = []
        var order = 0
        for d in file.days {
            guard let date = parseDay(d.date) else { throw CocoaError(.coderInvalidValue) }
            let day = TripDay(date: date, city: d.city, title: d.title)
            days.append(day)
            for label in d.items {
                items.append(ChecklistItem(kind: .itinerary, label: label, dayID: day.id, sortOrder: order))
                order += 1
            }
        }
        return Trip(name: file.name, startDate: start, endDate: end,
                    destinations: file.destinations, days: days, items: items, schemaVersion: 1)
    }

    static func parseDay(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.date(from: s)
    }
}
