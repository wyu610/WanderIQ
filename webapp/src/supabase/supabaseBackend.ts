import type { SupabaseClient } from "@supabase/supabase-js";
import type { ChangePage, RemoteSyncBackend } from "../sync/remoteSyncBackend";
import type { EntityKind, SyncRecord } from "../sync/types";
import { recordToRow, rowToRecord, type Row } from "./rowMapping";

const TABLE: Record<EntityKind, string> = { trip: "trips", day: "trip_days", item: "trip_items" };

/** RemoteSyncBackend over Supabase PostgREST. server_updated_at drives the cursor. */
export class SupabaseBackend implements RemoteSyncBackend {
  constructor(private readonly client: SupabaseClient) {}

  async send(records: SyncRecord[]): Promise<void> {
    const { data } = await this.client.auth.getUser();
    const ownerId = data.user?.id ?? "";
    for (const kind of ["trip", "day", "item"] as EntityKind[]) {
      const rows = records.filter((r) => r.kind === kind).map((r) => recordToRow(r, ownerId));
      if (rows.length === 0) continue;
      const { error } = await this.client.from(TABLE[kind]).upsert(rows, { onConflict: "id" });
      if (error) throw error;
    }
  }

  async changes(since: number): Promise<ChangePage> {
    const sinceISO = new Date(since * 1000).toISOString();
    const records: SyncRecord[] = [];
    let maxStamp = since;
    for (const kind of ["trip", "day", "item"] as EntityKind[]) {
      const { data, error } = await this.client.from(TABLE[kind]).select("*")
        .gt("server_updated_at", sinceISO).order("server_updated_at", { ascending: true });
      if (error) throw error;
      for (const row of (data ?? []) as Row[]) {
        records.push(rowToRecord(kind, row));
        const s = Math.floor(Date.parse(String(row.server_updated_at)) / 1000);
        if (s > maxStamp) maxStamp = s;
      }
    }
    return { records, cursor: maxStamp };
  }
}
