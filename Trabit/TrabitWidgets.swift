import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

// MARK: - Widget Timeline Entry

struct HabitEntry: TimelineEntry {
    let date: Date
    let habits: [HabitSnapshot]
    let completedCount: Int
    let totalCount: Int
}

struct HabitSnapshot: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: String
    let isDone: Bool
    let isMetricHabit: Bool // completion-only habits can be logged directly from widget
}

// MARK: - Timeline Provider

struct TrabitTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitEntry {
        HabitEntry(
            date: Date(),
            habits: [
                HabitSnapshot(id: "1", name: "Running", icon: "figure.run", color: "FF9500", isDone: true, isMetricHabit: true),
                HabitSnapshot(id: "2", name: "Floss", icon: "sparkles", color: "FF2D55", isDone: false, isMetricHabit: false),
                HabitSnapshot(id: "3", name: "Water", icon: "drop.fill", color: "5AC8FA", isDone: false, isMetricHabit: false),
                HabitSnapshot(id: "4", name: "Pushups", icon: "figure.strengthtraining.traditional", color: "AF52DE", isDone: false, isMetricHabit: true),
            ],
            completedCount: 1,
            totalCount: 4
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : loadCurrentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitEntry>) -> Void) {
        let entry = loadCurrentEntry()
        // Refresh at start of next hour and at midnight
        let nextHour = Calendar.current.nextDate(after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextHour)))
    }

    private func loadCurrentEntry() -> HabitEntry {
        do {
            let schema = Schema([Habit.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            let allHabits = try context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)]))
            let active = allHabits.filter { !$0.isArchived }
            let today = Date()

            let snapshots = active.prefix(5).map { habit in
                HabitSnapshot(
                    id: habit.name,
                    name: habit.name,
                    icon: habit.iconSymbol,
                    color: habit.hexColor,
                    isDone: habit.isCompleted(on: today),
                    isMetricHabit: !habit.definedMetrics.isEmpty
                )
            }

            let completed = active.filter { $0.isCompleted(on: today) }.count
            return HabitEntry(date: today, habits: Array(snapshots), completedCount: completed, totalCount: active.count)
        } catch {
            return HabitEntry(date: Date(), habits: [], completedCount: 0, totalCount: 0)
        }
    }
}

// MARK: - AppIntent for Widget Tap-to-Complete

