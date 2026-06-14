export type EntityKind = "trip" | "day" | "item";
export type SyncOp = "upsert" | "delete";

/** Times are epoch numbers (seconds), matching the conformance fixture. */
export interface PendingChange {
  kind: EntityKind;
  id: string;
  tripId: string;
  op: SyncOp;
  modifiedAt: number;
}

export interface SyncRecord {
  kind: EntityKind;
  id: string;
  tripId: string;
  modifiedAt: number;
  deleted: boolean;
  fields?: Record<string, string>;
}

/** Stable coalescing key: one pending change per (kind, id). */
export function entityKey(c: { kind: EntityKind; id: string }): string {
  return `${c.kind}:${c.id}`;
}
