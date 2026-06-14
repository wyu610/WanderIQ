# WanderIQ v2 — Sub-project 3c: App Cutover (Supabase sync, retire CloudKit) Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the CloudKit sync with the Supabase sync engine end-to-end: persist the outbox + cursor/tombstones, capture local edits via `TripDiff`, push/pull (with Realtime) through `SupabaseRemoteSyncBackend` for the signed-in user, and remove all CloudKit code.

**Architecture:** A new `SupabaseSyncCoordinator` (app target, `@MainActor @Observable`) mirrors the old coordinator's lifecycle but uses sub-project 2's pure engine: it keeps `lastKnown` trip snapshots, turns each local mutation into outbox entries via `TripDiff` → `SyncEngine.captureUpsert/captureDelete`, persists the `Outbox`+`SyncState` through a new `SyncStore` (JSON files, like `TripRepository`), debounce-pushes through `SupabaseRemoteSyncBackend`, and pulls on start/foreground/Realtime applying via `SyncEngine.applyPull`. Sync only runs when authenticated. The CloudKit `SyncCoordinator`, `CloudSharingView`, the trip-detail share button, the CloudKit entitlements, and the share-acceptance scene routing are all removed. Per-trip email-invite sharing returns in sub-project 5.

**Tech Stack:** WanderIQKit (pure stores/capture, TDD), supabase-swift (Realtime), SwiftUI, XcodeGen.

**Spec:** design §6 (sync), §8.1 (iOS client: replace SyncCoordinator, remove CloudKit), §11 (CloudKit retired). Builds on 3a (transport) + 3b (auth).

**Merge policy:** This sub-project removes working CloudKit sync. Its logic is unit-tested and the app is build-verified, but **DO NOT merge to main until the user verifies real two-device sync after signing in** (Task 6). Until then it lives on `feature/v2-sp3c-app-cutover`.

**Verification:** package `cd WanderIQKit && make test` (67 baseline + new store/capture tests); app build `xcodegen generate && xcodebuild ... build`; runtime end-to-end deferred to Task 6 (user, authenticated, two devices).

---

### Task 1: `SyncStore` — persist Outbox + SyncState (WanderIQKit, TDD)

