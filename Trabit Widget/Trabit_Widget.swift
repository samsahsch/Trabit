// Trabit_Widget.swift — iPhone Home Screen & Lock Screen Widgets
// Design: minimum friction to log. Small = next habit + one-tap done.
// Medium = top 3 habits, each directly loggable. Large = full list + friend nudge.
// Uses App Group UserDefaults cache written by the main app.

import WidgetKit
import SwiftUI
import AppIntents

private let groupID = "group.com.samsahsch.Trabit"

// MARK: - Cache types

struct WidgetHabitItem: Codable, Identifiable {
    var id: String
    var name: String
    var icon: String
    var color: String
    var isDone: Bool
    var isMetric: Bool
}

struct WidgetFriendItem: Codable, Identifiable {
    var id: String
    var name: String
    var completedToday: Int
    var totalToday: Int
}

struct WidgetCache {
    static let defaults = UserDefaults(suiteName: groupID) ?? .standard

    static func loadHabits() -> [WidgetHabitItem] {
        guard let data = defaults.data(forKey: "widget_habits_v2"),
              let items = try? JSONDecoder().decode([WidgetHabitItem].self, from: data)
        else { return [] }
        return items
    }

    static func loadFriends() -> [WidgetFriendItem] {
        guard let data = defaults.data(forKey: "widget_friends"),
              let items = try? JSONDecoder().decode([WidgetFriendItem].self, from: data)
        else { return [] }
        return items
    }

    static func loadCounts() -> (completed: Int, total: Int) {
        (defaults.integer(forKey: "widget_completed"), defaults.integer(forKey: "widget_total"))
    }
}

// MARK: - Complete-habit intent (no app open for non-metric habits)

struct WidgetCompleteHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Habit"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Habit ID") var habitID: String

    init() { self.habitID = "" }
    init(habitID: String) { self.habitID = habitID }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Update the UserDefaults cache directly so the widget reflects change instantly
        let d = UserDefaults(suiteName: groupID) ?? .standard
        guard var habits = try? JSONDecoder().decode([WidgetHabitItem].self, from: d.data(forKey: "widget_habits_v2") ?? Data())
        else { return .result() }

        if let idx = habits.firstIndex(where: { $0.id == habitID }) {
            habits[idx].isDone = true
        }
        if let data = try? JSONEncoder().encode(habits) {
            d.set(data, forKey: "widget_habits_v2")
        }
        let done = habits.filter(\.isDone).count
        d.set(done, forKey: "widget_completed")
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// Open app to log a metric habit (needs numeric input)
struct WidgetOpenHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Metric Habit"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Habit ID") var habitID: String
    init() { self.habitID = "" }
    init(habitID: String) { self.habitID = habitID }

    func perform() async throws -> some IntentResult { .result() }
}

// MARK: - Timeline Entry

struct WidgetEntry: TimelineEntry {
    let date: Date
    let habits: [WidgetHabitItem]
    let completed: Int
    let total: Int
    let friends: [WidgetFriendItem]

    var progress: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    var incomplete: [WidgetHabitItem] { habits.filter { !$0.isDone } }
    var allDone: Bool { total > 0 && completed == total }
}

// MARK: - Timeline Provider

