# Planova iOS v2 CloudKit Sync + Family Sharing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trips sync across the user's devices and can be shared read/write with family members via iCloud, offline-first, replacing the PWA's Supabase sync.

**Architecture:** Raw CloudKit via `CKSyncEngine` (iOS 17+). One custom zone per trip in the private database; shared trips arrive via the shared database. One `CKRecord` per entity (Trip meta / TripDay / ChecklistItem) so concurrent family checkmarks never conflict. Pure logic (record mapping, trip diffing, remote upsert) lives in PlanovaKit and is unit-tested with `make test`; the `SyncCoordinator` (engines, delegate, persistence of engine state) and sharing UI live in the app target. Family sharing = zone-wide `CKShare` + `UICloudSharingController`.

**Tech Stack:** CloudKit (`CKSyncEngine`, `CKShare`), Swift 5.10/SwiftUI, XcodeGen, Swift Testing (via `make test` in PlanovaKit).

**Spec:** sections 5.3–5.4 of `docs/superpowers/specs/2026-06-10-planova-ios-design.md`.

---

## Critical context for the implementer

- Build: `xcodegen generate && xcodebuild -project Planova.xcodeproj -scheme Planova -destination 'generic/platform=iOS Simulator' build` → `** BUILD SUCCEEDED **`.
- Package tests: `cd PlanovaKit && make test` (NOT bare `swift test`).
- UI smoke test (must keep passing): `xcodebuild test -project Planova.xcodeproj -scheme Planova -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PlanovaUITests`.
- **CKSyncEngine API note:** signatures below follow Apple's CKSyncEngine sample (WWDC23). If the Xcode 26.5 SDK differs slightly (label/optionality), adapt minimally and record the change in your report — do not restructure.
- **No iCloud account is available in CI/simulator by default.** Everything must degrade gracefully: with no account or no entitlement provisioning, the app runs exactly as v1 (local only). End-to-end sync is verified manually by the user (Task 10).
- Branch: create `feature/ios-v2-cloudkit-sync` from `main` before Task 1.

## File structure

```
Planova.entitlements                      // iCloud container + CloudKit (new)
Signing.xcconfig                          // DEVELOPMENT_TEAM, gitignored (user-created)
Signing.xcconfig.example                  // committed template
project.yml                               // entitlements, background mode, xcconfig
PlanovaKit/Sources/PlanovaKit/
  CloudKitMapping.swift                   // zone/record IDs, Trip⇄CKRecord field mapping
  TripDiff.swift                          // old/new Trip → pending record saves/deletes
  TripStore.swift                         // + applyRemote / removeRemote / onRemoteChange
PlanovaKit/Tests/PlanovaKitTests/
  CloudKitMappingTests.swift
  TripDiffTests.swift
  TripStoreRemoteTests.swift
Planova/Sync/
  SyncCoordinator.swift                   // CKSyncEngine lifecycle, delegate, conflicts
  CloudSharingView.swift                  // UICloudSharingController wrapper + share creation
Planova/App/
  AppModel.swift                          // wire SyncCoordinator
  PlanovaApp.swift                        // AppDelegate/SceneDelegate for share acceptance
Planova/Features/TripList/TripListView.swift   // sync status footer
Planova/Features/TripDetail/TripDetailView.swift // Share toolbar button
Planova/Resources/Localizable.xcstrings   // new keys
```

---

### Task 1: Entitlements, signing config, project plumbing

**Files:**
- Create: `Planova.entitlements`, `Signing.xcconfig.example`
- Modify: `project.yml`, `.gitignore`

- [ ] **Step 1: Create branch**

```bash
git checkout main && git checkout -b feature/ios-v2-cloudkit-sync
```

- [ ] **Step 2: Create `Planova.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>iCloud.com.planova.Planova</string>
	</array>
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudKit</string>
	</array>
	<key>aps-environment</key>
	<string>development</string>
</dict>
</plist>
```

- [ ] **Step 3: Create `Signing.xcconfig.example`**

```
// Copy to Signing.xcconfig (gitignored) and fill in your Apple Developer Team ID
// (Xcode → Settings → Accounts, or developer.apple.com → Membership).
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

Append to `.gitignore`:

```
Signing.xcconfig
```

- [ ] **Step 4: Wire into `project.yml`**

Replace the full file with:

```yaml
name: Planova
options:
  bundleIdPrefix: com.planova
  deploymentTarget:
    iOS: "17.0"
configFiles:
  Debug: Signing.xcconfig
  Release: Signing.xcconfig
packages:
  PlanovaKit:
    path: PlanovaKit
targets:
  Planova:
    type: application
    platform: iOS
    sources: [Planova]
    dependencies:
      - package: PlanovaKit
    scheme:
      testTargets: [PlanovaUITests]
    entitlements:
      path: Planova.entitlements
      properties:
        com.apple.developer.icloud-container-identifiers: [iCloud.com.planova.Planova]
        com.apple.developer.icloud-services: [CloudKit]
        aps-environment: development
    info:
      path: Planova/Info.plist
      properties:
        UILaunchScreen: {}
        CFBundleDisplayName: Planova
        CFBundleLocalizations: [en, zh-Hans]
        UIBackgroundModes: [remote-notification]
    settings:
      base:
        TARGETED_DEVICE_FAMILY: "1,2"
        SWIFT_VERSION: "5.10"
        CURRENT_PROJECT_VERSION: 1
        MARKETING_VERSION: 0.2.0
  PlanovaUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [PlanovaUITests]
    dependencies:
      - target: Planova
    settings:
      base:
        GENERATE_INFOPLIST_FILE: true
