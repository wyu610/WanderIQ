import { openDB, type IDBPDatabase } from "idb";
import type { PendingChange } from "../sync/types";

export interface PersistedState {
  pending: PendingChange[];
  tombstones: [string, number][]; // entries of Map<id, deletedAt>
  cursor: number;
}

const STORE = "sync";
const KEY = "state";

/** One-object-store IndexedDB persistence for the sync state + outbox. */
export class IdbStore {
  private dbp: Promise<IDBPDatabase>;
  constructor(name = "wanderiq") {
    this.dbp = openDB(name, 1, {
      upgrade(db) { db.createObjectStore(STORE); },
    });
  }

  async save(state: PersistedState): Promise<void> {
    (await this.dbp).put(STORE, state, KEY);
  }

  async load(): Promise<PersistedState> {
    const v = (await (await this.dbp).get(STORE, KEY)) as PersistedState | undefined;
    return v ?? { pending: [], tombstones: [], cursor: 0 };
  }

  /** Drop persisted sync state (sign-out / account deletion wipe). */
  async clear(): Promise<void> {
    (await this.dbp).delete(STORE, KEY);
  }
}
