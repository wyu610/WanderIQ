# WanderIQ v2 — Sub-project 6b: TypeScript Import/Export Codec (cross-platform parity)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The TypeScript twin of 6a — JSON (whole-trip, canonical) + CSV (flat item-level, UTF-8 BOM) — implementing the SAME format, verified by a Vitest test that reads the SAME `trip-export-sample.json` fixture 6a created. This is the cross-platform guarantee: a trip exported on iOS imports on the web and vice-versa.

**Architecture:** `webapp/src/export/tripExportCodec.ts` exporting `exportJSON(trip): string`, `importJSON(text): Trip`, `exportCSV(trip): string`, `importCSVItems(csv, trip): Trip`. The web `Trip` model stores dates as **epoch-seconds numbers**, so the codec converts epoch↔`YYYY-MM-DD` (trip/day dates, UTC) and epoch↔ISO-8601 (reminderDate) — exactly inverse to 6a's Swift `Date` handling. Import returns a **fresh-id** trip (new `crypto.randomUUID()` for trip/days/items, `dayIndex`→new day id). CSV import returns a new trip with rows appended as items.

**Interop hazard handled here:** Swift's `ISO8601DateFormatter()` (6a) does NOT parse fractional seconds, but JS `Date.toISOString()` emits `.000Z`. So `exportJSON` MUST strip milliseconds from `reminderDate` (→ `…:00Z`), matching Swift's output byte-for-byte, so an iOS device can import a web-exported file. `importJSON` tolerates BOTH (JS `Date.parse` accepts either) and tolerates ABSENT keys (Swift's `JSONEncoder` omits nil optionals rather than emitting `null`).

**Tech Stack:** TypeScript, Vitest, `crypto.randomUUID()` (Node 24 / browser). No new deps.

**Spec:** `docs/superpowers/specs/2026-06-15-wanderiq-v2-export-format.md` (written in 6a). Swift codec = `WanderIQKit/Sources/WanderIQKit/Export/TripExportCodec.swift`.

**Verification:** `cd webapp && npm test` (42 baseline → +new export tests) + `npm run build`.

---

### Task 1: TripExportCodec (TS) — JSON + CSV

**Files:**
- Create: `webapp/src/export/tripExportCodec.ts`

- [ ] **Step 1: Write the codec**

Create `webapp/src/export/tripExportCodec.ts`:
```ts
import type { Trip, TripDay, ChecklistItem, ItemKind, Place } from "../model/trip";

// ── date helpers ───────────────────────────────────────────────
// trip/day dates: epoch-seconds ↔ "YYYY-MM-DD" (UTC date-only).
const epochToDateOnly = (sec: number): string => new Date(sec * 1000).toISOString().slice(0, 10);
const dateOnlyToEpoch = (s: string): number => Math.floor(Date.parse(`${s}T00:00:00Z`) / 1000);
// reminderDate: epoch-seconds ↔ ISO-8601 WITHOUT millis (matches Swift ISO8601DateFormatter).
const epochToIso = (sec: number): string => new Date(sec * 1000).toISOString().replace(/\.\d{3}Z$/, "Z");
const isoToEpoch = (s: string): number => Math.floor(Date.parse(s) / 1000);

// ── wire DTOs (canonical JSON shape) ───────────────────────────
interface PlaceDTO { name: string; query: string; latitude: number | null; longitude: number | null; }
interface DayDTO { date: string; city: string; title: string; }
interface ItemDTO {
  kind: string; label: string; notes: string; dayIndex: number | null; time: string | null;
  owner: string | null; isDone: boolean; sortOrder: number; reminderDate: string | null; place: PlaceDTO | null;
}
interface TripDTO {
  schemaVersion: number; name: string; startDate: string; endDate: string;
  destinations: string[]; days: DayDTO[]; items: ItemDTO[];
}

// ── JSON ───────────────────────────────────────────────────────
export function exportJSON(trip: Trip): string {
  const dayIndex = new Map(trip.days.map((d, i) => [d.id, i]));
  const dto: TripDTO = {
    schemaVersion: 1,
    name: trip.name,
    startDate: epochToDateOnly(trip.startDate),
    endDate: epochToDateOnly(trip.endDate),
    destinations: trip.destinations,
    days: trip.days.map((d) => ({ date: epochToDateOnly(d.date), city: d.city, title: d.title })),
    items: trip.items.map((it) => ({
      kind: it.kind,
      label: it.label,
      notes: it.notes,
      dayIndex: it.dayId !== undefined ? (dayIndex.get(it.dayId) ?? null) : null,
      time: it.time ?? null,
      owner: it.owner ?? null,
      isDone: it.isDone,
      sortOrder: it.sortOrder,
      reminderDate: it.reminderDate !== undefined ? epochToIso(it.reminderDate) : null,
      place: it.place
        ? { name: it.place.name, query: it.place.query,
            latitude: it.place.latitude ?? null, longitude: it.place.longitude ?? null }
        : null,
    })),
  };
  return JSON.stringify(dto, null, 2);
}

/** Parse a canonical export into a fresh-id Trip (tolerates absent or null optionals). */
export function importJSON(text: string): Trip {
  const dto = JSON.parse(text) as TripDTO;
  const now = Math.floor(Date.now() / 1000);
  const days: TripDay[] = (dto.days ?? []).map((d) => ({
    id: crypto.randomUUID(), date: dateOnlyToEpoch(d.date), city: d.city, title: d.title, modifiedAt: now,
  }));
  const items: ChecklistItem[] = (dto.items ?? []).map((i) => {
    const di = i.dayIndex;
    const dayId = di != null && di >= 0 && di < days.length ? days[di].id : undefined;
    const place: Place | undefined = i.place
      ? { name: i.place.name, query: i.place.query,
          latitude: i.place.latitude ?? undefined, longitude: i.place.longitude ?? undefined }
      : undefined;
    return {
      id: crypto.randomUUID(),
      kind: i.kind as ItemKind,
      label: i.label,
      notes: i.notes ?? "",
      dayId,
      time: i.time ?? undefined,
      owner: i.owner ?? undefined,
      isDone: i.isDone ?? false,
      sortOrder: i.sortOrder ?? 0,
      reminderDate: i.reminderDate != null ? isoToEpoch(i.reminderDate) : undefined,
      place,
      modifiedAt: now,
    };
  });
  return {
    id: crypto.randomUUID(),
    name: dto.name,
    startDate: dateOnlyToEpoch(dto.startDate),
    endDate: dateOnlyToEpoch(dto.endDate),
    destinations: dto.destinations ?? [],
    days, items, schemaVersion: 1, modifiedAt: now,
  };
}

// ── CSV (flat item-level, UTF-8 BOM) ───────────────────────────
const CSV_HEADER = "kind,label,notes,day_date,time,owner,is_done,place_name,place_query";

export function exportCSV(trip: Trip): string {
  const dayDate = new Map(trip.days.map((d) => [d.id, epochToDateOnly(d.date)]));
  const lines = [CSV_HEADER];
  for (const it of trip.items) {
    const cols = [
      it.kind, it.label, it.notes,
      it.dayId !== undefined ? (dayDate.get(it.dayId) ?? "") : "",
      it.time ?? "", it.owner ?? "", it.isDone ? "true" : "false",
      it.place?.name ?? "", it.place?.query ?? "",
    ];
    lines.push(cols.map(csvField).join(","));
  }
  return `﻿${lines.join("\n")}\n`;
}

/** Append CSV rows as items to a copy of `trip`, matching/creating a day by date. */
export function importCSVItems(csv: string, trip: Trip): Trip {
  const body = csv.startsWith("﻿") ? csv.slice(1) : csv;
  const rows = parseCSV(body);
  if (rows.length <= 1) return trip;
  const now = Math.floor(Date.now() / 1000);
  const byDate = new Map(trip.days.map((d) => [epochToDateOnly(d.date), d.id]));
  const days = [...trip.days];
  const items = [...trip.items];
  for (const row of rows.slice(1)) {
    if (row.length < 9) continue;
    let dayId: string | undefined;
    const d = row[3];
    if (d) {
      const existing = byDate.get(d);
      if (existing) dayId = existing;
      else {
        const id = crypto.randomUUID();
        days.push({ id, date: dateOnlyToEpoch(d), city: "", title: "", modifiedAt: now });
        byDate.set(d, id);
        dayId = id;
      }
    }
    const place: Place | undefined = row[7] ? { name: row[7], query: row[8] } : undefined;
    items.push({
      id: crypto.randomUUID(),
      kind: row[0] as ItemKind,
      label: row[1],
      notes: row[2],
      dayId,
      time: row[4] || undefined,
      owner: row[5] || undefined,
      isDone: row[6] === "true",
      sortOrder: items.length,
      place,
      modifiedAt: now,
    });
  }
  return { ...trip, days, items };
}

// RFC-4180-ish: quote fields containing comma/quote/newline; double inner quotes.
function csvField(s: string): string {
  if (!/[",\n]/.test(s)) return s;
  return `"${s.replace(/"/g, '""')}"`;
}

