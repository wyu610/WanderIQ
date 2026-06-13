# WanderIQ v2 — Design Spec

**Date:** 2026-06-13
**Status:** Approved direction; pending implementation planning
**Author:** brainstormed with Claude Code
**Supersedes sync architecture of:** v1 (CloudKit) — see `2026-06-10-planova-ios-design.md`

## 1. Summary

WanderIQ v2 turns the iOS-only, CloudKit-synced travel app into an
account-based, cross-platform product. A **Supabase** backend (Postgres +
Auth + Realtime + Row-Level Security) is the system of record. Two clients
consume it:

- the existing **native iOS app** (CloudKit sync retired), and
- an **evolved PWA** (the current `trip-webapp/`, rebuilt) that serves
  Android, web, and desktop.

Both clients are **offline-first**: a local store is the source of truth,
edits queue in an outbox, and sync happens when connectivity returns.
Authentication is Apple / Google / email-password. Trips are private to
their owner and shared per-trip by email invite with View/Edit roles. Data
imports and exports via JSON (full fidelity) and CSV (flat, item-level).

A deliberate side effect: v2 eliminates the v1 "every download sees my
trip" problem. With accounts and per-user data, a fresh signup sees an
empty account — no personal trip is seeded into the app bundle.

## 2. Goals

- Cross-platform: iOS native + PWA (Android/web/desktop) from one backend.
- Real accounts (Apple, Google, email/password) via Supabase Auth.
- Full offline-first read **and** write, syncing on reconnect, with
  per-record last-writer-wins conflict resolution.
- Per-trip sharing by email invite with `viewer` / `editor` roles,
  enforced by Postgres Row-Level Security.
- Import/export: JSON (canonical, whole-trip) and CSV (flat, item-level).
- Feature parity with v1 on both clients (prep / itinerary / packing,
  reminders, map links, per-day pin map where the platform allows).

## 3. Non-goals (explicitly out of scope for v2)

- PDF itinerary export, calendar (`.ics`) export, automated PWA-data
  importer — deferrable as small standalone features later.
- Field-level merge conflict resolution (whole-record LWW only).
- A from-scratch native Android app or a Flutter/KMP rewrite (the PWA is
  the Android/web client).
- An automated CloudKit→Supabase data bridge (migration is JSON
  export/import; see §10).
- Keeping CloudKit as a parallel iOS fallback (clean cutover; see §11).

## 4. Architecture overview

```
            ┌──────────────────────────────────────────┐
            │                 Supabase                   │
            │  Postgres + RLS · Auth · Realtime · Edge    │
            └──────────────────────────────────────────┘
                 ▲                              ▲
   offline-first │ sync protocol (one contract) │ offline-first
                 │                              │
        ┌────────┴────────┐            ┌────────┴────────┐
        │  iOS native app │            │   Evolved PWA   │
        │ (SwiftUI +      │            │ (Android/web/    │
        │  WanderIQKit)   │            │  desktop)        │
        │ local store +   │            │ IndexedDB +      │
        │ Swift sync engine│           │ TS sync engine   │
        └─────────────────┘            └─────────────────┘
```

The Swift and TypeScript sync engines share a **contract**, not code: the
data schema (§5) and the sync protocol (§6) are written specifications both
implement, validated by a shared conformance suite (§9).

## 5. Data model & security

### 5.1 Tables

All syncable rows carry three sync columns: `modified_at timestamptz`
(client edit clock), `server_updated_at timestamptz default now()` (server
stamp, used only for the pull cursor), and `deleted boolean default false`
(tombstone).

- **`profiles`** — public mirror of `auth.users`: `id` (= auth uid, PK),
  `display_name`, `created_at`. Lets the UI show who shared/owns.
- **`trips`** — `id uuid PK`, `owner_id uuid → auth.users`, `name`,
  `start_date date`, `end_date date`, `destinations text[]`,
  `schema_version int`, + sync columns.
- **`trip_days`** — `id uuid PK`, `trip_id → trips`, `date date`, `city`,
  `title`, + sync columns.