```

Note: this switches from `GENERATE_INFOPLIST_FILE` to an explicit generated `Planova/Info.plist` (XcodeGen writes it from `info.properties`) because `UIBackgroundModes` needs a real plist. If the previously gitignored generated files conflict, run `xcodegen generate` and check `git status` — `Planova/Info.plist` is generated by xcodegen and SHOULD be committed.

If no `Signing.xcconfig` exists yet, create a local one from the example with an empty value so builds still work unsigned:

```bash
[ -f Signing.xcconfig ] || printf 'DEVELOPMENT_TEAM =\n' > Signing.xcconfig
```

- [ ] **Step 5: Build**

```bash
xcodegen generate && xcodebuild -project Planova.xcodeproj -scheme Planova -destination 'generic/platform=iOS Simulator' build
```
Expected: `** BUILD SUCCEEDED **` (entitlements are not validated for simulator builds).

- [ ] **Step 6: Run UI smoke test (regression gate)**

```bash
xcodebuild test -project Planova.xcodeproj -scheme Planova -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PlanovaUITests
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add .gitignore project.yml Planova.entitlements Signing.xcconfig.example Planova/Info.plist
git commit -m "feat: add CloudKit entitlements and signing config plumbing"
```

---

### Task 2: CloudKitMapping (PlanovaKit)

**Files:**
- Create: `PlanovaKit/Sources/PlanovaKit/CloudKitMapping.swift`
- Test: `PlanovaKit/Tests/PlanovaKitTests/CloudKitMappingTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Testing
import CloudKit
@testable import PlanovaKit

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
}
```

- [ ] **Step 2: Run `cd PlanovaKit && make test`** — expect compile FAILURE (`CloudKitMapping` undefined).

- [ ] **Step 3: Implement**

`PlanovaKit/Sources/PlanovaKit/CloudKitMapping.swift`:

```swift
import Foundation
import CloudKit

/// Pure Trip ⇄ CKRecord mapping. One zone per trip; one record per entity.
/// Record types: TripMeta (singleton "trip-meta" per zone), TripDay, ChecklistItem
/// (recordName == entity UUID string).
public enum CloudKitMapping {

    public static let tripMetaRecordName = "trip-meta"
    private static let zonePrefix = "trip-"

    // MARK: Zone / record IDs

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
        if let v = record["destinations"] as? [String] { trip.destinations = v }
        if let v = record["schemaVersion"] as? Int { trip.schemaVersion = v }
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
        if let name = record["placeName"] as? String, let query = record["placeQuery"] as? String {
            place = Place(name: name, query: query,
                          latitude: record["placeLat"] as? Double,
                          longitude: record["placeLon"] as? Double)
        }
        return ChecklistItem(
            id: id, kind: kind, label: label,
            notes: record["notes"] as? String ?? "",
            dayID: (record["dayID"] as? String).flatMap(UUID.init(uuidString:)),
            time: record["time"] as? String,
            owner: record["owner"] as? String,
            isDone: (record["isDone"] as? Int ?? 0) != 0,
            sortOrder: record["sortOrder"] as? Int ?? 0,
            reminderDate: record["reminderDate"] as? Date,
            place: place,
            modifiedAt: record["modifiedAt"] as? Date ?? Date(timeIntervalSince1970: 0))
    }
}
```

- [ ] **Step 4: Run `make test`** — expect PASS (22 tests total: 17 existing + 5 new).
- [ ] **Step 5: Commit**

```bash
git add PlanovaKit && git commit -m "feat: add Trip-to-CKRecord mapping"
```

---

### Task 3: TripDiff (PlanovaKit)

**Files:**
- Create: `PlanovaKit/Sources/PlanovaKit/TripDiff.swift`
- Test: `PlanovaKit/Tests/PlanovaKitTests/TripDiffTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Testing
@testable import PlanovaKit

@Suite struct TripDiffTests {

    private func base() -> Trip {
        Trip(name: "T", startDate: Date(timeIntervalSince1970: 0), endDate: Date(timeIntervalSince1970: 1),
             days: [TripDay(date: Date(timeIntervalSince1970: 0), city: "c", title: "t")],
             items: [ChecklistItem(kind: .prep, label: "a"), ChecklistItem(kind: .packing, label: "b")])
    }

    @Test func nilOldMeansEverythingSaves() {
        let trip = base()
        let diff = TripDiff.changes(old: nil, new: trip)
        #expect(Set(diff.saves) == Set([.tripMeta] + trip.days.map { .day($0.id) } + trip.items.map { .item($0.id) }))
        #expect(diff.deletes.isEmpty)
    }

    @Test func noChangeMeansEmptyDiff() {
        let trip = base()
        let diff = TripDiff.changes(old: trip, new: trip)
        #expect(diff.saves.isEmpty)
        #expect(diff.deletes.isEmpty)
    }

    @Test func itemEditAndDeleteAndMetaChange() {
        let old = base()
        var new = old
        new.name = "Renamed"                        // meta save
        new.items[0].isDone = true                  // item save
        let removed = new.items.removeLast()        // item delete
        let added = ChecklistItem(kind: .doc, label: "new")
        new.items.append(added)                     // item save

        let diff = TripDiff.changes(old: old, new: new)
        #expect(Set(diff.saves) == Set([.tripMeta, .item(new.items[0].id), .item(added.id)]))
        #expect(diff.deletes == [.item(removed.id)])
    }

