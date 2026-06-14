# WanderIQ v2 — Sub-project 4c: Supabase-JS Backend + Auth + IndexedDB + Coordinator

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the web sync engine (4a/4b) its cloud: a `@supabase/supabase-js` `RemoteSyncBackend` (PostgREST + Realtime), email/Apple/Google auth, IndexedDB persistence, and a coordinator wiring capture/push/pull — the web twin of iOS sub-projects 3a+3b+3c.

**Architecture:** In `webapp/`. Pure + TDD: the **row mapping** (Postgres row ⇄ `SyncRecord`, converting ISO↔epoch dates) and the **IndexedDB store** (via `fake-indexeddb` in Vitest). Build-verified integration: the supabase-js `SupabaseBackend` (implements 4a's `RemoteSyncBackend`), a `WebAuth` controller, and a `WebSyncCoordinator`. Runtime (real auth, sync, Realtime) is verified in a browser after 4d adds the UI — there is no UI in 4c, so 4c ends build-green + unit-green, not runtime-verified.

**Tech Stack:** `@supabase/supabase-js` (dep), `idb` (typed IndexedDB wrapper, dep), `fake-indexeddb` (devDep, tests), Vite env (`import.meta.env.VITE_SUPABASE_*`).

**Spec:** design §8.2; §6; web twin of iOS `SupabaseRowMapping`(3a)/`AuthController`(3b)/`SupabaseSyncCoordinator`(3c). Verified supabase-js v2 API in the plan body.

**Prerequisite (USER):** create `webapp/.env` (gitignored) with `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` (the public anon key — same project as iOS). Only Task 7 (build that bundles env) and any runtime need it; Tasks 2 & 4 (pure) don't.

**Cross-reference:** iOS `SupabaseRowMapping` (3a) currently emits epoch-seconds strings for date columns — a deferred bug (its review's Minor #2). 4c does the ISO↔epoch conversion correctly; iOS 3a should be aligned when its 3c runtime verification surfaces it.

**Verification:** `cd webapp && npm test` (36 from 4b + new) and `npm run build`.

---

### Task 1: Dependencies + Vite env + Supabase client

**Files:**
- Modify: `webapp/package.json`
- Create: `webapp/src/supabase/client.ts`, `webapp/.env.example`, `webapp/src/env.d.ts`
- Modify: `webapp/.gitignore`

- [ ] **Step 1: Add dependencies**

Run:
```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
npm install @supabase/supabase-js idb
npm install -D fake-indexeddb
```

- [ ] **Step 2: Env types + example + gitignore**

Create `webapp/src/env.d.ts`:
```ts
interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL: string;
  readonly VITE_SUPABASE_ANON_KEY: string;
}
interface ImportMeta {
  readonly env: ImportMetaEnv;
}
```
Create `webapp/.env.example`:
```
VITE_SUPABASE_URL=https://YOUR-REF.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-public-key
```
Append to `webapp/.gitignore`:
```
.env
.env.*
!.env.example
```

- [ ] **Step 3: Supabase client singleton**

Create `webapp/src/supabase/client.ts`:
```ts
import { createClient } from "@supabase/supabase-js";

/** Single app-wide Supabase client (auth + data share it). */
export const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_ANON_KEY,
);
```

- [ ] **Step 4: Verify install + build (build needs a .env; create a placeholder if absent)**

Run:
```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
[ -f .env ] || cp .env.example .env   # placeholder values are fine for build-only
npm test
npm run build
```
Expected: install ok; `npm test` still 36 (no test changes); `npm run build` succeeds (env vars are inlined by Vite; placeholder values compile fine).

- [ ] **Step 5: Commit (NOT .env)**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/package.json webapp/package-lock.json webapp/src/supabase/client.ts webapp/.env.example webapp/src/env.d.ts webapp/.gitignore
git commit -m "chore(web): add supabase-js + idb deps, env config, client"
```

---

### Task 2: Postgres row mapping (SyncRecord ⇄ row, ISO↔epoch) — pure, TDD

**Files:**
- Create: `webapp/src/supabase/rowMapping.ts`
- Test: `webapp/src/supabase/rowMapping.test.ts`

Converts between Postgres rows (snake_case columns; `date`/`timestamptz` as ISO
strings) and `SyncRecord` (epoch-number `modifiedAt`; `fields` epoch-number
strings that 4b's `tripMapping` consumes). This is the web twin of iOS 3a's
`SupabaseRowMapping`, done with correct date conversion.

- [ ] **Step 1: Write the failing test**

Create `webapp/src/supabase/rowMapping.test.ts`:
```ts
import { test, expect } from "vitest";
import { recordToRow, rowToRecord } from "./rowMapping";
import type { SyncRecord } from "../sync/types";

const ISO = "2026-06-14T00:00:05.000Z";
const EPOCH = Math.floor(Date.parse(ISO) / 1000); // seconds

test("rowToRecord: item row → SyncRecord with epoch modifiedAt + string fields", () => {
  const row = {
    id: "i1", trip_id: "t1", kind: "prep", label: "Buy", notes: "", day_id: null,
    time: "09:30", item_owner: "Mom", is_done: true, sort_order: 2, reminder_date: null,
    place: { name: "Museum", query: "M", latitude: 31.2, longitude: 121.0 },
    modified_at: ISO, deleted: false,
  };
  const rec = rowToRecord("item", row);
  expect(rec.modifiedAt).toBe(EPOCH);
  expect(rec.deleted).toBe(false);
  expect(rec.fields?.label).toBe("Buy");
  expect(rec.fields?.isDone).toBe("true");
  expect(rec.fields?.sortOrder).toBe("2");
  expect(rec.fields?.placeName).toBe("Museum");
  expect(rec.fields?.placeLat).toBe("31.2");
});

test("rowToRecord: trip date column (ISO date) → epoch-seconds string field", () => {
  const row = { id: "t1", owner_id: "u", name: "China", start_date: "2026-07-11",
    end_date: "2026-07-31", destinations: ["SH", "HK"], schema_version: 1,
    modified_at: ISO, deleted: false };
  const rec = rowToRecord("trip", row);
  expect(rec.fields?.name).toBe("China");
  expect(rec.fields?.startDate).toBe(String(Math.floor(Date.parse("2026-07-11") / 1000)));
  expect(rec.fields?.destinations).toBe("SH\u{1f}HK");
});

test("recordToRow: trip SyncRecord → row with ISO dates and owner_id injected", () => {
  const rec: SyncRecord = { kind: "trip", id: "t1", tripId: "t1", modifiedAt: EPOCH, deleted: false,
    fields: { name: "China", startDate: String(Math.floor(Date.parse("2026-07-11") / 1000)),
      endDate: "0", destinations: "SH\u{1f}HK", schemaVersion: "1" } };
  const row = recordToRow(rec, "user-123") as Record<string, unknown>;
  expect(row.id).toBe("t1");
  expect(row.owner_id).toBe("user-123");
  expect(row.name).toBe("China");
  expect(row.start_date).toBe("2026-07-11");
  expect(row.destinations).toEqual(["SH", "HK"]);
  expect(row.modified_at).toBe(ISO);
  expect(row.deleted).toBe(false);
});

test("recordToRow: tombstone → minimal deleted row", () => {
  const rec: SyncRecord = { kind: "item", id: "i1", tripId: "t1", modifiedAt: EPOCH, deleted: true };
  const row = recordToRow(rec, "user-123") as Record<string, unknown>;
  expect(row.id).toBe("i1");
  expect(row.trip_id).toBe("t1");
  expect(row.deleted).toBe(true);
  expect(row.modified_at).toBe(ISO);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd webapp && npm test`
Expected: FAIL — cannot resolve `./rowMapping`.

- [ ] **Step 3: Write the mapping**

Create `webapp/src/supabase/rowMapping.ts`:
```ts
import type { EntityKind, SyncRecord } from "../sync/types";

const SEP = "\u{1f}";
const isoToEpoch = (s: string | null): number => (s ? Math.floor(Date.parse(s) / 1000) : 0);
const epochToISO = (e: number): string => new Date(e * 1000).toISOString();
// Postgres `date` columns are date-only; emit YYYY-MM-DD.
const epochToDate = (e: number): string => new Date(e * 1000).toISOString().slice(0, 10);

/** A Postgres row as returned by supabase-js (loose: columns vary by table). */
export type Row = Record<string, unknown>;

/** Pull side: Postgres row → SyncRecord (fields are epoch-number strings). */
export function rowToRecord(kind: EntityKind, row: Row): SyncRecord {
  const id = String(row.id);
  const tripId = kind === "trip" ? id : String(row.trip_id);
  const modifiedAt = isoToEpoch(row.modified_at as string | null);
  const deleted = Boolean(row.deleted);
  if (deleted) return { kind, id, tripId, modifiedAt, deleted: true };

  let fields: Record<string, string> = {};
  if (kind === "trip") {
    fields = {
      name: String(row.name ?? ""),
      startDate: String(isoToEpoch(row.start_date as string | null)),
      endDate: String(isoToEpoch(row.end_date as string | null)),
      destinations: ((row.destinations as string[] | null) ?? []).join(SEP),
      schemaVersion: String((row.schema_version as number | null) ?? 1),
    };
  } else if (kind === "day") {
    fields = {
      date: String(isoToEpoch(row.date as string | null)),
      city: String(row.city ?? ""),
      title: String(row.title ?? ""),
    };
  } else {
    fields = {
      kind: String(row.kind ?? "prep"),
      label: String(row.label ?? ""),
      notes: String(row.notes ?? ""),
      isDone: row.is_done ? "true" : "false",
      sortOrder: String((row.sort_order as number | null) ?? 0),
    };
    if (row.day_id != null) fields.dayID = String(row.day_id);
    if (row.time != null) fields.time = String(row.time);
    if (row.item_owner != null) fields.owner = String(row.item_owner);
    if (row.reminder_date != null) fields.reminderDate = String(isoToEpoch(row.reminder_date as string));
    const place = row.place as { name: string; query: string; latitude?: number; longitude?: number } | null;
    if (place) {
      fields.placeName = place.name; fields.placeQuery = place.query;
      if (place.latitude != null) fields.placeLat = String(place.latitude);
      if (place.longitude != null) fields.placeLon = String(place.longitude);
    }
  }
  return { kind, id, tripId, modifiedAt, deleted: false, fields };
}

/** Push side: SyncRecord → Postgres row. `ownerId` is injected on trip rows. */
export function recordToRow(rec: SyncRecord, ownerId: string): Row {
  const base: Row = { id: rec.id, modified_at: epochToISO(rec.modifiedAt), deleted: rec.deleted };
  if (rec.kind !== "trip") base.trip_id = rec.tripId;
  if (rec.kind === "trip") base.owner_id = ownerId;
  if (rec.deleted) return base;

  const f = rec.fields ?? {};
  const numF = (k: string): number => Number(f[k] ?? "0");
  if (rec.kind === "trip") {
    base.name = f.name ?? "";
    base.start_date = epochToDate(numF("startDate"));
    base.end_date = epochToDate(numF("endDate"));
    base.destinations = f.destinations ? f.destinations.split(SEP) : [];
    base.schema_version = Number(f.schemaVersion ?? "1");
  } else if (rec.kind === "day") {
    base.date = epochToDate(numF("date"));
    base.city = f.city ?? "";
    base.title = f.title ?? "";
  } else {
    base.kind = f.kind ?? "prep";
    base.label = f.label ?? "";
    base.notes = f.notes ?? "";
    base.is_done = f.isDone === "true";
    base.sort_order = numF("sortOrder");
    base.day_id = f.dayID ?? null;
    base.time = f.time ?? null;
    base.item_owner = f.owner ?? null;
    base.reminder_date = f.reminderDate ? epochToISO(numF("reminderDate")) : null;
    base.place = f.placeName
      ? { name: f.placeName, query: f.placeQuery ?? "",
          latitude: f.placeLat ? Number(f.placeLat) : null,
          longitude: f.placeLon ? Number(f.placeLon) : null }
      : null;
  }
  return base;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd webapp && npm test`
Expected: PASS (4 new + 36 = 40).

- [ ] **Step 5: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/supabase/rowMapping.ts webapp/src/supabase/rowMapping.test.ts
git commit -m "feat(web): Postgres row <-> SyncRecord mapping (ISO<->epoch)"
```

---

### Task 3: SupabaseBackend (implements RemoteSyncBackend) — build-verified

**Files:**
- Create: `webapp/src/supabase/supabaseBackend.ts`

- [ ] **Step 1: Write the backend**

Create `webapp/src/supabase/supabaseBackend.ts`:
```ts
import type { SupabaseClient } from "@supabase/supabase-js";
import type { ChangePage, RemoteSyncBackend } from "../sync/remoteSyncBackend";
import type { EntityKind, SyncRecord } from "../sync/types";
import { recordToRow, rowToRecord, type Row } from "./rowMapping";

const TABLE: Record<EntityKind, string> = { trip: "trips", day: "trip_days", item: "trip_items" };

/** RemoteSyncBackend over Supabase PostgREST. server_updated_at drives the cursor. */
export class SupabaseBackend implements RemoteSyncBackend {
  constructor(private readonly client: SupabaseClient) {}

  async send(records: SyncRecord[]): Promise<void> {
    const { data } = await this.client.auth.getUser();
    const ownerId = data.user?.id ?? "";
    for (const kind of ["trip", "day", "item"] as EntityKind[]) {
      const rows = records.filter((r) => r.kind === kind).map((r) => recordToRow(r, ownerId));
      if (rows.length === 0) continue;
      const { error } = await this.client.from(TABLE[kind]).upsert(rows, { onConflict: "id" });
      if (error) throw error;
    }
  }

  async changes(since: number): Promise<ChangePage> {
    const sinceISO = new Date(since * 1000).toISOString();
    const records: SyncRecord[] = [];
    let maxStamp = since;
    for (const kind of ["trip", "day", "item"] as EntityKind[]) {
      const { data, error } = await this.client.from(TABLE[kind]).select("*")
        .gt("server_updated_at", sinceISO).order("server_updated_at", { ascending: true });
      if (error) throw error;
      for (const row of (data ?? []) as Row[]) {
        records.push(rowToRecord(kind, row));
        const s = Math.floor(Date.parse(String(row.server_updated_at)) / 1000);
        if (s > maxStamp) maxStamp = s;
      }
    }
    return { records, cursor: maxStamp };
  }
}
```

- [ ] **Step 2: Build (no runtime — needs a browser + auth later)**

Run:
```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
npm run build
npm test
```
Expected: build succeeds; 40 tests still pass. If supabase-js types reject any
call (`.upsert`, `.gt`, `.order`, `.getUser`), report it — the API was verified
against v2 docs but adjust to the installed types if needed.

- [ ] **Step 3: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/supabase/supabaseBackend.ts
git commit -m "feat(web): SupabaseBackend (PostgREST push/pull)"
```

---

### Task 4: IndexedDB store (persist TripState + Outbox) — TDD via fake-indexeddb

**Files:**
- Create: `webapp/src/store/idbStore.ts`
- Test: `webapp/src/store/idbStore.test.ts`

Persists the serialized `TripState` (trips, tombstones, cursor) and the `Outbox`
pending list under fixed keys in one IndexedDB object store.

- [ ] **Step 1: Write the failing test**

Create `webapp/src/store/idbStore.test.ts`:
```ts
import { test, expect, beforeEach } from "vitest";
import "fake-indexeddb/auto";
import { IdbStore } from "./idbStore";
import { Outbox } from "../sync/outbox";

beforeEach(() => { indexedDB = new IDBFactory(); });

test("saves and loads outbox + cursor", async () => {
  const store = new IdbStore("test-db");
  const box = new Outbox();
  box.enqueue({ kind: "item", id: "i", tripId: "t", op: "upsert", modifiedAt: 3 });
  await store.save({ pending: box.toJSON(), tombstones: [["x", 7]], cursor: 9 });

  const loaded = await store.load();
  expect(loaded.pending.length).toBe(1);
  expect(loaded.cursor).toBe(9);
  expect(loaded.tombstones).toEqual([["x", 7]]);
});

test("load returns empty defaults on a fresh db", async () => {
  const loaded = await new IdbStore("fresh-db").load();
  expect(loaded.pending).toEqual([]);
  expect(loaded.cursor).toBe(0);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd webapp && npm test`
Expected: FAIL — cannot resolve `./idbStore`.

- [ ] **Step 3: Write the store**

Create `webapp/src/store/idbStore.ts`:
```ts
import { openDB, type IDBPDatabase } from "idb";
import type { PendingChange } from "../sync/types";

export interface PersistedState {
  pending: PendingChange[];
  tombstones: [string, number][]; // entries of Map<id, deletedAt>
  cursor: number;
}

const STORE = "sync";
const KEY = "state";

/** One-object-store IndexedDB persistence for the sync state + outbox. */
export class IdbStore {
  private dbp: Promise<IDBPDatabase>;
  constructor(name = "wanderiq") {
    this.dbp = openDB(name, 1, {
      upgrade(db) { db.createObjectStore(STORE); },
    });
  }

  async save(state: PersistedState): Promise<void> {
    (await this.dbp).put(STORE, state, KEY);
  }

  async load(): Promise<PersistedState> {
    const v = (await (await this.dbp).get(STORE, KEY)) as PersistedState | undefined;
    return v ?? { pending: [], tombstones: [], cursor: 0 };
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd webapp && npm test`
Expected: PASS (2 new + 40 = 42).

- [ ] **Step 5: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/store/idbStore.ts webapp/src/store/idbStore.test.ts
git commit -m "feat(web): IndexedDB persistence for sync state + outbox"
```

---

### Task 5: WebAuth controller — build-verified

**Files:**
- Create: `webapp/src/auth/webAuth.ts`

- [ ] **Step 1: Write the controller**

Create `webapp/src/auth/webAuth.ts`:
```ts
import type { Session } from "@supabase/supabase-js";
import { supabase } from "../supabase/client";

export type Phase = "loading" | "signedOut" | "signedIn";

/** Minimal observable auth wrapper (the UI in 4d subscribes to `onChange`). */
export class WebAuth {
  phase: Phase = "loading";
  email: string | null = null;
  private listeners = new Set<() => void>();

  constructor() {
    supabase.auth.getSession().then(({ data }) => this.apply(data.session));
    supabase.auth.onAuthStateChange((_event, session) => this.apply(session));
  }

  onChange(fn: () => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  get isSignedIn(): boolean { return this.phase === "signedIn"; }

  async signIn(email: string, password: string): Promise<string | null> {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    return error?.message ?? null;
  }
  async signUp(email: string, password: string): Promise<string | null> {
    const { error } = await supabase.auth.signUp({ email, password });
    return error?.message ?? null;
  }
  async signInWithGoogle(): Promise<void> {
    await supabase.auth.signInWithOAuth({ provider: "google",
      options: { redirectTo: window.location.origin } });
  }
  async signInWithApple(): Promise<void> {
    await supabase.auth.signInWithOAuth({ provider: "apple",
      options: { redirectTo: window.location.origin } });
  }
  async signOut(): Promise<void> { await supabase.auth.signOut(); }

  private apply(session: Session | null): void {
    this.phase = session ? "signedIn" : "signedOut";
    this.email = session?.user.email ?? null;
    this.listeners.forEach((fn) => fn());
  }
}
```

- [ ] **Step 2: Build + commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
npm run build && npm test
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/auth/webAuth.ts
git commit -m "feat(web): WebAuth controller (email/Google/Apple)"
```
Expected: build succeeds; 42 tests pass.

---

### Task 6: WebSyncCoordinator — build-verified

**Files:**
- Create: `webapp/src/sync/webSyncCoordinator.ts`

Ties together: a `TripState` (4b), `Outbox` (4a), `IdbStore` (T4),
`SupabaseBackend` (T3). Captures local trip edits, debounce-pushes, pulls on
start + Realtime. Auth-gated by the caller (only constructed/started when signed
in). The 4d UI drives `noteLocalChange` and renders `state.trips`.

- [ ] **Step 1: Write the coordinator**

Create `webapp/src/sync/webSyncCoordinator.ts`:
```ts
import { supabase } from "../supabase/client";
import { SupabaseBackend } from "../supabase/supabaseBackend";
import { IdbStore } from "../store/idbStore";
import { Outbox } from "./outbox";
import { applyPull, capture, type TripState } from "./tripSync";
import type { Trip } from "../model/trip";
import type { RemoteSyncBackend } from "./remoteSyncBackend";

export class WebSyncCoordinator {
  readonly state: TripState = { trips: new Map(), tombstones: new Map(), cursor: 0 };
  private outbox = new Outbox();
  private readonly backend: RemoteSyncBackend = new SupabaseBackend(supabase);
  private readonly store = new IdbStore();
  private pushTimer: ReturnType<typeof setTimeout> | undefined;

  /** Load persisted state, pull, and subscribe to Realtime. */
  async start(): Promise<void> {
    const p = await this.store.load();
    this.outbox = Outbox.fromJSON(p.pending);
    this.state.tombstones = new Map(p.tombstones);
    this.state.cursor = p.cursor;
    await this.fetchNow();
    this.subscribeRealtime();
  }

  noteLocalChange(old: Trip | undefined, next: Trip): void {
    capture(old, next, this.outbox, this.state, Math.floor(Date.now() / 1000));
    this.state.trips.set(next.id, next);
    void this.persist();
    this.schedulePush();
  }

  async fetchNow(): Promise<void> {
    const page = await this.backend.changes(this.state.cursor);
    applyPull(page.records, page.cursor, this.state);
    await this.persist();
  }

  private schedulePush(): void {
    clearTimeout(this.pushTimer);
    this.pushTimer = setTimeout(() => void this.flush(), 400);
  }

  private async flush(): Promise<void> {
    const pending = [...this.outbox.pending];
    if (pending.length === 0) return;
    // Build records from current trip state via the trip mapping path is done
    // by 4b's recordFields; here we send minimal records and let pull reconcile.
    const { recordFields } = await import("./tripMapping");
    for (const c of pending) {
      const fields = c.op === "delete" ? undefined : recordFields(c.kind, c.id, this.state.trips);
      await this.backend.send([{ kind: c.kind, id: c.id, tripId: c.tripId,
        modifiedAt: c.modifiedAt, deleted: c.op === "delete", fields }]);
      this.outbox.acknowledge(c);
    }
    await this.persist();
  }

  private subscribeRealtime(): void {
    supabase.channel("wanderiq-web")
      .on("postgres_changes", { event: "*", schema: "public", table: "trips" }, () => void this.fetchNow())
      .on("postgres_changes", { event: "*", schema: "public", table: "trip_days" }, () => void this.fetchNow())
      .on("postgres_changes", { event: "*", schema: "public", table: "trip_items" }, () => void this.fetchNow())
      .subscribe();
  }

  private persist(): Promise<void> {
    return this.store.save({ pending: this.outbox.toJSON(),
      tombstones: [...this.state.tombstones.entries()], cursor: this.state.cursor });
  }
}
```

> Note: the coordinator builds wire `fields` via 4b's `recordFields` (the single
> source of trip→fields mapping); `SupabaseBackend` then turns those into
> Postgres rows via `recordToRow`. The coordinator itself does not import
> `recordToRow` — keep the flush path going through `backend.send`.

- [ ] **Step 2: Build + test**

```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
npm run build
npm test
```
Expected: build succeeds (fix the noted unused import if `noUnusedLocals`
complains); 42 tests still pass.

- [ ] **Step 3: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/sync/webSyncCoordinator.ts
git commit -m "feat(web): WebSyncCoordinator (capture/push/pull/realtime)"
```

---

## Done criteria

- `cd webapp && npm test` passes (36 from 4b + rowMapping + idbStore = 42).
- `npm run build` succeeds with supabase-js, idb, auth, backend, coordinator.
- Pure layers (row mapping, IndexedDB store) are unit-tested; integration
  (backend, auth, coordinator) is build-verified. Real runtime (auth + sync +
  Realtime in a browser) is verified after 4d adds the UI.
- `webapp/.env` (anon key) gitignored; `.env.example` committed.
- Next: **4d** — the UI (prep/itinerary/packing views, auth screen, PWA
  manifest/service worker) wiring `WebAuth` + `WebSyncCoordinator`; then the
  browser end-to-end verification (and a possible Playwright smoke).

## Notes / risks

- The coordinator's `flush` reuses 4b's `recordFields` for the wire `fields`,
  which `SupabaseBackend.send` maps to Postgres rows via `recordToRow` — one
  mapping path, no duplication.
- Same push-reentrancy consideration as iOS 3c: `flush` snapshots `pending`
  first; revisit if edits during a flush need stronger guarantees.
- iOS 3a `SupabaseRowMapping` date format (epoch strings) should be reconciled
  with this correct ISO↔epoch mapping when iOS 3c is runtime-verified.
