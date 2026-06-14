import { test, expect } from "vitest";
import { FakeRemoteBackend } from "./remoteSyncBackend";

test("push then pull returns records after cursor", async () => {
  const backend = new FakeRemoteBackend();
  await backend.send([{ kind: "item", id: "i", tripId: "t", modifiedAt: 5, deleted: false, fields: { label: "X" } }]);
  const page = await backend.changes(0);
  expect(page.records.length).toBe(1);
  expect(page.cursor).toBeGreaterThan(0);
  const empty = await backend.changes(page.cursor);
  expect(empty.records.length).toBe(0);
});