function parseCSV(text: string): string[][] {
  const rows: string[][] = [];
  let field = "";
  let row: string[] = [];
  let inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; }
        else inQuotes = false;
      } else field += c;
    } else if (c === '"') inQuotes = true;
    else if (c === ",") { row.push(field); field = ""; }
    else if (c === "\n") { row.push(field); rows.push(row); field = ""; row = []; }
    else if (c === "\r") { /* skip */ }
    else field += c;
  }
  if (field !== "" || row.length > 0) { row.push(field); rows.push(row); }
  return rows;
}
```

- [ ] **Step 2: Build + tests (no test yet — just compile)**

```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
npm run build
```
Expected: tsc compiles clean. If a type error appears (e.g. `crypto` typing), report exact (BLOCKED) — `crypto.randomUUID()` is already used in `src/model/trip.ts:47`, so it resolves.

- [ ] **Step 3: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/export/tripExportCodec.ts
git commit -m "feat(web): TS trip import/export codec (canonical format)"
```

---

### Task 2: Cross-platform parity test (reads the SHARED fixture)

**Files:**
- Create: `webapp/src/export/tripExport.test.ts`

- [ ] **Step 1: Write the failing test**

Create `webapp/src/export/tripExport.test.ts` (mirrors how `src/sync/conformance.test.ts`
reads the shared fixture):
```ts
import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { exportJSON, importJSON, exportCSV, importCSVItems } from "./tripExportCodec";
import { newTrip } from "../model/trip";

// The SAME fixture the Swift codec round-trips (6a) — the cross-platform guarantee.
const fixturePath = join(
  dirname(fileURLToPath(import.meta.url)),
  "../../../WanderIQKit/Tests/WanderIQKitTests/Fixtures/trip-export-sample.json",
);
const fixtureText = readFileSync(fixturePath, "utf8");

describe("trip export/import — cross-platform parity", () => {
  it("imports the shared Swift fixture with day-index remap + fresh ids", () => {
    const trip = importJSON(fixtureText);
    expect(trip.name).toBe("Sample Trip");
    expect(trip.days).toHaveLength(2);
    expect(trip.items).toHaveLength(2);

    const museum = trip.items.find((i) => i.label === "Astronomy Museum")!;
    expect(museum.dayId).toBe(trip.days[1].id);          // dayIndex 1 → 2nd day's fresh id
    expect(museum.place?.name).toBe("Shanghai Astronomy Museum");
    expect(museum.reminderDate).toBe(Math.floor(Date.parse("2026-07-10T01:30:00Z") / 1000));

    const passport = trip.items.find((i) => i.label === "Passport")!;
    expect(passport.dayId).toBeUndefined();              // dayIndex null → no day
    expect(passport.isDone).toBe(true);

    // Trip/day dates decode as UTC date-only.
    expect(trip.startDate).toBe(Math.floor(Date.parse("2026-07-11T00:00:00Z") / 1000));
    expect(trip.days[0].date).toBe(Math.floor(Date.parse("2026-07-11T00:00:00Z") / 1000));
  });

  it("re-exports Swift-importable JSON (no fractional seconds) and round-trips", () => {
    const trip = importJSON(fixtureText);
    const json = exportJSON(trip);
    // CRITICAL interop check: reminderDate must have NO millis (Swift can't parse .000Z).
    expect(json).toMatch(/"reminderDate": "2026-07-10T01:30:00Z"/);
    expect(json).not.toMatch(/\.\d{3}Z/);

    const trip2 = importJSON(json);
    expect(trip2.items).toHaveLength(2);
    expect(trip2.days).toHaveLength(2);
    expect(trip2.id).not.toBe(trip.id);                  // always a fresh trip id
    const museum2 = trip2.items.find((i) => i.label === "Astronomy Museum")!;
    expect(museum2.dayId).toBe(trip2.days[1].id);
  });

  it("CSV export has BOM + header + quoting; import adds items", () => {
    const trip = importJSON(fixtureText);
    const csv = exportCSV(trip);
    expect(csv.startsWith("﻿")).toBe(true);
    expect(csv).toContain("kind,label,notes,day_date,time,owner,is_done,place_name,place_query");
    expect(csv).toContain("Astronomy Museum");

    const empty = newTrip({ name: "T" });
    const filled = importCSVItems(
      '﻿kind,label,notes,day_date,time,owner,is_done,place_name,place_query\n' +
        'prep,"Buy, tickets",note,,09:30,Mom,false,,\n',
      empty,
    );
    expect(filled.items).toHaveLength(1);
    expect(filled.items[0].label).toBe("Buy, tickets");   // comma-in-quotes parsed
    expect(filled.items[0].kind).toBe("prep");
    expect(filled.items[0].time).toBe("09:30");
    expect(filled.items[0].isDone).toBe(false);
  });
});
```

