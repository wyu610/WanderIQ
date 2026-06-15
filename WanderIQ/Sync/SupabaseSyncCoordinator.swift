import Foundation
import Supabase
import Observation
import WanderIQKit

/// Drives Supabase sync for the signed-in user using the pure SyncEngine.
/// Captures local edits into a persisted outbox (debounced push) and applies
/// pulled changes to the TripStore. No-ops when signed out.
@MainActor
@Observable
final class SupabaseSyncCoordinator {
    enum Status: Equatable { case idle, syncing, error(String) }
    private(set) var status: Status = .idle

    @ObservationIgnored private let store: TripStore
    @ObservationIgnored private let backend: RemoteSyncBackend
    @ObservationIgnored private let syncStore: SyncStore
    @ObservationIgnored private let client = AppSupabase.client

    @ObservationIgnored private var outbox: Outbox
    @ObservationIgnored private var state: SyncState
    @ObservationIgnored private var lastKnown: [UUID: Trip] = [:]
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var realtime: Task<Void, Never>?

    init(store: TripStore, stateDirectory: URL,
         backend: RemoteSyncBackend = SupabaseRemoteSyncBackend()) {
        self.store = store
        self.backend = backend
        self.syncStore = SyncStore(directory: stateDirectory)
        let loaded = syncStore.load()
        self.outbox = loaded.outbox
        self.state = loaded.state
        self.lastKnown = Dictionary(uniqueKeysWithValues: store.trips.map { ($0.id, $0) })
    }

    /// Synchronous: the in-memory session (no refresh). Sync no-ops when nil.
    private var isAuthed: Bool { client.auth.currentSession != nil }

    /// Called after sign-in (and on launch if already signed in).
    func start() async {
        guard isAuthed else { return }
        try? await SharingService().claimInvites()
        await fetchNow()
        subscribeRealtime()
    }

    /// Capture a local mutation into the outbox and schedule a push.
    func noteLocalChange(_ trip: Trip) {
        SyncEngine.capture(old: lastKnown[trip.id], new: trip,
                           into: &outbox, state: &state, now: Date())
        lastKnown[trip.id] = trip
        persist()
        schedulePush()
    }

    func noteLocalDelete(tripID: UUID) {
        // Tombstone the trip; peers remove it (and its children) on pull.
        SyncEngine.captureDelete(kind: .trip, id: tripID, tripID: tripID,
                                 deletedAt: Date(), into: &outbox, state: &state)
        lastKnown[tripID] = nil
        persist()
        schedulePush()
    }

    /// Manual/foreground pull.
    func fetchNow() async {
        guard isAuthed else { return }
        status = .syncing
        do {
            let page = try await backend.changes(since: state.cursor)
            SyncEngine.applyPull(page.records, cursor: page.cursor, store: store, state: &state)
            lastKnown = Dictionary(uniqueKeysWithValues: store.trips.map { ($0.id, $0) })
            persist()
            status = .idle
        } catch { status = .error(error.localizedDescription) }
    }

    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, self.isAuthed else { return }
            // SyncEngine.push can't take `inout self.outbox` across awaits
            // (exclusivity on a class property), so push a snapshot copy, then
            // acknowledge on the live outbox ONLY the keys actually sent. Edits
            // enqueued during the await stay in self.outbox untouched, and a
            // partial failure leaves un-sent entries queued.
            let before = Set(self.outbox.pending.map(\.key))
            var box = self.outbox
            do {
                try await SyncEngine.push(outbox: &box, store: self.store, backend: self.backend)
            } catch {
                self.status = .error(error.localizedDescription)
            }
            let sent = before.subtracting(box.pending.map(\.key))
            for key in sent { self.outbox.acknowledge(key) }
            self.persist()
        }
    }

    private func subscribeRealtime() {
        realtime?.cancel()
        realtime = Task { [weak self] in
            guard let self else { return }
            let channel = self.client.channel("wanderiq-sync")
            let trips = channel.postgresChange(AnyAction.self, schema: "public", table: "trips")
            let days  = channel.postgresChange(AnyAction.self, schema: "public", table: "trip_days")
            let items = channel.postgresChange(AnyAction.self, schema: "public", table: "trip_items")
            do { try await channel.subscribe() } catch { return }
            // Any change to an accessible row → targeted pull (cursor pull is
            // authoritative; Realtime is just a latency optimization).
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await _ in trips { await self.fetchNow() } }
                group.addTask { for await _ in days  { await self.fetchNow() } }
                group.addTask { for await _ in items { await self.fetchNow() } }
            }
        }
    }

    private func persist() { try? syncStore.save(outbox: outbox, state: state) }

    func stop() {
        pushTask?.cancel(); realtime?.cancel()
    }
}
