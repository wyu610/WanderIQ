# WanderIQ v2 — Sub-project 3a: Supabase Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `SupabaseRemoteSyncBackend`, a concrete `RemoteSyncBackend` (from sub-project 2) that pushes/pulls `SyncRecord`s to the live Supabase Postgres tables via `supabase-swift`, with all pure mapping logic unit-tested in `WanderIQKit`.

**Architecture:** Keep `WanderIQKit` dependency-free: it gains pure, Codable Postgres **row types** and a pure **`SupabaseRowMapping`** (row ⇄ `SyncRecord`) that are fully unit-tested. The `supabase-swift` dependency and the thin network shell (`SupabaseRemoteSyncBackend`) live in the **app target** (mirroring how CloudKit was app-only). Dates cross the wire as ISO-8601 strings parsed in the mapper, resolving the date-format note from the sub-project 2 review. This sub-project does NOT touch auth, AppModel wiring, or CloudKit — those are 3b and 3c.

**Tech Stack:** supabase-swift (Supabase + PostgREST products), Swift Testing (package), XcodeGen, xcodebuild.

**Spec:** `docs/superpowers/specs/2026-06-13-wanderiq-v2-design.md` §6 (sync), §5.1 (columns); protocol contract `2026-06-13-wanderiq-v2-sync-protocol.md`. Implements the transport half of §12 sub-projects 2–3.

**Prerequisite (USER):** the dev project's **anon key** and **project URL** (Supabase dashboard → Project Settings → API). These are the public client credentials (NOT the DB password). Stored in a gitignored `Supabase.xcconfig` (Task 1).

**Verification:** package tests `cd WanderIQKit && make test` (baseline 62, must not regress); app build `xcodegen generate && xcodebuild -project WanderIQ.xcodeproj -scheme WanderIQ -destination 'generic/platform=iOS Simulator' build`.

**Supabase-swift API reference (verified current):**
- `SupabaseClient(supabaseURL: URL, supabaseKey: String)`.
- Upsert: `try await client.from("table").upsert(encodableArray, onConflict: "id").execute()`.
- Select with cursor: `let rows: [Row] = try await client.from("table").select().gt("server_updated_at", value: isoString).order("server_updated_at", ascending: true).execute().value`.

---

### Task 1: supabase-swift dependency + SupabaseConfig (app target)

**Files:**
- Modify: `project.yml`
- Create: `Supabase.xcconfig.example`
- Modify: `.gitignore`
- Create: `WanderIQ/Sync/SupabaseConfig.swift`

- [ ] **Step 1: Add the package dependency and config file to project.yml**

In `project.yml`, under the top-level `packages:` map (which currently has `WanderIQKit`), add the remote package:
```yaml
packages:
  WanderIQKit:
    path: WanderIQKit
  Supabase:
    url: https://github.com/supabase/supabase-swift
    from: "2.0.0"
```
Under the `WanderIQ` target's `dependencies:` list (which currently has `- package: WanderIQKit`), add:
```yaml
      - package: Supabase
        product: Supabase
```
Under the `WanderIQ` target's `configFiles:` — there is none yet at target level; the project-level `configFiles` already points Debug/Release at `Signing.xcconfig`. Add a second xcconfig include by changing the target to include Supabase config via an `xcconfig` `#include`. Simplest: in `Signing.xcconfig` add a line `#include? "Supabase.xcconfig"` (the `?` makes it optional so CI without the file still builds). Do this in Step 3.

- [ ] **Step 2: Add ignore rules + example**