- [ ] **Step 2: Run the test**

```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
npm test
```
Expected: all green (the codec from Task 1 satisfies these). If the fixture path
fails to resolve, confirm the relative depth matches `src/sync/conformance.test.ts`
(both are `src/<dir>/*.test.ts`, so `../../../WanderIQKit/...` is correct). Total
should be 42 + 3 = 45 tests (or +1 file with 3 cases — report the count).

- [ ] **Step 3: Build + commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp && npm run build && npm test
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/export/tripExport.test.ts
git commit -m "test(web): cross-platform export parity vs shared Swift fixture"
```

---

## Done criteria

- `cd webapp && npm test` (45) + `npm run build` pass.
- The TS codec imports the SAME `trip-export-sample.json` 6a created, with day-index
  remap, fresh ids, correct epoch↔date conversions, and CSV BOM/quoting.
- `exportJSON` emits NO fractional seconds (an iOS device can import a web export).
- **Both clients now share one export format, proven against one fixture** — the
  Swift↔TS parity guarantee. Only the two UIs remain: **6c** (iOS: `fileExporter`
  /`fileImporter`) and **6d** (web: `Blob` download + `<input type=file>`).

## Notes for 6c / 6d

- JSON import = create a NEW trip (web: feed `importJSON` result through the same
  create path as `tripActions` so it enters the outbox/sync; iOS: `AppModel` add +
  `noteLocalChange`). CSV import = mutate the open trip (append items) then capture.
- 6c iOS: `.fileExporter` with a JSON/CSV `Transferable` or `FileDocument`, and
  `.fileImporter` to pick a file; route the picked URL's contents through
  `TripExportCodec`.
- 6d web: `new Blob([text], {type})` + an `<a download>` for export; a hidden
  `<input type="file">` for import; wire both into `TripDetailView` / `TripListView`.
