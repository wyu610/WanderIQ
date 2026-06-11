import Foundation
import UserNotifications
import PlanovaKit

/// Reconciles pending local notifications with the current set of
/// future, not-done reminder items across all trips.
enum ReminderScheduler {

    /// Called at the deliberate moment a user enables a reminder, so the
    /// system permission dialog appears in context rather than mid-mutation.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func refresh(trips: [Trip]) async {
        let center = UNUserNotificationCenter.current()
        let desired = ReminderPlanner.desiredReminders(for: trips, now: Date())

        // TODO: surface denied-authorization state in the UI (spec: inline
        // hint linking to Settings) — until then, schedules silently no-op.
        let pendingIDs = Set(await center.pendingNotificationRequests().map(\.identifier))
        let plan = ReminderPlanner.diff(desired: desired, pendingIDs: pendingIDs)

        center.removePendingNotificationRequests(withIdentifiers: plan.cancel)
        for reminder in plan.schedule {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: reminder.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(
                identifier: reminder.id, content: content, trigger: trigger))
        }
    }
}
