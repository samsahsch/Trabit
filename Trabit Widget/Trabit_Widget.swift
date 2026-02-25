// Trabit_Widget.swift — iPhone Home Screen & Lock Screen Widgets
// Uses a shared UserDefaults (App Group) cache written by the main app.
// To enable live data: add the "App Groups" capability to both the main app
// and this widget extension, using the group ID "group.com.samsahsch.Trabit".

import WidgetKit
import SwiftUI

// MARK: - Shared progress cache (read-only in widgets)

struct WidgetProgressCache {
    static let suiteName = "group.com.samsahsch.Trabit"

    // Keys
    static let completedKey = "widget_completed"
    static let totalKey = "widget_total"
    static let habitsKey = "widget_habits"   // JSON array of HabitCacheItem

    struct HabitCacheItem: Codable, Identifiable {
        var id: String
        var name: String
        var icon: String
        var color: String
        var isDone: Bool
    }

    static func load() -> (completed: Int, total: Int, habits: [HabitCacheItem]) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let completed = defaults.integer(forKey: completedKey)
        let total = defaults.integer(forKey: totalKey)
        var habits: [HabitCacheItem] = []
        if let data = defaults.data(forKey: habitsKey),
           let decoded = try? JSONDecoder().decode([HabitCacheItem].self, from: data) {
            habits = decoded
        }
        return (completed, total, habits)
    }

    /// Called from the main app to update widget data.
    static func save(completed: Int, total: Int, habits: [HabitCacheItem]) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.set(completed, forKey: completedKey)
        defaults.set(total, forKey: totalKey)
        if let data = try? JSONEncoder().encode(habits) {
            defaults.set(data, forKey: habitsKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Timeline Entry

struct TrabitWidgetEntry: TimelineEntry {
    let date: Date
    let habits: [WidgetProgressCache.HabitCacheItem]
    let completed: Int
    let total: Int
}

// MARK: - Timeline Provider

struct TrabitWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrabitWidgetEntry {
        TrabitWidgetEntry(date: Date(), habits: [
            .init(id: "1", name: "Running", icon: "figure.run", color: "FF9500", isDone: true),
            .init(id: "2", name: "Water", icon: "drop.fill", color: "007AFF", isDone: false),
            .init(id: "3", name: "Floss", icon: "sparkles", color: "34C759", isDone: false),
        ], completed: 1, total: 3)
    }

    func getSnapshot(in context: Context, completion: @escaping (TrabitWidgetEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrabitWidgetEntry>) -> Void) {
        let entry = loadEntry()
        let nextUpdate = Calendar.current.nextDate(after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadEntry() -> TrabitWidgetEntry {
        let cache = WidgetProgressCache.load()
        return TrabitWidgetEntry(date: Date(), habits: cache.habits, completed: cache.completed, total: cache.total)
    }
}

// MARK: - Small Widget View

struct TrabitSmallWidgetView: View {
    let entry: TrabitWidgetEntry

    var progress: Double {
        guard entry.total > 0 else { return 0 }
        return Double(entry.completed) / Double(entry.total)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(entry.completed)")
                        .font(.title2).bold()
                    Text("of \(entry.total)")
                        .font(.caption2).opacity(0.7)
                }
            }
            .frame(width: 72, height: 72)

            Text(progress == 1 ? "All done!" : "\(entry.total - entry.completed) left")
                .font(.caption2).opacity(0.8)
        }
        .foregroundStyle(.white)
        .containerBackground(Color.blue.gradient, for: .widget)
    }
}

// MARK: - Medium Widget View

struct TrabitMediumWidgetView: View {
    let entry: TrabitWidgetEntry

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: entry.total > 0 ? Double(entry.completed) / Double(entry.total) : 0)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(entry.completed)/\(entry.total)")
                        .font(.caption2).bold()
                }
                .frame(width: 48, height: 48)
                Text("Today")
                    .font(.caption2).opacity(0.7)
            }
            .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.habits.prefix(4)) { h in
                    HStack(spacing: 6) {
                        Image(systemName: h.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(h.isDone ? .green : Color.white.opacity(0.35))
                            .font(.caption)
                        Text(h.name)
                            .font(.caption)
                            .foregroundStyle(h.isDone ? Color.white.opacity(0.4) : Color.white)
                            .strikethrough(h.isDone)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .containerBackground(Color(red: 0.07, green: 0.07, blue: 0.18).gradient, for: .widget)
    }
}

// MARK: - Lock Screen Views

struct TrabitInlineView: View {
    let entry: TrabitWidgetEntry
    var body: some View {
        Label("\(entry.completed)/\(entry.total) habits", systemImage: "checklist")
    }
}

struct TrabitRectangularView: View {
    let entry: TrabitWidgetEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Trabit", systemImage: "checklist").font(.caption2).bold()
            Text("\(entry.completed) of \(entry.total) habits done")
                .font(.caption2)
            if let next = entry.habits.first(where: { !$0.isDone }) {
                Text("Next: \(next.name)").font(.caption2).opacity(0.7)
            }
        }
    }
}

// MARK: - Widget Structs

struct TrabitSmallWidget: Widget {
    let kind = "TrabitSmallWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrabitWidgetProvider()) { entry in
            TrabitSmallWidgetView(entry: entry)
        }
        .configurationDisplayName("Trabit Progress")
        .description("Today's habit completion ring.")
        .supportedFamilies([.systemSmall])
    }
}

struct TrabitMediumWidget: Widget {
    let kind = "TrabitMediumWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrabitWidgetProvider()) { entry in
            TrabitMediumWidgetView(entry: entry)
        }
        .configurationDisplayName("Trabit Habits")
        .description("Your habit list for today.")
        .supportedFamilies([.systemMedium])
    }
}

struct TrabitLockScreenWidget: Widget {
    let kind = "TrabitLockScreenWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrabitWidgetProvider()) { entry in
            TrabitInlineView(entry: entry)
        }
        .configurationDisplayName("Trabit")
        .description("Today's habit count on your lock screen.")
        .supportedFamilies([.accessoryInline])
    }
}

struct TrabitRectangularWidget: Widget {
    let kind = "TrabitRectangularWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrabitWidgetProvider()) { entry in
            TrabitRectangularView(entry: entry)
        }
        .configurationDisplayName("Trabit Detail")
        .description("Habit progress detail on your lock screen.")
        .supportedFamilies([.accessoryRectangular])
    }
}