    @Test func dayChanges() {
        let old = base()
        var new = old
        new.days[0].title = "changed"
        let diff = TripDiff.changes(old: old, new: new)
        #expect(diff.saves == [.day(new.days[0].id)])
    }
}
```

- [ ] **Step 2: Run `make test`** — expect compile FAILURE.

- [ ] **Step 3: Implement**

`PlanovaKit/Sources/PlanovaKit/TripDiff.swift`:

```swift
import Foundation

/// A CloudKit-agnostic description of which records changed between two
/// snapshots of a trip. The sync layer turns these into CKRecord.IDs.
public enum TripRecordRef: Hashable, Sendable {
    case tripMeta
    case day(UUID)
    case item(UUID)
}

public enum TripDiff {

    public static func changes(old: Trip?, new: Trip)
        -> (saves: [TripRecordRef], deletes: [TripRecordRef]) {
        guard let old else {
            return ([.tripMeta] + new.days.map { .day($0.id) } + new.items.map { .item($0.id) }, [])
        }
        var saves: [TripRecordRef] = []
        var deletes: [TripRecordRef] = []

        let metaChanged = old.name != new.name || old.startDate != new.startDate
            || old.endDate != new.endDate || old.destinations != new.destinations
            || old.schemaVersion != new.schemaVersion
        if metaChanged { saves.append(.tripMeta) }

        let oldDays = Dictionary(uniqueKeysWithValues: old.days.map { ($0.id, $0) })
        let newDays = Dictionary(uniqueKeysWithValues: new.days.map { ($0.id, $0) })
        for (id, day) in newDays where oldDays[id] != day { saves.append(.day(id)) }
        for id in oldDays.keys where newDays[id] == nil { deletes.append(.day(id)) }

        let oldItems = Dictionary(uniqueKeysWithValues: old.items.map { ($0.id, $0) })
        let newItems = Dictionary(uniqueKeysWithValues: new.items.map { ($0.id, $0) })
        for (id, item) in newItems where oldItems[id] != item { saves.append(.item(id)) }
        for id in oldItems.keys where newItems[id] == nil { deletes.append(.item(id)) }

        return (saves, deletes)
    }
}
```

- [ ] **Step 4: Run `make test`** — expect PASS (26 tests).
- [ ] **Step 5: Commit**

```bash
git add PlanovaKit && git commit -m "feat: add trip snapshot diffing for sync"
```

---

### Task 4: TripStore remote-apply API (PlanovaKit)

**Files:**
- Modify: `PlanovaKit/Sources/PlanovaKit/TripStore.swift`
- Test: `PlanovaKit/Tests/PlanovaKitTests/TripStoreRemoteTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Testing
import Foundation
@testable import PlanovaKit

@Suite struct TripStoreRemoteTests {

    @Test func upsertRemoteCreatesShellAndDoesNotTriggerOnChange() {
        let store = TripStore()
        var onChangeFired = false
        var remoteChanged: Trip?
        store.onChange = { _ in onChangeFired = true }
        store.onRemoteChange = { remoteChanged = $0 }
        let id = UUID()

        store.upsertRemote(tripID: id) { trip in
            trip.name = "From cloud"
        }

        #expect(store.trip(id: id)?.name == "From cloud")
        #expect(onChangeFired == false)
        #expect(remoteChanged?.id == id)
    }

    @Test func upsertRemoteMutatesExistingTrip() {
        let trip = Trip(name: "Local", startDate: Date(timeIntervalSince1970: 0), endDate: Date(timeIntervalSince1970: 1))
        let store = TripStore(trips: [trip])

        store.upsertRemote(tripID: trip.id) { $0.items.append(ChecklistItem(kind: .prep, label: "x")) }

        #expect(store.trip(id: trip.id)?.items.count == 1)
        #expect(store.trip(id: trip.id)?.name == "Local")
    }

    @Test func removeRemoteDeletesAndNotifiesRemoval() {
        let trip = Trip(name: "T", startDate: Date(timeIntervalSince1970: 0), endDate: Date(timeIntervalSince1970: 1))
        let store = TripStore(trips: [trip])
        var removed: UUID?
        store.onRemoteRemove = { removed = $0 }

        store.removeRemote(tripID: trip.id)

        #expect(store.trip(id: trip.id) == nil)
        #expect(removed == trip.id)
    }
}
```

- [ ] **Step 2: Run `make test`** — expect compile FAILURE.

- [ ] **Step 3: Implement** — add to `TripStore` (after the existing `onChange` property and `resetPacking` method respectively):

```swift
    /// Fired after a remote (cloud-originated) mutation; the app layer hooks
    /// disk persistence here. Deliberately separate from onChange so remote
    /// applies never re-enter the sync send queue.
    @ObservationIgnored public var onRemoteChange: ((Trip) -> Void)?

    /// Fired after a remote deletion (zone deleted / share revoked).
    @ObservationIgnored public var onRemoteRemove: ((UUID) -> Void)?

    /// Apply a cloud-originated mutation, creating an empty shell trip if
    /// this is the first record fetched for an unknown trip (its real name
    /// and dates arrive with the TripMeta record).
    public func upsertRemote(tripID: UUID, _ mutate: (inout Trip) -> Void) {
        if let i = trips.firstIndex(where: { $0.id == tripID }) {
            mutate(&trips[i])
            onRemoteChange?(trips[i])
        } else {
            var shell = Trip(id: tripID, name: "",
                             startDate: Date(timeIntervalSince1970: 0),
                             endDate: Date(timeIntervalSince1970: 0))
            mutate(&shell)
            trips.append(shell)
            trips.sort { $0.startDate < $1.startDate }
            onRemoteChange?(shell)
        }
    }

    public func removeRemote(tripID: UUID) {
        guard trips.contains(where: { $0.id == tripID }) else { return }
        trips.removeAll { $0.id == tripID }
        onRemoteRemove?(tripID)
    }
