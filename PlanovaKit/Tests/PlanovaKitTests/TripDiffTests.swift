import Testing
import Foundation
@testable import PlanovaKit

@Suite struct TripDiffTests {

    private func base() -> Trip {
        Trip(name: "T", startDate: Date(timeIntervalSince1970: 0), endDate: Date(timeIntervalSince1970: 1),
             days: [TripDay(date: Date(timeIntervalSince1970: 0), city: "c", title: "t")],
             items: [ChecklistItem(kind: .prep, label: "a"), ChecklistItem(kind: .packing, label: "b")])
    }

    @Test func nilOldMeansEverythingSaves() {
        let trip = base()
        let diff = TripDiff.changes(old: nil, new: trip)
        #expect(Set(diff.saves) == Set([.tripMeta] + trip.days.map { .day($0.id) } + trip.items.map { .item($0.id) }))
        #expect(diff.deletes.isEmpty)
    }

    @Test func noChangeMeansEmptyDiff() {
        let trip = base()
        let diff = TripDiff.changes(old: trip, new: trip)
        #expect(diff.saves.isEmpty)
        #expect(diff.deletes.isEmpty)
    }

    @Test func itemEditAndDeleteAndMetaChange() {
        let old = base()
        var new = old
        new.name = "Renamed"                        // meta save
        new.items[0].isDone = true                  // item save
        let removed = new.items.removeLast()        // item delete
        let added = ChecklistItem(kind: .doc, label: "new")
        new.items.append(added)                     // item save

        let diff = TripDiff.changes(old: old, new: new)
        #expect(Set(diff.saves) == Set([.tripMeta, .item(new.items[0].id), .item(added.id)]))
        #expect(diff.deletes == [.item(removed.id)])
    }

    @Test func dayChanges() {
        let old = base()
        var new = old
        new.days[0].title = "changed"
        let diff = TripDiff.changes(old: old, new: new)
        #expect(diff.saves == [.day(new.days[0].id)])
    }
}
