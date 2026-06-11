# Planova iOS — Design Spec

**Date:** 2026-06-10
**Status:** Approved direction; pending final spec review
**Author:** brainstormed with Claude Code

## 1. Summary

Planova is a native SwiftUI app for iPhone and iPad: a simple, travel-focused
checklist and itinerary app with reminders, map suggestions, and family
sharing via iCloud. It is the successor to the existing single-file PWA in
`trip-webapp/` (the 2026 China trip checklist), generalized so any trip can be
created, and shipped to the family via TestFlight before the July 11, 2026
trip.

## 2. Goals (v1 — TestFlight by ~July 5, 2026)

- Multiple trips; the 2026 China trip pre-seeded on first launch.
- Per-trip content mirroring the PWA's mental model, three sections:
  - **Prep** — time-sensitive bookings, hotels, documents.
  - **Itinerary** — day-by-day accordion; "today" auto-highlighted during the trip.
  - **Packing** — daily go-out checklist with one-tap reset.
- Check/uncheck items; full editing (label, notes, day, time, owner) on a par
  with the PWA's bottom-sheet editor; add and delete items.
- **Reminders:** any item can carry a date+time that fires a local
  notification (e.g. the 7/10 09:30 Astronomy Museum ticket sale).
- **Maps:** per-item "open in Maps" action, plus a per-day map screen with
  pins for items that have an attached place.
- **Family sharing:** share a trip with family via native iCloud sharing;
  edits and checkmarks sync to all participants, offline-first.
- **Bilingual UI:** Simplified Chinese + English via String Catalog,
  following device language.
- Progress indicators: per-day counts, per-section counts, trip countdown.

## 3. Non-goals (v2, after the trip)

