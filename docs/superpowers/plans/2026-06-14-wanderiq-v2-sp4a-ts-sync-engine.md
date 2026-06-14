# WanderIQ v2 — Sub-project 4a: TypeScript Sync Engine + Conformance Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the pure sync engine (conflict resolution, outbox, record apply/push) to TypeScript in a new `webapp/` Vite project, and prove it agrees with the Swift engine by passing the **same `sync-conformance.json`** fixture under Vitest.

**Architecture:** A new `webapp/` directory (a Vite + TypeScript + Vitest project) is created alongside the untouched live `trip-webapp/` (the v1 family PWA). 4a ports only the *pure, domain-free* engine: value types, `ConflictResolver` (LWW), `Outbox` (coalescing), `SyncState`, a `RemoteSyncBackend` interface + in-memory fake, and a record-level `SyncEngine` (apply a list of `SyncRecord`s via the resolver; flush an outbox through a backend). Times are epoch numbers (the fixture's format). The Trip domain model, IndexedDB store, Supabase-JS backend, auth, and UI are sub-projects 4b/4c. The conformance test reads the canonical fixture at `../WanderIQKit/Tests/WanderIQKitTests/Fixtures/sync-conformance.json` so both engines run the identical file.

**Tech Stack:** Node 24 (installed), Vite, TypeScript, Vitest. No `@supabase/supabase-js` yet (4b).

**Spec:** design §8.2 (PWA: TS sync engine implementing §6), §6 (protocol), §10 (cross-engine conformance); protocol contract `2026-06-13-wanderiq-v2-sync-protocol.md`. Mirrors sub-project 2's Swift engine.

**Decision:** New `webapp/` dir; `trip-webapp/` (live v1 PWA) is left untouched and retired only once v2 web ships.

**Verification:** `cd webapp && npm test` (Vitest); `npm run build` (Vite produces static output).

---

### Task 1: Scaffold the `webapp/` Vite + TS + Vitest project

**Files:**
- Create: `webapp/package.json`, `webapp/tsconfig.json`, `webapp/vitest.config.ts`, `webapp/.gitignore`, `webapp/index.html`, `webapp/src/main.ts`

- [ ] **Step 1: Create package.json**

Create `webapp/package.json`:
```json
{
  "name": "wanderiq-web",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview",
    "test": "vitest run --passWithNoTests"
  },
  "devDependencies": {
    "typescript": "^5.5.0",
    "vite": "^5.4.0",
    "vitest": "^2.1.0"
  }
}
```

- [ ] **Step 2: Create tsconfig.json**

Create `webapp/tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "noEmit": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "resolveJsonModule": true,
    "skipLibCheck": true,
    "types": ["vitest/globals"]
  },
  "include": ["src", "*.config.ts"]
}
```

- [ ] **Step 3: Create vitest + a minimal app entry**

Create `webapp/vitest.config.ts`:
```ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: { globals: true, environment: "node" },
});
```
Create `webapp/index.html`:
```html
<!doctype html>
<html lang="en">
  <head><meta charset="UTF-8" /><title>WanderIQ</title></head>
  <body><div id="app"></div><script type="module" src="/src/main.ts"></script></body>
</html>
```
Create `webapp/src/main.ts`:
```ts
// UI bootstrap arrives in sub-project 4c.
document.getElementById("app")!.textContent = "WanderIQ";
```
Create `webapp/.gitignore`:
```
node_modules/
dist/
```

- [ ] **Step 4: Install and verify the toolchain**

Run:
```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
npm install
npm test    # vitest run — passes with no test files yet (or "no tests")
npm run build
```
Expected: install succeeds; `vitest run` exits 0 (no failures); `vite build` produces `dist/`.

- [ ] **Step 5: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/package.json webapp/tsconfig.json webapp/vitest.config.ts webapp/.gitignore webapp/index.html webapp/src/main.ts webapp/package-lock.json
git commit -m "chore(web): scaffold Vite + TS + Vitest webapp project"
```

---

### Task 2: Sync value types (TS, TDD)

**Files:**
- Create: `webapp/src/sync/types.ts`
- Test: `webapp/src/sync/types.test.ts`

- [ ] **Step 1: Write the failing test**

Create `webapp/src/sync/types.test.ts`:
```ts
import { test, expect } from "vitest";
import { entityKey, type PendingChange } from "./types";

test("entityKey is stable per (kind,id), independent of op/time", () => {
  const a: PendingChange = { kind: "item", id: "x", tripId: "t", op: "upsert", modifiedAt: 1 };
  const b: PendingChange = { kind: "item", id: "x", tripId: "t2", op: "delete", modifiedAt: 2 };
  expect(entityKey(a)).toBe(entityKey(b));
});

test("different kind, same id → distinct keys", () => {
  expect(entityKey({ kind: "day", id: "x", tripId: "t", op: "upsert", modifiedAt: 1 }))
    .not.toBe(entityKey({ kind: "item", id: "x", tripId: "t", op: "upsert", modifiedAt: 1 }));
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd webapp && npm test`
Expected: FAIL — cannot resolve `./types`.

- [ ] **Step 3: Write the types**

Create `webapp/src/sync/types.ts`:
```ts
export type EntityKind = "trip" | "day" | "item";
export type SyncOp = "upsert" | "delete";

/** Times are epoch numbers (seconds), matching the conformance fixture. */
export interface PendingChange {
  kind: EntityKind;
  id: string;
  tripId: string;
  op: SyncOp;
  modifiedAt: number;
}

export interface SyncRecord {
  kind: EntityKind;
  id: string;
  tripId: string;
  modifiedAt: number;
  deleted: boolean;
  fields?: Record<string, string>;
}

/** Stable coalescing key: one pending change per (kind, id). */
export function entityKey(c: { kind: EntityKind; id: string }): string {
  return `${c.kind}:${c.id}`;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd webapp && npm test`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/sync/types.ts webapp/src/sync/types.test.ts
git commit -m "feat(web): sync value types"
```

---

### Task 3: ConflictResolver (TS, TDD — mirrors the Swift rules exactly)

**Files:**
- Create: `webapp/src/sync/conflictResolver.ts`
- Test: `webapp/src/sync/conflictResolver.test.ts`

- [ ] **Step 1: Write the failing test (the 8 rules)**

Create `webapp/src/sync/conflictResolver.test.ts`:
```ts
import { test, expect } from "vitest";
import { resolve } from "./conflictResolver";

test("remote upsert newer applies", () =>
  expect(resolve(1, null, 2, false)).toBe("applyRemote"));
test("remote upsert older kept", () =>
  expect(resolve(2, null, 1, false)).toBe("keepLocal"));
test("tie keeps local", () =>
  expect(resolve(2, null, 2, false)).toBe("keepLocal"));
test("remote delete newer than local edit applies", () =>
  expect(resolve(1, null, 2, true)).toBe("applyRemote"));
test("local edit newer than remote delete kept", () =>
  expect(resolve(3, null, 2, true)).toBe("keepLocal"));
test("local tombstone ties remote upsert → stays deleted", () =>
  expect(resolve(null, 2, 2, false)).toBe("keepLocal"));
test("remote upsert newer than tombstone resurrects", () =>
  expect(resolve(null, 1, 2, false)).toBe("applyRemote"));
test("unknown entity remote upsert applies", () =>
  expect(resolve(null, null, 1, false)).toBe("applyRemote"));
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd webapp && npm test`
Expected: FAIL — cannot resolve `./conflictResolver`.

- [ ] **Step 3: Write the resolver (mirror of Swift ConflictResolver)**

Create `webapp/src/sync/conflictResolver.ts`:
```ts
export type Decision = "applyRemote" | "keepLocal";

/**
 * Pure whole-record last-writer-wins (protocol §"Pull"). Mirrors the Swift
 * ConflictResolver exactly so both engines pass sync-conformance.json.
 * Times are epoch numbers; null means "absent".
 */
export function resolve(
  localModifiedAt: number | null,
  tombstone: number | null,
  remoteModifiedAt: number,
  remoteDeleted: boolean,
): Decision {
  if (remoteDeleted) {
    if (localModifiedAt !== null && localModifiedAt > remoteModifiedAt) return "keepLocal";
    return "applyRemote";
  }
  if (tombstone !== null && tombstone >= remoteModifiedAt) return "keepLocal";
  if (localModifiedAt !== null && localModifiedAt >= remoteModifiedAt) return "keepLocal";
  return "applyRemote";
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd webapp && npm test`
Expected: PASS (8 resolver tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/sync/conflictResolver.ts webapp/src/sync/conflictResolver.test.ts
git commit -m "feat(web): last-writer-wins conflict resolver"
```

---

### Task 4: Outbox (TS, TDD)

**Files:**
- Create: `webapp/src/sync/outbox.ts`
- Test: `webapp/src/sync/outbox.test.ts`

- [ ] **Step 1: Write the failing test**

Create `webapp/src/sync/outbox.test.ts`:
```ts
import { test, expect } from "vitest";
import { Outbox } from "./outbox";

test("enqueue coalesces by key, keeping latest", () => {
  const box = new Outbox();
  box.enqueue({ kind: "item", id: "a", tripId: "t", op: "upsert", modifiedAt: 1 });
  box.enqueue({ kind: "item", id: "a", tripId: "t", op: "delete", modifiedAt: 2 });
  expect(box.pending.length).toBe(1);
  expect(box.pending[0].op).toBe("delete");
});

test("pending preserves insertion order across keys", () => {
  const box = new Outbox();
  box.enqueue({ kind: "day", id: "a", tripId: "t", op: "upsert", modifiedAt: 1 });
  box.enqueue({ kind: "item", id: "b", tripId: "t", op: "upsert", modifiedAt: 1 });
  expect(box.pending.map((c) => c.id)).toEqual(["a", "b"]);
});

test("acknowledge removes only the matching key", () => {
  const box = new Outbox();
  box.enqueue({ kind: "day", id: "a", tripId: "t", op: "upsert", modifiedAt: 1 });
  box.enqueue({ kind: "day", id: "b", tripId: "t", op: "upsert", modifiedAt: 1 });
  box.acknowledge({ kind: "day", id: "a" });
  expect(box.pending.map((c) => c.id)).toEqual(["b"]);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd webapp && npm test`
Expected: FAIL — cannot resolve `./outbox`.

- [ ] **Step 3: Write the outbox**

Create `webapp/src/sync/outbox.ts`:
```ts
import { entityKey, type EntityKind, type PendingChange } from "./types";

/** Insertion-ordered, key-coalesced pending changes (protocol §"Outbox"). */
export class Outbox {
  private order: string[] = [];
  private byKey = new Map<string, PendingChange>();

  get pending(): PendingChange[] {
    return this.order.map((k) => this.byKey.get(k)!).filter(Boolean);
  }
  get isEmpty(): boolean {
    return this.byKey.size === 0;
  }

  enqueue(change: PendingChange): void {
    const key = entityKey(change);
    if (!this.byKey.has(key)) this.order.push(key);
    this.byKey.set(key, change);
  }

  acknowledge(ref: { kind: EntityKind; id: string }): void {
    const key = entityKey(ref);
    this.byKey.delete(key);
    this.order = this.order.filter((k) => k !== key);
  }

  toJSON(): PendingChange[] {
    return this.pending;
  }
  static fromJSON(list: PendingChange[]): Outbox {
    const box = new Outbox();
    for (const c of list) box.enqueue(c);
    return box;
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd webapp && npm test`
Expected: PASS (3 outbox tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/sync/outbox.ts webapp/src/sync/outbox.test.ts
git commit -m "feat(web): coalescing outbox"
```

---

### Task 5: RemoteSyncBackend interface + in-memory fake (TS, TDD)

**Files:**
- Create: `webapp/src/sync/remoteSyncBackend.ts`
- Test: `webapp/src/sync/remoteSyncBackend.test.ts`

- [ ] **Step 1: Write the failing test**

Create `webapp/src/sync/remoteSyncBackend.test.ts`:
```ts
import { test, expect } from "vitest";
import { FakeRemoteBackend } from "./remoteSyncBackend";

test("push then pull returns records after cursor", async () => {
  const backend = new FakeRemoteBackend();
  await backend.send([{ kind: "item", id: "i", tripId: "t", modifiedAt: 5, deleted: false, fields: { label: "X" } }]);
  const page = await backend.changes(0);
  expect(page.records.length).toBe(1);
  expect(page.cursor).toBeGreaterThan(0);
  const empty = await backend.changes(page.cursor);
  expect(empty.records.length).toBe(0);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd webapp && npm test`
Expected: FAIL — cannot resolve `./remoteSyncBackend`.

- [ ] **Step 3: Write the interface + fake**

Create `webapp/src/sync/remoteSyncBackend.ts`:
```ts
import { entityKey, type SyncRecord } from "./types";

export interface ChangePage {
  records: SyncRecord[];
  cursor: number;
}

/** Transport abstraction. The Supabase implementation arrives in 4b. */
export interface RemoteSyncBackend {
  send(records: SyncRecord[]): Promise<void>;
  changes(since: number): Promise<ChangePage>;
}

/** In-memory backend for tests; monotonic server clock models server_updated_at. */
export class FakeRemoteBackend implements RemoteSyncBackend {
  private stored = new Map<string, { record: SyncRecord; serverAt: number }>();
  private clock = 0;

  async send(records: SyncRecord[]): Promise<void> {
    for (const r of records) {
      this.clock += 1;
      this.stored.set(entityKey(r), { record: r, serverAt: this.clock });
    }
  }

  async changes(since: number): Promise<ChangePage> {
    const fresh = [...this.stored.values()]
      .filter((e) => e.serverAt > since)
      .sort((a, b) => a.serverAt - b.serverAt);
    const cursor = fresh.length ? fresh[fresh.length - 1].serverAt : since;
    return { records: fresh.map((e) => e.record), cursor };
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd webapp && npm test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/sync/remoteSyncBackend.ts webapp/src/sync/remoteSyncBackend.test.ts
git commit -m "feat(web): RemoteSyncBackend interface and in-memory fake"
```

---

### Task 6: Record-level apply/push + push driver (TS, TDD)

**Files:**
- Create: `webapp/src/sync/syncEngine.ts`
- Test: `webapp/src/sync/syncEngine.test.ts`

A record-level engine: `applyRecords` reduces a list of remote records into a
local record map (keyed by entityKey) + tombstones using the resolver;
`pushAll` flushes an outbox of records through a backend. (Trip-model apply and
diff-capture arrive in 4b/4c with the domain model.)

- [ ] **Step 1: Write the failing test**

Create `webapp/src/sync/syncEngine.test.ts`:
```ts
import { test, expect } from "vitest";
import { applyRecords, pushAll, type LocalState } from "./syncEngine";
import { Outbox } from "./outbox";
import { FakeRemoteBackend } from "./remoteSyncBackend";
import type { SyncRecord } from "./types";

function emptyState(): LocalState {
  return { records: new Map(), tombstones: new Map(), cursor: 0 };
}

test("applyRecords applies newer upsert and advances cursor", () => {
  const s = emptyState();
  const rec: SyncRecord = { kind: "item", id: "i", tripId: "t", modifiedAt: 5, deleted: false, fields: { label: "X" } };
  applyRecords([rec], 9, s);
  expect(s.records.get("item:i")?.fields?.label).toBe("X");
  expect(s.cursor).toBe(9);
});

test("applyRecords honors a remote tombstone", () => {
  const s = emptyState();
  s.records.set("item:i", { kind: "item", id: "i", tripId: "t", modifiedAt: 1, deleted: false, fields: {} });
  applyRecords([{ kind: "item", id: "i", tripId: "t", modifiedAt: 2, deleted: true }], 9, s);
  expect(s.records.has("item:i")).toBe(false);
  expect(s.tombstones.get("i")).toBe(2);
});

test("pushAll sends pending records and clears the outbox", async () => {
  const box = new Outbox();
  box.enqueue({ kind: "item", id: "i", tripId: "t", op: "upsert", modifiedAt: 3 });
  const records = new Map<string, SyncRecord>([
    ["item:i", { kind: "item", id: "i", tripId: "t", modifiedAt: 3, deleted: false, fields: { label: "Buy" } }],
  ]);
  const backend = new FakeRemoteBackend();
  await pushAll(box, records, backend);
  expect(box.isEmpty).toBe(true);
  const page = await backend.changes(0);
  expect(page.records[0].fields?.label).toBe("Buy");
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd webapp && npm test`
Expected: FAIL — cannot resolve `./syncEngine`.

- [ ] **Step 3: Write the engine**

Create `webapp/src/sync/syncEngine.ts`:
```ts
import { resolve } from "./conflictResolver";
import { entityKey, type SyncRecord } from "./types";
import type { Outbox } from "./outbox";
import type { RemoteSyncBackend } from "./remoteSyncBackend";

/** Record-level local mirror, keyed by entityKey. */
export interface LocalState {
  records: Map<string, SyncRecord>;
  tombstones: Map<string, number>; // id -> deletedAt
  cursor: number;
}

/** Apply a page of remote records via LWW, then advance the cursor. */
export function applyRecords(records: SyncRecord[], cursor: number, s: LocalState): void {
  for (const r of records) {
    const key = entityKey(r);
    const local = s.records.get(key);
    const decision = resolve(
      local ? local.modifiedAt : null,
      s.tombstones.get(r.id) ?? null,
      r.modifiedAt,
      r.deleted,
    );
    if (decision !== "applyRemote") continue;
    if (r.deleted) {
      s.records.delete(key);
      s.tombstones.set(r.id, r.modifiedAt);
    } else {
      s.records.set(key, r);
      s.tombstones.delete(r.id);
    }
  }
  s.cursor = Math.max(s.cursor, cursor);
}

/** Flush the outbox oldest-first, sending each record from `records`. */
export async function pushAll(
  outbox: Outbox,
  records: Map<string, SyncRecord>,
  backend: RemoteSyncBackend,
): Promise<void> {
  for (const change of [...outbox.pending]) {
    const key = entityKey(change);
    const record: SyncRecord =
      change.op === "delete"
        ? { kind: change.kind, id: change.id, tripId: change.tripId, modifiedAt: change.modifiedAt, deleted: true }
        : records.get(key) ?? {
            kind: change.kind, id: change.id, tripId: change.tripId,
            modifiedAt: change.modifiedAt, deleted: false, fields: {},
          };
    await backend.send([record]);
    outbox.acknowledge(change);
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd webapp && npm test`
Expected: PASS (3 engine tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/sync/syncEngine.ts webapp/src/sync/syncEngine.test.ts
git commit -m "feat(web): record-level apply + push driver"
```

---

### Task 7: Cross-engine conformance (reads the SHARED fixture)

**Files:**
- Create: `webapp/src/sync/conformance.test.ts`

This is the payoff: the TS resolver runs the identical scenarios the Swift
engine passes, from the one canonical fixture file.

- [ ] **Step 1: Write the conformance test against the shared fixture**

Create `webapp/src/sync/conformance.test.ts`:
```ts
import { test, expect } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { resolve as resolvePath, dirname } from "node:path";
import { resolve as resolveConflict, type Decision } from "./conflictResolver";

interface Scenario {
  name: string;
  localModifiedAt: number | null;
  tombstone: number | null;
  remoteModifiedAt: number;
  remoteDeleted: boolean;
  expect: Decision;
}

// Canonical fixture shared with the Swift engine (sub-project 2).
const fixturePath = resolvePath(
  dirname(fileURLToPath(import.meta.url)),
  "../../../WanderIQKit/Tests/WanderIQKitTests/Fixtures/sync-conformance.json",
);
const scenarios: Scenario[] = JSON.parse(readFileSync(fixturePath, "utf8")).scenarios;

test("the shared conformance fixture is non-empty", () => {
  expect(scenarios.length).toBeGreaterThan(0);
});

test.each(scenarios)("conformance: $name", (s) => {
  expect(resolveConflict(s.localModifiedAt, s.tombstone, s.remoteModifiedAt, s.remoteDeleted))
    .toBe(s.expect);
});
```

- [ ] **Step 2: Run to verify it passes**

Run: `cd webapp && npm test`
Expected: PASS — all 8 shared scenarios green (plus the non-empty guard).
If the path can't be resolved, confirm the relative depth from
`webapp/src/sync/` to repo root is `../../../`.

- [ ] **Step 3: Final full run + build, then commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
npm test
npm run build
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/sync/conformance.test.ts
git commit -m "test(web): cross-engine conformance against the shared Swift fixture"
```

---

## Done criteria

- `cd webapp && npm test` passes: types, resolver, outbox, fake backend, engine,
  and the shared-fixture conformance (8 scenarios identical to Swift).
- `npm run build` produces static output (Vite).
- `trip-webapp/` (v1 PWA) is untouched.
- Next: **4b** — Supabase-JS backend (PostgREST + Realtime), email/Apple/Google
  auth, IndexedDB local store, the Trip domain model + Trip-level apply/diff;
  then **4c** — the UI (prep/itinerary/packing) and PWA install.

## Notes for 4b/4c

- 4b adds the Trip domain model + a Trip-level apply (mapping SyncRecord.fields
  ↔ model) and diff-capture, mirroring the Swift SyncMapping/TripDiff, plus the
  Supabase-JS `RemoteSyncBackend` implementation and IndexedDB persistence.
- The shared fixture only covers `ConflictResolver`; if 4b ports more pure logic
  (e.g. field mapping), consider extending the fixture so both engines cover it.
