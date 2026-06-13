import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SyncEngineApplyTests {
    let tripID = UUID()

    private func trip(modifiedAt: Date) -> Trip {
        Trip(id: tripID, name: "Old", startDate: Date(timeIntervalSince1970: 0),
             endDate: Date(timeIntervalSince1970: 0), modifiedAt: modifiedAt)
    }

    @Test func newerRemoteTripOverwritesLocalFields() {
        let store = TripStore(trips: [trip(modifiedAt: Date(timeIntervalSince1970: 1))])
        var state = SyncState()
        let rec = SyncRecord(kind: .trip, id: tripID, tripID: tripID,
                             modifiedAt: Date(timeIntervalSince1970: 2), deleted: false,
                             fields: ["name": "New", "startDate": "0", "endDate": "0",
                                      "destinations": "", "schemaVersion": "1"])
        SyncEngine.applyPull([rec], cursor: Date(timeIntervalSince1970: 9),
                             store: store, state: &state)
        #expect(store.trip(id: tripID)?.name == "New")
        #expect(state.cursor == Date(timeIntervalSince1970: 9))
    }

    @Test func olderRemoteTripIsIgnored() {
        let store = TripStore(trips: [trip(modifiedAt: Date(timeIntervalSince1970: 5))])
        var state = SyncState()
        let rec = SyncRecord(kind: .trip, id: tripID, tripID: tripID,
                             modifiedAt: Date(timeIntervalSince1970: 2), deleted: false,
                             fields: ["name": "Stale", "startDate": "0", "endDate": "0",
                                      "destinations": "", "schemaVersion": "1"])
        SyncEngine.applyPull([rec], cursor: Date(timeIntervalSince1970: 9),
                             store: store, state: &state)
        #expect(store.trip(id: tripID)?.name == "Old")
    }

    @Test func remoteTripTombstoneRemovesTripAndRecordsTombstone() {
        let store = TripStore(trips: [trip(modifiedAt: Date(timeIntervalSince1970: 1))])
        var state = SyncState()
        let rec = SyncRecord(kind: .trip, id: tripID, tripID: tripID,
                             modifiedAt: Date(timeIntervalSince1970: 2), deleted: true)
        SyncEngine.applyPull([rec], cursor: Date(timeIntervalSince1970: 9),
                             store: store, state: &state)
        #expect(store.trip(id: tripID) == nil)
        #expect(state.tombstones[tripID] == Date(timeIntervalSince1970: 2))
    }
}
