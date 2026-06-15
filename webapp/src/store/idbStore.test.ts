import { test, expect, beforeEach } from "vitest";
import "fake-indexeddb/auto";
import { IdbStore } from "./idbStore";
import { Outbox } from "../sync/outbox";

beforeEach(() => { indexedDB = new IDBFactory(); });

test("saves and loads outbox + cursor", async () => {
  const store = new IdbStore("test-db");
  const box = new Outbox();
  box.enqueue({ kind: "item", id: "i", tripId: "t", op: "upsert", modifiedAt: 3 });
  await store.save({ pending: box.toJSON(), tombstones: [["x", 7]], cursor: 9 });

  const loaded = await store.load();
  expect(loaded.pending.length).toBe(1);
  expect(loaded.cursor).toBe(9);
  expect(loaded.tombstones).toEqual([["x", 7]]);
});

test("load returns empty defaults on a fresh db", async () => {
  const loaded = await new IdbStore("fresh-db").load();
  expect(loaded.pending).toEqual([]);
  expect(loaded.cursor).toBe(0);
});
