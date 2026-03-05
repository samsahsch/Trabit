// Trabit_Watch_Widget.swift — Watch face complications.
// Shows progress ring + next habit. Tapping a complication opens the Watch app
// directly to the habit list for one-tap logging.

import WidgetKit
import SwiftUI
import AppIntents

private let watchGroupID = "group.com.samsahsch.Trabit"

// MARK: - Cache read (mirrors WatchProgressCache in Watch App)

private func loadWatchCache() -> (completed: Int, total: Int, nextHabit: String, habits: [WatchWidgetHabit]) {
    let d = UserDefaults(suiteName: watchGroupID) ?? .standard
    let completed = d.integer(forKey: "watch_completed")
    let total     = d.integer(forKey: "watch_total")
    let next      = d.string(forKey: "watch_nextHabit") ?? ""
    var habits: [WatchWidgetHabit] = []
    if let data = d.data(forKey: "watch_habits_v2"),
       let items = try? JSONDecoder().decode([WatchWidgetHabit].self, from: data) {
        habits = items
    }
    return (completed, total, next, habits)
}

struct WatchWidgetHabit: Codable, Identifiable {
    var id: String
    var name: String
    var icon: String
    var color: String
    var isDone: Bool
}

// MARK: - Timeline Entry

struct WatchEntry: TimelineEntry {
    let date: Date
    let completed: Int
    let total: Int
    let nextHabit: String
    let habits: [WatchWidgetHabit]

    var progress: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    var allDone: Bool { total > 0 && completed == total }
}

// MARK: - Timeline Provider

struct WatchWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry {
        WatchEntry(date: .now, completed: 2, total: 5, nextHabit: "Running",
                   habits: [WatchWidgetHabit(id: "1", name: "Running", icon: "figure.run", color: "FF9500", isDone: false)])
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let entry = makeEntry()
        // Refresh every 15 minutes or at midnight
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func makeEntry() -> WatchEntry {
        let (completed, total, next, habits) = loadWatchCache()
        return WatchEntry(date: .now, completed: completed, total: total, nextHabit: next, habits: habits)
    }
}

// MARK: - Complications

// 1. Circular — progress gauge with fraction text
struct TrabitCircularComplication: Widget {
    static let kind = "com.samsahsch.Trabit.watch.circular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchWidgetProvider()) { entry in
            CircularView(entry: entry)
                .widgetURL(URL(string: "trabit://today"))
        }
        .configurationDisplayName("Trabit Progress")
        .description("Ring showing today's habit progress.")
        .supportedFamilies([.accessoryCircular])
    }
}

private struct CircularView: View {
    let entry: WatchEntry
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Gauge(value: entry.progress) {
                Image(systemName: "checkmark")
            } currentValueLabel: {
                Text("\(entry.completed)")
                    .font(.system(size: 11, weight: .bold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(entry.allDone ? .green : .blue)
        }
    }
}

// 2. Rectangular — next habit name + progress bar
struct TrabitRectangularComplication: Widget {
    static let kind = "com.samsahsch.Trabit.watch.rectangular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchWidgetProvider()) { entry in
            RectangularView(entry: entry)
                .widgetURL(URL(string: "trabit://today"))
        }
        .configurationDisplayName("Trabit Next Habit")
        .description("Shows your next habit and today's progress.")
        .supportedFamilies([.accessoryRectangular])
    }
}

private struct RectangularView: View {
    let entry: WatchEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(entry.allDone ? .green : .blue)
                Text("Trabit")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.completed)/\(entry.total)")
                    .font(.caption2.weight(.bold))
            }

            if entry.allDone {
                Text("All habits done! 🎉")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Text(entry.nextHabit.isEmpty ? "Open Trabit" : entry.nextHabit)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }

            Gauge(value: entry.progress) {}
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(entry.allDone ? .green : .blue)
        }
    }
}

// 3. Corner — icon + fraction
struct TrabitCornerComplication: Widget {
    static let kind = "com.samsahsch.Trabit.watch.corner"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchWidgetProvider()) { entry in
            CornerView(entry: entry)
                .widgetURL(URL(string: "trabit://today"))
        }
        .configurationDisplayName("Trabit Corner")
        .description("Habit progress in the watch corner.")
        .supportedFamilies([.accessoryCorner])
    }
}

private struct CornerView: View {
    let entry: WatchEntry
    var body: some View {
        Image(systemName: entry.allDone ? "checkmark.seal.fill" : "checkmark.circle")
            .foregroundStyle(entry.allDone ? .green : .blue)
            .widgetLabel {
                Gauge(value: entry.progress) {
                    Text("\(entry.completed)/\(entry.total)")
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(entry.allDone ? .green : .blue)
            }
    }
}

// 4. Inline — plain text for watch face
struct TrabitInlineComplication: Widget {
    static let kind = "com.samsahsch.Trabit.watch.inline"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchWidgetProvider()) { entry in
            InlineView(entry: entry)
                .widgetURL(URL(string: "trabit://today"))
        }
        .configurationDisplayName("Trabit Inline")
        .description("Habit count on your watch face.")
        .supportedFamilies([.accessoryInline])
    }
}

private struct InlineView: View {
    let entry: WatchEntry
    var body: some View {
        if entry.allDone {
            Label("All done!", systemImage: "checkmark.seal.fill")
        } else if !entry.nextHabit.isEmpty {
            Label("\(entry.completed)/\(entry.total) · \(entry.nextHabit)", systemImage: "checkmark.circle")
        } else {
            Label("\(entry.completed)/\(entry.total) habits", systemImage: "checkmark.circle")
        }
    }
}