```

- [ ] **Step 4: Run `make test`** — expect PASS (29 tests).
- [ ] **Step 5: Commit**

```bash
git add PlanovaKit && git commit -m "feat: add remote-apply API to TripStore"
```

---

### Task 5: SyncCoordinator — engines, state, account status

**Files:**
- Create: `Planova/Sync/SyncCoordinator.swift`
- Modify: `Planova/App/AppModel.swift`

- [ ] **Step 1: Create `Planova/Sync/SyncCoordinator.swift`**

```swift
import Foundation
import CloudKit
import Observation
import PlanovaKit

/// Owns the CloudKit sync engines (private + shared databases), persists
/// their state serializations, and bridges between TripStore and CKRecords.
/// All UI-facing state is @MainActor.
@MainActor
@Observable
final class SyncCoordinator {

    enum Status: Equatable {
        case unavailable(String)   // no iCloud account / restricted
        case idle
        case syncing
        case error(String)
    }

    private(set) var status: Status = .unavailable("Checking iCloud…")

    static let containerID = "iCloud.com.planova.Planova"

    private let container: CKContainer
    private let store: TripStore
    private let stateDirectory: URL
    @ObservationIgnored private var privateEngine: CKSyncEngine?
    @ObservationIgnored private var sharedEngine: CKSyncEngine?
    /// Snapshot of each trip as of the last diff, for change detection.
    @ObservationIgnored private var lastKnown: [UUID: Trip] = [:]
    /// Trips that live in the shared database (we are a participant).
    @ObservationIgnored private(set) var sharedTripIDs: Set<UUID> = []
    /// Zone owner names for shared trips (needed to build record IDs).
    @ObservationIgnored private var zoneOwners: [UUID: String] = [:]

    init(store: TripStore, stateDirectory: URL) {
        self.container = CKContainer(identifier: Self.containerID)
        self.store = store
        self.stateDirectory = stateDirectory
    }

    // MARK: - Lifecycle

    func start() async {
        do {
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                status = .unavailable(Self.describe(accountStatus))
                return
            }
        } catch {
            status = .unavailable(error.localizedDescription)
            return
        }
        lastKnown = Dictionary(uniqueKeysWithValues: store.trips.map { ($0.id, $0) })
        privateEngine = makeEngine(database: container.privateCloudDatabase, stateFile: "private-sync-state")
        sharedEngine = makeEngine(database: container.sharedCloudDatabase, stateFile: "shared-sync-state")
        status = .idle
        // First run: ensure every local trip has a zone + records queued.
        for trip in store.trips where !sharedTripIDs.contains(trip.id) {
            queueFullTrip(trip)
        }
    }

    private func makeEngine(database: CKDatabase, stateFile: String) -> CKSyncEngine {
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: loadState(stateFile),
            delegate: self)
        configuration.automaticallySync = true
        return CKSyncEngine(configuration)
    }

    /// Manual refresh (pull-to-refresh / foreground), since simulator gets no push.
    func fetchNow() async {
        guard let privateEngine, let sharedEngine else { return }
        status = .syncing
        try? await privateEngine.fetchChanges()
        try? await sharedEngine.fetchChanges()
        status = .idle
    }

    private static func describe(_ s: CKAccountStatus) -> String {
        switch s {
        case .noAccount: return String(localized: "Sign in to iCloud to sync")
        case .restricted: return String(localized: "iCloud is restricted")
        case .temporarilyUnavailable: return String(localized: "iCloud temporarily unavailable")
        default: return String(localized: "iCloud unavailable")
        }
    }

    // MARK: - State serialization persistence

    private func stateURL(_ name: String) -> URL {
        stateDirectory.appendingPathComponent(name + ".data")
    }

    private func loadState(_ name: String) -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL(name)) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ serialization: CKSyncEngine.State.Serialization, name: String) {
        try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(serialization) {
            try? data.write(to: stateURL(name), options: .atomic)
        }
    }

    private func stateFileName(for engine: CKSyncEngine) -> String {
        engine === privateEngine ? "private-sync-state" : "shared-sync-state"
    }

    // MARK: - Helpers used by send/fetch paths (Tasks 6–7)

    func owner(for tripID: UUID) -> String {
        zoneOwners[tripID] ?? CKCurrentUserDefaultName
    }

    func engine(for tripID: UUID) -> CKSyncEngine? {
        sharedTripIDs.contains(tripID) ? sharedEngine : privateEngine
    }

    func noteShared(tripID: UUID, ownerName: String) {
        sharedTripIDs.insert(tripID)
        zoneOwners[tripID] = ownerName
    }

    func queueFullTrip(_ trip: Trip) {
        // Implemented in Task 6.
    }
}

