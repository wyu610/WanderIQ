# WanderIQ v2 — Sub-project 6a: Swift Import/Export Codec + Canonical Format

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Define a canonical, cross-platform trip-export format and implement the Swift codec — JSON (whole-trip, lossless, import creates a fresh-id trip) and CSV (flat item-level, UTF-8 BOM) — with a shared fixture both the Swift and (later) TS codecs must round-trip.

**Architecture:** Pure logic in `WanderIQKit`. A `TripExport` `Codable` DTO is the canonical wire shape: dates as ISO strings (`YYYY-MM-DD` for trip/day dates, full ISO-8601 for `reminderDate`), items reference their day by **index** (not UUID — so exports carry no internal ids and import can remap cleanly). `TripExportCodec.exportJSON(trip) -> Data` and `importJSON(Data) -> Trip` (fresh UUIDs for trip/days/items, `dayIndex`→new day id remap, `modifiedAt = now`). `TripExportCodec.exportCSV(trip) -> String` (UTF-8 BOM, flat items) and `importCSVItems(String, into:)` (rows → items, matching/creating days by date). A canonical sample lives at `WanderIQKit/Tests/WanderIQKitTests/Fixtures/trip-export-sample.json`; the Swift tests round-trip it, and sub-project 6b's TS codec reads the SAME file — the cross-platform guarantee.

**Tech Stack:** Swift 5.10, `WanderIQKit`, Swift Testing, Foundation. No new deps.

**Spec:** design §9.2 (JSON canonical whole-trip + CSV flat item-level, UTF-8 BOM). TS codec = 6b; iOS UI = 6c; web UI = 6d.

**Canonical export JSON format (v1):**
```json
{
  "schemaVersion": 1,
  "name": "2026 China",
  "startDate": "2026-07-11",
  "endDate": "2026-07-31",
  "destinations": ["Shanghai", "HK"],
  "days": [ { "date": "2026-07-11", "city": "Shanghai", "title": "Arrive" } ],
  "items": [ {
    "kind": "prep", "label": "Passport", "notes": "",
    "dayIndex": 0, "time": "09:30", "owner": "Mom",
    "isDone": false, "sortOrder": 0,
    "reminderDate": "2026-07-10T09:30:00Z",
    "place": { "name": "Museum", "query": "Museum SH", "latitude": 31.2, "longitude": 121.0 }
  } ]
}
```
`dayIndex`, `time`, `owner`, `reminderDate`, `place` are nullable/omittable. `modifiedAt`/ids are NOT exported (import generates fresh).

**Verification:** `cd WanderIQKit && make test` (baseline today; +new export tests).

---

### Task 1: Canonical export format spec + shared fixture

**Files:**
- Create: `docs/superpowers/specs/2026-06-15-wanderiq-v2-export-format.md`
- Create: `WanderIQKit/Tests/WanderIQKitTests/Fixtures/trip-export-sample.json`

- [ ] **Step 1: Write the format spec**

Create `docs/superpowers/specs/2026-06-15-wanderiq-v2-export-format.md` documenting
the v1 format above (the JSON block + field notes: ISO `YYYY-MM-DD` for
trip/day dates, full ISO-8601 for `reminderDate`, `dayIndex` references
`days[]`, ids/modifiedAt excluded, import creates a fresh-id trip). State that
both the Swift (6a) and TypeScript (6b) codecs implement it and both round-trip
`trip-export-sample.json`.

- [ ] **Step 2: Write the canonical sample fixture**

Create `WanderIQKit/Tests/WanderIQKitTests/Fixtures/trip-export-sample.json`:
```json
{
  "schemaVersion": 1,
  "name": "Sample Trip",
  "startDate": "2026-07-11",
  "endDate": "2026-07-12",
  "destinations": ["Shanghai", "Hong Kong"],
  "days": [
    { "date": "2026-07-11", "city": "Shanghai", "title": "Arrive" },
    { "date": "2026-07-12", "city": "Shanghai", "title": "Museum" }
  ],
  "items": [
    { "kind": "prep", "label": "Passport", "notes": "", "dayIndex": null,
      "time": null, "owner": "Mom", "isDone": true, "sortOrder": 0,
      "reminderDate": null, "place": null },
    { "kind": "itinerary", "label": "Astronomy Museum", "notes": "tickets",
      "dayIndex": 1, "time": "09:30", "owner": null, "isDone": false, "sortOrder": 1,
      "reminderDate": "2026-07-10T01:30:00Z",
      "place": { "name": "Shanghai Astronomy Museum", "query": "Astronomy Museum",
                 "latitude": 30.9, "longitude": 121.7 } }
  ]
}
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-06-15-wanderiq-v2-export-format.md WanderIQKit/Tests/WanderIQKitTests/Fixtures/trip-export-sample.json
git commit -m "docs(export): canonical trip-export format v1 + shared fixture"
```

---

### Task 2: Swift JSON codec (TripExportCodec)

**Files:**
- Create: `WanderIQKit/Sources/WanderIQKit/Export/TripExportCodec.swift`
- Test: `WanderIQKit/Tests/WanderIQKitTests/TripExportJSONTests.swift`

- [ ] **Step 1: Write the failing test**

