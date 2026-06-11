import Foundation
import Observation

@Observable
public final class TripStore {
    public private(set) var trips: [Trip]

    /// Called with the changed trip after every mutation; the app layer
    /// hooks persistence (and later, sync) here.
    @ObservationIgnored public var onChange: ((Trip) -> Void)?

    public init(trips: [Trip] = []) {
        self.trips = trips.sorted { $0.startDate < $1.startDate }
    }

    public func trip(id: UUID) -> Trip? {
        trips.first { $0.id == id }
    }

    public func addTrip(_ trip: Trip) {
        trips.append(trip)
        trips.sort { $0.startDate < $1.startDate }
        onChange?(trip)
    }

    /// Removal from disk is the caller's responsibility (no trip left to save).
    public func deleteTrip(id: UUID) {
        trips.removeAll { $0.id == id }
    }

    private func mutate(_ tripID: UUID, _ change: (inout Trip) -> Void) {
        guard let i = trips.firstIndex(where: { $0.id == tripID }) else { return }
        change(&trips[i])
        onChange?(trips[i])
    }

    public func toggle(itemID: UUID, in tripID: UUID, now: Date = Date()) {
        mutate(tripID) { trip in
            guard let j = trip.items.firstIndex(where: { $0.id == itemID }) else { return }
            trip.items[j].isDone.toggle()
            trip.items[j].modifiedAt = now
        }
    }

    public func addItem(_ item: ChecklistItem, to tripID: UUID, now: Date = Date()) {
        mutate(tripID) { trip in
            var item = item
            item.sortOrder = (trip.items.filter { $0.kind == item.kind }.map(\.sortOrder).max() ?? -1) + 1
            item.modifiedAt = now
            trip.items.append(item)
        }
    }

    public func updateItem(_ item: ChecklistItem, in tripID: UUID, now: Date = Date()) {
        mutate(tripID) { trip in
            guard let j = trip.items.firstIndex(where: { $0.id == item.id }) else { return }
            var item = item
            item.modifiedAt = now
            trip.items[j] = item
        }
    }

    public func deleteItem(id: UUID, in tripID: UUID) {
        mutate(tripID) { $0.items.removeAll { $0.id == id } }
    }

    public func resetPacking(in tripID: UUID, now: Date = Date()) {
        mutate(tripID) { trip in
            for j in trip.items.indices where trip.items[j].kind == .packing && trip.items[j].isDone {
                trip.items[j].isDone = false
                trip.items[j].modifiedAt = now
            }
        }
    }
}
