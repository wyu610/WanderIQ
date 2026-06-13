# WanderIQ v2 — Sync Protocol + iOS Sync Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure, network-free offline-sync engine for WanderIQ v2 in `WanderIQKit` — outbox, tombstones, last-writer-wins conflict resolution, and a pull cursor — behind a `RemoteSyncBackend` protocol, validated by a cross-engine conformance suite, with zero new dependencies.

**Architecture:** Mirrors v1's split: pure testable logic lives in `WanderIQKit` (like `CloudKitMapping`), the impure transport lives in the app (next sub-project). The engine operates on an injected `RemoteSyncBackend` (faked in tests) and an injected persistence pair (in-memory in tests, JSON-file in the app). Conflicts resolve by whole-record last-writer-wins on `modifiedAt`; deletes are tombstones carrying `deletedAt`. The conformance suite is a declarative scenario list that the Swift engine runs now and a future TypeScript engine will run identically.

**Tech Stack:** Swift 5.10, `WanderIQKit` Swift package, Swift Testing (`import Testing`), Foundation only. No `supabase-swift`, no network — that arrives in sub-project 3.

**Spec:** `docs/superpowers/specs/2026-06-13-wanderiq-v2-design.md` §6 (sync protocol), §10 (cross-engine conformance suite). The normative protocol is extracted to its own doc in Task 1.

**Scope boundary:** This sub-project produces the engine + protocol abstraction + conformance suite, all unit-tested. The `supabase-swift` implementation of `RemoteSyncBackend` (real PostgREST push/pull + Realtime + auth) and wiring into `AppModel` is sub-project 3.

**Verification:** `cd WanderIQKit && make test` (baseline today: 36 tests, all passing — do not regress).

---

### Task 1: Extract the sync protocol contract doc

**Files:**
- Create: `docs/superpowers/specs/2026-06-13-wanderiq-v2-sync-protocol.md`

- [ ] **Step 1: Write the normative contract**

Create `docs/superpowers/specs/2026-06-13-wanderiq-v2-sync-protocol.md` with this content:

```markdown
# WanderIQ v2 Sync Protocol (normative)

Both the Swift engine (this sub-project) and the future TypeScript engine
implement this contract. The conformance suite (`sync-conformance.json`)
encodes its rules as executable scenarios.

## Entities
Three syncable entity kinds: `trip`, `day`, `item`. Each has a UUID `id`, a
`tripID` (a trip's tripID is its own id), and a `modifiedAt` (client edit
clock, UTC).

## Records
A remote record is `{ kind, id, tripID, modifiedAt, deleted, fields }`.
`deleted = true` marks a tombstone. `fields` is the entity payload (absent for
tombstones).

## Outbox (push)
- Every local create/update enqueues an upsert entry; every local delete
  enqueues a delete entry. Entries are keyed by `(kind, id)`; a newer entry
  for the same key replaces the older (coalescing).
- An upsert entry references the entity; the payload is read from the local
  store at push time (latest state). A delete entry carries `deletedAt`
  (= the deletion's `modifiedAt`).
- On push, entries flush oldest-first; each acknowledged entry is removed.

## Tombstones
- A local delete records `tombstones[id] = deletedAt` and removes the entity
  from the store.
- Tombstones are retained until a pull cursor advances past them (the delete
  has round-tripped), then may be pruned.

## Pull + conflict resolution
For each incoming remote record R against local state L:
- If R.deleted:
  - If L exists and `L.modifiedAt > R.modifiedAt` → keep L (local edit wins).
  - Else → remove L, set `tombstones[R.id] = R.modifiedAt`.
- Else (R is an upsert):
  - If a tombstone T exists for R.id and `T >= R.modifiedAt` → ignore R
    (local delete wins; entity stays deleted).
  - Else if L exists and `L.modifiedAt >= R.modifiedAt` → keep L.
  - Else → apply R (insert or overwrite L), clear any tombstone for R.id.
- Ties (`==`) resolve to the LOCAL value (no spurious overwrite).

## Cursor
- The client stores `lastPulledAt`. A pull fetches records with
  `server_updated_at > lastPulledAt`, then advances `lastPulledAt` to the max
  `server_updated_at` seen. `server_updated_at` is server-stamped and used
  ONLY for the cursor, never for conflict resolution.

## Realtime
- A Realtime change event triggers a targeted pull. Realtime is an
  optimization; the cursor pull is authoritative, so a missed event
  self-heals on the next pull.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-06-13-wanderiq-v2-sync-protocol.md
git commit -m "docs: normative v2 sync protocol contract"
```

---

### Task 2: Sync value types (`SyncRecord`, `EntityKind`, `PendingChange`)

**Files:**
- Create: `WanderIQKit/Sources/WanderIQKit/Sync/SyncTypes.swift`
- Test: `WanderIQKit/Tests/WanderIQKitTests/SyncTypesTests.swift`

- [ ] **Step 1: Write the failing test**

Create `WanderIQKit/Tests/WanderIQKitTests/SyncTypesTests.swift`:
```swift
import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SyncTypesTests {

    @Test func pendingChangeKeyIgnoresOpAndTime() {
        let id = UUID()
        let a = PendingChange(kind: .item, id: id, tripID: UUID(), op: .upsert,
                              modifiedAt: Date(timeIntervalSince1970: 1))
        let b = PendingChange(kind: .item, id: id, tripID: UUID(), op: .delete,
                              modifiedAt: Date(timeIntervalSince1970: 2))
        #expect(a.key == b.key)              // same (kind, id) → same coalescing key
    }

    @Test func differentKindSameIdAreDistinctKeys() {
        let id = UUID()
        let day  = PendingChange(kind: .day,  id: id, tripID: UUID(), op: .upsert, modifiedAt: .now)
        let item = PendingChange(kind: .item, id: id, tripID: UUID(), op: .upsert, modifiedAt: .now)
        #expect(day.key != item.key)
    }

    @Test func syncRecordRoundTripsThroughCodable() throws {
        let rec = SyncRecord(kind: .trip, id: UUID(), tripID: UUID(),
                             modifiedAt: Date(timeIntervalSince1970: 100),
                             deleted: false, fields: ["name": "HK"])
        let data = try JSONEncoder().encode(rec)
        let back = try JSONDecoder().decode(SyncRecord.self, from: data)
        #expect(back == rec)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd WanderIQKit && make test`