Create `WanderIQKit/Tests/WanderIQKitTests/TripExportJSONTests.swift`:
```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd WanderIQKit && make test`
Expected: FAIL — `cannot find 'TripExportCodec' in scope` (and the Fixtures
resource: it is already declared via `.copy("Fixtures")` from sub-project 2's
Package.swift, so no Package change is needed).

- [ ] **Step 3: Write the codec**

Create `WanderIQKit/Sources/WanderIQKit/Export/TripExportCodec.swift`:
```swift
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
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd WanderIQKit && make test`
Expected: PASS — the round-trip test green (`Bundle.module` finds the fixture via
the existing `.copy("Fixtures")` resource).

- [ ] **Step 5: Commit**

```bash
git add WanderIQKit/Sources/WanderIQKit/Export/TripExportCodec.swift WanderIQKit/Tests/WanderIQKitTests/TripExportJSONTests.swift
git commit -m "feat(export): Swift JSON trip codec (canonical format)"
```

---

### Task 3: Swift CSV codec (flat items, UTF-8 BOM)

**Files:**
- Modify: `WanderIQKit/Sources/WanderIQKit/Export/TripExportCodec.swift`
- Test: `WanderIQKit/Tests/WanderIQKitTests/TripExportCSVTests.swift`

- [ ] **Step 1: Write the failing test**

Create `WanderIQKit/Tests/WanderIQKitTests/TripExportCSVTests.swift`:
```swift
import Testing
import Foundation
@testable import WanderIQKit

@Suite struct TripExportCSVTests {

    private func sampleTrip() -> Trip {
        let day = TripDay(date: Date(timeIntervalSince1970: 0), city: "SH", title: "")
        let item = ChecklistItem(kind: .packing, label: "Socks, 3 pairs", notes: "warm",
                                 dayID: day.id, isDone: true, sortOrder: 0)
        return Trip(name: "T", startDate: Date(timeIntervalSince1970: 0),
                    endDate: Date(timeIntervalSince1970: 0), days: [day], items: [item])
    }

    @Test func exportCSVStartsWithBOMandHeaderAndQuotesCommas() {
        let csv = TripExportCodec.exportCSV(sampleTrip())
        #expect(csv.hasPrefix("\u{FEFF}"))  // UTF-8 BOM (Excel + 中文)
        #expect(csv.contains("kind,label,notes,day_date,time,owner,is_done,place_name,place_query"))
        #expect(csv.contains("\"Socks, 3 pairs\""))  // comma-containing field quoted
        #expect(csv.contains("packing"))
        #expect(csv.contains("true"))
    }

    @Test func importCSVItemsAddsItemsToTrip() {
        var trip = Trip(name: "T", startDate: Date(timeIntervalSince1970: 0),
                        endDate: Date(timeIntervalSince1970: 0))
        let csv = "\u{FEFF}kind,label,notes,day_date,time,owner,is_done,place_name,place_query\n" +
                  "prep,\"Buy, tickets\",note,,09:30,Mom,false,,\n"
        TripExportCodec.importCSVItems(csv, into: &trip)
        #expect(trip.items.count == 1)
        #expect(trip.items[0].label == "Buy, tickets")
        #expect(trip.items[0].kind == .prep)
        #expect(trip.items[0].time == "09:30")
        #expect(trip.items[0].isDone == false)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd WanderIQKit && make test`
Expected: FAIL — `type 'TripExportCodec' has no member 'exportCSV'`.

- [ ] **Step 3: Add CSV to the codec**

Append inside `public enum TripExportCodec` in
`WanderIQKit/Sources/WanderIQKit/Export/TripExportCodec.swift`:
```swift
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd WanderIQKit && make test`
Expected: PASS — both CSV tests green.

- [ ] **Step 5: Commit**

```bash
git add WanderIQKit/Sources/WanderIQKit/Export/TripExportCodec.swift WanderIQKit/Tests/WanderIQKitTests/TripExportCSVTests.swift
git commit -m "feat(export): Swift CSV item codec (UTF-8 BOM, RFC-4180 quoting)"
```

---

## Done criteria

- `cd WanderIQKit && make test` passes the new JSON round-trip + CSV tests, on
  top of the existing suite.
- The canonical format spec + `trip-export-sample.json` are committed; the Swift
  codec round-trips the fixture; import always yields a fresh-id trip; CSV is
  UTF-8 BOM + RFC-4180-quoted.
- Next: **6b** — the TypeScript codec in `webapp/` implementing the same format,
  with a Vitest test that reads the SAME `trip-export-sample.json` (via the
  relative path, like the sync conformance) — the cross-platform guarantee. Then
  **6c** (iOS UI: export share sheet + import file picker) and **6d** (web UI:
  export download + import file input).

## Notes for 6b/6c/6d

- 6b reads `../WanderIQKit/Tests/WanderIQKitTests/Fixtures/trip-export-sample.json`
  and must import→re-export to a structurally-equal trip, proving Swift↔TS format
  parity (extend with a byte-equality check on canonicalized JSON if desired).
- JSON import = new trip (call `AppModel.addTrip` / web `tripActions` create-path);
  CSV import = add items to the open trip.
- 6c iOS: `Transferable`/`fileExporter` + `fileImporter`. 6d web: `Blob` download +
  `<input type=file>`.
