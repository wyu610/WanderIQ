# WanderIQ v2 — Sub-project 6d: Web Import/Export UI (final v2 sub-project)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the 6b TS codec into the Preact UI — export the open trip as a JSON or CSV download, and import a JSON/CSV file as a new trip. The last sub-project of the v2 build.

**Architecture:** A small `webapp/src/ui/fileTransfer.ts` with two helpers: `download(filename, text, mime)` (Blob + a transient `<a download>`) and a PURE `tripFromImport(filename, text): Trip` that dispatches by extension (`.csv` → `importCSVItems` onto a `newTrip`; else `importJSON`). `tripFromImport` is unit-tested. `store.ts` gains `tripActions.importTrip(trip)` → `commit(trip)` (a new trip's `old` is undefined → captured as an insert, so it syncs). `TripDetailView` gets Export JSON/CSV buttons; `TripListView` gets an Import button backed by a hidden `<input type="file">`. **Import creates a NEW trip** (matches iOS 6c + the format's fresh-id import). UI wiring is build+browser verified; `tripFromImport` and the codec are unit-tested.

**Tech Stack:** Preact + signals, `preact/hooks` `useRef`, Vitest, DOM `Blob`/`URL.createObjectURL`. No new deps.

**Spec:** design §9.2. iOS equivalent = 6c (merged). Codec = `webapp/src/export/tripExportCodec.ts` (6b).

**Verification:** `cd webapp && npm test` (45 → 47) + `npm run build`. Signed-in download/upload runtime = user (browser).

---

### Task 1: fileTransfer helpers (+ test) and tripActions.importTrip

**Files:**
- Create: `webapp/src/ui/fileTransfer.ts`
- Create: `webapp/src/ui/fileTransfer.test.ts`
- Modify: `webapp/src/ui/store.ts`

- [ ] **Step 1: Write the failing test**

Create `webapp/src/ui/fileTransfer.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { tripFromImport } from "./fileTransfer";
import { exportJSON } from "../export/tripExportCodec";
import { newTrip } from "../model/trip";

describe("tripFromImport", () => {
  it("parses a .json file into a trip", () => {
    const json = exportJSON(newTrip({ name: "Roundtrip", startDate: 0, endDate: 0 }));
    const trip = tripFromImport("Roundtrip.json", json);
    expect(trip.name).toBe("Roundtrip");
  });

  it("parses a .csv file into a new trip named after the file", () => {
    const csv =
      "kind,label,notes,day_date,time,owner,is_done,place_name,place_query\n" +
      "packing,Socks,,,,,,,\n";
    const trip = tripFromImport("Beach.csv", csv);
    expect(trip.name).toBe("Beach");          // extension stripped
    expect(trip.items).toHaveLength(1);
    expect(trip.items[0].label).toBe("Socks");
  });
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp && npm test
```
Expected: FAIL — cannot resolve `./fileTransfer` / `tripFromImport`.

- [ ] **Step 3: Write the helpers**

Create `webapp/src/ui/fileTransfer.ts`:
```ts
import { importJSON, importCSVItems } from "../export/tripExportCodec";
import { newTrip, type Trip } from "../model/trip";

/** Dispatch by extension: .csv → items onto a new trip; otherwise canonical JSON. */
export function tripFromImport(filename: string, text: string): Trip {
  if (filename.toLowerCase().endsWith(".csv")) {
    return importCSVItems(text, newTrip({ name: filename.replace(/\.[^.]+$/, "") }));
  }
  return importJSON(text);
}

/** Trigger a browser download of `text` as `filename`. */
export function download(filename: string, text: string, mime: string): void {
  const url = URL.createObjectURL(new Blob([text], { type: mime }));
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
```

- [ ] **Step 4: Add tripActions.importTrip**

In `webapp/src/ui/store.ts`, add to the `tripActions` object (after `addItem`):
```ts
  importTrip(trip: Trip): void {
    commit(trip);
  },
```
(`Trip` is already imported in store.ts. `commit` captures it into the outbox; for
an imported trip `old` is undefined → an insert.)

- [ ] **Step 5: Run to verify it passes + build**

