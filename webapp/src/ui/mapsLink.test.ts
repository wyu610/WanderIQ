import { describe, it, expect } from "vitest";
import { mapsUrl } from "./mapsLink";

describe("mapsUrl", () => {
  it("uses lat,lon when present", () => {
    expect(mapsUrl({ name: "Museum", query: "q", latitude: 30.9, longitude: 121.7 }))
      .toBe("https://www.google.com/maps/search/?api=1&query=30.9%2C121.7");
  });
  it("falls back to query, then name", () => {
    expect(mapsUrl({ name: "Museum", query: "Shanghai Museum" }))
      .toBe("https://www.google.com/maps/search/?api=1&query=Shanghai%20Museum");
    expect(mapsUrl({ name: "Museum", query: "" }))
      .toBe("https://www.google.com/maps/search/?api=1&query=Museum");
  });
});