Create `Supabase.xcconfig.example`:
```
// Copy to Supabase.xcconfig (gitignored) and fill in the dev project's
// PUBLIC client credentials from Supabase dashboard → Settings → API.
SUPABASE_URL = https:/$()/YOUR-REF.supabase.co
SUPABASE_ANON_KEY = your-anon-public-key
```
(The `$()` splits the `//` so Xcode's xcconfig parser does not treat the URL as a comment.)

Add to `.gitignore` (after the existing `Signing.xcconfig` line):
```
Supabase.xcconfig
```

- [ ] **Step 3: Wire the xcconfig include and Info.plist passthrough**

Append to `Signing.xcconfig`:
```
#include? "Supabase.xcconfig"
```
In `project.yml`, under the `WanderIQ` target `info.properties`, add two keys so the build settings reach the bundle:
```yaml
        SUPABASE_URL: $(SUPABASE_URL)
        SUPABASE_ANON_KEY: $(SUPABASE_ANON_KEY)
```

- [ ] **Step 4: Create the config reader**

Create `WanderIQ/Sync/SupabaseConfig.swift`:
```swift
import Foundation

/// Reads the public Supabase client credentials injected via Supabase.xcconfig
/// → Info.plist. Fatal-errors early in DEBUG if missing so misconfig is obvious.
enum SupabaseConfig {
    static var url: URL {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let u = URL(string: s), !s.isEmpty else {
            fatalError("SUPABASE_URL missing — copy Supabase.xcconfig.example to Supabase.xcconfig")
        }
        return u
    }
    static var anonKey: String {
        guard let k = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !k.isEmpty else {
            fatalError("SUPABASE_ANON_KEY missing — copy Supabase.xcconfig.example to Supabase.xcconfig")
        }
        return k
    }
}
```

- [ ] **Step 5: Generate, resolve packages, and build**

USER provides the anon key + URL; create `Supabase.xcconfig` from the example with real values. Then run:
```bash
cd /Users/wyu610/_Dev/WanderIQ
cp Supabase.xcconfig.example Supabase.xcconfig   # then edit in real values
xcodegen generate
xcodebuild -project WanderIQ.xcodeproj -scheme WanderIQ -destination 'generic/platform=iOS Simulator' build
```
Expected: `** BUILD SUCCEEDED **` and `import Supabase` resolves (SPM fetches supabase-swift).

- [ ] **Step 6: Commit (config files only; never Supabase.xcconfig)**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add project.yml Supabase.xcconfig.example .gitignore Signing.xcconfig WanderIQ/Sync/SupabaseConfig.swift
git commit -m "chore(ios): add supabase-swift dependency and config reader"
```

---

### Task 2: Postgres row types (WanderIQKit, pure, TDD)

**Files:**
- Create: `WanderIQKit/Sources/WanderIQKit/Sync/SupabaseRows.swift`
- Test: `WanderIQKit/Tests/WanderIQKitTests/SupabaseRowsTests.swift`

Row structs mirror the Postgres columns (snake_case). Date/timestamp columns are
typed as `String` (ISO-8601) and parsed in the mapper (Task 3), avoiding any
JSON date-decoding-strategy coupling.

- [ ] **Step 1: Write the failing test**

Create `WanderIQKit/Tests/WanderIQKitTests/SupabaseRowsTests.swift`:
```swift
import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SupabaseRowsTests {
    @Test func tripRowDecodesSnakeCaseJSON() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-0000000000a1",
         "owner_id":"00000000-0000-0000-0000-0000000000b2",
         "name":"China","start_date":"2026-07-11","end_date":"2026-07-31",
         "destinations":["Shanghai","HK"],"schema_version":1,
         "modified_at":"2026-06-13T00:00:05Z","deleted":false}
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(TripRow.self, from: json)
        #expect(row.name == "China")
        #expect(row.destinations == ["Shanghai", "HK"])
        #expect(row.modified_at == "2026-06-13T00:00:05Z")
        #expect(row.deleted == false)
    }

    @Test func itemRowEncodesWithSnakeCaseKeys() throws {
        let row = ItemRow(id: "i1", trip_id: "t1", kind: "prep", label: "X",
                          notes: "", day_id: nil, time: nil, item_owner: nil,
                          is_done: true, sort_order: 0, reminder_date: nil,
                          place: nil, modified_at: "2026-06-13T00:00:05Z", deleted: false)
        let data = try JSONEncoder().encode(row)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains("\"is_done\":true"))
        #expect(s.contains("\"sort_order\":0"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd WanderIQKit && make test`
Expected: FAIL — `cannot find 'TripRow' in scope`.

- [ ] **Step 3: Write the row types**

Create `WanderIQKit/Sources/WanderIQKit/Sync/SupabaseRows.swift`:
```swift
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd WanderIQKit && make test`
Expected: PASS (2 new SupabaseRows tests + 62 prior = 64).

