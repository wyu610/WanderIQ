import { entityKey, type SyncRecord } from "./types";

export interface ChangePage {
  records: SyncRecord[];
  cursor: number;
}

/** Transport abstraction. The Supabase implementation arrives in 4b. */
export interface RemoteSyncBackend {
  send(records: SyncRecord[]): Promise<void>;
  changes(since: number): Promise<ChangePage>;
}

/** In-memory backend for tests; monotonic server clock models server_updated_at. */
export class FakeRemoteBackend implements RemoteSyncBackend {
  private stored = new Map<string, { record: SyncRecord; serverAt: number }>();
  private clock = 0;

  async send(records: SyncRecord[]): Promise<void> {
    for (const r of records) {
      this.clock += 1;
      this.stored.set(entityKey(r), { record: r, serverAt: this.clock });
    }
  }

  async changes(since: number): Promise<ChangePage> {
    const fresh = [...this.stored.values()]
      .filter((e) => e.serverAt > since)
      .sort((a, b) => a.serverAt - b.serverAt);
    const cursor = fresh.length ? fresh[fresh.length - 1].serverAt : since;
    return { records: fresh.map((e) => e.record), cursor };
  }
}
