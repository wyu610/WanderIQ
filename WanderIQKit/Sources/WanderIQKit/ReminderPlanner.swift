import Foundation

public struct PlannedReminder: Equatable, Sendable {
    public let id: String      // ChecklistItem UUID string == notification identifier
    public let date: Date
    public let title: String
    public let body: String

    public init(id: String, date: Date, title: String, body: String) {
        self.id = id
        self.date = date
        self.title = title
        self.body = body
    }
}

public enum ReminderPlanner {

    public static func desiredReminders(for trips: [Trip], now: Date) -> [PlannedReminder] {
        trips.flatMap { trip in
            trip.items.compactMap { item -> PlannedReminder? in
                guard let date = item.reminderDate, date > now, !item.isDone else { return nil }
                return PlannedReminder(id: item.id.uuidString, date: date, title: item.label, body: trip.name)
            }
        }
    }

    /// Scheduling a request with an identifier that is already pending
    /// replaces it, so `schedule` is simply every desired reminder; only
    /// stale identifiers need explicit cancellation.
    public static func diff(desired: [PlannedReminder], pendingIDs: Set<String>)
        -> (cancel: [String], schedule: [PlannedReminder]) {
        let desiredIDs = Set(desired.map(\.id))
        return (pendingIDs.subtracting(desiredIDs).sorted(), desired)
    }
}
