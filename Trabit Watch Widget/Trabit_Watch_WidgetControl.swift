// Trabit_Watch_WidgetControl.swift — Watch Digital Crown control / smart stack action
// Uses shared UserDefaults (App Group) to read/write progress without depending on SwiftData types.

import AppIntents
import SwiftUI
import WidgetKit

struct WatchLogNextIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Next Habit"
    static let description = IntentDescription("Marks the next incomplete habit as done from your wrist.")
    static var openAppWhenRun: Bool = true   // Open Watch app to do the actual logging

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Opening the app is the reliable cross-target action on watchOS.
        // The Watch app handles the actual logging.
        let cache = WatchProgressCache.load()
        if cache.nextHabit.isEmpty {
            return .result(dialog: "All habits are done for today!")
        }
        return .result(dialog: IntentDialog(stringLiteral: "Opening Trabit to log \(cache.nextHabit)."))
    }
}

struct WatchControlValue {
    let nextHabit: String
    let completed: Int
    let total: Int
}

struct WatchControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: WatchControlConfig) -> WatchControlValue {
        WatchControlValue(nextHabit: "Running", completed: 1, total: 3)
    }

    func currentValue(configuration: WatchControlConfig) async throws -> WatchControlValue {
        let cache = WatchProgressCache.load()
        return WatchControlValue(nextHabit: cache.nextHabit, completed: cache.completed, total: cache.total)
    }
}

struct WatchControlConfig: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Trabit Watch Quick Log"
}

struct Trabit_Watch_WidgetControl: ControlWidget {
    static let kind: String = "com.samsahsch.Trabit.watchcontrol"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: WatchControlProvider()
        ) { value in
            ControlWidgetButton(action: WatchLogNextIntent()) {
                if value.nextHabit.isEmpty {
                    Label("All Done!", systemImage: "checkmark.seal.fill")
                } else {
                    Label(value.nextHabit, systemImage: "checkmark.circle")
                }
            }
        }
        .displayName("Log Next Habit")
        .description("Log your next habit from the watch face.")
    }
}
