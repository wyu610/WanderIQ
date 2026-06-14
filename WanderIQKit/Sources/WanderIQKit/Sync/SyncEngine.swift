import Foundation

/// Pure sync orchestration over a TripStore + SyncState. No network: callers
/// pass already-fetched records (pull) or read `pending` (push).
public enum SyncEngine {

    /// Apply a page of remote records to the store using LWW, then advance the
    /// cursor. Trip-kind records map to the trip's own fields; day/item records
    /// map to entries inside their trip (created as a shell if unknown).
    public static func applyPull(_ records: [SyncRecord], cursor: Date,
                                 store: TripStore, state: inout SyncState) {
        for rec in records { apply(rec, store: store, state: &state) }
        state.cursor = max(state.cursor, cursor)
    }

    private static func apply(_ rec: SyncRecord, store: TripStore, state: inout SyncState) {
        let localModifiedAt = localModified(of: rec, store: store)
        let decision = ConflictResolver.resolve(
            localModifiedAt: localModifiedAt,
            tombstone: state.tombstones[rec.id],
            remoteModifiedAt: rec.modifiedAt,
            remoteDeleted: rec.deleted)
        guard decision == .applyRemote else { return }

        if rec.deleted {
            remove(rec, store: store)
            state.tombstones[rec.id] = rec.modifiedAt
        } else {
            insertOrUpdate(rec, store: store)
            state.tombstones[rec.id] = nil
        }
    }

    private static func localModified(of rec: SyncRecord, store: TripStore) -> Date? {
        switch rec.kind {
        case .trip: return store.trip(id: rec.id)?.modifiedAt
        case .day:  return store.trip(id: rec.tripID)?.days.first { $0.id == rec.id }?.modifiedAt
        case .item: return store.trip(id: rec.tripID)?.items.first { $0.id == rec.id }?.modifiedAt
        }
    }

    private static func remove(_ rec: SyncRecord, store: TripStore) {
        switch rec.kind {
        case .trip: store.removeRemote(tripID: rec.id)
        case .day:  store.upsertRemote(tripID: rec.tripID) { $0.days.removeAll { $0.id == rec.id } }
        case .item: store.upsertRemote(tripID: rec.tripID) { $0.items.removeAll { $0.id == rec.id } }
        }
    }

    private static func insertOrUpdate(_ rec: SyncRecord, store: TripStore) {
        store.upsertRemote(tripID: rec.tripID) { trip in
            SyncMapping.apply(rec, to: &trip)
        }
    }

    // MARK: - Local change capture (push side)

    public static func captureUpsert(kind: EntityKind, id: UUID, tripID: UUID,
                                     modifiedAt: Date, into outbox: inout Outbox) {
        outbox.enqueue(PendingChange(kind: kind, id: id, tripID: tripID,
                                     op: .upsert, modifiedAt: modifiedAt))
    }

    public static func captureDelete(kind: EntityKind, id: UUID, tripID: UUID,
                                     deletedAt: Date, into outbox: inout Outbox,
                                     state: inout SyncState) {
        outbox.enqueue(PendingChange(kind: kind, id: id, tripID: tripID,
                                     op: .delete, modifiedAt: deletedAt))
        state.tombstones[id] = deletedAt
    }

    // MARK: - Push

    /// Flush the outbox oldest-first. Upserts read the latest entity state from
    /// the store; deletes send a tombstone. Each acknowledged entry is removed.
    public static func push(outbox: inout Outbox, store: TripStore,
                            backend: RemoteSyncBackend) async throws {
        for change in outbox.pending {
            let record = buildRecord(for: change, store: store)
            try await backend.send([record])
            outbox.acknowledge(change.key)
        }
    }

    static func buildRecord(for change: PendingChange, store: TripStore) -> SyncRecord {
        if change.op == .delete {
            return SyncRecord(kind: change.kind, id: change.id, tripID: change.tripID,
                              modifiedAt: change.modifiedAt, deleted: true)
        }
        let fields = SyncMapping.fields(kind: change.kind, id: change.id,
                                        tripID: change.tripID, store: store)
        return SyncRecord(kind: change.kind, id: change.id, tripID: change.tripID,
                          modifiedAt: change.modifiedAt, deleted: false, fields: fields)
    }

    // MARK: - Capture from a trip diff (push side)

    /// Diff `old`→`new` and enqueue the resulting upserts/deletes. Saves carry
    /// the entity's own modifiedAt; deletes carry `now` as the deletion time.
    public static func capture(old: Trip?, new: Trip, into outbox: inout Outbox,
                               state: inout SyncState, now: Date) {
        let diff = TripDiff.changes(old: old, new: new)
        for ref in diff.saves {
            switch ref {
            case .tripMeta:
                captureUpsert(kind: .trip, id: new.id, tripID: new.id,
                              modifiedAt: new.modifiedAt ?? now, into: &outbox)
            case .day(let id):
                let at = new.days.first { $0.id == id }?.modifiedAt ?? now
                captureUpsert(kind: .day, id: id, tripID: new.id, modifiedAt: at, into: &outbox)
            case .item(let id):
                let at = new.items.first { $0.id == id }?.modifiedAt ?? now
                captureUpsert(kind: .item, id: id, tripID: new.id, modifiedAt: at, into: &outbox)
            }
        }
        for ref in diff.deletes {
            switch ref {
            case .tripMeta:
                captureDelete(kind: .trip, id: new.id, tripID: new.id,
                              deletedAt: now, into: &outbox, state: &state)
            case .day(let id):
                captureDelete(kind: .day, id: id, tripID: new.id,
                              deletedAt: now, into: &outbox, state: &state)
            case .item(let id):
                captureDelete(kind: .item, id: id, tripID: new.id,
                              deletedAt: now, into: &outbox, state: &state)
            }
        }
    }
}