struct CompleteNextHabitWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Next Habit"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Habit Name")
    var habitName: String

    init() { self.habitName = "" }
    init(habitName: String) { self.habitName = habitName }

    @MainActor
    func perform() async throws -> some IntentResult {
        let schema = Schema([Habit.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            return .result()
        }
        let context = container.mainContext
        let habits = try context.fetch(FetchDescriptor<Habit>())
        let today = Date()

        let target = habitName.isEmpty
            ? habits.first(where: { !$0.isArchived && !$0.isCompleted(on: today) })
            : habits.first(where: { $0.name == habitName && !$0.isArchived })

        if let habit = target, habit.definedMetrics.isEmpty {
            habit.logs.append(ActivityLog(date: today))
            try? context.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
        return .result()
    }
}

// MARK: - Small Widget View

struct TrabitSmallWidgetView: View {
    let entry: HabitEntry

    var progress: Double {
        guard entry.totalCount > 0 else { return 0 }
        return Double(entry.completedCount) / Double(entry.totalCount)
    }

    // First incomplete non-metric habit (can be tapped to complete in widget)
    var nextCompletable: HabitSnapshot? {
        entry.habits.first(where: { !$0.isDone && !$0.isMetricHabit })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Progress ring + count
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: -1) {
                        Text("\(entry.completedCount)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("/\(entry.totalCount)")
                            .font(.system(size: 10))
                            .opacity(0.7)
                    }
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(progress == 1 ? "All done!" : "\(entry.totalCount - entry.completedCount) left")
                        .font(.caption2).bold()
                    Text("Today")
                        .font(.system(size: 9)).opacity(0.6)
                }
            }

            Divider().overlay(Color.white.opacity(0.25))

            // Up to 2 incomplete habits — tap to complete if no metrics needed
            let incomplete = entry.habits.filter { !$0.isDone }.prefix(2)
            if incomplete.isEmpty {
                Label("Great work!", systemImage: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                ForEach(incomplete) { habit in
                    if habit.isMetricHabit {
                        // Metric habits: tap opens app
                        Link(destination: URL(string: "trabit://today")!) {
                            HabitPillView(habit: habit)
                        }
                    } else {
                        // Completion-only: log directly via intent
                        Button(intent: CompleteNextHabitWidgetIntent(habitName: habit.name)) {
                            HabitPillView(habit: habit)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .containerBackground(Color.blue.gradient, for: .widget)
        .widgetURL(URL(string: "trabit://today"))
    }
}

private struct HabitPillView: View {
    let habit: HabitSnapshot
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: habit.icon)
                .font(.system(size: 10))
            Text(habit.name)
                .font(.caption2)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color.white.opacity(0.18))
        .clipShape(Capsule())
    }
}

// MARK: - Medium Widget View

struct TrabitMediumWidgetView: View {
    let entry: HabitEntry

    var progress: Double {
        guard entry.totalCount > 0 else { return 0 }
        return Double(entry.completedCount) / Double(entry.totalCount)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Left: progress ring
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: -1) {
                        Text("\(entry.completedCount)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("/\(entry.totalCount)")
                            .font(.system(size: 11)).opacity(0.7)
                    }
                }
                .frame(width: 56, height: 56)
                Text("Today")
                    .font(.caption2).opacity(0.6)
            }
            .foregroundStyle(.white)

            Divider().overlay(Color.white.opacity(0.2))

            // Right: habit list with tap-to-complete
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.habits.prefix(5)) { habit in
                    if habit.isMetricHabit || habit.isDone {
                        // Open app for metric habits or done habits
                        Link(destination: URL(string: "trabit://today")!) {
                            MediumHabitRow(habit: habit)
                        }
                    } else {
                        // Completion-only: tap to complete inline
                        Button(intent: CompleteNextHabitWidgetIntent(habitName: habit.name)) {
                            MediumHabitRow(habit: habit)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if entry.habits.isEmpty {
                    Text("No habits yet")
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .containerBackground(Color(red: 0.07, green: 0.07, blue: 0.18).gradient, for: .widget)
        .widgetURL(URL(string: "trabit://today"))
    }
}

private struct MediumHabitRow: View {
    let habit: HabitSnapshot
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: habit.icon)
                .foregroundStyle(habit.isDone ? Color.green.opacity(0.8) : Color.white.opacity(0.6))
                .font(.caption).frame(width: 16)
            Text(habit.name)
                .font(.caption)
                .foregroundStyle(habit.isDone ? Color.white.opacity(0.4) : Color.white)
                .strikethrough(habit.isDone)
                .lineLimit(1)
            Spacer()
            Image(systemName: habit.isDone ? "checkmark.circle.fill" : (habit.isMetricHabit ? "plus.circle" : "circle"))
                .font(.caption)
                .foregroundStyle(habit.isDone ? .green : (habit.isMetricHabit ? Color.white.opacity(0.4) : Color.white.opacity(0.3)))
        }
    }
}

// MARK: - Lock Screen Widgets

struct TrabitLockScreenWidgetView: View {
    let entry: HabitEntry
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
            Text("\(entry.completedCount)/\(entry.totalCount) habits")
        }
        .containerBackground(.clear, for: .widget)
    }
}

struct TrabitLockScreenCircularView: View {
    let entry: HabitEntry
    var progress: Double { entry.totalCount > 0 ? Double(entry.completedCount) / Double(entry.totalCount) : 0 }
    var body: some View {
        ZStack {
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .tint(.blue)
            VStack(spacing: -1) {
                Text("\(entry.completedCount)")
                    .font(.system(size: 12, weight: .bold))
                Text("/\(entry.totalCount)")
                    .font(.system(size: 8))
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Widget Configurations

struct TrabitWidget: Widget {
    let kind: String = "TrabitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrabitTimelineProvider()) { entry in
            TrabitMediumWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Habits")
        .description("See your habits and tap to log completion.")
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