// MARK: - CKSyncEngineDelegate (fleshed out in Tasks 6–7)

extension SyncCoordinator: CKSyncEngineDelegate {

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await handle(event, engine: syncEngine)
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await makeBatch(context: context, engine: syncEngine)
    }

    private func handle(_ event: CKSyncEngine.Event, engine: CKSyncEngine) {
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization, name: stateFileName(for: engine))
        default:
            break   // send/fetch events implemented in Tasks 6–7
        }
    }

    private func makeBatch(context: CKSyncEngine.SendChangesContext,
                           engine: CKSyncEngine) -> CKSyncEngine.RecordZoneChangeBatch? {
        nil   // Implemented in Task 6.
    }
}
```

- [ ] **Step 2: Wire into `AppModel`** — in `Planova/App/AppModel.swift`:

Add a property after `private let repository: TripRepository`:

```swift
    let sync: SyncCoordinator
```

In `init()`, after `self.store = TripStore(trips: trips)` and before `seedIfNeeded()`:

```swift
        self.sync = SyncCoordinator(store: store,
                                    stateDirectory: URL.applicationSupportDirectory.appendingPathComponent("sync"))
```

At the end of `init()`:

```swift
        store.onRemoteChange = { [weak self] trip in
            self?.scheduleSave(trip)
            self?.refreshReminders()
        }
        store.onRemoteRemove = { [weak self] id in
            try? self?.repository.delete(id: id)
            self?.refreshReminders()
        }
        Task { await sync.start() }
```

- [ ] **Step 3: Build** (standard command) — expect `** BUILD SUCCEEDED **`. If the CKSyncEngine delegate signatures differ in the Xcode 26.5 SDK, adapt minimally and record the change.

- [ ] **Step 4: Commit**

```bash
git add Planova && git commit -m "feat: add SyncCoordinator skeleton with engine lifecycle and account status"
```

---

### Task 6: SyncCoordinator — send path and conflicts

**Files:**
- Modify: `Planova/Sync/SyncCoordinator.swift`
- Modify: `Planova/App/AppModel.swift`

- [ ] **Step 1: Implement change queueing.** Replace the stub `func queueFullTrip(_ trip: Trip)` and add `noteLocalChange` / `noteLocalDelete`:

```swift
    /// Queue every record of a trip (first sync of a local trip).
    func queueFullTrip(_ trip: Trip) {
        guard let engine = engine(for: trip.id) else { return }
        let owner = owner(for: trip.id)
        if !sharedTripIDs.contains(trip.id) {
            let zone = CKRecordZone(zoneID: CloudKitMapping.zoneID(forTripID: trip.id, owner: owner))
            engine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
        }
        let diff = TripDiff.changes(old: nil, new: trip)
        engine.state.add(pendingRecordZoneChanges: diff.saves.map { .saveRecord(recordID($0, tripID: trip.id)) })
        lastKnown[trip.id] = trip
    }

    /// Called (via AppModel) after every local mutation.
    func noteLocalChange(_ trip: Trip) {
        guard let engine = engine(for: trip.id) else { return }
        if lastKnown[trip.id] == nil, !sharedTripIDs.contains(trip.id) {
            queueFullTrip(trip)
            return
        }
        let diff = TripDiff.changes(old: lastKnown[trip.id], new: trip)
        guard !diff.saves.isEmpty || !diff.deletes.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges:
            diff.saves.map { .saveRecord(recordID($0, tripID: trip.id)) } +
            diff.deletes.map { .deleteRecord(recordID($0, tripID: trip.id)) })
        lastKnown[trip.id] = trip
    }

    /// Called when the user deletes a trip locally: drop the whole zone.
    func noteLocalDelete(tripID: UUID) {
        guard let engine = engine(for: tripID) else { return }
        engine.state.add(pendingDatabaseChanges:
            [.deleteZone(CloudKitMapping.zoneID(forTripID: tripID, owner: owner(for: tripID)))])
        lastKnown[tripID] = nil
    }

    private func recordID(_ ref: TripRecordRef, tripID: UUID) -> CKRecord.ID {
        let owner = owner(for: tripID)
        switch ref {
        case .tripMeta: return CloudKitMapping.tripMetaRecordID(tripID: tripID, owner: owner)
        case .day(let id): return CloudKitMapping.dayRecordID(id, tripID: tripID, owner: owner)
        case .item(let id): return CloudKitMapping.itemRecordID(id, tripID: tripID, owner: owner)
        }
    }
```

- [ ] **Step 2: Implement the record provider.** Replace `makeBatch`:

```swift
    private func makeBatch(context: CKSyncEngine.SendChangesContext,
                           engine: CKSyncEngine) -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = engine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] recordID in
            await MainActor.run { self?.record(for: recordID) }
        }
    }

    /// Build the current CKRecord for a record ID, or nil if the entity no
    /// longer exists locally (the engine then drops the pending save).
    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let tripID = CloudKitMapping.tripID(fromZoneName: recordID.zoneID.zoneName),
              let trip = store.trip(id: tripID) else { return nil }
        let owner = recordID.zoneID.ownerName
        if recordID.recordName == CloudKitMapping.tripMetaRecordName {
            return CloudKitMapping.tripMetaRecord(for: trip, owner: owner)
        }
        guard let entityID = UUID(uuidString: recordID.recordName) else { return nil }
        if let item = trip.items.first(where: { $0.id == entityID }) {
            return CloudKitMapping.itemRecord(for: item, tripID: tripID, owner: owner)
        }
        if let day = trip.days.first(where: { $0.id == entityID }) {
            return CloudKitMapping.dayRecord(for: day, tripID: tripID, owner: owner)
        }
        return nil
    }
