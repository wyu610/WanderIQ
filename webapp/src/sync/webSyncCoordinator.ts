import { supabase } from "../supabase/client";
import { SupabaseBackend } from "../supabase/supabaseBackend";
import { IdbStore } from "../store/idbStore";
import { Outbox } from "./outbox";
import { applyPull, capture, type TripState } from "./tripSync";
import type { Trip } from "../model/trip";
import type { RemoteSyncBackend } from "./remoteSyncBackend";

export class WebSyncCoordinator {
  readonly state: TripState = { trips: new Map(), tombstones: new Map(), cursor: 0 };
  private outbox = new Outbox();
  private readonly backend: RemoteSyncBackend = new SupabaseBackend(supabase);
  private readonly store = new IdbStore();
  private pushTimer: ReturnType<typeof setTimeout> | undefined;
  onChange: (() => void) | undefined;

  /** Load persisted state, pull, and subscribe to Realtime. */
  async start(): Promise<void> {
    const p = await this.store.load();
    this.outbox = Outbox.fromJSON(p.pending);
    this.state.tombstones = new Map(p.tombstones);
    this.state.cursor = p.cursor;
    await this.fetchNow();
    this.subscribeRealtime();
  }

  noteLocalChange(old: Trip | undefined, next: Trip): void {
    capture(old, next, this.outbox, this.state, Math.floor(Date.now() / 1000));
    this.state.trips.set(next.id, next);
    void this.persist();
    this.schedulePush();
    this.notify();
  }

  async fetchNow(): Promise<void> {
    const page = await this.backend.changes(this.state.cursor);
    applyPull(page.records, page.cursor, this.state);
    await this.persist();
    this.notify();
  }

  private notify(): void { this.onChange?.(); }

  private schedulePush(): void {
    clearTimeout(this.pushTimer);
    this.pushTimer = setTimeout(() => void this.flush(), 400);
  }

  private async flush(): Promise<void> {
    const pending = [...this.outbox.pending];
    if (pending.length === 0) return;
    const { recordFields } = await import("./tripMapping");
    for (const c of pending) {
      const fields = c.op === "delete" ? undefined : recordFields(c.kind, c.id, this.state.trips);
      await this.backend.send([{ kind: c.kind, id: c.id, tripId: c.tripId,
        modifiedAt: c.modifiedAt, deleted: c.op === "delete", fields }]);
      this.outbox.acknowledge(c);
    }
    await this.persist();
    this.notify();
  }

  private subscribeRealtime(): void {
    supabase.channel("wanderiq-web")
      .on("postgres_changes", { event: "*", schema: "public", table: "trips" }, () => void this.fetchNow())
      .on("postgres_changes", { event: "*", schema: "public", table: "trip_days" }, () => void this.fetchNow())
      .on("postgres_changes", { event: "*", schema: "public", table: "trip_items" }, () => void this.fetchNow())
      .subscribe();
  }

  private persist(): Promise<void> {
    return this.store.save({ pending: this.outbox.toJSON(),
      tombstones: [...this.state.tombstones.entries()], cursor: this.state.cursor });
  }
}