struct TrabitWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now,
                    habits: [
                        WidgetHabitItem(id: "1", name: "Running", icon: "figure.run", color: "FF9500", isDone: true, isMetric: true),
                        WidgetHabitItem(id: "2", name: "Water", icon: "drop.fill", color: "007AFF", isDone: false, isMetric: false),
                        WidgetHabitItem(id: "3", name: "Floss", icon: "sparkles", color: "34C759", isDone: false, isMetric: false),
                    ],
                    completed: 1, total: 3,
                    friends: [WidgetFriendItem(id: "f1", name: "Alex", completedToday: 2, totalToday: 3)])
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = makeEntry()
        let next = Calendar.current.nextDate(after: .now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? Date(timeIntervalSinceNow: 3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> WidgetEntry {
        let habits = WidgetCache.loadHabits()
        let (completed, total) = WidgetCache.loadCounts()
        let friends = WidgetCache.loadFriends()
        return WidgetEntry(date: .now, habits: habits, completed: completed, total: total, friends: friends)
    }
}

// MARK: - Small Widget: Next habit + progress ring

struct SmallWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: entry.allDone ? [Color(hex: "1a472a"), Color(hex: "2d6a4f")] : [Color(hex: "0a0f2e"), Color(hex: "1a237e")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            VStack(spacing: 8) {
                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: entry.progress)
                        .stroke(
                            entry.allDone ? Color.green : Color.white,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(entry.completed)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("/ \(entry.total)")
                            .font(.system(size: 10))
                            .opacity(0.6)
                    }
                }
                .frame(width: 70, height: 70)
                .foregroundStyle(.white)

                if entry.allDone {
                    Text("All done!")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                } else if let next = entry.incomplete.first {
                    // Tap to complete directly (or open app for metric)
                    if next.isMetric {
                        Link(destination: URL(string: "trabit://log/\(next.id)")!) {
                            HabitPill(habit: next)
                        }
                    } else {
                        Button(intent: WidgetCompleteHabitIntent(habitID: next.id)) {
                            HabitPill(habit: next)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(10)
        }
        .containerBackground(for: .widget) { Color(hex: "0a0f2e") }
        .widgetURL(URL(string: "trabit://today"))
    }
}

// MARK: - Medium Widget: 3 habits, each directly loggable

struct MediumWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        HStack(spacing: 12) {
            // Left: progress ring
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: entry.progress)
                        .stroke(
                            entry.allDone ? Color.green : Color.white,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(entry.completed)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("/\(entry.total)")
                            .font(.system(size: 9)).opacity(0.6)
                    }
                }
                .frame(width: 52, height: 52)
                .foregroundStyle(.white)
                Text("today")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Right: habit rows
            VStack(alignment: .leading, spacing: 5) {
                ForEach(entry.habits.prefix(4)) { habit in
                    MediumHabitRow(habit: habit)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .containerBackground(
            LinearGradient(colors: [Color(hex: "0a0f2e"), Color(hex: "1a237e")], startPoint: .topLeading, endPoint: .bottomTrailing),
            for: .widget
        )
        .widgetURL(URL(string: "trabit://today"))
    }
}

// MARK: - Large Widget: full list + friend nudge

struct LargeWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Trabit")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(entry.allDone ? "All done today!" : "\(entry.total - entry.completed) left")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(entry.allDone ? .green : .white)
                }
                Spacer()
                ZStack {
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: entry.progress)
                        .stroke(entry.allDone ? Color.green : Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(entry.progress * 100))%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)
            }

            Divider().background(Color.white.opacity(0.1))

            // Habit list
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.habits.prefix(6)) { habit in
                    MediumHabitRow(habit: habit)
                }
            }

            // Friend nudge (if any friend is active today)
            if let friend = entry.friends.first(where: { $0.totalToday > 0 }) {
                Divider().background(Color.white.opacity(0.1))
                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    let pct = friend.totalToday > 0 ? Int(Double(friend.completedToday) / Double(friend.totalToday) * 100) : 0
                    Text("\(friend.name): \(pct)% done")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .containerBackground(
            LinearGradient(colors: [Color(hex: "0a0f2e"), Color(hex: "1a237e")], startPoint: .topLeading, endPoint: .bottomTrailing),
            for: .widget
        )
        .widgetURL(URL(string: "trabit://today"))
    }
}

// MARK: - Lock Screen Views

struct LockScreenInlineView: View {
    let entry: WidgetEntry
    var body: some View {
        if entry.allDone {
            Label("All done!", systemImage: "checkmark.seal.fill")
        } else if let next = entry.incomplete.first {
            Label("\(entry.completed)/\(entry.total) · \(next.name)", systemImage: "checkmark.circle")
        } else {
            Label("\(entry.completed)/\(entry.total) habits", systemImage: "checklist")
        }
    }
}