Expected: FAIL — `cannot find 'PendingChange' in scope`.

- [ ] **Step 3: Write the types**

Create `WanderIQKit/Sources/WanderIQKit/Sync/SyncTypes.swift`:
```swift
import Foundation

public enum EntityKind: String, Codable, Sendable, CaseIterable {
    case trip, day, item
}

public enum SyncOp: String, Codable, Sendable {
    case upsert, delete
}

/// Stable coalescing key: one pending change per (kind, id).
public struct EntityKey: Hashable, Codable, Sendable {
    public let kind: EntityKind
    public let id: UUID
    public init(kind: EntityKind, id: UUID) { self.kind = kind; self.id = id }
}

/// An outbox entry. Payload is read from the store at push time, so the entry
/// only needs to reference the entity and carry the relevant timestamp.
public struct PendingChange: Equatable, Codable, Sendable {
    public let kind: EntityKind
    public let id: UUID
    public let tripID: UUID
    public let op: SyncOp
    public let modifiedAt: Date

    public init(kind: EntityKind, id: UUID, tripID: UUID, op: SyncOp, modifiedAt: Date) {
        self.kind = kind; self.id = id; self.tripID = tripID
        self.op = op; self.modifiedAt = modifiedAt
    }
    public var key: EntityKey { EntityKey(kind: kind, id: id) }
}

/// A remote record as exchanged with the backend. `fields` carries the entity
/// payload for upserts; nil/ignored for tombstones. Kept JSON-shaped so the
/// same record format serves the conformance suite and the TS engine.
public struct SyncRecord: Equatable, Codable, Sendable {
    public let kind: EntityKind
    public let id: UUID
    public let tripID: UUID
    public let modifiedAt: Date
    public let deleted: Bool
    public let fields: [String: String]?

    public init(kind: EntityKind, id: UUID, tripID: UUID, modifiedAt: Date,
                deleted: Bool, fields: [String: String]? = nil) {
        self.kind = kind; self.id = id; self.tripID = tripID
        self.modifiedAt = modifiedAt; self.deleted = deleted; self.fields = fields
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd WanderIQKit && make test`
Expected: PASS (new SyncTypesTests green; 36 baseline still green).

- [ ] **Step 5: Commit**

```bash
git add WanderIQKit/Sources/WanderIQKit/Sync/SyncTypes.swift WanderIQKit/Tests/WanderIQKitTests/SyncTypesTests.swift
git commit -m "feat(sync): core sync value types"
```

---

### Task 3: Conflict resolver (pure decision function)

**Files:**
- Create: `WanderIQKit/Sources/WanderIQKit/Sync/ConflictResolver.swift`
- Test: `WanderIQKit/Tests/WanderIQKitTests/ConflictResolverTests.swift`

- [ ] **Step 1: Write the failing test**

Create `WanderIQKit/Tests/WanderIQKitTests/ConflictResolverTests.swift`:
```swift
import Testing
import Foundation
@testable import WanderIQKit

@Suite struct ConflictResolverTests {
    let t1 = Date(timeIntervalSince1970: 1)
    let t2 = Date(timeIntervalSince1970: 2)
    let t3 = Date(timeIntervalSince1970: 3)

    @Test func remoteUpsertNewerThanLocalApplies() {
        #expect(ConflictResolver.resolve(localModifiedAt: t1, tombstone: nil,
                                         remoteModifiedAt: t2, remoteDeleted: false) == .applyRemote)
    }
    @Test func remoteUpsertOlderThanLocalKept() {
        #expect(ConflictResolver.resolve(localModifiedAt: t2, tombstone: nil,
                                         remoteModifiedAt: t1, remoteDeleted: false) == .keepLocal)
    }
    @Test func tieKeepsLocal() {
        #expect(ConflictResolver.resolve(localModifiedAt: t2, tombstone: nil,
                                         remoteModifiedAt: t2, remoteDeleted: false) == .keepLocal)
    }
    @Test func remoteDeleteNewerThanLocalEditApplies() {
        #expect(ConflictResolver.resolve(localModifiedAt: t1, tombstone: nil,
                                         remoteModifiedAt: t2, remoteDeleted: true) == .applyRemote)
    }
    @Test func localEditNewerThanRemoteDeleteKept() {
        #expect(ConflictResolver.resolve(localModifiedAt: t3, tombstone: nil,
                                         remoteModifiedAt: t2, remoteDeleted: true) == .keepLocal)
    }
    @Test func localTombstoneAtOrAfterRemoteUpsertIgnoresRemote() {
        // Local delete at t2 vs remote upsert at t2 → stays deleted.
        #expect(ConflictResolver.resolve(localModifiedAt: nil, tombstone: t2,
                                         remoteModifiedAt: t2, remoteDeleted: false) == .keepLocal)
    }
    @Test func remoteUpsertNewerThanLocalTombstoneResurrects() {
        #expect(ConflictResolver.resolve(localModifiedAt: nil, tombstone: t1,
                                         remoteModifiedAt: t2, remoteDeleted: false) == .applyRemote)
    }
    @Test func remoteUpsertForUnknownEntityApplies() {
        #expect(ConflictResolver.resolve(localModifiedAt: nil, tombstone: nil,
                                         remoteModifiedAt: t1, remoteDeleted: false) == .applyRemote)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd WanderIQKit && make test`