- Widgets, Live Activities, Siri/App Intents.
- Trip templates and a template gallery.
- Richer map experience (routing, clustering, offline tiles).
- iPad layouts beyond standard `NavigationSplitView`.
- Android/web client; App Store public release (TestFlight only for v1).
- Import of *modified* PWA state (only the default China-trip content is
  seeded; the PWA remains the family's live tool until the app is trusted).

## 4. Platform & distribution

- Swift 5.10+, SwiftUI, **iOS/iPadOS 17 minimum** (required by `CKSyncEngine`).
- Universal app: tab-based navigation on iPhone, `NavigationSplitView` on iPad.
- Apple Developer Program account required (enroll immediately — approval can
  take days). Distribution via TestFlight to family devices.
- The PWA stays deployed as a fallback for the July trip.

## 5. Architecture

Single Xcode app target `Planova`, organized by feature folders:

```
Planova/
  Models/            // Codable value types: Trip, TripDay, ChecklistItem, Place
  Store/             // TripStore: local persistence, source of truth
  Sync/              // CloudKit sync engine wrapper + record mapping + sharing
  Reminders/         // ReminderScheduler (UNUserNotificationCenter)
  Features/
    TripList/        // trip list, create/edit trip
    Prep/            // prep + hotels + docs checklists
    Itinerary/       // day accordion, day detail
    Packing/         // packing checklist + daily reset
    DayMap/          // per-day MapKit view, place attach flow
    ItemEditor/      // bottom-sheet item editor (shared by all sections)
  Resources/         // Localizable.xcstrings, seed JSON, assets
PlanovaTests/        // unit tests
```

Principles: the UI reads only from `TripStore` (an `@Observable` object);
sync and notifications are side effects driven by store mutations. Each unit
is independently testable: models are pure values, the store works without
CloudKit, the sync layer maps records without touching UI.

### 5.1 Data model (local source of truth, `Codable` structs)

- `Trip` — `id: UUID`, `name`, `startDate`, `endDate`, `destinations: [String]`,
  `days: [TripDay]`, `items: [ChecklistItem]`, `schemaVersion`.
- `TripDay` — `id`, `date`, `city`, `title`.
- `ChecklistItem` — `id`, `kind` (`prep | hotel | doc | itinerary | packing`),
  `label`, `notes`, `dayID: UUID?` (itinerary items), `time: String?`,
  `owner: String?`, `isDone: Bool`, `sortOrder`, `reminderDate: Date?`,
  `place: Place?`, `modifiedAt: Date`.
- `Place` — `name`, `query` (search string for Maps), `latitude?`, `longitude?`.

One item entity for everything checkable (as in the PWA) keeps the editor,
sync mapping, and progress math uniform; `kind` + `dayID` decide where it
renders.

### 5.2 Local persistence — `TripStore`

- One JSON document per trip in Application Support
  (`trips/<uuid>.json`), plus a lightweight index file.
- Debounced atomic writes (~150 ms after last mutation, flushed on
  background), mirroring the PWA's save behavior.
- The store exposes intent methods (`toggle(item:)`, `addItem`, `moveItem`,
  `resetPacking(for:)`, …); every mutation stamps `modifiedAt` and notifies
  the sync layer.

### 5.3 Sync — raw CloudKit via `CKSyncEngine`

- CloudKit container `iCloud.com.<team>.planova`, **private database**, one
  custom zone per trip (`trip-<uuid>`). Shared trips arrive in the
  **shared database** via the same engine.
- Record types: `Trip` (one record), `TripDay`, `ChecklistItem` — one record
  per entity so concurrent family edits to different items never conflict.
  `Place` is embedded in the item record (encoded fields).
- A `SyncCoordinator` owns two `CKSyncEngine` instances (private + shared),
  persists engine state serializations alongside the trip files, queues
  record changes on store mutations, and applies fetched changes back into
  `TripStore`.
- **Conflict policy:** per-record last-writer-wins using CloudKit server
  semantics; for the common case (checkmark races) records are per-item so
  conflicts are rare. On a true conflict the server record wins and the local
  change is re-applied only if `modifiedAt` is newer.
- **Offline-first:** all edits apply locally first; the engine retries when
  connectivity returns (matters in mainland China — same posture as the PWA).
- **No iCloud account:** app fully works locally; sync/sharing UI shows an
  explanatory disabled state. `CKContainer.accountStatus` checked at launch
  and on `CKAccountChanged`.

### 5.4 Family sharing

- Zone-wide sharing: one `CKShare` on the trip's custom zone; every record in
  the zone is shared with participants (read/write).
- UI: "Share trip" in the trip menu presents `UICloudSharingController`
  (wrapped for SwiftUI); participants accept via the standard iCloud invite
  link — replaces the PWA's hand-rolled invite-link + Supabase flow.
- Participant edits flow through the shared-database sync engine; the owner
  can stop sharing, which retains a local copy for everyone (CloudKit
  default behavior surfaced in UI copy).

### 5.5 Reminders

- `ReminderScheduler` reconciles `UNUserNotificationCenter` pending requests
  with the set of items having a future `reminderDate` and `isDone == false`
  (notification identifier = item UUID). Reconcile runs after store mutations
  and at launch.
- Permission requested the first time a user sets a reminder; denied state
  shows an inline hint linking to Settings.
- Completing or deleting an item cancels its notification. Notifications fire
  with the app closed — the key capability the PWA could not provide.

### 5.6 Maps

- **Open-in-Maps:** items with a `place` get a map button; uses `MKMapItem`
  (when coordinates are resolved) or an Apple Maps search URL fallback.
- **Attach place flow:** in the item editor, a search field backed by
  `MKLocalSearch` lets the user pick a POI; stores name + query + coords.
  Items without a resolvable POI keep query-only places (link works, no pin).
- **Day map:** each itinerary day offers a `Map` (SwiftUI/MapKit) showing
  `Marker`s for that day's placed items; tapping a marker highlights the item.
- Mainland-China note: Apple Maps China data is AutoNavi-backed; coordinate
  shifting is handled by MapKit automatically. Some niche POIs won't resolve —
  acceptable; such items simply have no pin.

### 5.7 Localization & seed content

- `Localizable.xcstrings` with `zh-Hans` and `en`; UI follows device locale.
- Seed: `Resources/seed-china-2026.json` ported from the PWA's `DAYS`, `PREP`,
  `HOTELS`, `DOCS`, `PACK` constants (content remains Chinese — it is user
  data, not UI). Created on first launch only.

## 6. Error handling

- Store I/O failures: surface a non-blocking banner ("changes may not be
  saved"), keep in-memory state usable — same posture as the PWA's
  `storageOK` flag.
- Sync errors: silent retry with backoff (engine-managed); persistent failure
  shows a sync-status line in trip settings, never blocks local use.
- Notification permission denied, iCloud unavailable, zone-share revoked:
  each has a designed inline state, no dead ends.

## 7. Testing

- **Unit tests:** seed import (counts/structure match the PWA data), store
  mutations and persistence round-trip, reminder reconciliation diffs,
  model ⇄ `CKRecord` mapping both directions, conflict-resolution policy.
- **UI smoke tests:** check/uncheck, add/edit/delete item, packing reset.
- **Manual:** two-iCloud-account sharing test (owner + participant) on real
  devices before TestFlight; airplane-mode offline edit + resync test.

## 8. Risks & schedule

| Risk | Mitigation |
| --- | --- |
| Apple Developer enrollment delay | Enroll day 1; sideload to own device meanwhile |
| CloudKit sharing complexity (top schedule risk) | Zone-sharing + `CKSyncEngine` sample-code path; fallback: ship v1 with private sync only, family keeps PWA for shared checking this trip |
| Mainland-China connectivity | Offline-first store; iCloud/APNs generally reachable; PWA remains backup |
| 4-week timeline | Strict v1 scope; v2 list above is explicitly deferred |

Week-by-week intent: (1) models, store, UI skeleton + seed; (2) editor,
reminders, packing reset, localization; (3) sync engine + sharing;
(4) maps, polish, TestFlight beta to family.
