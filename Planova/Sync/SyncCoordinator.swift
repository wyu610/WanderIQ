import Foundation
import CloudKit
import Observation
import PlanovaKit

/// Owns the CloudKit sync engines (private + shared databases), persists
/// their state serializations, and bridges between TripStore and CKRecords.
/// All UI-facing state is @MainActor.
@MainActor
@Observable
final class SyncCoordinator {

    enum Status: Equatable {
        case unavailable(String)   // no iCloud account / restricted
        case idle
        case syncing
        case error(String)
    }

    private(set) var status: Status = .unavailable("Checking iCloud…")

    static let containerID = "iCloud.com.planova.Planova"

    private let container: CKContainer
    private let store: TripStore
    private let stateDirectory: URL
    @ObservationIgnored private var privateEngine: CKSyncEngine?
    @ObservationIgnored private var sharedEngine: CKSyncEngine?
    /// Snapshot of each trip as of the last diff, for change detection.
    @ObservationIgnored private var lastKnown: [UUID: Trip] = [:]
    /// Trips that live in the shared database (we are a participant).
    @ObservationIgnored private(set) var sharedTripIDs: Set<UUID> = []
    /// Zone owner names for shared trips (needed to build record IDs).
    @ObservationIgnored private var zoneOwners: [UUID: String] = [:]

    init(store: TripStore, stateDirectory: URL) {
        self.container = CKContainer(identifier: Self.containerID)
        self.store = store
        self.stateDirectory = stateDirectory
    }

    // MARK: - Lifecycle

    func start() async {
        do {
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                status = .unavailable(Self.describe(accountStatus))
                return
            }
        } catch {
            status = .unavailable(error.localizedDescription)
            return
        }
        lastKnown = Dictionary(uniqueKeysWithValues: store.trips.map { ($0.id, $0) })
        privateEngine = makeEngine(database: container.privateCloudDatabase, stateFile: "private-sync-state")
        sharedEngine = makeEngine(database: container.sharedCloudDatabase, stateFile: "shared-sync-state")
        status = .idle
        // First run: ensure every local trip has a zone + records queued.
        for trip in store.trips where !sharedTripIDs.contains(trip.id) {
            queueFullTrip(trip)
        }
    }

    private func makeEngine(database: CKDatabase, stateFile: String) -> CKSyncEngine {
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: loadState(stateFile),
            delegate: self)
        configuration.automaticallySync = true
        return CKSyncEngine(configuration)
    }

    /// Manual refresh (pull-to-refresh / foreground), since simulator gets no push.
    func fetchNow() async {
        guard let privateEngine, let sharedEngine else { return }
        status = .syncing
        try? await privateEngine.fetchChanges()
        try? await sharedEngine.fetchChanges()
        status = .idle
    }

    private static func describe(_ s: CKAccountStatus) -> String {
        switch s {
        case .noAccount: return String(localized: "Sign in to iCloud to sync")
        case .restricted: return String(localized: "iCloud is restricted")
        case .temporarilyUnavailable: return String(localized: "iCloud temporarily unavailable")
        default: return String(localized: "iCloud unavailable")
        }
    }

    // MARK: - State serialization persistence

    private func stateURL(_ name: String) -> URL {
        stateDirectory.appendingPathComponent(name + ".data")
    }

    private func loadState(_ name: String) -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL(name)) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ serialization: CKSyncEngine.State.Serialization, name: String) {
        try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(serialization) {
            try? data.write(to: stateURL(name), options: .atomic)
        }
    }

    private func stateFileName(for engine: CKSyncEngine) -> String {
        engine === privateEngine ? "private-sync-state" : "shared-sync-state"
    }

    // MARK: - Helpers used by send/fetch paths (Tasks 6–7)

    func owner(for tripID: UUID) -> String {
        zoneOwners[tripID] ?? CKCurrentUserDefaultName
    }

    func engine(for tripID: UUID) -> CKSyncEngine? {
        sharedTripIDs.contains(tripID) ? sharedEngine : privateEngine
    }

    func noteShared(tripID: UUID, ownerName: String) {
        sharedTripIDs.insert(tripID)
        zoneOwners[tripID] = ownerName
    }

    func queueFullTrip(_ trip: Trip) {
        // Implemented in Task 6.
    }
}

// MARK: - CKSyncEngineDelegate (fleshed out in Tasks 6–7)

extension SyncCoordinator: CKSyncEngineDelegate {

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await MainActor.run { handle(event, engine: syncEngine) }
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await MainActor.run { makeBatch(context: context, engine: syncEngine) }
    }

    private func handle(_ event: CKSyncEngine.Event, engine: CKSyncEngine) {
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization, name: stateFileName(for: engine))
        default:
            break   // send/fetch events implemented in Tasks 6–7
        }
    }

    // SDK adaptation: RecordZoneChangeBatch(pendingChanges:recordProvider:) is async
    // in the Xcode 26.5 SDK; we use the synchronous init(recordsToSave:recordIDsToDelete:)
    // instead (stub returns nil until Task 6).
    private func makeBatch(context: CKSyncEngine.SendChangesContext,
                           engine: CKSyncEngine) -> CKSyncEngine.RecordZoneChangeBatch? {
        nil   // Implemented in Task 6.
    }
}