- [ ] **Step 5: Commit**

```bash
git add WanderIQKit/Sources/WanderIQKit/Sync/SupabaseRows.swift WanderIQKit/Tests/WanderIQKitTests/SupabaseRowsTests.swift
git commit -m "feat(sync): Codable Postgres row types"
```

---

### Task 3: SupabaseRowMapping (WanderIQKit, pure, TDD)

**Files:**
- Create: `WanderIQKit/Sources/WanderIQKit/Sync/SupabaseRowMapping.swift`
- Test: `WanderIQKit/Tests/WanderIQKitTests/SupabaseRowMappingTests.swift`

Converts each row type to a `SyncRecord` (pull side) and a `SyncRecord` to the
right row (push side). Dates are emitted as ISO-8601. The `fields` keys exactly
match what `SyncMapping.apply` consumes (from sub-project 2), so a pulled row
flows straight into the store.

- [ ] **Step 1: Write the failing test**

Create `WanderIQKit/Tests/WanderIQKitTests/SupabaseRowMappingTests.swift`:
```swift
import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SupabaseRowMappingTests {
    let at = "2026-06-13T00:00:05Z"
    var atDate: Date { ISO8601DateFormatter().date(from: at)! }

    @Test func itemRowToSyncRecordCarriesFieldsAndDeleted() {
        let row = ItemRow(id: "00000000-0000-0000-0000-0000000000e1",
                          trip_id: "00000000-0000-0000-0000-0000000000f1",
                          kind: "prep", label: "Buy", notes: "n", day_id: nil,
                          time: "09:30", item_owner: "Mom", is_done: true,
                          sort_order: 2, reminder_date: nil,
                          place: PlaceRow(name: "Museum", query: "Museum SH",
                                          latitude: 31.0, longitude: 121.0),
                          modified_at: at, deleted: false)
        let rec = SupabaseRowMapping.syncRecord(item: row)
        #expect(rec.kind == .item)
        #expect(rec.deleted == false)
        #expect(rec.modifiedAt == atDate)
        #expect(rec.fields?["label"] == "Buy")
        #expect(rec.fields?["isDone"] == "true")
        #expect(rec.fields?["placeName"] == "Museum")
        #expect(rec.fields?["placeLat"] == "31.0")
    }

    @Test func syncRecordToItemRowRoundTripsCoreFields() {
        let rec = SyncRecord(kind: .item, id: UUID(), tripID: UUID(),
                             modifiedAt: atDate, deleted: false,
                             fields: ["kind": "packing", "label": "Socks",
                                      "notes": "", "isDone": "false", "sortOrder": "1"])
        let row = SupabaseRowMapping.itemRow(from: rec)
        #expect(row.kind == "packing")
        #expect(row.label == "Socks")
        #expect(row.is_done == false)
        #expect(row.sort_order == 1)
        #expect(row.modified_at == at)
        #expect(row.deleted == false)
    }

    @Test func tripTombstoneRecordMapsToDeletedRow() {
        let id = UUID(); let trip = id
        let rec = SyncRecord(kind: .trip, id: id, tripID: trip,
                             modifiedAt: atDate, deleted: true)
        let row = SupabaseRowMapping.tripRow(from: rec)
        #expect(row.deleted == true)
        #expect(row.modified_at == at)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd WanderIQKit && make test`
Expected: FAIL — `cannot find 'SupabaseRowMapping' in scope`.

- [ ] **Step 3: Write the mapping**

Create `WanderIQKit/Sources/WanderIQKit/Sync/SupabaseRowMapping.swift`:
```swift
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd WanderIQKit && make test`
Expected: PASS (3 new mapping tests + prior = 67).

- [ ] **Step 5: Commit**

```bash
git add WanderIQKit/Sources/WanderIQKit/Sync/SupabaseRowMapping.swift WanderIQKit/Tests/WanderIQKitTests/SupabaseRowMappingTests.swift
git commit -m "feat(sync): pure row <-> SyncRecord mapping (ISO dates)"
```

---

### Task 4: SupabaseRemoteSyncBackend (app target)

