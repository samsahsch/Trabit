// Trabit_WidgetControl.swift — Action Button / Control Center widget
// Opens the Trabit app to log the next habit.
// Uses shared UserDefaults (App Group) to read current progress.

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Quick-log the next incomplete habit

struct LogNextHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Next Habit"
    static let description = IntentDescription("Opens Trabit to log your next habit.")
    static var openAppWhenRun: Bool = true   // Open app — logging requires SwiftData in main process

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cache = WidgetProgressCache.load()
        if cache.nextHabit.isEmpty {
            return .result(dialog: "All habits done for today!")
        }
        return .result(dialog: IntentDialog(stringLiteral: "Opening Trabit to log \(cache.nextHabit)."))
    }
}

// MARK: - Control Widget Value & Provider

struct TrabitControlValue {
    let nextHabit: String
    let completed: Int
    let total: Int
}

struct TrabitControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: TrabitControlConfiguration) -> TrabitControlValue {
        TrabitControlValue(nextHabit: "Running", completed: 1, total: 3)
    }

    func currentValue(configuration: TrabitControlConfiguration) async throws -> TrabitControlValue {
        let cache = WidgetProgressCache.load()
        return TrabitControlValue(nextHabit: cache.nextHabit, completed: cache.completed, total: cache.total)
    }
}

struct TrabitControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Trabit Quick Log"
}

// MARK: - Control Widget

struct Trabit_WidgetControl: ControlWidget {
    static let kind: String = "com.samsahsch.Trabit.control"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: TrabitControlProvider()
        ) { value in
            ControlWidgetButton(action: LogNextHabitIntent()) {
                if value.nextHabit.isEmpty {
                    Label("All Done!", systemImage: "checkmark.seal.fill")
                } else {
                    Label(value.nextHabit, systemImage: "checkmark.circle")
                }
            }
        }
        .displayName("Log Next Habit")
        .description("Quickly open Trabit to log your next habit from the Action Button or Control Center.")
    }
}
