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

    // MARK: - Helpers

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

    // MARK: - Send path (Task 6)

    /// Queue every record of a trip (first sync of a local trip).
    func queueFullTrip(_ trip: Trip) {
        guard let engine = engine(for: trip.id) else { return }
        let owner = owner(for: trip.id)
        if !sharedTripIDs.contains(trip.id) {
            let zone = CKRecordZone(zoneID: CloudKitMapping.zoneID(forTripID: trip.id, owner: owner))
            engine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
        }
        let diff = TripDiff.changes(old: nil, new: trip)
        engine.state.add(pendingRecordZoneChanges: diff.saves.map { .saveRecord(recordID($0, tripID: trip.id)) })
        lastKnown[trip.id] = trip
    }

    /// Called (via AppModel) after every local mutation.
    func noteLocalChange(_ trip: Trip) {
        guard let engine = engine(for: trip.id) else { return }
        if lastKnown[trip.id] == nil, !sharedTripIDs.contains(trip.id) {
            queueFullTrip(trip)
            return
        }
        let diff = TripDiff.changes(old: lastKnown[trip.id], new: trip)
        guard !diff.saves.isEmpty || !diff.deletes.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges:
            diff.saves.map { .saveRecord(recordID($0, tripID: trip.id)) } +
            diff.deletes.map { .deleteRecord(recordID($0, tripID: trip.id)) })
        lastKnown[trip.id] = trip
    }

    /// Called when the user deletes a trip locally: drop the whole zone.
    func noteLocalDelete(tripID: UUID) {
        guard let engine = engine(for: tripID) else { return }
        engine.state.add(pendingDatabaseChanges:
            [.deleteZone(CloudKitMapping.zoneID(forTripID: tripID, owner: owner(for: tripID)))])
        lastKnown[tripID] = nil
    }

    private func recordID(_ ref: TripRecordRef, tripID: UUID) -> CKRecord.ID {
        let owner = owner(for: tripID)
        switch ref {
        case .tripMeta: return CloudKitMapping.tripMetaRecordID(tripID: tripID, owner: owner)
        case .day(let id): return CloudKitMapping.dayRecordID(id, tripID: tripID, owner: owner)
        case .item(let id): return CloudKitMapping.itemRecordID(id, tripID: tripID, owner: owner)
        }
    }

    /// Build the current CKRecord for a record ID, or nil if the entity no
    /// longer exists locally (the engine then drops the pending save).
    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let tripID = CloudKitMapping.tripID(fromZoneName: recordID.zoneID.zoneName),
              let trip = store.trip(id: tripID) else { return nil }
        let owner = recordID.zoneID.ownerName
        if recordID.recordName == CloudKitMapping.tripMetaRecordName {
            return CloudKitMapping.tripMetaRecord(for: trip, owner: owner)
        }
        guard let entityID = UUID(uuidString: recordID.recordName) else { return nil }
        if let item = trip.items.first(where: { $0.id == entityID }) {
            return CloudKitMapping.itemRecord(for: item, tripID: tripID, owner: owner)
        }
        if let day = trip.days.first(where: { $0.id == entityID }) {
            return CloudKitMapping.dayRecord(for: day, tripID: tripID, owner: owner)
        }
        return nil
    }

    // MARK: - Conflict resolution

    /// Spec conflict policy: per-record last-writer-wins. The server copy is
    /// the baseline; if our local entity was modified more recently than the
    /// server's, requeue our save (now carrying the server change tag).
    private func handleFailedSave(_ record: CKRecord, error: CKError, engine: CKSyncEngine) {
        switch error.code {
        case .serverRecordChanged:
            guard let serverRecord = error.serverRecord,
                  let tripID = CloudKitMapping.tripID(fromZoneName: record.recordID.zoneID.zoneName) else { return }
            let serverModified = serverRecord["modifiedAt"] as? Date ?? .distantPast
            let localModified = record["modifiedAt"] as? Date ?? .distantPast
            if localModified > serverModified {
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            } else {
                applyFetchedRecord(serverRecord)   // accept server copy locally (Task 7)
            }
            _ = tripID
        case .zoneNotFound:
            // Zone was deleted remotely or never created: recreate and resend everything.
            if let tripID = CloudKitMapping.tripID(fromZoneName: record.recordID.zoneID.zoneName),
               let trip = store.trip(id: tripID) {
                queueFullTrip(trip)
            }
        case .unknownItem, .invalidArguments:
            break   // dropped: entity no longer exists or schema mismatch
        default:
            status = .error(error.localizedDescription)
        }
    }

    /// Stub until Task 7.
    private func applyFetchedRecord(_ record: CKRecord) {}
}

// MARK: - CKSyncEngineDelegate

extension SyncCoordinator: CKSyncEngineDelegate {

    // SDK note: CKSyncEngineDelegate inherits Sendable and the coordinator is
    // @MainActor, so these nonisolated implementations await onto the main actor
    // before touching any mutable state.

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await MainActor.run { handle(event, engine: syncEngine) }
    }

    // SDK adaptation: RecordZoneChangeBatch.init(pendingChanges:recordProvider:) is
    // declared `async` in the Xcode 26.5 SDK (it was non-async in the WWDC23 sample).
    // We use the synchronous init(recordsToSave:recordIDsToDelete:) instead, resolving
    // records inline on the main actor.
    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await MainActor.run { makeBatch(context: context, engine: syncEngine) }
    }

    // MARK: Private helpers (all @MainActor via class isolation)

    private func handle(_ event: CKSyncEngine.Event, engine: CKSyncEngine) {
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization, name: stateFileName(for: engine))

        case .sentRecordZoneChanges(let sent):
            for failed in sent.failedRecordSaves {
                handleFailedSave(failed.record, error: failed.error, engine: engine)
            }

        default:
            break   // fetch events implemented in Task 7
        }
    }

    private func makeBatch(context: CKSyncEngine.SendChangesContext,
                           engine: CKSyncEngine) -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = engine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }

        var recordsToSave: [CKRecord] = []
        var recordIDsToDelete: [CKRecord.ID] = []

        for change in pending {
            switch change {
            case .saveRecord(let recordID):
                if let record = record(for: recordID) {
                    recordsToSave.append(record)
                }
                // If record(for:) returns nil the entity was deleted locally;
                // the engine drops the pending save when we don't include it.
            case .deleteRecord(let recordID):
                recordIDsToDelete.append(recordID)
            @unknown default:
                break
            }
        }

        guard !recordsToSave.isEmpty || !recordIDsToDelete.isEmpty else { return nil }
        return CKSyncEngine.RecordZoneChangeBatch(
            recordsToSave: recordsToSave,
            recordIDsToDelete: recordIDsToDelete)
    }
}