**Files:**
- Create: `WanderIQ/Sync/SupabaseRemoteSyncBackend.swift`

This is the network shell. It conforms to `WanderIQKit.RemoteSyncBackend`,
groups records by table for upsert, and queries the three tables for changes,
delegating ALL value translation to the pure `SupabaseRowMapping`. It is
build-verified here and integration-smoke-tested in Task 5 (app-target network
code is not unit-tested in the package).

- [ ] **Step 1: Write the backend**

Create `WanderIQ/Sync/SupabaseRemoteSyncBackend.swift`:
```swift
import Foundation
import Supabase
import WanderIQKit

/// Concrete RemoteSyncBackend backed by Supabase PostgREST. Tables: trips,
/// trip_days, trip_items. server_updated_at is server-stamped (trigger);
/// the cursor filters on it. RLS scopes rows to the signed-in user.
final class SupabaseRemoteSyncBackend: RemoteSyncBackend {
    private let client: SupabaseClient

    init(client: SupabaseClient) { self.client = client }

    convenience init() {
        self.init(client: SupabaseClient(supabaseURL: SupabaseConfig.url,
                                         supabaseKey: SupabaseConfig.anonKey))
    }

    // MARK: Push

    func send(_ records: [SyncRecord]) async throws {
        // owner_id is NOT NULL and RLS requires it == auth.uid(); the pure
        // mapper can't know the user, so inject it here. Requires an
        // authenticated session (arrives in 3b) — push is a no-op pre-auth.
        let uid = try await client.auth.session.user.id.uuidString.lowercased()
        var trips = records.filter { $0.kind == .trip }.map(SupabaseRowMapping.tripRow(from:))
        for i in trips.indices { trips[i].owner_id = uid }
        let days  = records.filter { $0.kind == .day  }.map(SupabaseRowMapping.dayRow(from:))
        let items = records.filter { $0.kind == .item }.map(SupabaseRowMapping.itemRow(from:))
        if !trips.isEmpty { try await client.from("trips").upsert(trips, onConflict: "id").execute() }
        if !days.isEmpty  { try await client.from("trip_days").upsert(days, onConflict: "id").execute() }
        if !items.isEmpty { try await client.from("trip_items").upsert(items, onConflict: "id").execute() }
    }

    // MARK: Pull

    func changes(since cursor: Date) async throws -> ChangePage {
        let iso = ISO8601DateFormatter().string(from: cursor)
        async let tripRows: [TripRow] = client.from("trips").select()
            .gt("server_updated_at", value: iso)
            .order("server_updated_at", ascending: true).execute().value
        async let dayRows: [DayRow] = client.from("trip_days").select()
            .gt("server_updated_at", value: iso)
            .order("server_updated_at", ascending: true).execute().value
        async let itemRows: [ItemRow] = client.from("trip_items").select()
            .gt("server_updated_at", value: iso)
            .order("server_updated_at", ascending: true).execute().value

        let records =
            try await tripRows.map(SupabaseRowMapping.syncRecord(trip:)) +
            (try await dayRows.map(SupabaseRowMapping.syncRecord(day:))) +
            (try await itemRows.map(SupabaseRowMapping.syncRecord(item:)))

        // Advance the cursor to the newest server_updated_at fetched. We fetch
        // it as a column on a lightweight follow-up only if rows exist; here we
        // approximate using the max modifiedAt is WRONG (client clock), so we
        // instead request server_updated_at explicitly via a dedicated decode.
        let newCursor = try await maxServerUpdatedAt(defaulting: cursor)
        return ChangePage(records: records, cursor: newCursor)
    }

    /// The max server_updated_at across the three tables visible to this user,
    /// or `fallback` if there are none. Decoded as ISO strings to avoid date
    /// decoding-strategy coupling.
    private func maxServerUpdatedAt(defaulting fallback: Date) async throws -> Date {
        struct Stamp: Decodable { let server_updated_at: String }
        func newest(_ table: String) async throws -> Date? {
            let rows: [Stamp] = try await client.from(table).select("server_updated_at")
                .order("server_updated_at", ascending: false).limit(1).execute().value
            return rows.first.flatMap { ISO8601DateFormatter().date(from: $0.server_updated_at) }
        }
        let stamps = [try await newest("trips"),
                      try await newest("trip_days"),
                      try await newest("trip_items")].compactMap { $0 }
        return stamps.max() ?? fallback
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
cd /Users/wyu610/_Dev/WanderIQ
xcodegen generate
xcodebuild -project WanderIQ.xcodeproj -scheme WanderIQ -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add WanderIQ/Sync/SupabaseRemoteSyncBackend.swift WanderIQ.xcodeproj
git commit -m "feat(ios): SupabaseRemoteSyncBackend (PostgREST push/pull)"
```

