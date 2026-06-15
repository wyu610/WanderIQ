import { test, expect } from "vitest";
import { recordToRow, rowToRecord } from "./rowMapping";
import type { SyncRecord } from "../sync/types";

const ISO = "2026-06-14T00:00:05.000Z";
const EPOCH = Math.floor(Date.parse(ISO) / 1000); // seconds

test("rowToRecord: item row → SyncRecord with epoch modifiedAt + string fields", () => {
  const row = {
    id: "i1", trip_id: "t1", kind: "prep", label: "Buy", notes: "", day_id: null,
    time: "09:30", item_owner: "Mom", is_done: true, sort_order: 2, reminder_date: null,
    place: { name: "Museum", query: "M", latitude: 31.2, longitude: 121.0 },
    modified_at: ISO, deleted: false,
  };
  const rec = rowToRecord("item", row);
  expect(rec.modifiedAt).toBe(EPOCH);
  expect(rec.deleted).toBe(false);
  expect(rec.fields?.label).toBe("Buy");
  expect(rec.fields?.isDone).toBe("true");
  expect(rec.fields?.sortOrder).toBe("2");
  expect(rec.fields?.placeName).toBe("Museum");
  expect(rec.fields?.placeLat).toBe("31.2");
});

test("rowToRecord: trip date column (ISO date) → epoch-seconds string field", () => {
  const row = { id: "t1", owner_id: "u", name: "China", start_date: "2026-07-11",
    end_date: "2026-07-31", destinations: ["SH", "HK"], schema_version: 1,
    modified_at: ISO, deleted: false };
  const rec = rowToRecord("trip", row);
  expect(rec.fields?.name).toBe("China");
  expect(rec.fields?.startDate).toBe(String(Math.floor(Date.parse("2026-07-11") / 1000)));
  expect(rec.fields?.destinations).toBe("SH\u{1f}HK");
});

test("recordToRow: trip SyncRecord → row with ISO dates and owner_id injected", () => {
  const rec: SyncRecord = { kind: "trip", id: "t1", tripId: "t1", modifiedAt: EPOCH, deleted: false,
    fields: { name: "China", startDate: String(Math.floor(Date.parse("2026-07-11") / 1000)),
      endDate: "0", destinations: "SH\u{1f}HK", schemaVersion: "1" } };
  const row = recordToRow(rec, "user-123") as Record<string, unknown>;
  expect(row.id).toBe("t1");
  expect(row.owner_id).toBe("user-123");
  expect(row.name).toBe("China");
  expect(row.start_date).toBe("2026-07-11");
  expect(row.destinations).toEqual(["SH", "HK"]);
  expect(row.modified_at).toBe(ISO);
  expect(row.deleted).toBe(false);
});

test("recordToRow: tombstone → minimal deleted row", () => {
  const rec: SyncRecord = { kind: "item", id: "i1", tripId: "t1", modifiedAt: EPOCH, deleted: true };
  const row = recordToRow(rec, "user-123") as Record<string, unknown>;
  expect(row.id).toBe("i1");
  expect(row.trip_id).toBe("t1");
  expect(row.deleted).toBe(true);
  expect(row.modified_at).toBe(ISO);
});
