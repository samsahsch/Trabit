import Foundation
import UserNotifications
import SwiftData

final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    /// Request notification permission from the user
    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Schedule (or reschedule) the reminder for a habit
    func scheduleReminder(for habit: Habit) {
        // Remove any existing notification for this habit
        removeReminder(for: habit)

        guard habit.reminderEnabled, !habit.isArchived else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to \(habit.name)"
        content.body = habit.definedMetrics.isEmpty
            ? "Tap to mark it done!"
            : "Tap to log your \(habit.name) session."
        content.sound = .default
        content.categoryIdentifier = "HABIT_REMINDER"

        var dateComponents = DateComponents()
        dateComponents.hour = habit.reminderHour
        dateComponents.minute = habit.reminderMinute

        // Schedule based on frequency
        switch habit.frequencyType {
        case .daily, .interval:
            // Daily trigger at the specified time
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: notificationID(for: habit),
                content: content,
                trigger: trigger
            )
            center.add(request)

        case .weekdays:
            // One notification per selected weekday
            for weekday in habit.frequencyWeekdays ?? [] {
                var weekdayComponents = dateComponents
                weekdayComponents.weekday = weekday
                let trigger = UNCalendarNotificationTrigger(dateMatching: weekdayComponents, repeats: true)
                let request = UNNotificationRequest(
                    identifier: "\(notificationID(for: habit))_\(weekday)",
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }

        case .weekly:
            // Once a week on Monday at the specified time
            dateComponents.weekday = 2
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: notificationID(for: habit),
                content: content,
                trigger: trigger
            )
            center.add(request)

        case .monthly:
            // First of each month
            dateComponents.day = 1
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: notificationID(for: habit),
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    /// Remove all notifications for a habit
    func removeReminder(for habit: Habit) {
        let baseID = notificationID(for: habit)
        var ids = [baseID]
        // Also remove weekday-specific notifications
        for weekday in 1...7 {
            ids.append("\(baseID)_\(weekday)")
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Reschedule all reminders (call on app launch or after model changes)
    func rescheduleAll(context: ModelContext) {
        center.removeAllPendingNotificationRequests()
        guard let habits = try? context.fetch(FetchDescriptor<Habit>()) else { return }
        for habit in habits where habit.reminderEnabled && !habit.isArchived {
            scheduleReminder(for: habit)
        }
    }

    private func notificationID(for habit: Habit) -> String {
        "trabit_reminder_\(habit.name.lowercased().replacingOccurrences(of: " ", with: "_"))"
    }
}
