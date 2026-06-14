import { test, expect } from "vitest";
import { Outbox } from "./outbox";
import { FakeRemoteBackend } from "./remoteSyncBackend";
import { capture, applyPull, type TripState } from "./tripSync";
import { recordFields } from "./tripMapping";
import { newTrip } from "../model/trip";
import type { SyncRecord } from "./types";

test("A's trip+day+item converge onto B", async () => {
  const tripId = "00000000-0000-0000-0000-0000000000f1";
  const backend = new FakeRemoteBackend();

  // Device A
  const a: TripState = { trips: new Map(), tombstones: new Map(), cursor: 0 };
  const t = newTrip({ id: tripId, name: "China", modifiedAt: 5 });
  t.days.push({ id: "d1", date: 0, city: "Shanghai", title: "Arrive", modifiedAt: 5 });
  t.items.push({ id: "i1", kind: "prep", label: "Passport", notes: "", isDone: false, sortOrder: 0, modifiedAt: 5 });
  a.trips.set(tripId, t);
  const box = new Outbox();
  capture(undefined, t, box, a, 5);
  for (const c of [...box.pending]) {
    const rec: SyncRecord = c.op === "delete"
      ? { kind: c.kind, id: c.id, tripId: c.tripId, modifiedAt: c.modifiedAt, deleted: true }
      : { kind: c.kind, id: c.id, tripId: c.tripId, modifiedAt: c.modifiedAt, deleted: false,
          fields: recordFields(c.kind, c.id, a.trips) };
    await backend.send([rec]);
    box.acknowledge(c);
  }

  // Device B
  const b: TripState = { trips: new Map(), tombstones: new Map(), cursor: 0 };
  const page = await backend.changes(0);
  applyPull(page.records, page.cursor, b);

  const bt = b.trips.get(tripId)!;
  expect(bt.name).toBe("China");
  expect(bt.days[0].city).toBe("Shanghai");
  expect(bt.items[0].label).toBe("Passport");
});
