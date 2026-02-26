// TrabitMigration.swift — Versioned schema migration plan for SwiftData.
// Add a new schema version every time models change (new fields, new types, renames).
// Lightweight migrations (adding optional fields with defaults) are automatic.
// Complex migrations (renames, type changes) need a custom MigrationStage.

import SwiftData
import Foundation

// MARK: - Schema Versions

enum TrabitSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Habit.self, MetricDefinition.self, GoalDefinition.self, ActivityLog.self, LogPoint.self]
    }
}

enum TrabitSchemaV2: VersionedSchema {
    // Adds: UserProfile, FriendConnection, GoalDefinition.isShared
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Habit.self, MetricDefinition.self, GoalDefinition.self, ActivityLog.self, LogPoint.self,
         UserProfile.self, FriendConnection.self]
    }
}

// MARK: - Migration Plan

enum TrabitMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TrabitSchemaV1.self, TrabitSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    // V1 → V2: lightweight — new tables (UserProfile, FriendConnection) and
    // a new Bool column (isShared, defaulting to false) on GoalDefinition.
    // SwiftData handles lightweight migrations for additions automatically.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: TrabitSchemaV1.self,
        toVersion: TrabitSchemaV2.self
    )
}

// MARK: - Shared ModelContainer (used by app + intents + widgets)

func trabitModelContainer() throws -> ModelContainer {
    let schema = Schema(TrabitSchemaV2.models, version: TrabitSchemaV2.versionIdentifier)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    return try ModelContainer(
        for: schema,
        migrationPlan: TrabitMigrationPlan.self,
        configurations: [config]
    )
}
