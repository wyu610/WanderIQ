# WanderIQ v2 — Sub-project 8: Web trip-detail parity with iOS

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the web app's trip experience up to the native iOS app: per-item
editing (notes, owner, day, time, reminder, place), trip dates + a day-by-day
itinerary, and "open in Maps". The web `Trip`/`ChecklistItem`/`TripDay` model
ALREADY carries every field and they already sync — this is purely exposing them
in the Preact UI, so there are **no model, mapping, or backend changes**.

**Parity reference (iOS):** `WanderIQ/Features/ItemEditor/ItemEditorView.swift`
(fields: name, notes, owner [hidden for doc/hotel], day + time [itinerary only],
reminder date+time, place [prep/hotel/itinerary]), `WanderIQ/Features/TripList/
TripListView.swift` `NewTripView` (date range → day rows), and
`WanderIQKit/.../MapLink.swift` (maps deep link).

**Reminders note:** the web sets `reminderDate` (it syncs); the **iOS** app fires
the actual local notification. The web does NOT schedule background
notifications (that needs Web Push + a server — out of scope). Setting the time
on the web is the parity deliverable.

**Tech Stack:** Preact + signals, Vitest. Web model `webapp/src/model/trip.ts`
(dates = epoch SECONDS; `time` = "HH:mm" string; `place = {name, query, latitude?,
longitude?}`).

**Verification:** `cd webapp && npm test` + `npm run build`; deploy at the end.

---

### Task 1: Pure helpers + store actions (item upsert/delete, dated create, maps URL)

**Files:**
- Create: `webapp/src/model/tripDays.ts`, `webapp/src/model/tripDays.test.ts`
- Create: `webapp/src/ui/mapsLink.ts`, `webapp/src/ui/mapsLink.test.ts`
- Modify: `webapp/src/ui/store.ts`

- [ ] **Step 1: Failing tests for the two pure helpers**

`webapp/src/model/tripDays.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { daysInRange } from "./tripDays";

describe("daysInRange", () => {
  it("builds one TripDay per UTC day, inclusive", () => {
    const start = Date.parse("2026-07-11T00:00:00Z") / 1000;
    const end = Date.parse("2026-07-13T00:00:00Z") / 1000;
    const days = daysInRange(start, end);
    expect(days).toHaveLength(3);
    expect(days[0].date).toBe(start);
    expect(days[2].date).toBe(end);
    expect(days.every((d) => d.city === "" && d.title === "" && typeof d.id === "string")).toBe(true);
  });
  it("returns a single day when start == end, and [] when end < start", () => {
    const t = Date.parse("2026-07-11T00:00:00Z") / 1000;
    expect(daysInRange(t, t)).toHaveLength(1);
    expect(daysInRange(t, t - 86400)).toHaveLength(0);
  });
});
```

`webapp/src/ui/mapsLink.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { mapsUrl } from "./mapsLink";

describe("mapsUrl", () => {
  it("uses lat,lon when present", () => {
    expect(mapsUrl({ name: "Museum", query: "q", latitude: 30.9, longitude: 121.7 }))
      .toBe("https://www.google.com/maps/search/?api=1&query=30.9%2C121.7");
  });
  it("falls back to query, then name", () => {
    expect(mapsUrl({ name: "Museum", query: "Shanghai Museum" }))
      .toBe("https://www.google.com/maps/search/?api=1&query=Shanghai%20Museum");
    expect(mapsUrl({ name: "Museum", query: "" }))
      .toBe("https://www.google.com/maps/search/?api=1&query=Museum");
  });
});
```

- [ ] **Step 2: Run, see them fail** (`cd webapp && npm test`) — modules missing.

- [ ] **Step 3: Implement the helpers**