```

Note: if `RecordZoneChangeBatch(pendingChanges:recordProvider:)`'s provider is synchronous in this SDK, drop the `await MainActor.run` wrapper accordingly (the coordinator is @MainActor; use `MainActor.assumeIsolated` if needed). Record any adaptation.

- [ ] **Step 3: Handle sent-changes events and conflicts.** In `handle(_:engine:)`, add a case before `default`:

```swift
        case .sentRecordZoneChanges(let sent):
            for failed in sent.failedRecordSaves {
                handleFailedSave(failed.record, error: failed.error, engine: engine)
            }
```

And add the conflict handler method to the extension:

```swift
    /// Spec conflict policy: per-record last-writer-wins. The server copy is
    /// the baseline; if our local entity was modified more recently than the
    /// server's, requeue our save (now carrying the server change tag).
    private func handleFailedSave(_ record: CKRecord, error: CKError, engine: CKSyncEngine) {
        switch error.code {
        case .serverRecordChanged:
            guard let serverRecord = error.serverRecord,
                  let tripID = CloudKitMapping.tripID(fromZoneName: record.recordID.zoneID.zoneName) else { return }
            let serverModified = serverRecord["modifiedAt"] as? Date ?? .distantPast
            let localModified = record["modifiedAt"] as? Date ?? .distantPast
            if localModified > serverModified {
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            } else {
                applyFetchedRecord(serverRecord)   // accept server copy locally (Task 7)
            }
            _ = tripID
        case .zoneNotFound:
            // Zone was deleted remotely or never created: recreate and resend everything.
            if let tripID = CloudKitMapping.tripID(fromZoneName: record.recordID.zoneID.zoneName),
               let trip = store.trip(id: tripID) {
                queueFullTrip(trip)
            }
        case .unknownItem, .invalidArguments:
            break   // dropped: entity no longer exists or schema mismatch
        default:
            status = .error(error.localizedDescription)
        }
    }

    /// Stub until Task 7.
    private func applyFetchedRecord(_ record: CKRecord) {}
```

- [ ] **Step 4: Route AppModel mutations into the coordinator.** In `Planova/App/AppModel.swift`:

In `init()`, replace the existing `store.onChange` line with:

```swift
        store.onChange = { [weak self] trip in
            self?.scheduleSave(trip)
            self?.sync.noteLocalChange(trip)
        }
```

In `deleteTrip(id:)`, add as the first line:

```swift
        sync.noteLocalDelete(tripID: id)
```

- [ ] **Step 5: Build** — expect `** BUILD SUCCEEDED **`.
- [ ] **Step 6: Commit**

```bash
git add Planova && git commit -m "feat: implement sync send path with per-record conflict policy"
```

---

### Task 7: SyncCoordinator — fetch path

**Files:**
- Modify: `Planova/Sync/SyncCoordinator.swift`

- [ ] **Step 1: Handle fetched events.** In `handle(_:engine:)`, add cases before `default`:

```swift
        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions {
                if let tripID = CloudKitMapping.tripID(fromZoneName: deletion.zoneID.zoneName) {
                    store.removeRemote(tripID: tripID)
                    lastKnown[tripID] = nil
                    sharedTripIDs.remove(tripID)
                }
            }
            for modification in changes.modifications where engine === sharedEngine {
                // A zone appearing in the shared DB = a trip shared with us.
                if let tripID = CloudKitMapping.tripID(fromZoneName: modification.zoneID.zoneName) {
                    noteShared(tripID: tripID, ownerName: modification.zoneID.ownerName)
                }
            }

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                if engine === sharedEngine,
                   let tripID = CloudKitMapping.tripID(fromZoneName: modification.record.recordID.zoneID.zoneName) {
                    noteShared(tripID: tripID, ownerName: modification.record.recordID.zoneID.ownerName)
                }
                applyFetchedRecord(modification.record)
            }
            for deletion in changes.deletions {
                applyFetchedDeletion(deletion.recordID)
            }
```

- [ ] **Step 2: Implement apply methods.** Replace the `applyFetchedRecord` stub:

```swift
    private func applyFetchedRecord(_ record: CKRecord) {
        guard let tripID = CloudKitMapping.tripID(fromZoneName: record.recordID.zoneID.zoneName) else { return }
        store.upsertRemote(tripID: tripID) { trip in
            switch record.recordType {
            case "TripMeta":
                CloudKitMapping.applyTripMeta(record, to: &trip)
            case "TripDay":
                guard let day = CloudKitMapping.day(from: record) else { return }
                if let i = trip.days.firstIndex(where: { $0.id == day.id }) {
                    trip.days[i] = day
                } else {
                    trip.days.append(day)
                    trip.days.sort { $0.date < $1.date }
                }
            case "ChecklistItem":
                guard let item = CloudKitMapping.item(from: record) else { return }
                if let i = trip.items.firstIndex(where: { $0.id == item.id }) {
                    trip.items[i] = item
                } else {
                    trip.items.append(item)
                }
            default:
                break
            }
        }
        // Keep the diff baseline in step so remote applies don't echo back up.
        if let updated = store.trip(id: tripID) { lastKnown[tripID] = updated }
    }

    private func applyFetchedDeletion(_ recordID: CKRecord.ID) {
        guard let tripID = CloudKitMapping.tripID(fromZoneName: recordID.zoneID.zoneName),
              let entityID = UUID(uuidString: recordID.recordName) else { return }
        store.upsertRemote(tripID: tripID) { trip in
            trip.items.removeAll { $0.id == entityID }
            trip.days.removeAll { $0.id == entityID }
        }
        if let updated = store.trip(id: tripID) { lastKnown[tripID] = updated }
    }
