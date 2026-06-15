import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { exportJSON, importJSON, exportCSV, importCSVItems } from "./tripExportCodec";
import { newTrip } from "../model/trip";

// The SAME fixture the Swift codec round-trips (6a) — the cross-platform guarantee.
const fixturePath = join(
  dirname(fileURLToPath(import.meta.url)),
  "../../../WanderIQKit/Tests/WanderIQKitTests/Fixtures/trip-export-sample.json",
);
const fixtureText = readFileSync(fixturePath, "utf8");

describe("trip export/import — cross-platform parity", () => {
  it("imports the shared Swift fixture with day-index remap + fresh ids", () => {
    const trip = importJSON(fixtureText);
    expect(trip.name).toBe("Sample Trip");
    expect(trip.days).toHaveLength(2);
    expect(trip.items).toHaveLength(2);

    const museum = trip.items.find((i) => i.label === "Astronomy Museum")!;
    expect(museum.dayId).toBe(trip.days[1].id);          // dayIndex 1 → 2nd day's fresh id
    expect(museum.place?.name).toBe("Shanghai Astronomy Museum");
    expect(museum.reminderDate).toBe(Math.floor(Date.parse("2026-07-10T01:30:00Z") / 1000));

    const passport = trip.items.find((i) => i.label === "Passport")!;
    expect(passport.dayId).toBeUndefined();              // dayIndex null → no day
    expect(passport.isDone).toBe(true);

    // Trip/day dates decode as UTC date-only.
    expect(trip.startDate).toBe(Math.floor(Date.parse("2026-07-11T00:00:00Z") / 1000));
    expect(trip.days[0].date).toBe(Math.floor(Date.parse("2026-07-11T00:00:00Z") / 1000));
  });

  it("re-exports Swift-importable JSON (no fractional seconds) and round-trips", () => {
    const trip = importJSON(fixtureText);
    const json = exportJSON(trip);
    // CRITICAL interop check: reminderDate must have NO millis (Swift can't parse .000Z).
    expect(json).toMatch(/"reminderDate": "2026-07-10T01:30:00Z"/);
    expect(json).not.toMatch(/\.\d{3}Z/);

    const trip2 = importJSON(json);
    expect(trip2.items).toHaveLength(2);
    expect(trip2.days).toHaveLength(2);
    expect(trip2.id).not.toBe(trip.id);                  // always a fresh trip id
    const museum2 = trip2.items.find((i) => i.label === "Astronomy Museum")!;
    expect(museum2.dayId).toBe(trip2.days[1].id);
  });

  it("CSV export has BOM + header + quoting; import adds items", () => {
    const trip = importJSON(fixtureText);
    const csv = exportCSV(trip);
    expect(csv.startsWith("﻿")).toBe(true);
    expect(csv).toContain("kind,label,notes,day_date,time,owner,is_done,place_name,place_query");
    expect(csv).toContain("Astronomy Museum");

    const empty = newTrip({ name: "T" });
    const filled = importCSVItems(
      '﻿kind,label,notes,day_date,time,owner,is_done,place_name,place_query\n' +
        'prep,"Buy, tickets",note,,09:30,Mom,false,,\n',
      empty,
    );
    expect(filled.items).toHaveLength(1);
    expect(filled.items[0].label).toBe("Buy, tickets");   // comma-in-quotes parsed
    expect(filled.items[0].kind).toBe("prep");
    expect(filled.items[0].time).toBe("09:30");
    expect(filled.items[0].isDone).toBe(false);
  });
});