**Files:**
- Create: `WanderIQKit/Sources/WanderIQKit/Sync/SyncStore.swift`
- Test: `WanderIQKit/Tests/WanderIQKitTests/SyncStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Create `WanderIQKit/Tests/WanderIQKitTests/SyncStoreTests.swift`:
```swift
import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SyncStoreTests {
    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @Test func savesAndLoadsOutboxAndState() throws {
        let store = SyncStore(directory: tempDir())
        var box = Outbox()
        box.enqueue(PendingChange(kind: .item, id: UUID(), tripID: UUID(),
                                  op: .upsert, modifiedAt: Date(timeIntervalSince1970: 3)))
        var state = SyncState(); state.cursor = Date(timeIntervalSince1970: 9)
        try store.save(outbox: box, state: state)

        let loaded = store.load()
        #expect(loaded.outbox.pending.count == 1)
        #expect(loaded.state.cursor == Date(timeIntervalSince1970: 9))
    }

    @Test func loadReturnsEmptyDefaultsWhenAbsent() {
        let loaded = SyncStore(directory: tempDir()).load()
        #expect(loaded.outbox.isEmpty)
        #expect(loaded.state.cursor == .distantPast)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd WanderIQKit && make test`
Expected: FAIL — `cannot find 'SyncStore' in scope`.

- [ ] **Step 3: Write the store**

Create `WanderIQKit/Sources/WanderIQKit/Sync/SyncStore.swift`:
```swift
import Foundation

/// Persists the Outbox and SyncState as two JSON files in `directory`
/// (mirrors TripRepository's approach). Family-scale data; no SQLite needed.
public struct SyncStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    private var outboxURL: URL { directory.appendingPathComponent("outbox.json") }
    private var stateURL: URL { directory.appendingPathComponent("sync-state.json") }

    private var encoder: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }
    private var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    public func load() -> (outbox: Outbox, state: SyncState) {
        let outbox = (try? Data(contentsOf: outboxURL))
            .flatMap { try? decoder.decode(Outbox.self, from: $0) } ?? Outbox()
        let state = (try? Data(contentsOf: stateURL))
            .flatMap { try? decoder.decode(SyncState.self, from: $0) } ?? SyncState()
        return (outbox, state)
    }

    public func save(outbox: Outbox, state: SyncState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(outbox).write(to: outboxURL, options: .atomic)
        try encoder.encode(state).write(to: stateURL, options: .atomic)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd WanderIQKit && make test`
Expected: PASS (2 new + 67 prior = 69).

- [ ] **Step 5: Commit**

```bash
git add WanderIQKit/Sources/WanderIQKit/Sync/SyncStore.swift WanderIQKit/Tests/WanderIQKitTests/SyncStoreTests.swift
git commit -m "feat(sync): persist outbox + sync state as JSON"
```

---

### Task 2: `SyncEngine.capture(old:new:into:state:now:)` from a trip diff (WanderIQKit, TDD)

**Files:**
- Modify: `WanderIQKit/Sources/WanderIQKit/Sync/SyncEngine.swift`
- Test: `WanderIQKit/Tests/WanderIQKitTests/SyncEngineDiffCaptureTests.swift`

Turns a before/after trip snapshot into outbox entries using the existing
`TripDiff`. `.tripMeta` → kind `.trip`; `.day`/`.item` → their kinds. Saves use
the entity's `modifiedAt`; deletes use `now`.

- [ ] **Step 1: Write the failing test**

Create `WanderIQKit/Tests/WanderIQKitTests/SyncEngineDiffCaptureTests.swift`:
```swift
import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SyncEngineDiffCaptureTests {
    let tripID = UUID()

    private func trip(name: String, items: [ChecklistItem] = [], at: Date) -> Trip {
        Trip(id: tripID, name: name, startDate: Date(timeIntervalSince1970: 0),
             endDate: Date(timeIntervalSince1970: 0), items: items, modifiedAt: at)
    }

    @Test func newTripCapturesTripAndItemUpserts() {
        var box = Outbox(); var state = SyncState()
        let item = ChecklistItem(id: UUID(), kind: .prep, label: "X",
                                 modifiedAt: Date(timeIntervalSince1970: 5))
        let new = trip(name: "China", items: [item], at: Date(timeIntervalSince1970: 5))
        SyncEngine.capture(old: nil, new: new, into: &box, state: &state,
                           now: Date(timeIntervalSince1970: 5))
        let kinds = Set(box.pending.map(\.kind))
        #expect(kinds == [.trip, .item])
        #expect(box.pending.allSatisfy { $0.op == .upsert })
    }

    @Test func deletedItemCapturesDeleteAndTombstone() {
        var box = Outbox(); var state = SyncState()
        let item = ChecklistItem(id: UUID(), kind: .prep, label: "X",
                                 modifiedAt: Date(timeIntervalSince1970: 5))
        let old = trip(name: "China", items: [item], at: Date(timeIntervalSince1970: 5))
        let new = trip(name: "China", items: [], at: Date(timeIntervalSince1970: 5))
        SyncEngine.capture(old: old, new: new, into: &box, state: &state,
                           now: Date(timeIntervalSince1970: 7))
        #expect(box.pending.contains { $0.kind == .item && $0.op == .delete })
        #expect(state.tombstones[item.id] == Date(timeIntervalSince1970: 7))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd WanderIQKit && make test`
Expected: FAIL — `type 'SyncEngine' has no member 'capture'`.

- [ ] **Step 3: Add `capture` to `SyncEngine`**

Append inside the `public enum SyncEngine { ... }` body in
`WanderIQKit/Sources/WanderIQKit/Sync/SyncEngine.swift`:
```swift

    // MARK: - Capture from a trip diff (push side)

    /// Diff `old`→`new` and enqueue the resulting upserts/deletes. Saves carry
    /// the entity's own modifiedAt; deletes carry `now` as the deletion time.
    public static func capture(old: Trip?, new: Trip, into outbox: inout Outbox,
                               state: inout SyncState, now: Date) {
        let diff = TripDiff.changes(old: old, new: new)
        for ref in diff.saves {
            switch ref {
            case .tripMeta:
                captureUpsert(kind: .trip, id: new.id, tripID: new.id,
                              modifiedAt: new.modifiedAt ?? now, into: &outbox)
            case .day(let id):
                let at = new.days.first { $0.id == id }?.modifiedAt ?? now
                captureUpsert(kind: .day, id: id, tripID: new.id, modifiedAt: at, into: &outbox)
            case .item(let id):
                let at = new.items.first { $0.id == id }?.modifiedAt ?? now
                captureUpsert(kind: .item, id: id, tripID: new.id, modifiedAt: at, into: &outbox)
            }
        }
        for ref in diff.deletes {
            switch ref {
            case .tripMeta:
                captureDelete(kind: .trip, id: new.id, tripID: new.id,
                              deletedAt: now, into: &outbox, state: &state)
            case .day(let id):
                captureDelete(kind: .day, id: id, tripID: new.id,
                              deletedAt: now, into: &outbox, state: &state)
            case .item(let id):
                captureDelete(kind: .item, id: id, tripID: new.id,
                              deletedAt: now, into: &outbox, state: &state)
            }
        }
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd WanderIQKit && make test`
Expected: PASS (2 new + 69 = 71).

- [ ] **Step 5: Commit**

```bash
git add WanderIQKit/Sources/WanderIQKit/Sync/SyncEngine.swift WanderIQKit/Tests/WanderIQKitTests/SyncEngineDiffCaptureTests.swift
git commit -m "feat(sync): capture outbox entries from a trip diff"
```

---

### Task 3: SupabaseSyncCoordinator (app target)

**Files:**
- Create: `WanderIQ/Sync/SupabaseSyncCoordinator.swift`

The integration shell. Build-verified here; runtime exercised in Task 6.

- [ ] **Step 1: Write the coordinator**

Create `WanderIQ/Sync/SupabaseSyncCoordinator.swift`:
```swift
import Foundation
import Supabase
import Observation
import WanderIQKit

/// Drives Supabase sync for the signed-in user using the pure SyncEngine.
/// Captures local edits into a persisted outbox (debounced push) and applies
/// pulled changes to the TripStore. No-ops when signed out.
@MainActor
@Observable
final class SupabaseSyncCoordinator {
    enum Status: Equatable { case idle, syncing, error(String) }
    private(set) var status: Status = .idle

    @ObservationIgnored private let store: TripStore
    @ObservationIgnored private let backend: RemoteSyncBackend
    @ObservationIgnored private let syncStore: SyncStore
    @ObservationIgnored private let client = AppSupabase.client

    @ObservationIgnored private var outbox: Outbox
    @ObservationIgnored private var state: SyncState
    @ObservationIgnored private var lastKnown: [UUID: Trip] = [:]
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var realtime: Task<Void, Never>?

    init(store: TripStore, stateDirectory: URL,
         backend: RemoteSyncBackend = SupabaseRemoteSyncBackend()) {
        self.store = store
        self.backend = backend
        self.syncStore = SyncStore(directory: stateDirectory)
        let loaded = syncStore.load()
        self.outbox = loaded.outbox
        self.state = loaded.state
        self.lastKnown = Dictionary(uniqueKeysWithValues: store.trips.map { ($0.id, $0) })
    }

    private var isAuthed: Bool { (try? client.auth.session) != nil }

    /// Called after sign-in (and on launch if already signed in).
    func start() async {
        guard isAuthed else { return }
        await fetchNow()
        subscribeRealtime()
    }

    /// Capture a local mutation into the outbox and schedule a push.
    func noteLocalChange(_ trip: Trip) {
        SyncEngine.capture(old: lastKnown[trip.id], new: trip,
                           into: &outbox, state: &state, now: Date())
        lastKnown[trip.id] = trip
        persist()
        schedulePush()
    }

    func noteLocalDelete(tripID: UUID) {
        // Tombstone the trip; peers remove it (and its children) on pull.
        SyncEngine.captureDelete(kind: .trip, id: tripID, tripID: tripID,
                                 deletedAt: Date(), into: &outbox, state: &state)
        lastKnown[tripID] = nil
        persist()
        schedulePush()
    }

    /// Manual/foreground pull.
    func fetchNow() async {
        guard isAuthed else { return }
        status = .syncing
        do {
            let page = try await backend.changes(since: state.cursor)
            SyncEngine.applyPull(page.records, cursor: page.cursor, store: store, state: &state)
            lastKnown = Dictionary(uniqueKeysWithValues: store.trips.map { ($0.id, $0) })
            persist()
            status = .idle
        } catch { status = .error(error.localizedDescription) }
    }

    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, self.isAuthed else { return }
            do {
                try await SyncEngine.push(outbox: &self.outbox, store: self.store,
                                          backend: self.backend)
                self.persist()
            } catch { self.status = .error(error.localizedDescription) }
        }
    }

    private func subscribeRealtime() {
        realtime?.cancel()
        realtime = Task { [weak self] in
            guard let self else { return }
            let channel = self.client.realtimeV2.channel("wanderiq-sync")
            let changes = channel.postgresChange(AnyAction.self, schema: "public")
            await channel.subscribe()
            for await _ in changes {
                await self.fetchNow()
            }
        }
    }

    private func persist() { try? syncStore.save(outbox: outbox, state: state) }

    func stop() {
        pushTask?.cancel(); realtime?.cancel()
    }
}
```

- [ ] **Step 2: Regenerate and build**

```bash
cd /Users/wyu610/_Dev/WanderIQ
xcodegen generate
xcodebuild -project WanderIQ.xcodeproj -scheme WanderIQ -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'BUILD (SUCCEEDED|FAILED)|error:' | head -10
```
Expected: `** BUILD SUCCEEDED **`. The Realtime API (`realtimeV2.channel`, `postgresChange(AnyAction.self, schema:)`, `channel.subscribe()`) is from supabase-swift; if any symbol errors, report it VERBATIM (BLOCKED) — the Realtime surface is the least-certain API in this plan and may need adjustment to the installed version.

- [ ] **Step 3: Commit**

```bash
git add WanderIQ/Sync/SupabaseSyncCoordinator.swift
git commit -m "feat(ios): SupabaseSyncCoordinator (capture/push/pull/realtime)"
```

---

### Task 4: Rewire AppModel to the Supabase coordinator

**Files:**
- Modify: `WanderIQ/App/AppModel.swift`
- Modify: `WanderIQ/App/WanderIQApp.swift`

- [ ] **Step 1: Swap the coordinator in AppModel**

In `WanderIQ/App/AppModel.swift`:
- Change the property `let sync: SyncCoordinator` to `let sync: SupabaseSyncCoordinator`.
- In `init()`, replace the `SyncCoordinator(store:stateDirectory:)` construction with
  `SupabaseSyncCoordinator(store: store, stateDirectory: URL.applicationSupportDirectory.appendingPathComponent("sync"))`.
- Remove the CloudKit share-acceptance block in `init()`:
  ```swift
        AppDelegate.sharedModel = self
        if let pending = AppDelegate.pendingShareMetadata {
            AppDelegate.pendingShareMetadata = nil
            Task { await sync.acceptShare(metadata: pending) }
        }
  ```
  (Delete it — share acceptance returns with email invites in sub-project 5.)
- In `deleteTrip(id:)`, the existing `sync.noteLocalDelete(tripID: id)` call stays
  (the new coordinator has the same method name).
- The `store.onChange` hook stays calling `self?.sync.noteLocalChange(trip)`.
- Keep `Task { await sync.start() }`.

- [ ] **Step 2: Start sync on sign-in**

In `WanderIQ/App/WanderIQApp.swift`, the `.signedIn` case currently shows
`TripListView().environment(model)`. Add a `.task` that starts sync once signed
in:
```swift
                case .signedIn:
                    TripListView()
                        .environment(model)
                        .task { await model.sync.start() }
```

- [ ] **Step 3: Regenerate and build**

```bash
cd /Users/wyu610/_Dev/WanderIQ
xcodegen generate
xcodebuild -project WanderIQ.xcodeproj -scheme WanderIQ -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'BUILD (SUCCEEDED|FAILED)|error:' | head -10
```
Expected: this will FAIL to compile until Task 5 removes the CloudKit code that
references the old `SyncCoordinator` (e.g. `CloudSharingView`, the share button,
`sync.share`, `sync.acceptShare`). That is expected — Tasks 4 and 5 land
together. Proceed to Task 5, then build.

- [ ] **Step 4: (Build + commit happen at the end of Task 5)**

---

### Task 5: Remove CloudKit

**Files:**
- Delete: `WanderIQ/Sync/SyncCoordinator.swift`
- Delete: `WanderIQ/Sync/CloudSharingView.swift`
- Modify: `WanderIQ/Features/TripDetail/TripDetailView.swift`
- Modify: `WanderIQ/Features/TripList/TripListView.swift`
- Modify: `WanderIQ/App/WanderIQApp.swift`
- Modify: `project.yml`

- [ ] **Step 1: Delete the CloudKit files**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git rm WanderIQ/Sync/SyncCoordinator.swift WanderIQ/Sync/CloudSharingView.swift
```

- [ ] **Step 2: Remove the share UI from TripDetailView**

In `WanderIQ/Features/TripDetail/TripDetailView.swift`: remove `import CloudKit`,
the `@State private var activeShare: CKShare?` and `shareError` state, the
`.toolbar { ... share button ... }`, the `.sheet(item: $activeShare) { ... CloudSharingView ... }`,
the `.alert("Sharing failed", ...)`, and the bottom `extension CKShare: @retroactive Identifiable`.
Leave the `TabView` with the three tabs and `.navigationTitle` intact. The view
should reduce to: `if let trip = model.store.trip(id: tripID) { TabView { … three tabs … }.navigationTitle(trip.name).navigationBarTitleDisplayMode(.inline) } else { ContentUnavailableView(...) }`.

- [ ] **Step 3: Remove CloudKit from the app entry + scene delegate**

In `WanderIQ/App/WanderIQApp.swift`: remove `import CloudKit`; delete the
`SceneDelegate` class entirely and the `AppDelegate.configurationForConnecting`
method that returns it; reduce `AppDelegate` to just `static weak var sharedModel: AppModel?`
removal if unused (keep `AppDelegate` only if `@UIApplicationDelegateAdaptor`
needs it — if nothing else uses AppDelegate, remove the adaptor too). Verify no
remaining `CKShare`/`CloudKit` references: `grep -rn CloudKit WanderIQ/ || echo clean`.

- [ ] **Step 3b: Update TripListView's sync-status footer to the new Status**

`WanderIQ/Features/TripList/TripListView.swift` currently switches `model.sync.status`
over `.unavailable`/`.idle`/`.syncing`/`.error` with iCloud wording. The new
coordinator's `Status` has no `.unavailable` (the auth gate covers signed-out).
Replace the `syncStatusFooter` computed property with:
```swift
    @ViewBuilder
    private var syncStatusFooter: some View {
        switch model.sync.status {
        case .idle:
            Label("Synced", systemImage: "checkmark.circle")
        case .syncing:
            Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
        }
    }
```
Leave `.refreshable { await model.sync.fetchNow() }` unchanged (the new
coordinator has `fetchNow()`).

- [ ] **Step 4: Remove the CloudKit entitlements**

In `project.yml`, under the `WanderIQ` target `entitlements.properties`, remove
these two CloudKit keys (keep `aps-environment` and `applesignin`):
```yaml
        com.apple.developer.icloud-container-identifiers: [iCloud.com.wanderiq.WanderIQ]
        com.apple.developer.icloud-services: [CloudKit]
```

- [ ] **Step 5: Regenerate, build, verify no CloudKit remains**

```bash
cd /Users/wyu610/_Dev/WanderIQ
grep -rn "CloudKit\|CKShare\|CKRecord" WanderIQ/ || echo "no CloudKit refs in app"
xcodegen generate
xcodebuild -project WanderIQ.xcodeproj -scheme WanderIQ -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'BUILD (SUCCEEDED|FAILED)|error:' | head -10
cd WanderIQKit && make test 2>&1 | tail -1
```
Expected: no CloudKit refs in app; `** BUILD SUCCEEDED **`; package tests still pass (71).
(Note: `WanderIQKit/Sources/WanderIQKit/CloudKitMapping.swift` and its tests can
remain as dead-but-harmless code, or be removed in a follow-up; leaving them does
not affect the app. Do NOT delete them in this task to keep the diff focused.)

- [ ] **Step 6: Commit Tasks 4 + 5 together**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add WanderIQ/App/AppModel.swift WanderIQ/App/WanderIQApp.swift WanderIQ/Features/TripDetail/TripDetailView.swift WanderIQ/Features/TripList/TripListView.swift project.yml WanderIQ.entitlements WanderIQ/Info.plist
git commit -m "feat(ios): cut over AppModel to Supabase sync and remove CloudKit"
```

---

### Task 6: End-to-end verification (USER — authenticated, two devices)

**Files:** none

- [ ] **Step 1: Sign in on device A, create/edit a trip**

With "Confirm email" off (or via a confirmed account), build to a device/sim,
sign in, toggle a checklist item or add an item.

- [ ] **Step 2: Confirm it reached the server**

```bash
cd /Users/wyu610/_Dev/WanderIQ
source .env
/opt/homebrew/opt/libpq/bin/psql "$SUPABASE_DB_URL" -tAc "select count(*) from trip_items where is_done = true;"
```
Expected: reflects the toggle (push worked).

- [ ] **Step 3: Sign in as the same user on device B**

Confirm the trip and the edit appear (pull worked), and that a further edit on B
shows up on A within a few seconds (Realtime → pull). This is the true
offline-first multi-device proof.

- [ ] **Step 4: Merge to main**

Once Steps 1–3 pass, merge `feature/v2-sp3c-app-cutover` to main.

---

## Done criteria

- Package tests pass (71): SyncStore + diff-capture covered.
- App builds with zero CloudKit references; sync runs through Supabase for the
  signed-in user; signed-out is a no-op.
- Two-device sync verified by the user (Task 6) BEFORE merge.
- Next: **sub-project 4 — PWA rebuild** (the web/Android client on the same
  backend + protocol), then 5 (sharing), 6 (import/export).

## Risks / notes

- **Realtime API (Task 3)** is the least-certain surface; `realtimeV2`/
  `postgresChange` may differ in the installed supabase-swift — adjust to the
  compiler, keeping the behavior "any change → fetchNow()". Realtime is an
  optimization; cursor pull on foreground is the correctness path.
- Deleting a trip tombstones only the trip row; orphaned day/item rows remain
  server-side (harmless, inaccessible). A cascade tombstone can be added later.
- `CloudKitMapping` + its tests stay in WanderIQKit as dead code; remove in a
  later cleanup to keep this diff focused on the app cutover.
