import { test, expect } from "vitest";
import { applyRecord, recordFields } from "./tripMapping";
import { newTrip, type Trip } from "../model/trip";
import type { SyncRecord } from "./types";

function trips(...t: Trip[]): Map<string, Trip> {
  return new Map(t.map((x) => [x.id, x]));
}

test("applyRecord writes item fields into its trip", () => {
  const tripId = "00000000-0000-0000-0000-0000000000f1";
  const m = trips(newTrip({ id: tripId, name: "China" }));
  const rec: SyncRecord = {
    kind: "item", id: "i1", tripId, modifiedAt: 5, deleted: false,
    fields: { kind: "prep", label: "Buy", notes: "", isDone: "true", sortOrder: "2",
              placeName: "Museum", placeLat: "31.2" },
  };
  applyRecord(rec, m);
  const item = m.get(tripId)!.items[0];
  expect(item.label).toBe("Buy");
  expect(item.isDone).toBe(true);
  expect(item.sortOrder).toBe(2);
  expect(item.place?.name).toBe("Museum");
  expect(item.place?.latitude).toBeCloseTo(31.2);
  expect(item.modifiedAt).toBe(5);
});

test("applyRecord creates a shell trip when unknown, then applies trip fields", () => {
  const tripId = "00000000-0000-0000-0000-0000000000f2";
  const m = new Map<string, Trip>();
  applyRecord({ kind: "trip", id: tripId, tripId, modifiedAt: 9, deleted: false,
    fields: { name: "HK", startDate: "0", endDate: "0", destinations: "HK\u{1f}SZ", schemaVersion: "1" } }, m);
  expect(m.get(tripId)!.name).toBe("HK");
  expect(m.get(tripId)!.destinations).toEqual(["HK", "SZ"]);
});

test("recordFields round-trips an item back to wire fields", () => {
  const tripId = "00000000-0000-0000-0000-0000000000f1";
  const t = newTrip({ id: tripId, name: "China" });
  t.items.push({ id: "i1", kind: "packing", label: "Socks", notes: "", isDone: false,
    sortOrder: 1, modifiedAt: 3 });
  const f = recordFields("item", "i1", trips(t));
  expect(f.kind).toBe("packing");
  expect(f.label).toBe("Socks");
  expect(f.isDone).toBe("false");
  expect(f.sortOrder).toBe("1");
});
