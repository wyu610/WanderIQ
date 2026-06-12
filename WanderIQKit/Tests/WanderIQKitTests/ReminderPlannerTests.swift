import Foundation
import Testing
@testable import WanderIQKit

@Suite struct ReminderPlannerTests {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func trip(items: [ChecklistItem]) -> Trip {
        Trip(name: "China", startDate: now, endDate: now.addingTimeInterval(86_400), items: items)
    }

    @Test func testDesiredIncludesOnlyFutureUndoneReminders() {
        let future = ChecklistItem(kind: .prep, label: "抢票", reminderDate: now.addingTimeInterval(3600))
        let past = ChecklistItem(kind: .prep, label: "old", reminderDate: now.addingTimeInterval(-3600))
        let done = ChecklistItem(kind: .prep, label: "done", isDone: true, reminderDate: now.addingTimeInterval(3600))
        let none = ChecklistItem(kind: .prep, label: "none")

        let desired = ReminderPlanner.desiredReminders(for: [trip(items: [future, past, done, none])], now: now)

        #expect(desired.count == 1)
        #expect(desired[0].id == future.id.uuidString)
        #expect(desired[0].title == "抢票")
        #expect(desired[0].body == "China")
        #expect(desired[0].date == now.addingTimeInterval(3600))
    }

    @Test func testDiffCancelsStaleAndSchedulesAllDesired() {
        let item = ChecklistItem(kind: .prep, label: "a", reminderDate: now.addingTimeInterval(60))
        let desired = ReminderPlanner.desiredReminders(for: [trip(items: [item])], now: now)
        let pending: Set<String> = [item.id.uuidString, "stale-id"]

        let plan = ReminderPlanner.diff(desired: desired, pendingIDs: pending)

        #expect(plan.cancel == ["stale-id"])
        #expect(plan.schedule == desired)
    }
}