struct LockScreenRectangularView: View {
    let entry: WidgetEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "checkmark.circle.fill").font(.caption2)
                Text("Trabit").font(.caption2.weight(.bold))
                Spacer()
                Text("\(entry.completed)/\(entry.total)").font(.caption2.weight(.bold))
            }
            if entry.allDone {
                Text("All habits complete!")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else if let next = entry.incomplete.first {
                Text("Next: \(next.name)").font(.caption2)
            }
        }
    }
}

struct LockScreenCircularView: View {
    let entry: WidgetEntry
    var body: some View {
        Gauge(value: entry.progress) {
            Image(systemName: "checkmark")
        } currentValueLabel: {
            Text("\(entry.completed)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

// MARK: - Reusable subviews

private struct HabitPill: View {
    let habit: WidgetHabitItem
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: habit.icon)
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: habit.color))
            Text(habit.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.12)))
    }
}

private struct MediumHabitRow: View {
    let habit: WidgetHabitItem
    var body: some View {
        Group {
            if habit.isDone {
                habitContent
            } else if habit.isMetric {
                Link(destination: URL(string: "trabit://log/\(habit.id)")!) {
                    habitContent
                }
            } else {
                Button(intent: WidgetCompleteHabitIntent(habitID: habit.id)) {
                    habitContent
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var habitContent: some View {
        HStack(spacing: 7) {
            Image(systemName: habit.isDone ? "checkmark.circle.fill" : habit.icon)
                .font(.system(size: 13))
                .foregroundStyle(habit.isDone ? Color.green : Color(hex: habit.color))
                .frame(width: 18)
            Text(habit.name)
                .font(.system(size: 13, weight: habit.isDone ? .regular : .medium))
                .foregroundStyle(habit.isDone ? Color.white.opacity(0.35) : Color.white)
                .strikethrough(habit.isDone, color: .white.opacity(0.3))
                .lineLimit(1)
            Spacer(minLength: 0)
            if !habit.isDone && !habit.isMetric {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

// MARK: - Color hex extension

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b: UInt64
        switch h.count {
        case 6: (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (r, g, b) = (1, 1, 1)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255)
    }
}

// MARK: - Widget structs

struct TrabitSmallWidget: Widget {
    let kind = "TrabitSmallWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrabitWidgetProvider()) { SmallWidgetView(entry: $0) }
            .configurationDisplayName("Trabit Progress")
            .description("Next habit + progress ring. Tap to complete.")
            .supportedFamilies([.systemSmall])
    }
}

struct TrabitMediumWidget: Widget {
    let kind = "TrabitMediumWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrabitWidgetProvider()) { MediumWidgetView(entry: $0) }
            .configurationDisplayName("Trabit Habits")
            .description("Habit list with tap-to-complete.")
            .supportedFamilies([.systemMedium])
    }
}

struct TrabitLargeWidget: Widget {
    let kind = "TrabitLargeWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrabitWidgetProvider()) { LargeWidgetView(entry: $0) }
            .configurationDisplayName("Trabit Full List")
            .description("All habits + friend progress.")
            .supportedFamilies([.systemLarge])
    }
}

struct TrabitLockScreenInlineWidget: Widget {
    let kind = "TrabitLockScreenWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrabitWidgetProvider()) { LockScreenInlineView(entry: $0) }
            .configurationDisplayName("Trabit")
            .description("Habit count on your lock screen.")
            .supportedFamilies([.accessoryInline])
    }
}

struct TrabitLockScreenRectangularWidget: Widget {
    let kind = "TrabitRectangularWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrabitWidgetProvider()) { LockScreenRectangularView(entry: $0) }
            .configurationDisplayName("Trabit Detail")
            .description("Next habit on your lock screen.")
            .supportedFamilies([.accessoryRectangular])
    }
}

struct TrabitLockScreenCircularWidget: Widget {
    let kind = "TrabitCircularWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrabitWidgetProvider()) { LockScreenCircularView(entry: $0) }
            .configurationDisplayName("Trabit Ring")
            .description("Progress ring on your lock screen.")
            .supportedFamilies([.accessoryCircular])
    }
}
