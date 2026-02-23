import AppIntents
import SwiftData
import SwiftUI

// This is the bridge between Apple Intelligence (Siri) and your Trabit app.
struct LogHabitIntent: AppIntent {
    
    static var title: LocalizedStringResource = "Log Habit"
    static var description = IntentDescription("Log a quick session for a habit in Trabit.")
    
    // Siri will automatically try to figure out what Habit name the user said!
    @Parameter(title: "Habit Name")
    var habitName: String
    
    @Parameter(title: "Value (Optional)", description: "The number to log, e.g. 20 for 20 Laps")
    var value: Double?

    // The magical function that Siri executes behind the scenes
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        
        // 1. Connect to our SwiftData database
        let container = try ModelContainer(for: Habit.self)
        let context = container.mainContext
        
        // 2. Ask the database for all Habits
        let descriptor = FetchDescriptor<Habit>()
        let allHabits = try context.fetch(descriptor)
        
        // 3. Find the one Siri thought you meant
        guard let habit = allHabits.first(where: { $0.name.lowercased().contains(habitName.lowercased()) }) else {
            return .result(dialog: "I couldn't find a habit named \(habitName) in Trabit.")
        }
        
        // 4. Log the data!
        let log = ActivityLog(date: Date())
        
        if let val = value, let firstMetric = habit.definedMetrics.first {
            // If the user said a number ("Log 20 laps of swimming"), assign it to the primary metric
            log.entries.append(LogPoint(metricName: firstMetric.name, value: val))
        }
        
        habit.logs.append(log)
        
        // 5. Tell the user it succeeded
        return .result(dialog: "Successfully logged \(habit.name) in Trabit!")
    }
}