```

- [ ] **Step 3: Build** — expect `** BUILD SUCCEEDED **`.
- [ ] **Step 4: Run UI smoke test** (sync is inert without an account; the app must behave exactly as v1):

```bash
xcodebuild test -project Planova.xcodeproj -scheme Planova -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PlanovaUITests
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Planova && git commit -m "feat: implement sync fetch path applying remote records"
```

---

### Task 8: Family sharing — share creation, UI, and acceptance

**Files:**
- Create: `Planova/Sync/CloudSharingView.swift`
- Modify: `Planova/Sync/SyncCoordinator.swift`, `Planova/App/PlanovaApp.swift`, `Planova/Features/TripDetail/TripDetailView.swift`

- [ ] **Step 1: Add share creation to `SyncCoordinator`:**

```swift
    /// Fetch the zone-wide share for a trip, creating it if needed.
    /// Zone-wide shares have the fixed record name CKRecordNameZoneWideShare.
    func share(for trip: Trip) async throws -> CKShare {
        let zoneID = CloudKitMapping.zoneID(forTripID: trip.id, owner: owner(for: trip.id))
        let database = sharedTripIDs.contains(trip.id)
            ? container.sharedCloudDatabase : container.privateCloudDatabase
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        if let existing = try? await database.record(for: shareID) as? CKShare {
            return existing
        }
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = trip.name
        share.publicPermission = .none
        let (saved, _) = try await database.modifyRecords(saving: [share], deleting: [])
        for result in saved.values {
            if case .success(let record) = result, let savedShare = record as? CKShare {
                return savedShare
            }
        }
        return share
    }

    var cloudKitContainer: CKContainer { container }

    /// Accept an incoming share invitation, then fetch the new shared zone.
    func acceptShare(metadata: CKShare.Metadata) async {
        do {
            try await container.accept(metadata)
            await fetchNow()
        } catch {
            status = .error(error.localizedDescription)
        }
    }
```

- [ ] **Step 2: Create `Planova/Sync/CloudSharingView.swift`:**

```swift
import SwiftUI
import CloudKit
import UIKit
import PlanovaKit

/// SwiftUI wrapper for UICloudSharingController, presented from the trip
/// detail's Share button once the CKShare exists.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func cloudSharingController(_ controller: UICloudSharingController, failedToSaveShareWithError error: Error) {}
        func itemTitle(for controller: UICloudSharingController) -> String? {
            controller.share?[CKShare.SystemFieldKey.title] as? String
        }
        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {}
        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {}
    }
}
```

- [ ] **Step 3: Share button in `TripDetailView`.** Replace the file body's `TabView { ... }` chain so the view becomes:

```swift
import SwiftUI
import CloudKit
import PlanovaKit

struct TripDetailView: View {
    @Environment(AppModel.self) private var model
    let tripID: UUID
    @State private var activeShare: CKShare?
    @State private var shareError: String?

    var body: some View {
        if let trip = model.store.trip(id: tripID) {
            TabView {
                PrepView(trip: trip)
                    .tabItem { Label("Prep", systemImage: "checklist") }
                ItineraryView(trip: trip)
                    .tabItem { Label("Itinerary", systemImage: "calendar") }
                PackingView(trip: trip)
                    .tabItem { Label("Packing", systemImage: "bag") }
            }
            .navigationTitle(trip.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button {
                    Task {
                        do { activeShare = try await model.sync.share(for: trip) }
                        catch { shareError = error.localizedDescription }
                    }
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                }
                .disabled(!model.sync.isAvailable)
                .accessibilityLabel("Share Trip")
            }
            .sheet(item: $activeShare) { share in
                CloudSharingView(share: share, container: model.sync.cloudKitContainer)
            }
            .alert("Sharing failed", isPresented: .constant(shareError != nil)) {
                Button("OK") { shareError = nil }
            } message: {
                Text(shareError ?? "")
            }
        } else {
            ContentUnavailableView("Trip not found", systemImage: "questionmark.circle")
        }
    }
}

extension CKShare: @retroactive Identifiable {
    public var id: CKRecord.ID { recordID }
}
```

And add the convenience to `SyncCoordinator`:

```swift
    var isAvailable: Bool {
        if case .unavailable = status { return false }
        return true
    }
```

(If `@retroactive` is rejected by the SDK's Swift version, use `extension CKShare: Identifiable` and silence the warning; record the adaptation.)

- [ ] **Step 4: Share acceptance via scene delegate.** Replace `Planova/App/PlanovaApp.swift` with:

```swift
import SwiftUI
import CloudKit
import UIKit

@main
struct PlanovaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            TripListView()
                .environment(model)
        }
    }

    init() {}
}