---

### Task 5: Integration smoke verification (manual, against dev cloud)

**Files:**
- Create: `WanderIQ/Sync/SyncDebug.swift` (DEBUG-only helper)

Because the backend talks to the live dev project (RLS requires an authenticated
user, which arrives in 3b), this task verifies the unauthenticated-safe path:
the client initializes and a `changes(since:)` call succeeds and returns an
empty page against an empty/anon-restricted dataset, proving wiring + decoding.

- [ ] **Step 1: Add a DEBUG smoke helper**

Create `WanderIQ/Sync/SyncDebug.swift`:
```swift
#if DEBUG
import Foundation
import WanderIQKit

/// Manual smoke check for the Supabase transport wiring. Call from a temporary
/// button or `Task {}` in the app during 3a bring-up; remove/ignore after 3b.
enum SyncDebug {
    static func smoke() async {
        let backend = SupabaseRemoteSyncBackend()
        do {
            let page = try await backend.changes(since: .distantPast)
            print("SyncDebug: pulled \(page.records.count) records, cursor \(page.cursor)")
        } catch {
            print("SyncDebug: changes() failed: \(error)")
        }
    }
}
#endif
```

- [ ] **Step 2: Run the smoke check (manual, requires anon key configured)**

With `Supabase.xcconfig` populated, run the app in the simulator and trigger
`SyncDebug.smoke()` once (e.g. temporarily call it from `WanderIQApp` init in a
`Task {}`). Expected console output: `SyncDebug: pulled 0 records, cursor ...`
without an error — confirming the client initializes, the request is accepted,
and decoding works. (Anon/unauthenticated sees no rows under RLS; non-empty
results arrive once 3b adds auth.)

Troubleshooting — the row structs use snake_case property names matching the
Postgres columns and assume supabase-swift's PostgREST decoder does NOT apply
`convertFromSnakeCase`. If the smoke run logs a `DecodingError` about missing
keys, that assumption is wrong for the installed version: add explicit
`CodingKeys` to `TripRow`/`DayRow`/`ItemRow` mapping each property to its column
name, then re-run. (The package unit tests use a plain `JSONDecoder` and are
unaffected either way.)

- [ ] **Step 3: Commit**

```bash
git add WanderIQ/Sync/SyncDebug.swift WanderIQ.xcodeproj
git commit -m "test(ios): DEBUG smoke helper for Supabase transport"
```

---

## Done criteria

- `cd WanderIQKit && make test` passes (62 baseline + row-types + mapping = 67),
  proving all pure transport logic.
- The app builds with `supabase-swift`; `SupabaseRemoteSyncBackend` conforms to
  `RemoteSyncBackend` and compiles.
- `SyncDebug.smoke()` returns a page without error against the dev project.
- `Supabase.xcconfig` (anon key + URL) is gitignored; `.example` is committed.
- Next plans: **3b — Auth** (Supabase Auth + AuthView, gate the app), then
  **3c — App cutover** (wire SyncEngine into AppModel, file-persist Outbox +
  SyncState, Realtime → pull, retire CloudKit).

## Self-review notes (carried into 3c)

- `changes(since:)` advances the cursor via a dedicated `server_updated_at`
  query rather than the client `modifiedAt`, honoring the protocol's "cursor
  uses server time only" rule. If this proves chatty, 3c can switch to a single
  RPC/view returning the max stamp with the page.
- Auth is required for non-empty pulls (RLS); 3a only proves wiring. Real
  data-flow verification happens after 3b.