Expected: FAIL — `cannot find 'ConflictResolver' in scope`.

- [ ] **Step 3: Write the resolver**

Create `WanderIQKit/Sources/WanderIQKit/Sync/ConflictResolver.swift`:
```swift
import Foundation

/// Pure whole-record last-writer-wins resolution (spec §6.4). Decides what a
/// pull should do with one incoming remote record given local knowledge.
public enum ConflictResolver {
    public enum Decision: Equatable { case applyRemote, keepLocal }

    /// - localModifiedAt: the local entity's modifiedAt, or nil if absent.
    /// - tombstone: local deletion time for this id, or nil if not deleted.
    /// - remoteModifiedAt / remoteDeleted: the incoming record.
    public static func resolve(localModifiedAt: Date?,
                               tombstone: Date?,
                               remoteModifiedAt: Date,
                               remoteDeleted: Bool) -> Decision {
        if remoteDeleted {
            // Remote tombstone wins unless a strictly newer local edit exists.
            if let local = localModifiedAt, local > remoteModifiedAt { return .keepLocal }
            return .applyRemote
        }
        // Remote upsert. A local delete at or after the remote edit wins.
        if let dead = tombstone, dead >= remoteModifiedAt { return .keepLocal }
        // A local value at or after the remote edit wins (ties keep local).
        if let local = localModifiedAt, local >= remoteModifiedAt { return .keepLocal }
        return .applyRemote
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd WanderIQKit && make test`
Expected: PASS (8 ConflictResolver tests green).

- [ ] **Step 5: Commit**

```bash
git add WanderIQKit/Sources/WanderIQKit/Sync/ConflictResolver.swift WanderIQKit/Tests/WanderIQKitTests/ConflictResolverTests.swift
git commit -m "feat(sync): last-writer-wins conflict resolver"
```

---

### Task 4: Outbox (coalescing pending-change store)

**Files:**
- Create: `WanderIQKit/Sources/WanderIQKit/Sync/Outbox.swift`
- Test: `WanderIQKit/Tests/WanderIQKitTests/OutboxTests.swift`

- [ ] **Step 1: Write the failing test**

Create `WanderIQKit/Tests/WanderIQKitTests/OutboxTests.swift`:
```swift
import Testing
import Foundation
@testable import WanderIQKit

@Suite struct OutboxTests {
    let trip = UUID()

    @Test func enqueueCoalescesByKeyKeepingLatest() {
        var box = Outbox()
        let id = UUID()
        box.enqueue(PendingChange(kind: .item, id: id, tripID: trip, op: .upsert,
                                  modifiedAt: Date(timeIntervalSince1970: 1)))
        box.enqueue(PendingChange(kind: .item, id: id, tripID: trip, op: .delete,
                                  modifiedAt: Date(timeIntervalSince1970: 2)))
        #expect(box.pending.count == 1)
        #expect(box.pending.first?.op == .delete)        // latest wins
    }

    @Test func pendingPreservesInsertionOrderAcrossKeys() {
        var box = Outbox()
        let a = UUID(); let b = UUID()
        box.enqueue(PendingChange(kind: .day,  id: a, tripID: trip, op: .upsert, modifiedAt: .now))
        box.enqueue(PendingChange(kind: .item, id: b, tripID: trip, op: .upsert, modifiedAt: .now))
        #expect(box.pending.map(\.id) == [a, b])
    }

    @Test func acknowledgeRemovesOnlyMatchingKey() {
        var box = Outbox()
        let a = UUID(); let b = UUID()
        box.enqueue(PendingChange(kind: .day, id: a, tripID: trip, op: .upsert, modifiedAt: .now))
        box.enqueue(PendingChange(kind: .day, id: b, tripID: trip, op: .upsert, modifiedAt: .now))
        box.acknowledge(EntityKey(kind: .day, id: a))
        #expect(box.pending.map(\.id) == [b])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd WanderIQKit && make test`
Expected: FAIL — `cannot find 'Outbox' in scope`.

- [ ] **Step 3: Write the outbox**

Create `WanderIQKit/Sources/WanderIQKit/Sync/Outbox.swift`:
```swift
import Foundation

/// Insertion-ordered, key-coalesced set of pending changes (spec §6.2).
/// One entry per (kind, id); the newest enqueue for a key replaces the older
/// but keeps the original queue position so flush order stays stable.
public struct Outbox: Equatable, Codable, Sendable {
    private var order: [EntityKey] = []
    private var byKey: [EntityKey: PendingChange] = [:]

    public init() {}

    public var pending: [PendingChange] { order.compactMap { byKey[$0] } }

    public mutating func enqueue(_ change: PendingChange) {
        if byKey[change.key] == nil { order.append(change.key) }
        byKey[change.key] = change
    }

    public mutating func acknowledge(_ key: EntityKey) {
        byKey[key] = nil
        order.removeAll { $0 == key }
    }

    public var isEmpty: Bool { byKey.isEmpty }

    // Codable: persist as the ordered pending list; rebuild the index on decode.
    private enum CodingKeys: String, CodingKey { case pending }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list = try c.decode([PendingChange].self, forKey: .pending)
        for change in list { enqueue(change) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pending, forKey: .pending)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd WanderIQKit && make test`
Expected: PASS (3 Outbox tests green).

- [ ] **Step 5: Commit**

```bash
git add WanderIQKit/Sources/WanderIQKit/Sync/Outbox.swift WanderIQKit/Tests/WanderIQKitTests/OutboxTests.swift
git commit -m "feat(sync): coalescing outbox"
```

---

### Task 5: `RemoteSyncBackend` protocol + in-memory fake

