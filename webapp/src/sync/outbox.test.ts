import { test, expect } from "vitest";
import { Outbox } from "./outbox";

test("enqueue coalesces by key, keeping latest", () => {
  const box = new Outbox();
  box.enqueue({ kind: "item", id: "a", tripId: "t", op: "upsert", modifiedAt: 1 });
  box.enqueue({ kind: "item", id: "a", tripId: "t", op: "delete", modifiedAt: 2 });
  expect(box.pending.length).toBe(1);
  expect(box.pending[0].op).toBe("delete");
});

test("pending preserves insertion order across keys", () => {
  const box = new Outbox();
  box.enqueue({ kind: "day", id: "a", tripId: "t", op: "upsert", modifiedAt: 1 });
  box.enqueue({ kind: "item", id: "b", tripId: "t", op: "upsert", modifiedAt: 1 });
  expect(box.pending.map((c) => c.id)).toEqual(["a", "b"]);
});

test("acknowledge removes only the matching key", () => {
  const box = new Outbox();
  box.enqueue({ kind: "day", id: "a", tripId: "t", op: "upsert", modifiedAt: 1 });
  box.enqueue({ kind: "day", id: "b", tripId: "t", op: "upsert", modifiedAt: 1 });
  box.acknowledge({ kind: "day", id: "a" });
  expect(box.pending.map((c) => c.id)).toEqual(["b"]);
});
