import AppIntents
import SwiftData
import SwiftUI

// MARK: - Shared ModelContainer for Intents

private func trabitModelContainer() throws -> ModelContainer {
    let schema = Schema([Habit.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    return try ModelContainer(for: schema, configurations: [config])
}

// MARK: - Log Habit Intent (Siri: "Log pushups in Trabit")

struct LogHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Habit"
    static var description = IntentDescription("Log a quick session for a habit in Trabit.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Habit Name")
    var habitName: String

    @Parameter(title: "Value", description: "The number to log, e.g. 20 for reps or 5 for km")
    var value: Double?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try trabitModelContainer()
        let context = container.mainContext
        let allHabits = try context.fetch(FetchDescriptor<Habit>())

        guard let habit = allHabits.first(where: {
            $0.name.lowercased().contains(habitName.lowercased()) || habitName.lowercased().contains($0.name.lowercased())
        }) else {
            return .result(dialog: "I couldn't find a habit named '\(habitName)' in Trabit.")
        }

        let log = ActivityLog(date: Date())

        if let val = value, let firstMetric = habit.definedMetrics.first {
            log.entries.append(LogPoint(metricName: firstMetric.name, value: val))
            habit.logs.append(log)
            return .result(dialog: "Logged \(UnitHelpers.format(val)) \(firstMetric.unit) for \(habit.name).")
        }

        habit.logs.append(log)
        return .result(dialog: "Logged \(habit.name).")
    }
}

// MARK: - Quick Complete Intent (Siri: "Complete floss in Trabit")

struct CompleteHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Habit"
    static var description = IntentDescription("Mark a habit as done for today in Trabit.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Habit Name")
    var habitName: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try trabitModelContainer()
        let context = container.mainContext
        let allHabits = try context.fetch(FetchDescriptor<Habit>())

        guard let habit = allHabits.first(where: {
            $0.name.lowercased().contains(habitName.lowercased()) || habitName.lowercased().contains($0.name.lowercased())
        }) else {
            return .result(dialog: "I couldn't find '\(habitName)' in Trabit.")
        }

        if habit.isCompleted(on: Date()) {
            return .result(dialog: "\(habit.name) is already done for today.")
        }

        habit.logs.append(ActivityLog(date: Date()))
        return .result(dialog: "\(habit.name) marked as done!")
    }
}

// MARK: - Check Progress Intent (Siri: "How's my progress in Trabit?")

struct CheckProgressIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Progress"
    static var description = IntentDescription("Check today's habit completion progress in Trabit.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try trabitModelContainer()
        let context = container.mainContext
        let allHabits = try context.fetch(FetchDescriptor<Habit>())
        let active = allHabits.filter { !$0.isArchived }

        let completed = active.filter { $0.isCompleted(on: Date()) }.count
        let total = active.count

        if total == 0 {
            return .result(dialog: "You don't have any habits set up in Trabit yet.")
        }

        if completed == total {
            return .result(dialog: "All \(total) habits completed today! Great job!")
        }

        let remaining = active.filter { !$0.isCompleted(on: Date()) }
            .map { $0.name }
            .joined(separator: ", ")

        return .result(dialog: "\(completed) of \(total) habits done today. Remaining: \(remaining).")
    }
}

// MARK: - App Shortcuts Provider (makes Siri discover these automatically)

struct TrabitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogHabitIntent(),
            phrases: [
                "Log a habit in \(.applicationName)",
                "Log activity in \(.applicationName)",
                "Record a habit in \(.applicationName)"
            ],
            shortTitle: "Log Habit",
            systemImageName: "checkmark.circle.fill"
        )
        AppShortcut(
            intent: CompleteHabitIntent(),
            phrases: [
                "Complete a habit in \(.applicationName)",
                "Mark a habit done in \(.applicationName)",
                "Finish a habit in \(.applicationName)"
            ],
            shortTitle: "Complete Habit",
            systemImageName: "checkmark.seal.fill"
        )
        AppShortcut(
            intent: CheckProgressIntent(),
            phrases: [
                "How's my progress in \(.applicationName)",
                "Check my habits in \(.applicationName)",
                "Show my progress in \(.applicationName)"
            ],
            shortTitle: "Check Progress",
            systemImageName: "chart.bar.fill"
        )
    }
}