**Files:**
- Create: `WanderIQKit/Sources/WanderIQKit/Sync/RemoteSyncBackend.swift` (protocol + ChangePage only)
- Create: `WanderIQKit/Tests/WanderIQKitTests/Support/FakeRemoteBackend.swift` (test-only fake, shared across test files in the target)
- Test: `WanderIQKit/Tests/WanderIQKitTests/FakeRemoteBackendTests.swift`

- [ ] **Step 1: Write the failing test**

Create `WanderIQKit/Tests/WanderIQKitTests/FakeRemoteBackendTests.swift`:
```swift
import Testing
import Foundation
@testable import WanderIQKit

@Suite struct FakeRemoteBackendTests {
    let trip = UUID()

    @Test func pushThenPullReturnsRecordsAfterCursor() async throws {
        let backend = FakeRemoteBackend()
        let rec = SyncRecord(kind: .item, id: UUID(), tripID: trip,
                             modifiedAt: Date(timeIntervalSince1970: 5),
                             deleted: false, fields: ["label": "X"])
        try await backend.send([rec])
        let page = try await backend.changes(since: .distantPast)
        #expect(page.records.count == 1)
        #expect(page.cursor > Date.distantPast)
        // A pull at the new cursor sees nothing new.
        let empty = try await backend.changes(since: page.cursor)
        #expect(empty.records.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd WanderIQKit && make test`
Expected: FAIL — `cannot find 'FakeRemoteBackend' in scope`.

- [ ] **Step 3: Write the protocol (Sources) and the fake (Tests)**

Create `WanderIQKit/Sources/WanderIQKit/Sync/RemoteSyncBackend.swift`:
```swift
import Foundation

/// One page of pulled changes plus the advanced cursor.
public struct ChangePage: Equatable, Sendable {
    public let records: [SyncRecord]
    public let cursor: Date
    public init(records: [SyncRecord], cursor: Date) {
        self.records = records; self.cursor = cursor
    }
}

/// Transport abstraction. Sub-project 3 implements this with supabase-swift
/// (PostgREST upserts + cursor query + Realtime). The engine depends only on
/// this protocol, so it is fully testable with a fake.
public protocol RemoteSyncBackend: Sendable {
    /// Upsert records (tombstones included) to the server.
    func send(_ records: [SyncRecord]) async throws
    /// Fetch records with server_updated_at strictly greater than `cursor`,
    /// and the new cursor (max server_updated_at seen, else `cursor`).
    func changes(since cursor: Date) async throws -> ChangePage
}
```

Create `WanderIQKit/Tests/WanderIQKitTests/Support/FakeRemoteBackend.swift`
(test-only; visible to every test file in the target):
```swift
import Foundation
@testable import WanderIQKit

/// In-memory backend for tests and the conformance suite. Stamps a monotonic
/// server time on each send to model `server_updated_at`.
actor FakeRemoteBackend: RemoteSyncBackend {
    private var stored: [EntityKey: (record: SyncRecord, serverAt: Date)] = [:]
    private var clock = Date(timeIntervalSince1970: 0)

    func send(_ records: [SyncRecord]) async throws {
        for r in records {
            clock = clock.addingTimeInterval(1)
            stored[EntityKey(kind: r.kind, id: r.id)] = (r, clock)
        }
    }

    func changes(since cursor: Date) async throws -> ChangePage {
        let fresh = stored.values.filter { $0.serverAt > cursor }
            .sorted { $0.serverAt < $1.serverAt }
        let newCursor = fresh.last?.serverAt ?? cursor
        return ChangePage(records: fresh.map(\.record), cursor: newCursor)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd WanderIQKit && make test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WanderIQKit/Sources/WanderIQKit/Sync/RemoteSyncBackend.swift WanderIQKit/Tests/WanderIQKitTests/Support/FakeRemoteBackend.swift WanderIQKit/Tests/WanderIQKitTests/FakeRemoteBackendTests.swift
git commit -m "feat(sync): RemoteSyncBackend protocol and in-memory fake"
```

---

### Task 6: `SyncState` (cursor + tombstones, persisted)

**Files:**
- Create: `WanderIQKit/Sources/WanderIQKit/Sync/SyncState.swift`
- Test: `WanderIQKit/Tests/WanderIQKitTests/SyncStateTests.swift`

- [ ] **Step 1: Write the failing test**

Create `WanderIQKit/Tests/WanderIQKitTests/SyncStateTests.swift`:
```swift
import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SyncStateTests {
    @Test func defaultsToDistantPastCursorAndNoTombstones() {
        let s = SyncState()
        #expect(s.cursor == .distantPast)
        #expect(s.tombstones.isEmpty)
    }
    @Test func roundTripsThroughCodable() throws {
        var s = SyncState()
        s.cursor = Date(timeIntervalSince1970: 42)
        let id = UUID()
        s.tombstones[id] = Date(timeIntervalSince1970: 7)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(SyncState.self, from: data)
        #expect(back == s)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd WanderIQKit && make test`
Expected: FAIL — `cannot find 'SyncState' in scope`.

- [ ] **Step 3: Write the state**

Create `WanderIQKit/Sources/WanderIQKit/Sync/SyncState.swift`:
```swift
import Foundation

/// Durable sync bookkeeping: the pull cursor and live tombstones.
/// `tombstones[id] = deletedAt`. Persisted by the app between launches.
public struct SyncState: Equatable, Codable, Sendable {
    public var cursor: Date
    public var tombstones: [UUID: Date]

    public init(cursor: Date = .distantPast, tombstones: [UUID: Date] = [:]) {
        self.cursor = cursor
        self.tombstones = tombstones
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd WanderIQKit && make test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WanderIQKit/Sources/WanderIQKit/Sync/SyncState.swift WanderIQKit/Tests/WanderIQKitTests/SyncStateTests.swift
git commit -m "feat(sync): persistable cursor + tombstone state"
```

---