`webapp/src/model/tripDays.ts`:
```ts
import type { TripDay } from "./trip";

const DAY = 86400; // seconds

/** One TripDay per UTC day from start..end inclusive (mirrors iOS NewTripView). */
export function daysInRange(startEpoch: number, endEpoch: number): TripDay[] {
  const start = Math.floor(startEpoch / DAY) * DAY;
  const end = Math.floor(endEpoch / DAY) * DAY;
  const days: TripDay[] = [];
  for (let d = start; d <= end; d += DAY) {
    days.push({ id: crypto.randomUUID(), date: d, city: "", title: "", modifiedAt: Math.floor(Date.now() / 1000) });
  }
  return days;
}
```

`webapp/src/ui/mapsLink.ts`:
```ts
import type { Place } from "../model/trip";

/** Universal Google Maps search URL (opens in any browser / the Maps app). */
export function mapsUrl(place: Place): string {
  const q = place.latitude != null && place.longitude != null
    ? `${place.latitude},${place.longitude}`
    : (place.query || place.name);
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(q)}`;
}
```

- [ ] **Step 4: Store actions**

In `webapp/src/ui/store.ts`, import `daysInRange`, change `create` to accept dates
and build days, and add `upsertItem` + `deleteItem` to `tripActions`:
```ts
import { daysInRange } from "../model/tripDays";
```
Replace `create`:
```ts
  create(name: string, start: number, end: number): void {
    commit(newTrip({ name, startDate: start, endDate: end, days: end >= start ? daysInRange(start, end) : [] }));
  },
```
Add (alongside the existing item actions):
```ts
  upsertItem(tripId: string, item: ChecklistItem): void {
    const t = coordinator?.state.trips.get(tripId);
    if (!t) return;
    const next: Trip = structuredClone(t);
    const i = next.items.findIndex((x) => x.id === item.id);
    if (i >= 0) next.items[i] = { ...item, modifiedAt: Math.floor(Date.now() / 1000) };
    else next.items.push({ ...item, sortOrder: next.items.length, modifiedAt: Math.floor(Date.now() / 1000) });
    commit(next);
  },
  deleteItem(tripId: string, itemId: string): void {
    const t = coordinator?.state.trips.get(tripId);
    if (!t) return;
    const next: Trip = structuredClone(t);
    next.items = next.items.filter((x) => x.id !== itemId);
    commit(next);
  },
```

- [ ] **Step 5: Run tests + build** (`npm test` → +4 cases; `npm run build`). Commit:
```bash
git add webapp/src/model/tripDays.ts webapp/src/model/tripDays.test.ts \
  webapp/src/ui/mapsLink.ts webapp/src/ui/mapsLink.test.ts webapp/src/ui/store.ts
