import Foundation
import Observation
import WanderIQKit

@MainActor
@Observable
final class AppModel {
    let store: TripStore
    private let repository: TripRepository
    @ObservationIgnored private var saveTasks: [UUID: Task<Void, Never>] = [:]
    let sync: SupabaseSyncCoordinator

    init() {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("trips")
        self.repository = TripRepository(directory: dir)
        // TODO: load per-file so one corrupt trip document doesn't hide all
        // trips (files stay on disk either way; spec: surface a banner).
        let trips = (try? repository.loadAll()) ?? []
        self.store = TripStore(trips: trips)
        self.sync = SupabaseSyncCoordinator(store: store,
                                            stateDirectory: URL.applicationSupportDirectory.appendingPathComponent("sync"))
        seedIfNeeded()
        store.onChange = { [weak self] trip in
            self?.scheduleSave(trip)
            self?.sync.noteLocalChange(trip)
        }
        store.onRemoteChange = { [weak self] trip in
            self?.scheduleSave(trip)
            self?.refreshReminders()
        }
        store.onRemoteRemove = { [weak self] id in
            try? self?.repository.delete(id: id)
            self?.refreshReminders()
        }
        // Sync starts from WanderIQApp once the user is signed in.
    }

    // MARK: - Intents (views call these, not the store directly)

    func addTrip(_ trip: Trip) {
        store.addTrip(trip)
        try? repository.save(trip)
    }

    func deleteTrip(id: UUID) {
        sync.noteLocalDelete(tripID: id)
        store.deleteTrip(id: id)
        try? repository.delete(id: id)
        refreshReminders()
    }

    func toggle(itemID: UUID, in tripID: UUID) {
        store.toggle(itemID: itemID, in: tripID)
        refreshReminders()
    }

    func addItem(_ item: ChecklistItem, to tripID: UUID) {
        store.addItem(item, to: tripID)
        refreshReminders()
    }

    func updateItem(_ item: ChecklistItem, in tripID: UUID) {
        store.updateItem(item, in: tripID)
        refreshReminders()
    }

    func deleteItem(id: UUID, in tripID: UUID) {
        store.deleteItem(id: id, in: tripID)
        refreshReminders()
    }

    func resetPacking(in tripID: UUID) {
        store.resetPacking(in: tripID)
    }

    // MARK: - Persistence (debounced, mirrors the PWA's 150 ms save)

    private func scheduleSave(_ trip: Trip) {
        saveTasks[trip.id]?.cancel()
        saveTasks[trip.id] = Task { [repository] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            try? repository.save(trip)
        }
    }

    // MARK: - Seed

    private func seedIfNeeded() {
        let key = "didSeedChinaTrip2026"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        if let trip = try? SeedLoader.loadChinaTrip2026() {
            store.addTrip(trip)
            try? repository.save(trip)
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: - Reminders (ReminderScheduler stub below is replaced in Task 9)

    func refreshReminders() {
        let trips = store.trips
        Task { await ReminderScheduler.refresh(trips: trips) }
    }
}
