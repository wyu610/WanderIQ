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
