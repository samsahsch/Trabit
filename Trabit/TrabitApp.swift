//
//  TrabitApp.swift
//  Trabit
//
//  Created by samss on 1/28/26.
//

import SwiftUI
import SwiftData

@main
struct TrackerAppApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Habit.self, // We tell the app to manage 'Habit' data
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContai xner: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
