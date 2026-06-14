import { entityKey, type EntityKind, type PendingChange } from "./types";

/** Insertion-ordered, key-coalesced pending changes (protocol §"Outbox"). */
export class Outbox {
  private order: string[] = [];
  private byKey = new Map<string, PendingChange>();

  get pending(): PendingChange[] {
    return this.order.map((k) => this.byKey.get(k)!).filter(Boolean);
  }
  get isEmpty(): boolean {
    return this.byKey.size === 0;
  }

  enqueue(change: PendingChange): void {
    const key = entityKey(change);
    if (!this.byKey.has(key)) this.order.push(key);
    this.byKey.set(key, change);
  }

  acknowledge(ref: { kind: EntityKind; id: string }): void {
    const key = entityKey(ref);
    this.byKey.delete(key);
    this.order = this.order.filter((k) => k !== key);
  }

  toJSON(): PendingChange[] {
    return this.pending;
  }
  static fromJSON(list: PendingChange[]): Outbox {
    const box = new Outbox();
    for (const c of list) box.enqueue(c);
    return box;
  }
}
