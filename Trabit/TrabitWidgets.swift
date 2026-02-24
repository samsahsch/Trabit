import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

// MARK: - Widget Timeline Provider

struct HabitEntry: TimelineEntry {
    let date: Date
    let habits: [HabitSnapshot]
    let completedCount: Int
    let totalCount: Int
}

struct HabitSnapshot {
    let name: String
    let icon: String
    let color: String
    let isDone: Bool
}

struct TrabitTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitEntry {
        HabitEntry(
            date: Date(),
            habits: [
                HabitSnapshot(name: "Running", icon: "figure.run", color: "FF9500", isDone: true),
                HabitSnapshot(name: "Floss", icon: "sparkles", color: "FF2D55", isDone: false),
                HabitSnapshot(name: "Water", icon: "drop.fill", color: "5AC8FA", isDone: true),
            ],
            completedCount: 2,
            totalCount: 3
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (HabitEntry) -> Void) {
        completion(placeholder(in: context))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitEntry>) -> Void) {
        let entry = loadCurrentEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func loadCurrentEntry() -> HabitEntry {
        do {
            let schema = Schema([Habit.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            let allHabits = try context.fetch(FetchDescriptor<Habit>())
            let active = allHabits.filter { !$0.isArchived }
            let today = Date()
            
            let snapshots = active.prefix(6).map { habit in
                HabitSnapshot(
                    name: habit.name,
                    icon: habit.iconSymbol,
                    color: habit.hexColor,
                    isDone: habit.isCompleted(on: today)
                )
            }
            
            let completed = active.filter { $0.isCompleted(on: today) }.count
            
            return HabitEntry(
                date: today,
                habits: snapshots,
                completedCount: completed,
                totalCount: active.count
            )
        } catch {
            return HabitEntry(date: Date(), habits: [], completedCount: 0, totalCount: 0)
        }
    }
}

// MARK: - Small Widget (Progress Ring)

struct TrabitSmallWidgetView: View {
    let entry: HabitEntry
    
    var progress: Double {
        guard entry.totalCount > 0 else { return 0 }
        return Double(entry.completedCount) / Double(entry.totalCount)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(entry.completedCount)")
                        .font(.title).bold()
                    Text("of \(entry.totalCount)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)
            
            Text("Today")
                .font(.caption).foregroundStyle(.secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Medium Widget (Habit List)

struct TrabitMediumWidgetView: View {
    let entry: HabitEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today's Habits")
                    .font(.headline)
                Spacer()
                Text("\(entry.completedCount)/\(entry.totalCount)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            
            ForEach(entry.habits.prefix(4), id: \.name) { habit in
                HStack(spacing: 8) {
                    Image(systemName: habit.icon)
                        .foregroundStyle(Color(hex: habit.color))
                        .frame(width: 20)
                    Text(habit.name)
                        .font(.subheadline)
                        .strikethrough(habit.isDone)
                        .foregroundStyle(habit.isDone ? .secondary : .primary)
                    Spacer()
                    Image(systemName: habit.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(habit.isDone ? .green : .secondary.opacity(0.3))
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Lock Screen Widget (Inline)

struct TrabitLockScreenWidgetView: View {
    let entry: HabitEntry
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
            Text("\(entry.completedCount)/\(entry.totalCount) habits")
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget Configuration

struct TrabitWidget: Widget {
    let kind: String = "TrabitWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrabitTimelineProvider()) { entry in
            TrabitMediumWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Habits")
        .description("See your daily habit progress at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TrabitLockScreenWidget: Widget {
    let kind: String = "TrabitLockScreenWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrabitTimelineProvider()) { entry in
            TrabitLockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Habit Progress")
        .description("Quick habit count on your Lock Screen.")
        .supportedFamilies([.accessoryInline, .accessoryCircular])
    }
}
