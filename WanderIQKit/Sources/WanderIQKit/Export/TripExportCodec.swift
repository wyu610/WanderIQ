import Foundation

/// Canonical cross-platform trip import/export (format v1). Shared with the TS
/// codec (sub-project 6b) via Fixtures/trip-export-sample.json.
public enum TripExportCodec {

    // MARK: Wire DTOs (the canonical JSON shape)

    struct PlaceDTO: Codable { var name: String; var query: String
        var latitude: Double?; var longitude: Double? }
    struct DayDTO: Codable { var date: String; var city: String; var title: String }
    struct ItemDTO: Codable {
        var kind: String; var label: String; var notes: String
        var dayIndex: Int?; var time: String?; var owner: String?
        var isDone: Bool; var sortOrder: Int; var reminderDate: String?; var place: PlaceDTO?
    }
    struct TripDTO: Codable {
        var schemaVersion: Int; var name: String
        var startDate: String; var endDate: String; var destinations: [String]
        var days: [DayDTO]; var items: [ItemDTO]
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let iso = ISO8601DateFormatter()

    // MARK: Export

    public static func exportJSON(_ trip: Trip) throws -> Data {
        let dayID = Dictionary(uniqueKeysWithValues: trip.days.enumerated().map { ($1.id, $0) })
        let dto = TripDTO(
            schemaVersion: 1, name: trip.name,
            startDate: dayFmt.string(from: trip.startDate),
            endDate: dayFmt.string(from: trip.endDate),
            destinations: trip.destinations,
            days: trip.days.map { DayDTO(date: dayFmt.string(from: $0.date), city: $0.city, title: $0.title) },
            items: trip.items.map { item in
                ItemDTO(kind: item.kind.rawValue, label: item.label, notes: item.notes,
                        dayIndex: item.dayID.flatMap { dayID[$0] }, time: item.time, owner: item.owner,
                        isDone: item.isDone, sortOrder: item.sortOrder,
                        reminderDate: item.reminderDate.map { iso.string(from: $0) },
                        place: item.place.map { PlaceDTO(name: $0.name, query: $0.query,
                                                         latitude: $0.latitude, longitude: $0.longitude) })
            })
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(dto)
    }

    // MARK: Import (always a fresh-id trip)

    public static func importJSON(_ data: Data) throws -> Trip {
        let dto = try JSONDecoder().decode(TripDTO.self, from: data)
        let now = Date()
        let days = dto.days.map { d in
            TripDay(date: dayFmt.date(from: d.date) ?? Date(timeIntervalSince1970: 0),
                    city: d.city, title: d.title, modifiedAt: now)
        }
        let items = dto.items.map { i -> ChecklistItem in
            let dayID: UUID? = i.dayIndex.flatMap { days.indices.contains($0) ? days[$0].id : nil }
            let place = i.place.map { Place(name: $0.name, query: $0.query,
                                            latitude: $0.latitude, longitude: $0.longitude) }
            return ChecklistItem(
                kind: ItemKind(rawValue: i.kind) ?? .prep, label: i.label, notes: i.notes,
                dayID: dayID, time: i.time, owner: i.owner, isDone: i.isDone, sortOrder: i.sortOrder,
                reminderDate: i.reminderDate.flatMap { iso.date(from: $0) }, place: place, modifiedAt: now)
        }
        return Trip(name: dto.name,
                    startDate: dayFmt.date(from: dto.startDate) ?? Date(timeIntervalSince1970: 0),
                    endDate: dayFmt.date(from: dto.endDate) ?? Date(timeIntervalSince1970: 0),
                    destinations: dto.destinations, days: days, items: items, modifiedAt: now)
    }

    // MARK: CSV (flat item-level, UTF-8 BOM)

    static let csvHeader = "kind,label,notes,day_date,time,owner,is_done,place_name,place_query"

    public static func exportCSV(_ trip: Trip) -> String {
        let dayDate = Dictionary(uniqueKeysWithValues: trip.days.map { ($0.id, dayFmt.string(from: $0.date)) })
        var lines = [csvHeader]
        for it in trip.items {
            let cols = [it.kind.rawValue, it.label, it.notes,
                        it.dayID.flatMap { dayDate[$0] } ?? "", it.time ?? "", it.owner ?? "",
                        it.isDone ? "true" : "false", it.place?.name ?? "", it.place?.query ?? ""]
            lines.append(cols.map(csvField).joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\n") + "\n"
    }

    /// Append CSV rows as items to `trip`, matching/creating a day by date.
    public static func importCSVItems(_ csv: String, into trip: inout Trip) {
        let body = csv.hasPrefix("\u{FEFF}") ? String(csv.dropFirst()) : csv
        let rows = parseCSV(body)
        guard rows.count > 1 else { return }
        let now = Date()
        var byDate = Dictionary(uniqueKeysWithValues: trip.days.map { (dayFmt.string(from: $0.date), $0.id) })
        for row in rows.dropFirst() where row.count >= 9 {
            var dayID: UUID?
            let d = row[3]
            if !d.isEmpty {
                if let existing = byDate[d] { dayID = existing }
                else if let date = dayFmt.date(from: d) {
                    let day = TripDay(date: date, city: "", title: "", modifiedAt: now)
                    trip.days.append(day); byDate[d] = day.id; dayID = day.id
                }
            }
            let place = row[7].isEmpty ? nil : Place(name: row[7], query: row[8])
            trip.items.append(ChecklistItem(
                kind: ItemKind(rawValue: row[0]) ?? .prep, label: row[1], notes: row[2],
                dayID: dayID, time: row[4].isEmpty ? nil : row[4],
                owner: row[5].isEmpty ? nil : row[5], isDone: row[6] == "true",
                sortOrder: trip.items.count, place: place, modifiedAt: now))
        }
    }

    // RFC-4180-ish: quote fields containing comma/quote/newline; double inner quotes.
    private static func csvField(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []; var field = ""; var row: [String] = []
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n": row.append(field); rows.append(row); field = ""; row = []
                case "\r": break
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
