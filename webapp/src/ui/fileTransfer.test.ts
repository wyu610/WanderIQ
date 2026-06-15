import { describe, it, expect } from "vitest";
import { tripFromImport } from "./fileTransfer";
import { exportJSON } from "../export/tripExportCodec";
import { newTrip } from "../model/trip";

describe("tripFromImport", () => {
  it("parses a .json file into a trip", () => {
    const json = exportJSON(newTrip({ name: "Roundtrip", startDate: 0, endDate: 0 }));
    const trip = tripFromImport("Roundtrip.json", json);
    expect(trip.name).toBe("Roundtrip");
  });

  it("parses a .csv file into a new trip named after the file", () => {
    const csv =
      "kind,label,notes,day_date,time,owner,is_done,place_name,place_query\n" +
      "packing,Socks,,,,,,,\n";
    const trip = tripFromImport("Beach.csv", csv);
    expect(trip.name).toBe("Beach");          // extension stripped
    expect(trip.items).toHaveLength(1);
    expect(trip.items[0].label).toBe("Socks");
  });
});
