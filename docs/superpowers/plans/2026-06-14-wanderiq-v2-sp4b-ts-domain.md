# WanderIQ v2 — Sub-project 4b: TypeScript Domain Model + Trip Mapping/Engine

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the web app a real `Trip` aggregate (the TS twin of the Swift models) with field mapping (`SyncRecord` ⇄ Trip/day/item) and Trip-level apply/diff-capture, all pure and Vitest-tested — building on 4a's record-level engine.

**Architecture:** Pure TypeScript in `webapp/src/sync/`, no `@supabase/supabase-js`, no IndexedDB, no UI (those are 4c/4d). Mirrors sub-project 2's Swift layer exactly: a `Trip` model (times as epoch numbers throughout), a `TripMapping` (apply a `SyncRecord` into a trips map; build a record's `fields` from a trip — keys identical to the Swift `SyncMapping`), a `TripDiff` (mirror of the Swift one), and `TripSync` (Trip-level `applyPull` using `ConflictResolver` + tombstones, and `capture` from a diff). Fully TDD; ends with an A→B round-trip mirroring the Swift `SyncRoundTripTests`.

**Tech Stack:** TypeScript, Vitest (already set up in `webapp/`). No new deps.

**Spec:** design §8.2; §6 (protocol). Web twin of Swift `Models.swift`, `SyncMapping.swift`, `TripDiff.swift`, `SyncEngine.applyPull/capture`.

