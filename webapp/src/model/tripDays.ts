import type { TripDay } from "./trip";

const DAY = 86400; // seconds

/** One TripDay per UTC day from start..end inclusive (mirrors iOS NewTripView). */
export function daysInRange(startEpoch: number, endEpoch: number): TripDay[] {
  const start = Math.floor(startEpoch / DAY) * DAY;
  const end = Math.floor(endEpoch / DAY) * DAY;
  const days: TripDay[] = [];
  for (let d = start; d <= end; d += DAY) {
    days.push({ id: crypto.randomUUID(), date: d, city: "", title: "", modifiedAt: Math.floor(Date.now() / 1000) });
  }
  return days;
}
