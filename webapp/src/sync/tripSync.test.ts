import { test, expect } from "vitest";
import { applyPull, capture, type TripState } from "./tripSync";
import { Outbox } from "./outbox";
import { newTrip, type Trip } from "../model/trip";
import type { SyncRecord } from "./types";

function state(...t: Trip[]): TripState {
  return { trips: new Map(t.map((x) => [x.id, x])), tombstones: new Map(), cursor: 0 };
}

test("applyPull applies a newer trip record and advances the cursor", () => {
  const s = state(newTrip({ id: "t", name: "Old", modifiedAt: 1 }));
  const rec: SyncRecord = { kind: "trip", id: "t", tripId: "t", modifiedAt: 2, deleted: false,
    fields: { name: "New", startDate: "0", endDate: "0", destinations: "", schemaVersion: "1" } };
  applyPull([rec], 9, s);
  expect(s.trips.get("t")!.name).toBe("New");
  expect(s.cursor).toBe(9);
});

test("applyPull removes a trip on a newer tombstone", () => {
  const s = state(newTrip({ id: "t", name: "X", modifiedAt: 1 }));
  applyPull([{ kind: "trip", id: "t", tripId: "t", modifiedAt: 2, deleted: true }], 9, s);
  expect(s.trips.has("t")).toBe(false);
  expect(s.tombstones.get("t")).toBe(2);
});

test("capture enqueues upserts for a new trip and its item", () => {
  const box = new Outbox(); const s = state();
  const t = newTrip({ id: "t", name: "China", modifiedAt: 5 });
  t.items.push({ id: "i1", kind: "prep", label: "X", notes: "", isDone: false, sortOrder: 0, modifiedAt: 5 });
  capture(undefined, t, box, s, 5);
  const kinds = box.pending.map((c) => c.kind).sort();
  expect(kinds).toEqual(["item", "trip"]);
});
