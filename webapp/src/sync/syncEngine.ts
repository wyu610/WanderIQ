import { resolve } from "./conflictResolver";
import { entityKey, type SyncRecord } from "./types";
import type { Outbox } from "./outbox";
import type { RemoteSyncBackend } from "./remoteSyncBackend";

/** Record-level local mirror, keyed by entityKey. */
export interface LocalState {
  records: Map<string, SyncRecord>;
  tombstones: Map<string, number>; // id -> deletedAt
  cursor: number;
}

/** Apply a page of remote records via LWW, then advance the cursor. */
export function applyRecords(records: SyncRecord[], cursor: number, s: LocalState): void {
  for (const r of records) {
    const key = entityKey(r);
    const local = s.records.get(key);
    const decision = resolve(
      local ? local.modifiedAt : null,
      s.tombstones.get(r.id) ?? null,
      r.modifiedAt,
      r.deleted,
    );
    if (decision !== "applyRemote") continue;
    if (r.deleted) {
      s.records.delete(key);
      s.tombstones.set(r.id, r.modifiedAt);
    } else {
      s.records.set(key, r);
      s.tombstones.delete(r.id);
    }
  }
  s.cursor = Math.max(s.cursor, cursor);
}

/** Flush the outbox oldest-first, sending each record from `records`. */
export async function pushAll(
  outbox: Outbox,
  records: Map<string, SyncRecord>,
  backend: RemoteSyncBackend,
): Promise<void> {
  for (const change of [...outbox.pending]) {
    const key = entityKey(change);
    const record: SyncRecord =
      change.op === "delete"
        ? { kind: change.kind, id: change.id, tripId: change.tripId, modifiedAt: change.modifiedAt, deleted: true }
        : records.get(key) ?? {
            kind: change.kind, id: change.id, tripId: change.tripId,
            modifiedAt: change.modifiedAt, deleted: false, fields: {},
          };
    await backend.send([record]);
    outbox.acknowledge(change);
  }
}