### Task 7: `SyncEngine.applyPull` (apply remote records to the store)

**Files:**
- Create: `WanderIQKit/Sources/WanderIQKit/Sync/SyncEngine.swift`
- Test: `WanderIQKit/Tests/WanderIQKitTests/SyncEngineApplyTests.swift`

The engine mutates a `TripStore` via its existing `upsertRemote`/`removeRemote`
API (so app-layer persistence callbacks fire) and updates a `SyncState`. This
task covers the pull/apply path; Task 8 covers local-change capture; Task 9
covers the round-trip with a backend.

- [ ] **Step 1: Write the failing test**

Create `WanderIQKit/Tests/WanderIQKitTests/SyncEngineApplyTests.swift`:
```swift
import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SyncEngineApplyTests {
    let tripID = UUID()

    private func trip(modifiedAt: Date) -> Trip {
        Trip(id: tripID, name: "Old", startDate: Date(timeIntervalSince1970: 0),
             endDate: Date(timeIntervalSince1970: 0), modifiedAt: modifiedAt)
    }

    @Test func newerRemoteTripOverwritesLocalFields() {
        let store = TripStore(trips: [trip(modifiedAt: Date(timeIntervalSince1970: 1))])
        var state = SyncState()
        let rec = SyncRecord(kind: .trip, id: tripID, tripID: tripID,
                             modifiedAt: Date(timeIntervalSince1970: 2), deleted: false,
                             fields: ["name": "New", "startDate": "0", "endDate": "0",
                                      "destinations": "", "schemaVersion": "1"])
        SyncEngine.applyPull([rec], cursor: Date(timeIntervalSince1970: 9),
                             store: store, state: &state)
        #expect(store.trip(id: tripID)?.name == "New")
        #expect(state.cursor == Date(timeIntervalSince1970: 9))
    }

    @Test func olderRemoteTripIsIgnored() {
        let store = TripStore(trips: [trip(modifiedAt: Date(timeIntervalSince1970: 5))])
        var state = SyncState()
        let rec = SyncRecord(kind: .trip, id: tripID, tripID: tripID,
                             modifiedAt: Date(timeIntervalSince1970: 2), deleted: false,
                             fields: ["name": "Stale", "startDate": "0", "endDate": "0",
                                      "destinations": "", "schemaVersion": "1"])
        SyncEngine.applyPull([rec], cursor: Date(timeIntervalSince1970: 9),
                             store: store, state: &state)
        #expect(store.trip(id: tripID)?.name == "Old")
    }

    @Test func remoteTripTombstoneRemovesTripAndRecordsTombstone() {
        let store = TripStore(trips: [trip(modifiedAt: Date(timeIntervalSince1970: 1))])
        var state = SyncState()
        let rec = SyncRecord(kind: .trip, id: tripID, tripID: tripID,
                             modifiedAt: Date(timeIntervalSince1970: 2), deleted: true)
        SyncEngine.applyPull([rec], cursor: Date(timeIntervalSince1970: 9),
                             store: store, state: &state)
        #expect(store.trip(id: tripID) == nil)
        #expect(state.tombstones[tripID] == Date(timeIntervalSince1970: 2))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd WanderIQKit && make test`
Expected: FAIL — `cannot find 'SyncEngine' in scope`.

- [ ] **Step 3: Write the apply path**

Create `WanderIQKit/Sources/WanderIQKit/Sync/SyncEngine.swift`:
```swift
import Foundation

/// Pure sync orchestration over a TripStore + SyncState. No network: callers
/// pass already-fetched records (pull) or read `pending` (push).
public enum SyncEngine {

    /// Apply a page of remote records to the store using LWW, then advance the
    /// cursor. Trip-kind records map to the trip's own fields; day/item records
    /// map to entries inside their trip (created as a shell if unknown).
    public static func applyPull(_ records: [SyncRecord], cursor: Date,
                                 store: TripStore, state: inout SyncState) {
        for rec in records { apply(rec, store: store, state: &state) }
        state.cursor = max(state.cursor, cursor)
    }

    private static func apply(_ rec: SyncRecord, store: TripStore, state: inout SyncState) {
        let localModifiedAt = localModified(of: rec, store: store)
        let decision = ConflictResolver.resolve(
            localModifiedAt: localModifiedAt,
            tombstone: state.tombstones[rec.id],
            remoteModifiedAt: rec.modifiedAt,
            remoteDeleted: rec.deleted)
        guard decision == .applyRemote else { return }

        if rec.deleted {
            remove(rec, store: store)
            state.tombstones[rec.id] = rec.modifiedAt
        } else {
            insertOrUpdate(rec, store: store)
            state.tombstones[rec.id] = nil
        }
    }

    private static func localModified(of rec: SyncRecord, store: TripStore) -> Date? {
        switch rec.kind {
        case .trip: return store.trip(id: rec.id)?.modifiedAt
        case .day:  return store.trip(id: rec.tripID)?.days.first { $0.id == rec.id }?.modifiedAt
        case .item: return store.trip(id: rec.tripID)?.items.first { $0.id == rec.id }?.modifiedAt
        }
    }

    private static func remove(_ rec: SyncRecord, store: TripStore) {
        switch rec.kind {
        case .trip: store.removeRemote(tripID: rec.id)
        case .day:  store.upsertRemote(tripID: rec.tripID) { $0.days.removeAll { $0.id == rec.id } }
        case .item: store.upsertRemote(tripID: rec.tripID) { $0.items.removeAll { $0.id == rec.id } }
        }
    }

    private static func insertOrUpdate(_ rec: SyncRecord, store: TripStore) {
        store.upsertRemote(tripID: rec.tripID) { trip in
            SyncMapping.apply(rec, to: &trip)
        }
    }
}
```

