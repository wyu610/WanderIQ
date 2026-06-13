import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SyncRoundTripTests {

    @Test func deviceAEditConvergesToDeviceB() async throws {
        let tripID = UUID()
        let backend = FakeRemoteBackend()

        // Device A: a trip with one day and one item, all queued for push.
        let day = TripDay(id: UUID(), date: Date(timeIntervalSince1970: 0), city: "Shanghai",
                          title: "Arrive", modifiedAt: Date(timeIntervalSince1970: 5))
        let item = ChecklistItem(id: UUID(), kind: .prep, label: "Passport",
                                 modifiedAt: Date(timeIntervalSince1970: 5))
        let tripA = Trip(id: tripID, name: "China", startDate: Date(timeIntervalSince1970: 0),
                         endDate: Date(timeIntervalSince1970: 0), days: [day], items: [item],
                         modifiedAt: Date(timeIntervalSince1970: 5))
        let storeA = TripStore(trips: [tripA])
        var boxA = Outbox()
        boxA.enqueue(PendingChange(kind: .trip, id: tripID, tripID: tripID, op: .upsert,
                                   modifiedAt: Date(timeIntervalSince1970: 5)))
        boxA.enqueue(PendingChange(kind: .day, id: day.id, tripID: tripID, op: .upsert,
                                   modifiedAt: Date(timeIntervalSince1970: 5)))
        boxA.enqueue(PendingChange(kind: .item, id: item.id, tripID: tripID, op: .upsert,
                                   modifiedAt: Date(timeIntervalSince1970: 5)))
        try await SyncEngine.push(outbox: &boxA, store: storeA, backend: backend)

        // Device B: empty, pulls everything.
        let storeB = TripStore(trips: [])
        var stateB = SyncState()
        let page = try await backend.changes(since: stateB.cursor)
        SyncEngine.applyPull(page.records, cursor: page.cursor, store: storeB, state: &stateB)

        #expect(storeB.trip(id: tripID)?.name == "China")
        #expect(storeB.trip(id: tripID)?.days.first?.city == "Shanghai")
        #expect(storeB.trip(id: tripID)?.items.first?.label == "Passport")
        #expect(stateB.cursor > .distantPast)
    }
}
