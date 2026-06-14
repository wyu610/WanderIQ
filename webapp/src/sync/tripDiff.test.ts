import { test, expect } from "vitest";
import { diffTrip } from "./tripDiff";
import { newTrip } from "../model/trip";

test("new trip → trip save + each day/item save, no deletes", () => {
  const t = newTrip({ id: "t", name: "China" });
  t.days.push({ id: "d1", date: 0, city: "SH", title: "", modifiedAt: 1 });
  t.items.push({ id: "i1", kind: "prep", label: "X", notes: "", isDone: false, sortOrder: 0, modifiedAt: 1 });
  const { saves, deletes } = diffTrip(undefined, t);
  expect(saves).toContainEqual({ kind: "trip", id: "t" });
  expect(saves).toContainEqual({ kind: "day", id: "d1" });
  expect(saves).toContainEqual({ kind: "item", id: "i1" });
  expect(deletes).toEqual([]);
});

test("removed item → delete ref", () => {
  const old = newTrip({ id: "t", name: "China" });
  old.items.push({ id: "i1", kind: "prep", label: "X", notes: "", isDone: false, sortOrder: 0, modifiedAt: 1 });
  const now = newTrip({ id: "t", name: "China" });
  const { deletes } = diffTrip(old, now);
  expect(deletes).toContainEqual({ kind: "item", id: "i1" });
});
