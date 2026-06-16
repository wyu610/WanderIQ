import { describe, it, expect } from "vitest";
import { daysInRange } from "./tripDays";

describe("daysInRange", () => {
  it("builds one TripDay per UTC day, inclusive", () => {
    const start = Date.parse("2026-07-11T00:00:00Z") / 1000;
    const end = Date.parse("2026-07-13T00:00:00Z") / 1000;
    const days = daysInRange(start, end);
    expect(days).toHaveLength(3);
    expect(days[0].date).toBe(start);
    expect(days[2].date).toBe(end);
    expect(days.every((d) => d.city === "" && d.title === "" && typeof d.id === "string")).toBe(true);
  });
  it("returns a single day when start == end, and [] when end < start", () => {
    const t = Date.parse("2026-07-11T00:00:00Z") / 1000;
    expect(daysInRange(t, t)).toHaveLength(1);
    expect(daysInRange(t, t - 86400)).toHaveLength(0);
  });
});
