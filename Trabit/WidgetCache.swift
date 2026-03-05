// WidgetCache.swift — Writes habit and friend progress to shared App Group UserDefaults
// so iPhone widgets, Watch app, and Watch complications can read it without opening SwiftData.

import Foundation
import WidgetKit

private let appGroupID = "group.com.samsahsch.Trabit"

// MARK: - v2 iPhone Widget Habit Item (includes isMetric for tap-to-complete logic)

struct WidgetHabitItemV2: Codable, Identifiable {
    var id: String
    var name: String
    var icon: String
    var color: String
    var isDone: Bool
    var isMetric: Bool
}

// MARK: - v2 Watch Habit Item (includes value/target for progress bar)

struct WatchHabitItemV2: Codable, Identifiable {
    var id: String
    var name: String
    var icon: String
    var color: String
    var isDone: Bool
    var isMetric: Bool
    var metricUnit: String
    var currentValue: Double
    var dailyTarget: Double
}

// MARK: - Widget Friend Item

struct WidgetFriendItemCache: Codable, Identifiable {
    var id: String
    var name: String
    var completedToday: Int
    var totalToday: Int
}

// MARK: - Watch Friend Snapshot (for the Watch friends sheet)

struct WatchFriendSnapshotCache: Codable, Identifiable {
    var id: String
    var name: String
    var completedToday: Int
    var totalToday: Int
    var topGoalName: String
    var topGoalProgress: Double
    var topGoalColor: String
}

// MARK: - WidgetProgressCache (legacy + v2 writer)

struct WidgetProgressCache {
    static let suiteName = appGroupID

    // Legacy keys (keep writing for backward compat with old widget builds)
    static let completedKey  = "widget_completed"
    static let totalKey      = "widget_total"
    static let nextHabitKey  = "widget_nextHabit"

    // v2 keys
    static let habitsV2Key   = "widget_habits_v2"
    static let friendsKey    = "widget_friends"

    struct HabitCacheItem: Codable, Identifiable {
        var id: String; var name: String; var icon: String; var color: String; var isDone: Bool
    }

    static func load() -> (completed: Int, total: Int, nextHabit: String, habits: [HabitCacheItem]) {
        let d = UserDefaults(suiteName: suiteName) ?? .standard
        let habits: [HabitCacheItem]
        if let data = d.data(forKey: habitsV2Key),
           let v2 = try? JSONDecoder().decode([WidgetHabitItemV2].self, from: data) {
            habits = v2.map { HabitCacheItem(id: $0.id, name: $0.name, icon: $0.icon, color: $0.color, isDone: $0.isDone) }
        } else {
            habits = []
        }
        return (d.integer(forKey: completedKey), d.integer(forKey: totalKey), d.string(forKey: nextHabitKey) ?? "", habits)
    }

    /// Full save: writes both legacy keys and new v2 items.
    static func save(
        completed: Int,
        total: Int,
        nextHabit: String,
        habitsV2: [WidgetHabitItemV2],
        watchHabits: [WatchHabitItemV2],
        friends: [WidgetFriendItemCache] = [],
        watchFriends: [WatchFriendSnapshotCache] = []
    ) {
        let d = UserDefaults(suiteName: suiteName) ?? .standard
        d.set(completed, forKey: completedKey)
        d.set(total, forKey: totalKey)
        d.set(nextHabit, forKey: nextHabitKey)

        if let data = try? JSONEncoder().encode(habitsV2) {
            d.set(data, forKey: habitsV2Key)
        }
        if let data = try? JSONEncoder().encode(watchHabits) {
            d.set(data, forKey: "watch_habits_v2")
        }
        d.set(completed, forKey: "watch_completed")
        d.set(total, forKey: "watch_total")
        d.set(nextHabit, forKey: "watch_nextHabit")

        if let data = try? JSONEncoder().encode(friends) {
            d.set(data, forKey: friendsKey)
        }
        if let data = try? JSONEncoder().encode(watchFriends) {
            d.set(data, forKey: "watch_friends")
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Convenience: legacy call signature used by older callers — upgrades to v2 automatically.
    static func save(completed: Int, total: Int, nextHabit: String, habits: [HabitCacheItem]) {
        let v2 = habits.map { WidgetHabitItemV2(id: $0.id, name: $0.name, icon: $0.icon, color: $0.color, isDone: $0.isDone, isMetric: false) }
        let watchV2 = habits.map { WatchHabitItemV2(id: $0.id, name: $0.name, icon: $0.icon, color: $0.color, isDone: $0.isDone, isMetric: false, metricUnit: "", currentValue: 0, dailyTarget: 0) }
        save(completed: completed, total: total, nextHabit: nextHabit, habitsV2: v2, watchHabits: watchV2)
    }
}

// MARK: - WatchProgressCache

struct WatchProgressCache {
    static let suiteName = appGroupID

    static func load() -> (completed: Int, total: Int, nextHabit: String) {
        let d = UserDefaults(suiteName: suiteName) ?? .standard
        return (d.integer(forKey: "watch_completed"), d.integer(forKey: "watch_total"), d.string(forKey: "watch_nextHabit") ?? "")
    }

    static func save(completed: Int, total: Int, nextHabit: String) {
        let d = UserDefaults(suiteName: suiteName) ?? .standard
        d.set(completed, forKey: "watch_completed")
        d.set(total, forKey: "watch_total")
        d.set(nextHabit, forKey: "watch_nextHabit")
    }
}