**Context7 note:** written without supabase-js (which I couldn't verify against live docs this session); the supabase-js backend + auth + IndexedDB are deferred to 4c precisely so this plan needs no unverified external API.

**Verification:** `cd webapp && npm test` (26 baseline from 4a + new) and `npm run build`.

**Field-mapping contract (must match the Swift `SyncMapping` keys exactly):**
- trip → `name, startDate, endDate, destinations, schemaVersion`
- day → `date, city, title`
- item → `kind, label, notes, isDone, sortOrder, dayID, time, owner, reminderDate, placeName, placeQuery, placeLat, placeLon`
Times are epoch-seconds strings on the wire; epoch numbers in the model. `destinations` join/split on the unit separator `\u{1f}`.

---

### Task 1: Trip domain model (TS)

**Files:**
- Create: `webapp/src/model/trip.ts`
- Test: `webapp/src/model/trip.test.ts`

- [ ] **Step 1: Write the failing test**

Create `webapp/src/model/trip.test.ts`:
```ts
import { test, expect } from "vitest";
import { newTrip, type Trip } from "./trip";

test("newTrip fills defaults and an id", () => {
  const t: Trip = newTrip({ name: "China" });
  expect(t.name).toBe("China");
  expect(t.id).toMatch(/[0-9a-f-]{36}/);
  expect(t.days).toEqual([]);
  expect(t.items).toEqual([]);
  expect(t.schemaVersion).toBe(1);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd webapp && npm test`
Expected: FAIL — cannot resolve `./trip`.

- [ ] **Step 3: Write the model**

Create `webapp/src/model/trip.ts`:
```ts
export type ItemKind = "prep" | "hotel" | "doc" | "itinerary" | "packing";

export interface Place {
  name: string;
  query: string;
  latitude?: number;
  longitude?: number;
}

export interface ChecklistItem {
  id: string;
  kind: ItemKind;
  label: string;
  notes: string;
  dayId?: string;
  time?: string;
  owner?: string;
  isDone: boolean;
  sortOrder: number;
  reminderDate?: number; // epoch seconds
  place?: Place;
  modifiedAt: number;    // epoch seconds
}

export interface TripDay {
  id: string;
  date: number;          // epoch seconds
  city: string;
  title: string;
  modifiedAt: number;
}

export interface Trip {
  id: string;
  name: string;
  startDate: number;     // epoch seconds
  endDate: number;
  destinations: string[];
  days: TripDay[];
  items: ChecklistItem[];
  schemaVersion: number;
  modifiedAt: number;
}

export function newTrip(partial: Partial<Trip> & { name: string }): Trip {
  return {
    id: partial.id ?? crypto.randomUUID(),
    name: partial.name,
    startDate: partial.startDate ?? 0,
    endDate: partial.endDate ?? 0,
    destinations: partial.destinations ?? [],
    days: partial.days ?? [],
    items: partial.items ?? [],
    schemaVersion: partial.schemaVersion ?? 1,
    modifiedAt: partial.modifiedAt ?? 0,
  };
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd webapp && npm test`
Expected: PASS (1 new + 26 prior = 27).

- [ ] **Step 5: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/model/trip.ts webapp/src/model/trip.test.ts
git commit -m "feat(web): Trip domain model"
```

---

### Task 2: TripMapping — SyncRecord ⇄ trip/day/item (TS, TDD)

**Files:**
- Create: `webapp/src/sync/tripMapping.ts`
- Test: `webapp/src/sync/tripMapping.test.ts`

Mirrors the Swift `SyncMapping`: `applyRecord` writes a non-deleted record into a
`Map<string, Trip>` (keyed by trip id, creating a shell trip if absent);
`recordFields` builds the wire `fields` for an entity from a trip.

- [ ] **Step 1: Write the failing test**

Create `webapp/src/sync/tripMapping.test.ts`:
```ts
import { test, expect } from "vitest";
import { applyRecord, recordFields } from "./tripMapping";
import { newTrip, type Trip } from "../model/trip";
import type { SyncRecord } from "./types";

function trips(...t: Trip[]): Map<string, Trip> {
  return new Map(t.map((x) => [x.id, x]));
}

test("applyRecord writes item fields into its trip", () => {
  const tripId = "00000000-0000-0000-0000-0000000000f1";
  const m = trips(newTrip({ id: tripId, name: "China" }));
  const rec: SyncRecord = {
    kind: "item", id: "i1", tripId, modifiedAt: 5, deleted: false,
    fields: { kind: "prep", label: "Buy", notes: "", isDone: "true", sortOrder: "2",
              placeName: "Museum", placeLat: "31.2" },
  };
  applyRecord(rec, m);
  const item = m.get(tripId)!.items[0];
  expect(item.label).toBe("Buy");
  expect(item.isDone).toBe(true);
  expect(item.sortOrder).toBe(2);
  expect(item.place?.name).toBe("Museum");
  expect(item.place?.latitude).toBeCloseTo(31.2);
  expect(item.modifiedAt).toBe(5);
});

test("applyRecord creates a shell trip when unknown, then applies trip fields", () => {
  const tripId = "00000000-0000-0000-0000-0000000000f2";
  const m = new Map<string, Trip>();
  applyRecord({ kind: "trip", id: tripId, tripId, modifiedAt: 9, deleted: false,
    fields: { name: "HK", startDate: "0", endDate: "0", destinations: "HKSZ", schemaVersion: "1" } }, m);
  expect(m.get(tripId)!.name).toBe("HK");
  expect(m.get(tripId)!.destinations).toEqual(["HK", "SZ"]);
});

test("recordFields round-trips an item back to wire fields", () => {
  const tripId = "00000000-0000-0000-0000-0000000000f1";
  const t = newTrip({ id: tripId, name: "China" });
  t.items.push({ id: "i1", kind: "packing", label: "Socks", notes: "", isDone: false,
    sortOrder: 1, modifiedAt: 3 });
  const f = recordFields("item", "i1", trips(t));
  expect(f.kind).toBe("packing");
  expect(f.label).toBe("Socks");
  expect(f.isDone).toBe("false");
  expect(f.sortOrder).toBe("1");
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd webapp && npm test`
Expected: FAIL — cannot resolve `./tripMapping`.

- [ ] **Step 3: Write the mapping**

Create `webapp/src/sync/tripMapping.ts`:
```ts
import { newTrip, type ChecklistItem, type ItemKind, type Place, type Trip, type TripDay } from "../model/trip";
import type { EntityKind, SyncRecord } from "./types";

const SEP = "\u{1f}";
const num = (s: string | undefined, d = 0): number => (s !== undefined && s !== "" ? Number(s) : d);

/** Apply a non-deleted record into the trips map (shell-creating its trip). */
export function applyRecord(rec: SyncRecord, trips: Map<string, Trip>): void {
  let trip = trips.get(rec.tripId);
  if (!trip) {
    trip = newTrip({ id: rec.tripId, name: "" });
    trips.set(rec.tripId, trip);
  }
  const f = rec.fields ?? {};
  if (rec.kind === "trip" && rec.id === trip.id) {
    if (f.name !== undefined) trip.name = f.name;
    if (f.startDate !== undefined) trip.startDate = num(f.startDate);
    if (f.endDate !== undefined) trip.endDate = num(f.endDate);
    if (f.destinations !== undefined) trip.destinations = f.destinations === "" ? [] : f.destinations.split(SEP);
    if (f.schemaVersion !== undefined) trip.schemaVersion = num(f.schemaVersion, 1);
    trip.modifiedAt = rec.modifiedAt;
  } else if (rec.kind === "day") {
    const day: TripDay = { id: rec.id, date: num(f.date), city: f.city ?? "",
      title: f.title ?? "", modifiedAt: rec.modifiedAt };
    upsertById(trip.days, day);
  } else if (rec.kind === "item") {
    let place: Place | undefined;
    if (f.placeName !== undefined) {
      place = { name: f.placeName, query: f.placeQuery ?? "",
        latitude: f.placeLat !== undefined ? Number(f.placeLat) : undefined,
        longitude: f.placeLon !== undefined ? Number(f.placeLon) : undefined };
    }
    const item: ChecklistItem = {
      id: rec.id, kind: (f.kind as ItemKind) ?? "prep", label: f.label ?? "",
      notes: f.notes ?? "", dayId: f.dayID, time: f.time, owner: f.owner,
      isDone: f.isDone === "true", sortOrder: num(f.sortOrder),
      reminderDate: f.reminderDate !== undefined ? num(f.reminderDate) : undefined,
      place, modifiedAt: rec.modifiedAt };
    upsertById(trip.items, item);
  }
}

/** Build wire fields for an entity from a trip (push side). */
export function recordFields(kind: EntityKind, id: string, trips: Map<string, Trip>): Record<string, string> {
  // For a trip record the entity id IS the trip id.
  const trip = trips.get(kind === "trip" ? id : tripIdOf(id, trips)) ?? [...trips.values()].find((t) => containsEntity(t, kind, id));
  if (!trip) return {};
  if (kind === "trip") {
    return { name: trip.name, startDate: String(trip.startDate), endDate: String(trip.endDate),
      destinations: trip.destinations.join(SEP), schemaVersion: String(trip.schemaVersion) };
  }
  if (kind === "day") {
    const d = trip.days.find((x) => x.id === id);
    return d ? { date: String(d.date), city: d.city, title: d.title } : {};
  }
  const it = trip.items.find((x) => x.id === id);
  if (!it) return {};
  const f: Record<string, string> = { kind: it.kind, label: it.label, notes: it.notes,
    isDone: it.isDone ? "true" : "false", sortOrder: String(it.sortOrder) };
  if (it.dayId !== undefined) f.dayID = it.dayId;
  if (it.time !== undefined) f.time = it.time;
  if (it.owner !== undefined) f.owner = it.owner;
  if (it.reminderDate !== undefined) f.reminderDate = String(it.reminderDate);
  if (it.place) {
    f.placeName = it.place.name; f.placeQuery = it.place.query;
    if (it.place.latitude !== undefined) f.placeLat = String(it.place.latitude);
    if (it.place.longitude !== undefined) f.placeLon = String(it.place.longitude);
  }
  return f;
}

function upsertById<T extends { id: string }>(arr: T[], v: T): void {
  const i = arr.findIndex((x) => x.id === v.id);
  if (i >= 0) arr[i] = v; else arr.push(v);
}
function containsEntity(t: Trip, kind: EntityKind, id: string): boolean {
  return kind === "day" ? t.days.some((d) => d.id === id) : t.items.some((it) => it.id === id);
}
function tripIdOf(entityId: string, trips: Map<string, Trip>): string {
  for (const t of trips.values()) {
    if (t.days.some((d) => d.id === entityId) || t.items.some((it) => it.id === entityId)) return t.id;
  }
  return "";
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd webapp && npm test`
Expected: PASS (3 new + 27 = 30).

- [ ] **Step 5: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/sync/tripMapping.ts webapp/src/sync/tripMapping.test.ts
git commit -m "feat(web): SyncRecord <-> trip/day/item field mapping"
```

---

### Task 3: TripDiff (TS, TDD — mirror of the Swift TripDiff)

**Files:**
- Create: `webapp/src/sync/tripDiff.ts`
- Test: `webapp/src/sync/tripDiff.test.ts`

- [ ] **Step 1: Write the failing test**

Create `webapp/src/sync/tripDiff.test.ts`:
```ts
import { test, expect } from "vitest";
import { diffTrip } from "./tripDiff";
import { newTrip } from "../model/trip";

test("new trip → trip save + each day/item save, no deletes", () => {
  const t = newTrip({ id: "t", name: "China" });
  t.days.push({ id: "d1", date: 0, city: "SH", title: "", modifiedAt: 1 });
  t.items.push({ id: "i1", kind: "prep", label: "X", notes: "", isDone: false, sortOrder: 0, modifiedAt: 1 });
  const { saves, deletes } = diffTrip(undefined, t);
  expect(saves).toContainEqual({ kind: "trip", id: "t" });
  expect(saves).toContainEqual({ kind: "day", id: "d1" });
  expect(saves).toContainEqual({ kind: "item", id: "i1" });
  expect(deletes).toEqual([]);
});

test("removed item → delete ref", () => {
  const old = newTrip({ id: "t", name: "China" });
  old.items.push({ id: "i1", kind: "prep", label: "X", notes: "", isDone: false, sortOrder: 0, modifiedAt: 1 });
  const now = newTrip({ id: "t", name: "China" });
  const { deletes } = diffTrip(old, now);
  expect(deletes).toContainEqual({ kind: "item", id: "i1" });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd webapp && npm test`
Expected: FAIL — cannot resolve `./tripDiff`.

- [ ] **Step 3: Write the diff**

Create `webapp/src/sync/tripDiff.ts`:
```ts
import type { Trip } from "../model/trip";
import type { EntityKind } from "./types";

export interface EntityRef { kind: EntityKind; id: string; }
export interface TripDiffResult { saves: EntityRef[]; deletes: EntityRef[]; }

const eq = (a: unknown, b: unknown): boolean => JSON.stringify(a) === JSON.stringify(b);

/** Mirror of the Swift TripDiff: which entities changed between snapshots. */
export function diffTrip(old: Trip | undefined, next: Trip): TripDiffResult {
  if (!old) {
    return {
      saves: [{ kind: "trip", id: next.id },
        ...next.days.map((d) => ({ kind: "day" as const, id: d.id })),
        ...next.items.map((i) => ({ kind: "item" as const, id: i.id }))],
      deletes: [],
    };
  }
  const saves: EntityRef[] = [];
  const deletes: EntityRef[] = [];

  const metaChanged = old.name !== next.name || old.startDate !== next.startDate
    || old.endDate !== next.endDate || !eq(old.destinations, next.destinations)
    || old.schemaVersion !== next.schemaVersion;
  if (metaChanged) saves.push({ kind: "trip", id: next.id });

  diffList(old.days, next.days, "day", saves, deletes);
  diffList(old.items, next.items, "item", saves, deletes);
  return { saves, deletes };
}

function diffList<T extends { id: string }>(
  oldArr: T[], newArr: T[], kind: EntityKind, saves: EntityRef[], deletes: EntityRef[],
): void {
  const oldMap = new Map(oldArr.map((x) => [x.id, x]));
  const newMap = new Map(newArr.map((x) => [x.id, x]));
  for (const [id, v] of newMap) if (!eq(oldMap.get(id), v)) saves.push({ kind, id });
  for (const id of oldMap.keys()) if (!newMap.has(id)) deletes.push({ kind, id });
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd webapp && npm test`
Expected: PASS (2 new + 30 = 32).

- [ ] **Step 5: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/sync/tripDiff.ts webapp/src/sync/tripDiff.test.ts
git commit -m "feat(web): trip diff (mirror of Swift TripDiff)"
```

---

### Task 4: TripSync — Trip-level applyPull + capture (TS, TDD)

**Files:**
- Create: `webapp/src/sync/tripSync.ts`
- Test: `webapp/src/sync/tripSync.test.ts`

Operates on a `TripState` (`trips` map + `tombstones` + `cursor`). `applyPull`
resolves each incoming record via `ConflictResolver` and applies through
`tripMapping`; `capture` turns a before/after trip diff into outbox entries +
tombstones. Mirrors the Swift `SyncEngine.applyPull`/`capture`.

- [ ] **Step 1: Write the failing test**

Create `webapp/src/sync/tripSync.test.ts`:
```ts
import { test, expect } from "vitest";
import { applyPull, capture, type TripState } from "./tripSync";
import { Outbox } from "./outbox";
import { newTrip, type Trip } from "../model/trip";
import type { SyncRecord } from "./types";

function state(...t: Trip[]): TripState {
  return { trips: new Map(t.map((x) => [x.id, x])), tombstones: new Map(), cursor: 0 };
}

test("applyPull applies a newer trip record and advances the cursor", () => {
  const s = state(newTrip({ id: "t", name: "Old", modifiedAt: 1 }));
  const rec: SyncRecord = { kind: "trip", id: "t", tripId: "t", modifiedAt: 2, deleted: false,
    fields: { name: "New", startDate: "0", endDate: "0", destinations: "", schemaVersion: "1" } };
  applyPull([rec], 9, s);
  expect(s.trips.get("t")!.name).toBe("New");
  expect(s.cursor).toBe(9);
});

test("applyPull removes a trip on a newer tombstone", () => {
  const s = state(newTrip({ id: "t", name: "X", modifiedAt: 1 }));
  applyPull([{ kind: "trip", id: "t", tripId: "t", modifiedAt: 2, deleted: true }], 9, s);
  expect(s.trips.has("t")).toBe(false);
  expect(s.tombstones.get("t")).toBe(2);
});

test("capture enqueues upserts for a new trip and its item", () => {
  const box = new Outbox(); const s = state();
  const t = newTrip({ id: "t", name: "China", modifiedAt: 5 });
  t.items.push({ id: "i1", kind: "prep", label: "X", notes: "", isDone: false, sortOrder: 0, modifiedAt: 5 });
  capture(undefined, t, box, s, 5);
  const kinds = box.pending.map((c) => c.kind).sort();
  expect(kinds).toEqual(["item", "trip"]);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd webapp && npm test`
Expected: FAIL — cannot resolve `./tripSync`.

- [ ] **Step 3: Write the engine**

Create `webapp/src/sync/tripSync.ts`:
```ts
import { resolve } from "./conflictResolver";
import { applyRecord } from "./tripMapping";
import { diffTrip } from "./tripDiff";
import type { Outbox } from "./outbox";
import type { SyncRecord } from "./types";
import type { Trip } from "../model/trip";

export interface TripState {
  trips: Map<string, Trip>;
  tombstones: Map<string, number>; // entity id -> deletedAt
  cursor: number;
}

function localModifiedAt(rec: SyncRecord, s: TripState): number | null {
  if (rec.kind === "trip") return s.trips.get(rec.id)?.modifiedAt ?? null;
  const trip = s.trips.get(rec.tripId);
  if (!trip) return null;
  const e = rec.kind === "day" ? trip.days.find((d) => d.id === rec.id)
                               : trip.items.find((i) => i.id === rec.id);
  return e ? e.modifiedAt : null;
}

function removeEntity(rec: SyncRecord, s: TripState): void {
  if (rec.kind === "trip") { s.trips.delete(rec.id); return; }
  const trip = s.trips.get(rec.tripId);
  if (!trip) return;
  if (rec.kind === "day") trip.days = trip.days.filter((d) => d.id !== rec.id);
  else trip.items = trip.items.filter((i) => i.id !== rec.id);
}

/** Apply a page of records via LWW, then advance the cursor. */
export function applyPull(records: SyncRecord[], cursor: number, s: TripState): void {
  for (const rec of records) {
    const decision = resolve(localModifiedAt(rec, s), s.tombstones.get(rec.id) ?? null,
                             rec.modifiedAt, rec.deleted);
    if (decision !== "applyRemote") continue;
    if (rec.deleted) { removeEntity(rec, s); s.tombstones.set(rec.id, rec.modifiedAt); }
    else { applyRecord(rec, s.trips); s.tombstones.delete(rec.id); }
  }
  s.cursor = Math.max(s.cursor, cursor);
}

/** Diff old→next and enqueue upserts/deletes. Saves use the entity modifiedAt. */
export function capture(old: Trip | undefined, next: Trip, outbox: Outbox, s: TripState, now: number): void {
  const { saves, deletes } = diffTrip(old, next);
  for (const ref of saves) {
    const at = ref.kind === "trip" ? next.modifiedAt
      : ref.kind === "day" ? (next.days.find((d) => d.id === ref.id)?.modifiedAt ?? now)
      : (next.items.find((i) => i.id === ref.id)?.modifiedAt ?? now);
    outbox.enqueue({ kind: ref.kind, id: ref.id, tripId: next.id, op: "upsert", modifiedAt: at });
  }
  for (const ref of deletes) {
    outbox.enqueue({ kind: ref.kind, id: ref.id, tripId: next.id, op: "delete", modifiedAt: now });
    s.tombstones.set(ref.id, now);
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd webapp && npm test`
Expected: PASS (3 new + 32 = 35).

- [ ] **Step 5: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/sync/tripSync.ts webapp/src/sync/tripSync.test.ts
git commit -m "feat(web): trip-level applyPull + capture"
```

---

### Task 5: A→B round-trip integration test (TS)

**Files:**
- Test: `webapp/src/sync/tripRoundTrip.test.ts`

Mirrors the Swift `SyncRoundTripTests`: device A captures a trip+day+item and
pushes record `fields` built via `recordFields`; device B pulls and converges.

- [ ] **Step 1: Write the test**

Create `webapp/src/sync/tripRoundTrip.test.ts`:
```ts
import { test, expect } from "vitest";
import { Outbox } from "./outbox";
import { FakeRemoteBackend } from "./remoteSyncBackend";
import { capture, applyPull, type TripState } from "./tripSync";
import { recordFields } from "./tripMapping";
import { newTrip } from "../model/trip";
import type { SyncRecord } from "./types";

test("A's trip+day+item converge onto B", async () => {
  const tripId = "00000000-0000-0000-0000-0000000000f1";
  const backend = new FakeRemoteBackend();

  // Device A
  const a: TripState = { trips: new Map(), tombstones: new Map(), cursor: 0 };
  const t = newTrip({ id: tripId, name: "China", modifiedAt: 5 });
  t.days.push({ id: "d1", date: 0, city: "Shanghai", title: "Arrive", modifiedAt: 5 });
  t.items.push({ id: "i1", kind: "prep", label: "Passport", notes: "", isDone: false, sortOrder: 0, modifiedAt: 5 });
  a.trips.set(tripId, t);
  const box = new Outbox();
  capture(undefined, t, box, a, 5);
  for (const c of [...box.pending]) {
    const rec: SyncRecord = c.op === "delete"
      ? { kind: c.kind, id: c.id, tripId: c.tripId, modifiedAt: c.modifiedAt, deleted: true }
      : { kind: c.kind, id: c.id, tripId: c.tripId, modifiedAt: c.modifiedAt, deleted: false,
          fields: recordFields(c.kind, c.id, a.trips) };
    await backend.send([rec]);
    box.acknowledge(c);
  }

  // Device B
  const b: TripState = { trips: new Map(), tombstones: new Map(), cursor: 0 };
  const page = await backend.changes(0);
  applyPull(page.records, page.cursor, b);

  const bt = b.trips.get(tripId)!;
  expect(bt.name).toBe("China");
  expect(bt.days[0].city).toBe("Shanghai");
  expect(bt.items[0].label).toBe("Passport");
});
```

- [ ] **Step 2: Run + build, then commit**

Run:
```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
npm test
npm run build
```
Expected: PASS (1 new + 35 = 36); build succeeds.
```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/sync/tripRoundTrip.test.ts
git commit -m "test(web): A-push to B-pull trip round-trip convergence"
```

---

## Done criteria

- `cd webapp && npm test` passes (26 from 4a + new domain/mapping/diff/engine/round-trip).
- `npm run build` succeeds.
- The web engine now has a full `Trip` aggregate matching the Swift model and
  mapping, ready to plug a real backend + store under.
- Next: **4c** — `@supabase/supabase-js` backend (PostgREST + Realtime),
  email/Apple/Google auth, IndexedDB persistence, and a coordinator wiring
  capture/push/pull (verify the supabase-js API against live docs first); then
  **4d** — the UI.

## Notes for 4c

- 4c reads the project URL + anon key from a web env (e.g. a `.env` consumed by
  Vite as `import.meta.env.VITE_SUPABASE_URL/ANON_KEY`); never commit real keys.
- Consider extending `sync-conformance.json` (or adding a mapping-conformance
  fixture) so the Swift and TS field mappings are also cross-checked, not just
  conflict resolution.
