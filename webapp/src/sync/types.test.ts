import { test, expect } from "vitest";
import { entityKey, type PendingChange } from "./types";

test("entityKey is stable per (kind,id), independent of op/time", () => {
  const a: PendingChange = { kind: "item", id: "x", tripId: "t", op: "upsert", modifiedAt: 1 };
  const b: PendingChange = { kind: "item", id: "x", tripId: "t2", op: "delete", modifiedAt: 2 };
  expect(entityKey(a)).toBe(entityKey(b));
});

test("different kind, same id → distinct keys", () => {
  expect(entityKey({ kind: "day", id: "x", tripId: "t", op: "upsert", modifiedAt: 1 }))
    .not.toBe(entityKey({ kind: "item", id: "x", tripId: "t", op: "upsert", modifiedAt: 1 }));
});
