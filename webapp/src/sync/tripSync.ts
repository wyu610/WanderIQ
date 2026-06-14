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
