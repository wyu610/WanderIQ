# WanderIQ v2 — Canonical Trip Export Format v1

**Spec section:** design §9.2 (JSON canonical whole-trip + CSV flat item-level, UTF-8 BOM).

Implementations: Swift codec (sub-project 6a: `WanderIQKit/Sources/WanderIQKit/Export/TripExportCodec.swift`) and TypeScript codec (sub-project 6b: `webapp/`). Both round-trip the shared fixture at `WanderIQKit/Tests/WanderIQKitTests/Fixtures/trip-export-sample.json` — that file is the cross-platform guarantee.

---

## JSON Format (whole-trip, lossless)

### Top-level shape

```json
{
  "schemaVersion": 1,
  "name": "2026 China",
  "startDate": "2026-07-11",
  "endDate": "2026-07-31",
  "destinations": ["Shanghai", "HK"],
  "days": [ { "date": "2026-07-11", "city": "Shanghai", "title": "Arrive" } ],
  "items": [ {
    "kind": "prep", "label": "Passport", "notes": "",
    "dayIndex": 0, "time": "09:30", "owner": "Mom",
    "isDone": false, "sortOrder": 0,
    "reminderDate": "2026-07-10T09:30:00Z",
    "place": { "name": "Museum", "query": "Museum SH", "latitude": 31.2, "longitude": 121.0 }
  } ]
}
```

### Field notes

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | `Int` | Always `1` for this version |
| `name` | `String` | Trip name |
| `startDate` / `endDate` | `String` (`YYYY-MM-DD`) | UTC calendar date |
| `destinations` | `[String]` | Ordered list of destination names |
| `days[].date` | `String` (`YYYY-MM-DD`) | UTC calendar date |
| `days[].city` | `String` | City name for the day |
| `days[].title` | `String` | User-given day title |
| `items[].kind` | `String` enum | One of: `prep`, `hotel`, `doc`, `itinerary`, `packing` |
| `items[].dayIndex` | `Int?` | Index into `days[]`; `null` means not linked to a day |
| `items[].time` | `String?` | `"HH:mm"` (24-hour); `null` if untimed |
| `items[].owner` | `String?` | Assigned person; `null` if unassigned |
| `items[].reminderDate` | `String?` | Full ISO-8601 (`YYYY-MM-DDTHH:MM:SSZ`); `null` if no reminder |
| `items[].place` | `Object?` | `{ name, query, latitude?, longitude? }`; `null` if no place |

**Excluded fields:** `id`, `modifiedAt` (and all internal UUIDs) are **not exported**. Import always creates a fresh-id trip — the importer generates new UUIDs for the trip, days, and items, and remaps `dayIndex → new day id`.

`dayIndex`, `time`, `owner`, `reminderDate`, and `place` are nullable/omittable in the JSON.

---

## CSV Format (flat item-level, UTF-8 BOM)

- File begins with the UTF-8 BOM (`﻿`) for correct rendering in Excel and CJK locales.
- One header row; one data row per item.
- Fields containing commas, double-quotes, or newlines are RFC-4180 quoted (wrapped in `"`, inner `"` doubled to `""`).

### Header

```
kind,label,notes,day_date,time,owner,is_done,place_name,place_query
```

| Column | Notes |
|---|---|
| `kind` | Same enum values as JSON |
| `label` | Item label |
| `notes` | Item notes (may be empty) |
| `day_date` | `YYYY-MM-DD` of the linked day; empty if not linked |
| `time` | `HH:mm`; empty if untimed |
| `owner` | Empty if unassigned |
| `is_done` | `true` or `false` |
| `place_name` | Empty if no place |
| `place_query` | Empty if no place |

**Import behaviour:** CSV import adds items to an existing trip. Day rows are matched by date (`day_date`); if a date is not already in the trip, a new `TripDay` is created for it.

---

## Shared Fixture

`WanderIQKit/Tests/WanderIQKitTests/Fixtures/trip-export-sample.json` is the canonical test fixture. Both the Swift codec (6a) and the TypeScript codec (6b) must import it, verify the structure, re-export, and re-import to prove round-trip fidelity.