git commit -m "feat(web): item upsert/delete + dated create + maps URL helper"
```

---

### Task 2: Item editor + richer trip detail (the main parity work)

**Files:**
- Create: `webapp/src/ui/ItemEditor.tsx`
- Modify: `webapp/src/ui/TripDetailView.tsx`, `webapp/src/ui/styles.css`

- [ ] **Step 1: ItemEditor component**

Create `webapp/src/ui/ItemEditor.tsx` — a panel that edits one item (existing or
new). Props: `{ tripId: string; trip: Trip; item?: ChecklistItem; kind: ItemKind;
onClose: () => void }`. Local state seeded from `item`. Fields, mirroring iOS:
- **Name** (text, required), **Notes** (textarea).
- **Owner** (text) — hide when `kind` is `doc` or `hotel`.
- When `kind === "itinerary"`: **Day** (`<select>` over `trip.days`, option label
  = the day's date `toLocaleDateString` + title; value = day id; allow none) and
  **Time** (`<input type="time">` ↔ the `"HH:mm"` string).
- **Reminder** (`<input type="datetime-local">` ↔ `reminderDate` epoch seconds;
  empty = no reminder). Add a one-line hint: "Reminders are delivered by the
  WanderIQ iOS app."
- **Place** (when kind is itinerary/prep/hotel): **Place name** + **Search text**
  (`query`) text inputs; if set, show an "Open in Maps" link using `mapsUrl`.
- **Save** → build a `ChecklistItem` (preserve `item.id` when editing, else
  `crypto.randomUUID()`; `time`/`owner`/`reminderDate`/`place` → undefined when
  empty; `dayId` only for itinerary) → `tripActions.upsertItem(tripId, item)` →
  `onClose()`. **Delete** (only when editing) → `tripActions.deleteItem` → close.
- Conversions: time `"HH:mm"` ↔ `<input type=time>` value (same format).
  reminder epoch→`datetime-local`: `new Date(sec*1000).toISOString().slice(0,16)`;
  back: `Math.floor(Date.parse(value) / 1000)`.

- [ ] **Step 2: Wire into TripDetailView**

In `webapp/src/ui/TripDetailView.tsx`:
- Add state `const [editing, setEditing] = useState<{ item?: ChecklistItem } | null>(null);`
- When `editing` is set, short-circuit render `<ItemEditor … />` (same pattern as
  the existing `sharing` short-circuit), passing the active tab's `addKind` and
  `editing.item`.
- In the item list: keep the checkbox for done, but make the **label tappable** to
  open `setEditing({ item: it })`. Show secondary detail under the label when
  present: `it.time`, `it.owner`, and an **Open in Maps** link (`mapsUrl(it.place)`,
  `target="_blank" rel="noopener"`) when `it.place`.
- Replace the plain "add by label" form's submit with: open the editor for a new
  item — `onClick={() => setEditing({})}` ("Add item" button) — OR keep the quick
  add-by-label AND add an "＋ details" affordance that opens the editor. (Quick-add
  may stay for speed; the editor is the parity piece.)
- For the **Itinerary** tab, group items by `dayId`: render each `trip.days` in
  order with its date as a subheading, then that day's itinerary items (sorted by
  `time`), then any with no day under "Unscheduled". (Mirror iOS itinerary-by-day.)

- [ ] **Step 3: Styles** — add minimal CSS for `.item-detail` (small, muted),
  `.itinerary-day h3`, and the editor form fields to `styles.css`.

- [ ] **Step 4: Build + tests** (`npm run build && npm test` — 51 tests unchanged).
  Commit:
```bash
git add webapp/src/ui/ItemEditor.tsx webapp/src/ui/TripDetailView.tsx webapp/src/ui/styles.css
git commit -m "feat(web): item editor (notes/owner/day/time/reminder/place) + itinerary by day + maps"
```

---

### Task 3: New-trip dates + trip-list dates

**Files:**
- Modify: `webapp/src/ui/TripListView.tsx`

- [ ] **Step 1: Dated create**

In `TripListView.tsx`, replace the name-only create form with name + two
`<input type="date">` (start, end). On submit, convert each date to epoch seconds
(`Date.parse(value + "T00:00:00Z")/1000`) and call
`tripActions.create(name, startEpoch, endEpoch)` (which now builds the days).
Default end = start when only start is given. Keep it compact.

- [ ] **Step 2: Show dates in the list**

For each trip row, show the date range when set (`startDate > 0`):
`new Date(t.startDate*1000).toLocaleDateString()` – `…(t.endDate)`, next to the
done count.

- [ ] **Step 3: Build + commit**
```bash
cd webapp && npm run build && npm test
git add webapp/src/ui/TripListView.tsx
git commit -m "feat(web): new-trip start/end dates (builds day itinerary) + list date range"
```

---

## Done criteria

- `cd webapp && npm test` (51) + `npm run build` pass.
- Web trip detail: tap an item to edit notes/owner/day/time/reminder/place; items
  show time/owner + an Open-in-Maps link; the Itinerary tab is grouped by day.
- New trip takes start/end dates and builds a day itinerary; the list shows dates.
- Reminder times set on the web sync and are delivered by the iOS app.
- Deploy: `cd webapp && npx vercel --prod --yes`.

## Notes
- No backend/model/sync changes — all fields already exist and sync (verified
  against `webapp/src/model/trip.ts`). Cross-engine conformance + parity fixtures
  are unaffected.
- True web-native scheduled reminders (Web Push + VAPID + a scheduled sender) remain
  a deferred, separate effort.
- iOS place attach uses MapKit search (`PlaceSearchView`); the web uses plain
  name/query text fields — a lighter but functional equivalent.
