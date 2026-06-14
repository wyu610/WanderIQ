import type { Trip } from "../model/trip";
import type { EntityKind } from "./types";

export interface EntityRef { kind: EntityKind; id: string; }
export interface TripDiffResult { saves: EntityRef[]; deletes: EntityRef[]; }

const eq = (a: unknown, b: unknown): boolean => JSON.stringify(a) === JSON.stringify(b);

/** Mirror of the Swift TripDiff: which entities changed between snapshots. */
export function diffTrip(old: Trip | undefined, next: Trip): TripDiffResult {
  if (!old) {
    return {
      saves: [{ kind: "trip", id: next.id },
        ...next.days.map((d) => ({ kind: "day" as const, id: d.id })),
        ...next.items.map((i) => ({ kind: "item" as const, id: i.id }))],
      deletes: [],
    };
  }
  const saves: EntityRef[] = [];
  const deletes: EntityRef[] = [];

  const metaChanged = old.name !== next.name || old.startDate !== next.startDate
    || old.endDate !== next.endDate || !eq(old.destinations, next.destinations)
    || old.schemaVersion !== next.schemaVersion;
  if (metaChanged) saves.push({ kind: "trip", id: next.id });

  diffList(old.days, next.days, "day", saves, deletes);
  diffList(old.items, next.items, "item", saves, deletes);
  return { saves, deletes };
}

function diffList<T extends { id: string }>(
  oldArr: T[], newArr: T[], kind: EntityKind, saves: EntityRef[], deletes: EntityRef[],
): void {
  const oldMap = new Map(oldArr.map((x) => [x.id, x]));
  const newMap = new Map(newArr.map((x) => [x.id, x]));
  for (const [id, v] of newMap) if (!eq(oldMap.get(id), v)) saves.push({ kind, id });
  for (const id of oldMap.keys()) if (!newMap.has(id)) deletes.push({ kind, id });
}
