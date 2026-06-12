import Foundation

/// A CloudKit-agnostic description of which records changed between two
/// snapshots of a trip. The sync layer turns these into CKRecord.IDs.
public enum TripRecordRef: Hashable, Sendable {
    case tripMeta
    case day(UUID)
    case item(UUID)
}

public enum TripDiff {

    public static func changes(old: Trip?, new: Trip)
        -> (saves: [TripRecordRef], deletes: [TripRecordRef]) {
        guard let old else {
            return ([.tripMeta] + new.days.map { .day($0.id) } + new.items.map { .item($0.id) }, [])
        }
        var saves: [TripRecordRef] = []
        var deletes: [TripRecordRef] = []

        let metaChanged = old.name != new.name || old.startDate != new.startDate
            || old.endDate != new.endDate || old.destinations != new.destinations
            || old.schemaVersion != new.schemaVersion
        if metaChanged { saves.append(.tripMeta) }

        let oldDays = Dictionary(uniqueKeysWithValues: old.days.map { ($0.id, $0) })
        let newDays = Dictionary(uniqueKeysWithValues: new.days.map { ($0.id, $0) })
        for (id, day) in newDays where oldDays[id] != day { saves.append(.day(id)) }
        for id in oldDays.keys where newDays[id] == nil { deletes.append(.day(id)) }

        let oldItems = Dictionary(uniqueKeysWithValues: old.items.map { ($0.id, $0) })
        let newItems = Dictionary(uniqueKeysWithValues: new.items.map { ($0.id, $0) })
        for (id, item) in newItems where oldItems[id] != item { saves.append(.item(id)) }
        for id in oldItems.keys where newItems[id] == nil { deletes.append(.item(id)) }

        return (saves, deletes)
    }
}