```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp && npm test && npm run build
```
Expected: 47 tests pass (45 + 2); build clean.

- [ ] **Step 6: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/ui/fileTransfer.ts webapp/src/ui/fileTransfer.test.ts webapp/src/ui/store.ts
git commit -m "feat(web): file transfer helpers + tripActions.importTrip"
```

---

### Task 2: Export buttons (detail) + Import button (list)

**Files:**
- Modify: `webapp/src/ui/TripDetailView.tsx`, `webapp/src/ui/TripListView.tsx`, `webapp/src/ui/styles.css`

- [ ] **Step 1: Export buttons in TripDetailView**

In `webapp/src/ui/TripDetailView.tsx`, import the codec + helper at the top:
```tsx
import { exportJSON, exportCSV } from "../export/tripExportCodec";
import { download } from "./fileTransfer";
```
Then, in the returned JSX, add an export action row right after the Share button
(`<button class="link" onClick={() => setSharing(true)}>Share</button>`):
```tsx
      <button class="link" onClick={() => download(`${trip.name || "trip"}.json`, exportJSON(trip), "application/json")}>Export JSON</button>
      <button class="link" onClick={() => download(`${trip.name || "trip"}.csv`, exportCSV(trip), "text/csv")}>Export CSV</button>
```
(`trip` is already in scope and non-null past the guard.)

- [ ] **Step 2: Import button in TripListView**

In `webapp/src/ui/TripListView.tsx`: import `useRef` and the helpers, add a hidden
file input + an Import button, and an `onPick` handler. Change the imports:
```tsx
import { useRef, useState } from "preact/hooks";
import { tripFromImport } from "./fileTransfer";
```
Add inside `TripListView`, before the `return`:
```tsx
  const fileRef = useRef<HTMLInputElement>(null);

  async function onPick(e: Event): Promise<void> {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    try {
      tripActions.importTrip(tripFromImport(file.name, await file.text()));
    } catch {
      /* ignore malformed file; could surface a toast later */
    }
    input.value = "";  // allow re-importing the same file
  }
```
In the `<header>`, add an Import button next to Sign out, and place the hidden
input anywhere in the returned tree (e.g. right after `<header>`):
```tsx
      <button class="link" onClick={() => fileRef.current?.click()}>Import</button>
```
```tsx
      <input ref={fileRef} type="file" accept=".json,.csv,application/json,text/csv"
             style="display:none" onChange={(e) => void onPick(e)} />
```

- [ ] **Step 3: (optional) styles** — the buttons reuse the existing `.link` class;
  no new CSS required. Skip editing styles.css unless a build/lint complains.

- [ ] **Step 4: Build + tests**

```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp && npm run build && npm test
```
Expected: build clean; 47 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/ui/TripDetailView.tsx webapp/src/ui/TripListView.tsx
git commit -m "feat(web): export downloads + import-file button"
```

---

### Task 3: Runtime verification (USER — browser)

**Files:** none

- [ ] Signed in: open a trip → Export JSON downloads a file; Export CSV downloads a
  CSV (opens in Excel with 中文 intact via the BOM). Then Import → pick that file →
  a new trip appears and syncs (and, cross-platform, a file exported from the iOS
  app imports here and vice-versa — the shared-format payoff). Report issues (no commit).

---

## Done criteria

- `cd webapp && npm test` (47) + `npm run build` pass.
- Export buttons download JSON/CSV of the open trip; Import reads a JSON/CSV file
  into a new (synced) trip; `tripFromImport` unit-tested both paths.
- **This completes sub-project 6 AND the entire v2 build** — Supabase backend, iOS
  app, and web app, each with auth, offline-first sync, sharing, and import/export,
  the two clients agreeing via shared `sync-conformance.json` (sync) and
  `trip-export-sample.json` (export format).

## Notes / remaining (USER, not code)

- Remaining user-gated items are verification/ship only: email-auth verify (unblocks
  all runtime), OAuth providers, rotate dev DB password, deploy webapp + retire
  trip-webapp v1, TestFlight a v2 iOS build, the 6c/6d import/export runtime checks.
- Follow-ups: "merge CSV into the open trip" (needs a replace path on both clients);
  optional import error toast.
