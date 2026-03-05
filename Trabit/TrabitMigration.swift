// TrabitMigration.swift — Shared ModelContainer for the main app, intents, and widgets.
//
// We intentionally do NOT use a SchemaMigrationPlan here. SwiftData's automatic
// lightweight migration handles the common cases (new tables, new optional columns
// with defaults) without needing an explicit plan. A plan is only required for
// destructive changes (renames, type changes) — none of which have occurred yet.
//
// To add a versioned migration plan in the future:
//  1. Create VersionedSchema enums for the before/after states.
//  2. Add a SchemaMigrationPlan with the appropriate MigrationStage.
//  3. Pass `migrationPlan:` to ModelContainer.
// Do NOT add a plan retroactively to an existing unversioned store — that causes
// the "unknown model version" crash because the store has no version stamp.

import SwiftData
import Foundation

private let appGroupID = "group.com.samsahsch.Trabit"

// MARK: - All model types in the current schema

private let trabitModels: [any PersistentModel.Type] = [
    Habit.self,
    MetricDefinition.self,
    GoalDefinition.self,
    ActivityLog.self,
    LogPoint.self,
    UserProfile.self,
    FriendConnection.self,
]

// MARK: - Shared ModelContainer

/// Returns a ModelContainer stored in the App Group container so the widget
/// extension and Siri intents can access the same data as the main app.
func trabitModelContainer() throws -> ModelContainer {
    let schema = Schema(trabitModels)

    // Store in the App Group container so widgets and intents share the same DB.
    if let groupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupID
    ) {
        let storeURL = groupURL
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("default.store")

        // Ensure the directory exists.
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try makeContainer(schema: schema, config: config, storeURL: storeURL)
    }

    // Fallback: no App Group (shouldn't happen in production).
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    return try ModelContainer(for: schema, configurations: [config])
}

/// Tries to open the container; if the store is corrupt/incompatible, deletes it
/// and tries once more with a fresh store. This handles the case where a previous
/// build left an incompatible store on disk.
private func makeContainer(schema: Schema, config: ModelConfiguration, storeURL: URL) throws -> ModelContainer {
    do {
        return try ModelContainer(for: schema, configurations: [config])
    } catch {
        // Store is unreadable (schema mismatch, corruption, etc.) — wipe and restart.
        deleteStore(at: storeURL)
        return try ModelContainer(for: schema, configurations: [config])
    }
}

private func deleteStore(at url: URL) {
    let fm = FileManager.default
    for suffix in ["", "-shm", "-wal"] {
        let file = URL(fileURLWithPath: url.path + suffix)
        try? fm.removeItem(at: file)
    }
}
