import { test, expect } from "vitest";
import { applyRecords, pushAll, type LocalState } from "./syncEngine";
import { Outbox } from "./outbox";
import { FakeRemoteBackend } from "./remoteSyncBackend";
import type { SyncRecord } from "./types";

function emptyState(): LocalState {
  return { records: new Map(), tombstones: new Map(), cursor: 0 };
}

test("applyRecords applies newer upsert and advances cursor", () => {
  const s = emptyState();
  const rec: SyncRecord = { kind: "item", id: "i", tripId: "t", modifiedAt: 5, deleted: false, fields: { label: "X" } };
  applyRecords([rec], 9, s);
  expect(s.records.get("item:i")?.fields?.label).toBe("X");
  expect(s.cursor).toBe(9);
});

test("applyRecords honors a remote tombstone", () => {
  const s = emptyState();
  s.records.set("item:i", { kind: "item", id: "i", tripId: "t", modifiedAt: 1, deleted: false, fields: {} });
  applyRecords([{ kind: "item", id: "i", tripId: "t", modifiedAt: 2, deleted: true }], 9, s);
  expect(s.records.has("item:i")).toBe(false);
  expect(s.tombstones.get("i")).toBe(2);
});

test("pushAll sends pending records and clears the outbox", async () => {
  const box = new Outbox();
  box.enqueue({ kind: "item", id: "i", tripId: "t", op: "upsert", modifiedAt: 3 });
  const records = new Map<string, SyncRecord>([
    ["item:i", { kind: "item", id: "i", tripId: "t", modifiedAt: 3, deleted: false, fields: { label: "Buy" } }],
  ]);
  const backend = new FakeRemoteBackend();
  await pushAll(box, records, backend);
  expect(box.isEmpty).toBe(true);
  const page = await backend.changes(0);
  expect(page.records[0].fields?.label).toBe("Buy");
});
