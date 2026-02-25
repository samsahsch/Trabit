// Trabit_Watch_Widget.swift — Apple Watch Complications
// Shows habit progress as a circular gauge, rectangular detail, and corner text.

import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Shared model container

private func watchWidgetModelContainer() -> ModelContainer? {
    let schema = Schema([Habit.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    return try? ModelContainer(for: schema, configurations: [config])
}

// MARK: - Entry & Provider

struct WatchEntry: TimelineEntry {
    let date: Date
    let completed: Int
    let total: Int
    let nextHabit: String
}

struct WatchWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry {
        WatchEntry(date: Date(), completed: 2, total: 5, nextHabit: "Running")
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let entry = loadEntry()
        let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> WatchEntry {
        guard let container = watchWidgetModelContainer() else {
            return WatchEntry(date: Date(), completed: 0, total: 0, nextHabit: "")
        }
        let context = container.mainContext
        let all = (try? context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let active = all.filter { !$0.isArchived }
        let today = Date()
        let completed = active.filter { $0.isCompleted(on: today) }.count
        let next = active.first(where: { !$0.isCompleted(on: today) })?.name ?? ""
        return WatchEntry(date: today, completed: completed, total: active.count, nextHabit: next)
    }
}

// MARK: - Complication Views

/// Circular gauge for watch face
struct WatchCircularView: View {
    let entry: WatchEntry
    var progress: Double { entry.total > 0 ? Double(entry.completed) / Double(entry.total) : 0 }

    var body: some View {
        ZStack {
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .tint(.blue)
            VStack(spacing: 0) {
                Text("\(entry.completed)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text("/\(entry.total)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

/// Rectangular detail for Infograph Modular
struct WatchRectangularView: View {
    let entry: WatchEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.caption2)
                Text("Trabit")
                    .font(.caption2).bold()
            }
            .foregroundStyle(.blue)

            Text("\(entry.completed) of \(entry.total) done")
                .font(.caption2)

            if !entry.nextHabit.isEmpty {
                Text("Next: \(entry.nextHabit)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

/// Corner text
struct WatchCornerView: View {
    let entry: WatchEntry
    var body: some View {
        Text("\(entry.completed)/\(entry.total)")
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .containerBackground(.clear, for: .widget)
    }
}

/// Inline text
struct WatchInlineView: View {
    let entry: WatchEntry
    var body: some View {
        Label("\(entry.completed)/\(entry.total) habits", systemImage: "checklist")
            .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Widget Definitions

struct TrabitCircularComplication: Widget {
    let kind = "TrabitCircularComplication"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchWidgetProvider()) { entry in
            WatchCircularView(entry: entry)
        }
        .configurationDisplayName("Trabit Progress")
        .description("Habit completion ring.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct TrabitRectangularComplication: Widget {
    let kind = "TrabitRectangularComplication"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchWidgetProvider()) { entry in
            WatchRectangularView(entry: entry)
        }
        .configurationDisplayName("Trabit Detail")
        .description("Today's habit progress detail.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct TrabitCornerComplication: Widget {
    let kind = "TrabitCornerComplication"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchWidgetProvider()) { entry in
            WatchCornerView(entry: entry)
        }
        .configurationDisplayName("Trabit Corner")
        .description("Habit count in watch face corner.")
        .supportedFamilies([.accessoryCorner])
    }
}

struct TrabitInlineComplication: Widget {
    let kind = "TrabitInlineComplication"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchWidgetProvider()) { entry in
            WatchInlineView(entry: entry)
        }
        .configurationDisplayName("Trabit Inline")
        .description("Habit count inline on watch face.")
        .supportedFamilies([.accessoryInline])
    }
}
