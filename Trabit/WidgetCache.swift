// WidgetCache.swift — Writes habit progress to shared UserDefaults so
// the iPhone widget and Apple Watch widget can read it.
// The same group ID is used in the widget extensions.

import Foundation
import WidgetKit

private let appGroupID = "group.com.samsahsch.Trabit"

// MARK: - iPhone Widget Progress Cache (mirrors struct in Trabit Widget target)

struct WidgetProgressCache {
    static let suiteName = appGroupID

    static let completedKey = "widget_completed"
    static let totalKey = "widget_total"
    static let nextHabitKey = "widget_nextHabit"
    static let habitsKey = "widget_habits"

    struct HabitCacheItem: Codable, Identifiable {
        var id: String
        var name: String
        var icon: String
        var color: String
        var isDone: Bool
    }

    static func load() -> (completed: Int, total: Int, nextHabit: String, habits: [HabitCacheItem]) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let completed = defaults.integer(forKey: completedKey)
        let total = defaults.integer(forKey: totalKey)
        let nextHabit = defaults.string(forKey: nextHabitKey) ?? ""
        var habits: [HabitCacheItem] = []
        if let data = defaults.data(forKey: habitsKey),
           let decoded = try? JSONDecoder().decode([HabitCacheItem].self, from: data) {
            habits = decoded
        }
        return (completed, total, nextHabit, habits)
    }

    static func save(completed: Int, total: Int, nextHabit: String, habits: [HabitCacheItem]) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.set(completed, forKey: completedKey)
        defaults.set(total, forKey: totalKey)
        defaults.set(nextHabit, forKey: nextHabitKey)
        if let data = try? JSONEncoder().encode(habits) {
            defaults.set(data, forKey: habitsKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Apple Watch Widget Progress Cache (mirrors struct in Trabit Watch Widget target)

struct WatchProgressCache {
    static let suiteName = appGroupID

    static let completedKey = "watchWidget_completed"
    static let totalKey = "watchWidget_total"
    static let nextHabitKey = "watchWidget_nextHabit"

    static func load() -> (completed: Int, total: Int, nextHabit: String) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let completed = defaults.integer(forKey: completedKey)
        let total = defaults.integer(forKey: totalKey)
        let next = defaults.string(forKey: nextHabitKey) ?? ""
        return (completed, total, next)
    }

    static func save(completed: Int, total: Int, nextHabit: String) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.set(completed, forKey: completedKey)
        defaults.set(total, forKey: totalKey)
        defaults.set(nextHabit, forKey: nextHabitKey)
    }
}
