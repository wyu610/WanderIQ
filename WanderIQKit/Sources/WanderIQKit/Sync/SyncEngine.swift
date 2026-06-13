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
}