Also create `WanderIQKit/Sources/WanderIQKit/Sync/SyncMapping.swift` (field
mapping between `SyncRecord.fields` and the domain models — string-valued to
match the JSON-shaped wire format the TS engine will share):
```swift
import Foundation

/// Maps SyncRecord.fields (string-valued) to/from domain models. The wire
/// format mirrors the Postgres columns from sub-project 1 (snake/camel kept
/// camel here; the supabase backend in sub-project 3 maps column names).
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd WanderIQKit && make test`
Expected: PASS (3 apply tests; 36 baseline intact).

- [ ] **Step 5: Commit**

```bash
git add WanderIQKit/Sources/WanderIQKit/Sync/SyncEngine.swift WanderIQKit/Sources/WanderIQKit/Sync/SyncMapping.swift WanderIQKit/Tests/WanderIQKitTests/SyncEngineApplyTests.swift
git commit -m "feat(sync): apply remote pull to store with LWW"
```

---

### Task 8: Capture local changes into the outbox + tombstones

**Files:**
- Modify: `WanderIQKit/Sources/WanderIQKit/Sync/SyncEngine.swift`
- Test: `WanderIQKit/Tests/WanderIQKitTests/SyncEngineCaptureTests.swift`

- [ ] **Step 1: Write the failing test**

Create `WanderIQKit/Tests/WanderIQKitTests/SyncEngineCaptureTests.swift`:
```swift
import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SyncEngineCaptureTests {
    let tripID = UUID()

    @Test func localUpsertEnqueuesUpsert() {
        var box = Outbox()
        let item = ChecklistItem(id: UUID(), kind: .prep, label: "X",
                                 modifiedAt: Date(timeIntervalSince1970: 3))
        SyncEngine.captureUpsert(kind: .item, id: item.id, tripID: tripID,
                                 modifiedAt: item.modifiedAt, into: &box)
        #expect(box.pending.count == 1)
        #expect(box.pending.first?.op == .upsert)
        #expect(box.pending.first?.modifiedAt == Date(timeIntervalSince1970: 3))
    }

    @Test func localDeleteEnqueuesDeleteAndRecordsTombstone() {
        var box = Outbox(); var state = SyncState()
        let id = UUID(); let at = Date(timeIntervalSince1970: 4)
        SyncEngine.captureDelete(kind: .item, id: id, tripID: tripID,
                                 deletedAt: at, into: &box, state: &state)
        #expect(box.pending.first?.op == .delete)
        #expect(state.tombstones[id] == at)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd WanderIQKit && make test`
Expected: FAIL — `type 'SyncEngine' has no member 'captureUpsert'`.

- [ ] **Step 3: Add capture functions to `SyncEngine`**

Append to `WanderIQKit/Sources/WanderIQKit/Sync/SyncEngine.swift` (inside the enum):
```swift
    // MARK: - Local change capture (push side)

    public static func captureUpsert(kind: EntityKind, id: UUID, tripID: UUID,
                                     modifiedAt: Date, into outbox: inout Outbox) {
        outbox.enqueue(PendingChange(kind: kind, id: id, tripID: tripID,
                                     op: .upsert, modifiedAt: modifiedAt))
    }

    public static func captureDelete(kind: EntityKind, id: UUID, tripID: UUID,
                                     deletedAt: Date, into outbox: inout Outbox,
                                     state: inout SyncState) {
        outbox.enqueue(PendingChange(kind: kind, id: id, tripID: tripID,
                                     op: .delete, modifiedAt: deletedAt))
        state.tombstones[id] = deletedAt
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd WanderIQKit && make test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WanderIQKit/Sources/WanderIQKit/Sync/SyncEngine.swift WanderIQKit/Tests/WanderIQKitTests/SyncEngineCaptureTests.swift
git commit -m "feat(sync): capture local changes into outbox and tombstones"
```

---

### Task 9: Push driver (flush outbox through a backend)

**Files:**
- Modify: `WanderIQKit/Sources/WanderIQKit/Sync/SyncEngine.swift`
- Test: `WanderIQKit/Tests/WanderIQKitTests/SyncEnginePushTests.swift`

- [ ] **Step 1: Write the failing test**

Create `WanderIQKit/Tests/WanderIQKitTests/SyncEnginePushTests.swift`:
```swift
import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SyncEnginePushTests {
    let tripID = UUID()

    @Test func pushSendsRecordsBuiltFromStoreAndClearsOutbox() async throws {
        let item = ChecklistItem(id: UUID(), kind: .prep, label: "Buy",
                                 modifiedAt: Date(timeIntervalSince1970: 3))
        let trip = Trip(id: tripID, name: "T", startDate: Date(timeIntervalSince1970: 0),
                        endDate: Date(timeIntervalSince1970: 0), items: [item],
                        modifiedAt: Date(timeIntervalSince1970: 1))
        let store = TripStore(trips: [trip])
        var box = Outbox()
        box.enqueue(PendingChange(kind: .item, id: item.id, tripID: tripID,
                                  op: .upsert, modifiedAt: item.modifiedAt))
        let backend = FakeRemoteBackend()

        try await SyncEngine.push(outbox: &box, store: store, backend: backend)

        #expect(box.isEmpty)
        let page = try await backend.changes(since: .distantPast)
        #expect(page.records.first?.fields?["label"] == "Buy")
    }

    @Test func pushSendsTombstoneForDeleteEntries() async throws {
        let store = TripStore(trips: [])
        var box = Outbox()
        let goneID = UUID()
        box.enqueue(PendingChange(kind: .item, id: goneID, tripID: tripID,
                                  op: .delete, modifiedAt: Date(timeIntervalSince1970: 4)))
        let backend = FakeRemoteBackend()

        try await SyncEngine.push(outbox: &box, store: store, backend: backend)

        let page = try await backend.changes(since: .distantPast)
        #expect(page.records.first?.deleted == true)
        #expect(page.records.first?.id == goneID)
        #expect(box.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd WanderIQKit && make test`