/// Routes CloudKit share-invitation acceptance into the sync coordinator.
/// SwiftUI apps receive userDidAcceptCloudKitShareWith via a scene delegate.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static weak var sharedModel: AppModel?

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        guard let model = AppDelegate.sharedModel else { return }
        Task { @MainActor in
            await model.sync.acceptShare(metadata: metadata)
        }
    }
}
```

And in `AppModel.init()`, add at the very end:

```swift
        AppDelegate.sharedModel = self
```

(`sharedModel` must be a `static weak var` typed `AppModel?`; AppModel is a class so this is fine.)

- [ ] **Step 5: Localization keys.** In `Planova/Resources/Localizable.xcstrings`, add inside `"strings"`:

```json
    "Share Trip" : { "localizations" : { "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "共享行程" } } } },
    "Sharing failed" : { "localizations" : { "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "共享失败" } } } },
    "OK" : { "localizations" : { "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "好" } } } },
```

- [ ] **Step 6: Build** — expect `** BUILD SUCCEEDED **`.
- [ ] **Step 7: Commit**

```bash
git add Planova && git commit -m "feat: add trip sharing via zone-wide CKShare and share acceptance"
```

---

### Task 9: Sync status UI

**Files:**
- Modify: `Planova/Features/TripList/TripListView.swift`, `Planova/Resources/Localizable.xcstrings`

- [ ] **Step 1: Status footer.** In `TripListView`, wrap the `List` content so the list gains a footer section. Replace the `List { ... }` block with:

```swift
            List {
                Section {
                    ForEach(model.store.trips) { trip in
                        NavigationLink(value: trip.id) {
                            TripRowView(trip: trip)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            model.deleteTrip(id: model.store.trips[index].id)
                        }
                    }
                } footer: {
                    syncStatusFooter
                }
            }
            .refreshable { await model.sync.fetchNow() }
```

And add to `TripListView`:

```swift
    @ViewBuilder
    private var syncStatusFooter: some View {
        switch model.sync.status {
        case .unavailable(let reason):
            Label(reason, systemImage: "icloud.slash")
        case .idle:
            Label("Synced with iCloud", systemImage: "icloud")
        case .syncing:
            Label("Syncing…", systemImage: "arrow.triangle.2.circlepath.icloud")
        case .error(let message):
            Label(message, systemImage: "exclamationmark.icloud")
        }
    }
```

- [ ] **Step 2: Localization keys** (same pattern as Task 8 step 5):

```json
    "Synced with iCloud" : { "localizations" : { "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "已与 iCloud 同步" } } } },
    "Syncing…" : { "localizations" : { "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "正在同步…" } } } },
    "Sign in to iCloud to sync" : { "localizations" : { "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "登录 iCloud 以同步" } } } },
    "iCloud is restricted" : { "localizations" : { "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "iCloud 受限" } } } },
    "iCloud temporarily unavailable" : { "localizations" : { "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "iCloud 暂时不可用" } } } },
    "iCloud unavailable" : { "localizations" : { "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "iCloud 不可用" } } } },
```

Validate: `python3 -c "import json; json.load(open('Planova/Resources/Localizable.xcstrings'))" && echo JSON OK`

- [ ] **Step 3: Build + UI smoke test** — both must pass (footer shows "Sign in to iCloud to sync" in the simulator; the smoke test doesn't assert footers).
- [ ] **Step 4: Commit**

```bash
git add Planova && git commit -m "feat: add sync status footer and pull-to-refresh"
```

---

### Task 10: Final verification (automated + USER ACTIONS)

**Files:** none — verification only.

- [ ] **Step 1: Full automated gate**

```bash
cd PlanovaKit && make test && cd ..
xcodegen generate
xcodebuild -project Planova.xcodeproj -scheme Planova -destination 'generic/platform=iOS Simulator' clean build
xcodebuild test -project Planova.xcodeproj -scheme Planova -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PlanovaUITests
```
Expected: 29 package tests pass; BUILD SUCCEEDED; TEST SUCCEEDED.

- [ ] **Step 2: USER ACTIONS (cannot be automated — present this checklist to the user)**

1. Copy `Signing.xcconfig.example` → `Signing.xcconfig` and set `DEVELOPMENT_TEAM` to your Team ID.
2. Open `Planova.xcodeproj` in Xcode once → select the Planova target → Signing & Capabilities → confirm the team is set and the `iCloud.com.planova.Planova` container shows without errors (Xcode creates the container in your developer account on first build).
3. In the simulator (or your iPhone): Settings → sign in with your Apple ID (iCloud).
4. Run the app; the trip list footer should change from "Sign in to iCloud to sync" to "Synced with iCloud". Toggle an item; open CloudKit Console (icloud.developer.apple.com) → your container → Records to confirm data arrives.
5. Two-account share test: run the app on a second device/simulator signed into a family member's Apple ID; on device 1 tap the share button in the trip → invite; accept the link on device 2; check items on both sides and pull-to-refresh — checkmarks must flow both ways.

- [ ] **Step 3: Tag**

```bash
git tag v0.2.0-sync
```

---

## Known deviations from spec (accepted)

- Record type for the trip record is `TripMeta` (spec said `Trip`) to avoid confusion with the model type; field-for-field identical intent.
- When an owner stops sharing, CloudKit deletes the shared zone for participants and this plan's fetch path removes the trip from the participant's device. The spec preferred retaining a local copy; surfacing a "keep a copy?" flow is deferred to Plan 3 polish.

## Out of scope (Plan 3)

MapKit place attachment + day maps, app icon, TestFlight signing/upload, production APNs environment, keep-local-copy on share revocation.
