import Foundation
import Testing
@testable import PlanovaKit

@Suite struct TripStoreTests {

    private func makeTrip() -> Trip {
        Trip(name: "T", startDate: Date(timeIntervalSince1970: 0), endDate: Date(timeIntervalSince1970: 86_400),
             items: [
                ChecklistItem(kind: .prep, label: "p0", sortOrder: 0),
                ChecklistItem(kind: .packing, label: "k0", isDone: true, sortOrder: 0),
                ChecklistItem(kind: .packing, label: "k1", isDone: true, sortOrder: 1)
             ])
    }

    @Test func testToggleFlipsDoneAndStampsModifiedAtAndNotifies() {
        let trip = makeTrip()
        let store = TripStore(trips: [trip])
        var changed: Trip?
        store.onChange = { changed = $0 }
        let now = Date(timeIntervalSince1970: 1000)

        store.toggle(itemID: trip.items[0].id, in: trip.id, now: now)

        let item = store.trip(id: trip.id)!.items[0]
        #expect(item.isDone == true)
        #expect(item.modifiedAt == now)
        #expect(changed?.id == trip.id)
    }

    @Test func testAddItemAppendsWithNextSortOrderForItsKind() {
        let trip = makeTrip()
        let store = TripStore(trips: [trip])

        store.addItem(ChecklistItem(kind: .packing, label: "k2"), to: trip.id)

        let packing = store.trip(id: trip.id)!.items.filter { $0.kind == .packing }
        #expect(packing.count == 3)
        #expect(packing.map { $0.sortOrder }.max() == 2)
    }

    @Test func testUpdateItemReplacesFields() {
        let trip = makeTrip()
        let store = TripStore(trips: [trip])
        var edited = trip.items[0]
        edited.label = "renamed"
        edited.owner = "妈妈"

        store.updateItem(edited, in: trip.id, now: Date(timeIntervalSince1970: 2000))

        let item = store.trip(id: trip.id)!.items[0]
        #expect(item.label == "renamed")
        #expect(item.owner == "妈妈")
        #expect(item.modifiedAt == Date(timeIntervalSince1970: 2000))
    }

    @Test func testDeleteItemRemovesIt() {
        let trip = makeTrip()
        let store = TripStore(trips: [trip])

        store.deleteItem(id: trip.items[0].id, in: trip.id)

        #expect(store.trip(id: trip.id)!.items.count == 2)
    }

    @Test func testResetPackingClearsOnlyPackingDoneFlags() {
        var trip = makeTrip()
        trip.items[0].isDone = true   // prep item stays done
        let store = TripStore(trips: [trip])

        store.resetPacking(in: trip.id)

        let items = store.trip(id: trip.id)!.items
        let prepItem = items.first { $0.kind == .prep }!
        let packingItems = items.filter { $0.kind == .packing }
        #expect(prepItem.isDone == true)
        #expect(packingItems.allSatisfy { !$0.isDone })
    }

    @Test func testTripsSortedByStartDate() {
        let early = Trip(name: "early", startDate: Date(timeIntervalSince1970: 0), endDate: Date(timeIntervalSince1970: 1))
        let late = Trip(name: "late", startDate: Date(timeIntervalSince1970: 9999), endDate: Date(timeIntervalSince1970: 10_000))
        let store = TripStore(trips: [late])
        store.addTrip(early)
        #expect(store.trips.map { $0.name } == ["early", "late"])
    }
}