Expected: FAIL — `type 'SyncEngine' has no member 'push'`.

- [ ] **Step 3: Add the push driver + record builder**

Append to `WanderIQKit/Sources/WanderIQKit/Sync/SyncEngine.swift` (inside the enum):
```swift
    // MARK: - Push

    /// Flush the outbox oldest-first. Upserts read the latest entity state from
    /// the store; deletes send a tombstone. Each acknowledged entry is removed.
    public static func push(outbox: inout Outbox, store: TripStore,
                            backend: RemoteSyncBackend) async throws {
        for change in outbox.pending {
            let record = buildRecord(for: change, store: store)
            try await backend.send([record])
            outbox.acknowledge(change.key)
        }
    }

    static func buildRecord(for change: PendingChange, store: TripStore) -> SyncRecord {
        if change.op == .delete {
            return SyncRecord(kind: change.kind, id: change.id, tripID: change.tripID,
                              modifiedAt: change.modifiedAt, deleted: true)
        }
        let fields = SyncMapping.fields(kind: change.kind, id: change.id,
                                        tripID: change.tripID, store: store)
        return SyncRecord(kind: change.kind, id: change.id, tripID: change.tripID,
                          modifiedAt: change.modifiedAt, deleted: false, fields: fields)
    }
```

Append the reverse mapping to `WanderIQKit/Sources/WanderIQKit/Sync/SyncMapping.swift`:
```swift
extension SyncMapping {
    /// Build wire fields for an entity from the store (push side).
    static func fields(kind: EntityKind, id: UUID, tripID: UUID, store: TripStore) -> [String: String] {
        guard let trip = store.trip(id: tripID) else { return [:] }
        switch kind {
        case .trip:
            return ["name": trip.name,
                    "startDate": String(trip.startDate.timeIntervalSince1970),
                    "endDate": String(trip.endDate.timeIntervalSince1970),
                    "destinations": trip.destinations.joined(separator: "\u{1f}"),
                    "schemaVersion": String(trip.schemaVersion)]
        case .day:
            guard let d = trip.days.first(where: { $0.id == id }) else { return [:] }
            return ["date": String(d.date.timeIntervalSince1970),
                    "city": d.city, "title": d.title]
        case .item:
            guard let it = trip.items.first(where: { $0.id == id }) else { return [:] }
            var f: [String: String] = [
                "kind": it.kind.rawValue, "label": it.label, "notes": it.notes,
                "isDone": it.isDone ? "true" : "false",
                "sortOrder": String(it.sortOrder)]
            if let v = it.dayID { f["dayID"] = v.uuidString }
            if let v = it.time { f["time"] = v }
            if let v = it.owner { f["owner"] = v }
            if let v = it.reminderDate { f["reminderDate"] = String(v.timeIntervalSince1970) }
            if let p = it.place {
                f["placeName"] = p.name; f["placeQuery"] = p.query
                if let lat = p.latitude { f["placeLat"] = String(lat) }
                if let lon = p.longitude { f["placeLon"] = String(lon) }
            }
            return f
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd WanderIQKit && make test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WanderIQKit/Sources/WanderIQKit/Sync/SyncEngine.swift WanderIQKit/Sources/WanderIQKit/Sync/SyncMapping.swift WanderIQKit/Tests/WanderIQKitTests/SyncEnginePushTests.swift
git commit -m "feat(sync): push driver flushing outbox through a backend"
```

---

### Task 10: Cross-engine conformance suite

**Files:**
- Create: `WanderIQKit/Tests/WanderIQKitTests/Fixtures/sync-conformance.json`
- Create: `WanderIQKit/Tests/WanderIQKitTests/SyncConformanceTests.swift`

The scenario file is engine-agnostic JSON; the future TypeScript engine runs
the SAME file. Each scenario: a local entity state (or none), a local tombstone
(or none), one incoming remote record, and the expected decision.

- [ ] **Step 1: Write the scenario fixture**

Create `WanderIQKit/Tests/WanderIQKitTests/Fixtures/sync-conformance.json`:
```json
{
  "scenarios": [
    {"name": "remote upsert newer applies",
     "localModifiedAt": 1, "tombstone": null, "remoteModifiedAt": 2, "remoteDeleted": false,
     "expect": "applyRemote"},
    {"name": "remote upsert older kept",
     "localModifiedAt": 2, "tombstone": null, "remoteModifiedAt": 1, "remoteDeleted": false,
     "expect": "keepLocal"},
    {"name": "tie keeps local",
     "localModifiedAt": 2, "tombstone": null, "remoteModifiedAt": 2, "remoteDeleted": false,
     "expect": "keepLocal"},
    {"name": "remote delete newer than local edit applies",
     "localModifiedAt": 1, "tombstone": null, "remoteModifiedAt": 2, "remoteDeleted": true,
     "expect": "applyRemote"},
    {"name": "local edit newer than remote delete kept",
     "localModifiedAt": 3, "tombstone": null, "remoteModifiedAt": 2, "remoteDeleted": true,
     "expect": "keepLocal"},
    {"name": "local tombstone ties remote upsert stays deleted",
     "localModifiedAt": null, "tombstone": 2, "remoteModifiedAt": 2, "remoteDeleted": false,
     "expect": "keepLocal"},
    {"name": "remote upsert newer than tombstone resurrects",
     "localModifiedAt": null, "tombstone": 1, "remoteModifiedAt": 2, "remoteDeleted": false,
     "expect": "applyRemote"},
    {"name": "unknown entity remote upsert applies",
     "localModifiedAt": null, "tombstone": null, "remoteModifiedAt": 1, "remoteDeleted": false,
     "expect": "applyRemote"}
  ]
}
```

- [ ] **Step 2: Write the conformance test (fails until fixture is wired)**

