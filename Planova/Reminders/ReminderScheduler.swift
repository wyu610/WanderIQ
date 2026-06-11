import Foundation
import UserNotifications
import PlanovaKit

/// Reconciles pending local notifications with the current set of
/// future, not-done reminder items across all trips.
enum ReminderScheduler {

    static func refresh(trips: [Trip]) async {
        let center = UNUserNotificationCenter.current()
        let desired = ReminderPlanner.desiredReminders(for: trips, now: Date())

        if !desired.isEmpty {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }

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