- **`trip_items`** — `id uuid PK`, `trip_id → trips`, `kind` (enum: prep,
  hotel, doc, itinerary, packing), `label`, `notes`, `day_id uuid` (nullable
  → trip_days), `time text` ("HH:mm"), `item_owner text` (free-text "who's
  responsible" — NOT an account), `is_done bool`, `sort_order int`,
  `reminder_date timestamptz`, `place jsonb` (name/query/latitude/longitude),
  + sync columns.
- **`trip_members`** — `id uuid PK`, `trip_id → trips`, `user_id uuid →
  auth.users` (nullable until invite accepted), `role` (enum: viewer,
  editor), `invited_email text`, `status` (enum: pending, accepted),
  `created_at`. Two partial unique indexes prevent duplicates:
  `unique (trip_id, user_id) where user_id is not null` and
  `unique (trip_id, lower(invited_email)) where invited_email is not null`.

`item_owner` (text label) is intentionally distinct from `trips.owner_id`
(the account). They are not conflated.

### 5.2 Row-Level Security

- **SELECT trip / days / items:** allowed if `auth.uid() = trips.owner_id`
  OR an accepted `trip_members` row exists for `(trip_id, auth.uid())`.
  Days/items resolve access through their parent trip (security-definer
  helper function `can_access_trip(trip_id)` to avoid recursive policy
  joins).
- **INSERT/UPDATE on days / items:** allowed if owner or member with
  `role = editor`.
- **DELETE (tombstone UPDATE) on days / items:** same as update.
- **trips:** owner may update/delete the trip row; editors may not delete
  the trip.
- **trip_members:** only the trip owner may insert/delete members; any user
  with trip access may read the member list.

## 6. Sync protocol (the shared contract)

This section is the authoritative protocol both client engines implement.
It will be extracted into its own doc during planning, but the normative
rules live here.

### 6.1 Local store
Each client keeps a durable local store (iOS: existing file/SQLite-backed
store extended with an outbox; PWA: IndexedDB). All reads and writes go
through the local store; the UI never blocks on the network.

### 6.2 Pull
- Client persists a `last_pulled_at` cursor (per database scope).
- On login, app foreground, manual refresh, or a Realtime signal: fetch all
  accessible rows where `server_updated_at > last_pulled_at`.
- Apply each remote row: if `remote.modified_at > local.modified_at`, take
  remote (including tombstones); otherwise keep local.
- Advance the cursor to the max `server_updated_at` observed.

### 6.3 Push (outbox)
- Every local mutation appends a pending change
  `{table, id, op (upsert|delete), payload, modified_at}` to an outbox.
- When online, flush the outbox in insertion order; on a successful upsert
  the server sets `server_updated_at = now()`; remove the entry on success;
  retry with backoff on failure.

### 6.4 Conflict resolution
- Whole-record **last-writer-wins by `modified_at`** (the v1 CloudKit
  policy). Field-level merge is out of scope.
- `modified_at` is client-generated. Known caveat: a device with a skewed
  clock can unfairly win or lose. Accepted (same as v1). `server_updated_at`
  is trusted only for the cursor, never for conflict resolution.

### 6.5 Deletes
- Deletions set `deleted = true` + bump `modified_at`; clients never
  hard-delete (a hard delete cannot propagate to an offline device).
  Tombstones sync like any update. The server purges tombstones older than
  a retention window (e.g. 90 days) via a scheduled job.

### 6.6 Realtime
- Clients subscribe to Postgres changes on `trips`/`trip_days`/`trip_items`
  filtered to accessible trip IDs. A change triggers a targeted pull.
- Realtime is an **optimization**, not the correctness mechanism: the
  cursor-based pull (§6.2) is authoritative, so a missed Realtime event
  self-heals on the next pull.

## 7. Authentication

- Supabase Auth with three providers: **Apple**, **Google**,
  **email/password**.
- **iOS:** Supabase Swift SDK. Sign in with Apple natively; Google via
  web-auth session; email/password forms. Session/refresh tokens stored in
  Keychain. (App Store requires Sign in with Apple when offering Google —
  satisfied.)
- **PWA:** Supabase JS SDK. OAuth redirect flow for Apple/Google;
  email/password forms. Session persisted in IndexedDB/localStorage.
- The JWT `sub` (auth uid) drives all RLS. Offline: a cached session lets
  the local store function without a live token; sync resumes on refresh.
- No session on launch → auth screen. After login → initial sync pulls the
  user's trips.

## 8. Clients

### 8.1 iOS (native, existing SwiftUI app)
- `WanderIQKit` value models survive. They already carry `modifiedAt`; add a
  tombstone flag and a local outbox store.
- Replace `SyncCoordinator` (CloudKit) with `SupabaseSyncCoordinator`
  implementing §6.
- Remove CloudKit entitlements and `CloudSharingView`; add `AuthView` and an
  email-invite sharing UI.
- `ReminderScheduler` unchanged. App remains offline-first via the local
  store.

### 8.2 PWA (evolved `trip-webapp/`)
- Drop the permissive single key-value table and anon-key "sharing".
- Add real auth, per-user data, an IndexedDB local store, and a TypeScript
  sync engine implementing §6.
- Reach feature parity with iOS: prep / itinerary / packing, reminders
  (where the platform allows), Apple/Google map links, per-day map.
- Remains an installable PWA (Android/web/desktop).

## 9. Sharing, import/export, migration

### 9.1 Sharing
1. Owner enters an email + role (`viewer`/`editor`).
2. App creates a `trip_members` row (`user_id` null, `invited_email` set,
   `status = pending`) and a signed invite token.
3. A Supabase **Edge Function** emails an invite link.
4. Invitee signs up / logs in; accepting links their `user_id` to the
   membership and sets `status = accepted`.
5. RLS now grants access; their client syncs the trip on next pull.
- Only the owner manages members or deletes the trip. Editors edit content;
  viewers are read-only (RLS + UI).

### 9.2 Import / export
- **JSON** — whole-trip, full fidelity (mirrors the in-memory Trip + days +
  items + places). Export serializes; import creates a **new trip owned by
  the importer** with fresh IDs to avoid collisions.
- **CSV** — flat, item-level within a trip. Columns:
  `kind,label,notes,day_date,time,owner,is_done,place_name,place_query`.
  Encoded UTF-8 **with BOM** so Excel preserves bilingual (中文) text.
  Import maps rows to items under matched/created days; place coordinates
  and trip metadata round-trip only through JSON.

### 9.3 Migration (v1 → v2)
- Ship a JSON export in a v1.x build; family exports once and imports into
  v2. No automated CloudKit→Supabase bridge. The canonical China trip is
  also re-seedable as a starting point.

## 10. Testing strategy

- **Sync logic (unit):** conflict resolution, outbox ordering, tombstone
  propagation, cursor advancement — tested against an in-memory fake, in the
  spirit of the existing `CloudKitMappingTests`.
- **Cross-engine conformance suite:** a shared set of given/when/then
  mutation scenarios that BOTH the Swift and TypeScript engines execute and
  must agree on. This is the primary safeguard against the two-engine drift
  risk inherent in the roll-our-own choice (§6).
- **RLS policy tests:** verify a user cannot read or write another user's
  trip; an editor cannot delete the trip; a viewer cannot write.
- **iOS UI smoke tests:** retained, updated for the auth gate.

## 11. Decisions locked during brainstorming

- Platforms: **Android + iOS** (plus web via the PWA) → a backend is
  required; CloudKit cannot reach Android.
- Android/web client: **evolve the existing PWA**, not a native Android app
  or a Flutter/KMP rewrite.
- Backend: **Supabase** (Postgres + Auth + Realtime + RLS; Edge Functions
  for invite emails).
- Offline: **full offline-first read + write**.
- Sync: **roll our own** outbox + Realtime with `modified_at` LWW
  (Approach A), de-risked by a written protocol contract + conformance
  suite. (Managed sync layers like PowerSync/ElectricSQL were considered and
  declined to avoid a third-party sync vendor.)
- Auth: **Apple + Google + email/password**.
- Sharing: **per-trip invite by email** with viewer/editor roles.
- Import/export: **JSON** (canonical) + **CSV** (flat item-level).
- CloudKit: **retired cleanly** in v2; v1 stays installable during
  transition but v2 is Supabase-only.

## 12. Implementation decomposition

This spec is the keystone. Implementation is sequenced into sub-projects,
each getting its own plan via the writing-plans skill:

1. **Supabase foundation** — schema, RLS policies, auth providers, Realtime
   config, Edge Function scaffold. (Blocked on the user creating a Supabase
   project + registering Apple/Google OAuth credentials.)
2. **Sync protocol + iOS engine** — extract the §6 contract doc, build the
   Swift outbox/Realtime engine + conformance suite.
3. **iOS app cutover** — auth UI, swap CloudKit → Supabase, retain features.
4. **PWA rebuild** — auth, per-user data, TS sync engine (same protocol),
   feature parity.
5. **Sharing** — email invites + roles + Edge Function + UI on both clients.
6. **Import/export** — JSON + CSV on both clients.

## 13. Prerequisites requiring user action

- Create a **Supabase project**; provide its URL + anon key (service-role
  key for migrations kept out of git, e.g. in a gitignored `.env`).
- Register **Apple** OAuth (Services ID + key) and **Google** OAuth client
  credentials; configure them in Supabase Auth.
- These gate sub-project 1.

## 14. Open items for planning (not blockers)

- Exact local-store technology on iOS (extend the current file store vs.
  adopt SQLite/GRDB) — decide in plan 2.
- Whether onboarding seeds a neutral "Sample Trip" or starts empty.
- Tombstone retention window and the scheduled purge mechanism.
- Reminder support boundaries on the PWA (web notification limits).