Create `WanderIQKit/Tests/WanderIQKitTests/SyncConformanceTests.swift`:
```swift
import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SyncConformanceTests {

    struct Scenario: Decodable {
        let name: String
        let localModifiedAt: Double?
        let tombstone: Double?
        let remoteModifiedAt: Double
        let remoteDeleted: Bool
        let expect: String
    }
    struct Suite_: Decodable { let scenarios: [Scenario] }

    static func load() throws -> [Scenario] {
        let url = Bundle.module.url(forResource: "sync-conformance", withExtension: "json",
                                    subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Suite_.self, from: data).scenarios
    }

    @Test func allConformanceScenariosMatch() throws {
        for s in try Self.load() {
            let decision = ConflictResolver.resolve(
                localModifiedAt: s.localModifiedAt.map { Date(timeIntervalSince1970: $0) },
                tombstone: s.tombstone.map { Date(timeIntervalSince1970: $0) },
                remoteModifiedAt: Date(timeIntervalSince1970: s.remoteModifiedAt),
                remoteDeleted: s.remoteDeleted)
            let expected: ConflictResolver.Decision = s.expect == "applyRemote" ? .applyRemote : .keepLocal
            #expect(decision == expected, "scenario: \(s.name)")
        }
    }
}
```

- [ ] **Step 3: Wire the fixture as a package resource**

Modify `WanderIQKit/Package.swift` — add a resource to the test target so
`Bundle.module` can find the JSON. Locate the `.testTarget(name: "WanderIQKitTests" …)`
entry and add a `resources:` parameter:
```swift
        .testTarget(
            name: "WanderIQKitTests",
            dependencies: ["WanderIQKit"],
            resources: [.copy("Fixtures")]
        ),
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd WanderIQKit && make test`
Expected: PASS — `allConformanceScenariosMatch` green over all 8 scenarios.

- [ ] **Step 5: Commit**

```bash
git add WanderIQKit/Tests/WanderIQKitTests/Fixtures/sync-conformance.json WanderIQKit/Tests/WanderIQKitTests/SyncConformanceTests.swift WanderIQKit/Package.swift
git commit -m "test(sync): cross-engine conformance suite (Swift runner)"
```

---

### Task 11: Round-trip integration test (two engines via one backend)

**Files:**
- Test: `WanderIQKit/Tests/WanderIQKitTests/SyncRoundTripTests.swift`

Proves the full loop: device A pushes, device B pulls and converges.

- [ ] **Step 1: Write the test**

Create `WanderIQKit/Tests/WanderIQKitTests/SyncRoundTripTests.swift`:
```swift
import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SyncRoundTripTests {

    @Test func deviceAEditConvergesToDeviceB() async throws {
        let tripID = UUID()
        let backend = FakeRemoteBackend()

        // Device A: a trip with one day and one item, all queued for push.
        let day = TripDay(id: UUID(), date: Date(timeIntervalSince1970: 0), city: "Shanghai",
                          title: "Arrive", modifiedAt: Date(timeIntervalSince1970: 5))
        let item = ChecklistItem(id: UUID(), kind: .prep, label: "Passport",
                                 modifiedAt: Date(timeIntervalSince1970: 5))
        let tripA = Trip(id: tripID, name: "China", startDate: Date(timeIntervalSince1970: 0),
                         endDate: Date(timeIntervalSince1970: 0), days: [day], items: [item],
                         modifiedAt: Date(timeIntervalSince1970: 5))
        let storeA = TripStore(trips: [tripA])
        var boxA = Outbox()
        boxA.enqueue(PendingChange(kind: .trip, id: tripID, tripID: tripID, op: .upsert,
                                   modifiedAt: Date(timeIntervalSince1970: 5)))
        boxA.enqueue(PendingChange(kind: .day, id: day.id, tripID: tripID, op: .upsert,
                                   modifiedAt: Date(timeIntervalSince1970: 5)))
        boxA.enqueue(PendingChange(kind: .item, id: item.id, tripID: tripID, op: .upsert,
                                   modifiedAt: Date(timeIntervalSince1970: 5)))
        try await SyncEngine.push(outbox: &boxA, store: storeA, backend: backend)

        // Device B: empty, pulls everything.
        let storeB = TripStore(trips: [])
        var stateB = SyncState()
        let page = try await backend.changes(since: stateB.cursor)
        SyncEngine.applyPull(page.records, cursor: page.cursor, store: storeB, state: &stateB)

        #expect(storeB.trip(id: tripID)?.name == "China")
        #expect(storeB.trip(id: tripID)?.days.first?.city == "Shanghai")
        #expect(storeB.trip(id: tripID)?.items.first?.label == "Passport")
        #expect(stateB.cursor > .distantPast)
    }
}
```

- [ ] **Step 2: Run to verify it passes**

Run: `cd WanderIQKit && make test`
Expected: PASS (and the whole suite: 36 baseline + all new sync tests).

- [ ] **Step 3: Commit**

```bash
git add WanderIQKit/Tests/WanderIQKitTests/SyncRoundTripTests.swift
git commit -m "test(sync): A-push to B-pull round-trip convergence"
```

---

## Done criteria

- `cd WanderIQKit && make test` passes: 36 baseline tests plus the full sync
  suite (types, resolver, outbox, fake backend, state, apply, capture, push,
  conformance, round-trip).
- The engine is pure and network-free; all transport is behind
  `RemoteSyncBackend`, faked in tests.
- The conformance fixture (`sync-conformance.json`) is engine-agnostic and ready
  for the future TypeScript engine to run identically.
- Next plan: **sub-project 3 — iOS app cutover** (implement `RemoteSyncBackend`
  with supabase-swift + Realtime, auth UI, swap `SyncCoordinator`, wire
  capture/push/pull into `AppModel`).
```
