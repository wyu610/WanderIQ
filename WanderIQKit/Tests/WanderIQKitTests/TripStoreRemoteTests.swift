import Testing
import Foundation
@testable import WanderIQKit

@Suite struct TripStoreRemoteTests {

    @Test func upsertRemoteCreatesShellAndDoesNotTriggerOnChange() {
        let store = TripStore()
        var onChangeFired = false
        var remoteChanged: Trip?
        store.onChange = { _ in onChangeFired = true }
        store.onRemoteChange = { remoteChanged = $0 }
        let id = UUID()

        store.upsertRemote(tripID: id) { trip in
            trip.name = "From cloud"
        }

        #expect(store.trip(id: id)?.name == "From cloud")
        #expect(onChangeFired == false)
        #expect(remoteChanged?.id == id)
    }

    @Test func upsertRemoteMutatesExistingTrip() {
        let trip = Trip(name: "Local", startDate: Date(timeIntervalSince1970: 0), endDate: Date(timeIntervalSince1970: 1))
        let store = TripStore(trips: [trip])

        store.upsertRemote(tripID: trip.id) { $0.items.append(ChecklistItem(kind: .prep, label: "x")) }

        #expect(store.trip(id: trip.id)?.items.count == 1)
        #expect(store.trip(id: trip.id)?.name == "Local")
    }

    @Test func removeRemoteDeletesAndNotifiesRemoval() {
        let trip = Trip(name: "T", startDate: Date(timeIntervalSince1970: 0), endDate: Date(timeIntervalSince1970: 1))
        let store = TripStore(trips: [trip])
        var removed: UUID?
        store.onRemoteRemove = { removed = $0 }

        store.removeRemote(tripID: trip.id)

        #expect(store.trip(id: trip.id) == nil)
        #expect(removed == trip.id)
    }
}
