// ContentView.swift — Trabit Apple Watch App
// Uses SwiftData with the same App Group store as the main iPhone app.
// SETUP REQUIRED: In Xcode, add the "App Groups" capability to both the
// "Trabit" target and "Trabit Watch App" target using "group.com.samsahsch.Trabit".

import SwiftUI
import SwiftData

// MARK: - Minimal model definitions for watchOS
// These mirror HabitModels.swift in the main app. Both targets share the same
// SwiftData store via App Groups so data stays in sync.

enum WatchFrequencyType: String, Codable, CaseIterable {
    case daily = "Daily"; case weekly = "Weekly"; case monthly = "Monthly"
    case interval = "Every X Days"; case weekdays = "Specific Days"
}

@Model final class WatchHabit {
    var name: String; var iconSymbol: String; var hexColor: String
    var sortOrder: Int; var isArchived: Bool = false; var dailyGoalCount: Int = 1
    @Relationship(deleteRule: .cascade) var logs: [WatchActivityLog] = []
    @Relationship(deleteRule: .cascade) var definedMetrics: [WatchMetricDef] = []

    init(name: String, icon: String, color: String, order: Int = 0) {
        self.name = name; self.iconSymbol = icon; self.hexColor = color; self.sortOrder = order
    }

    func isCompleted(on date: Date) -> Bool {
        logs.contains { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }
}

@Model final class WatchActivityLog {
    var date: Date
    @Relationship(deleteRule: .cascade) var entries: [WatchLogPoint] = []
    init(date: Date) { self.date = date }
}

@Model final class WatchLogPoint {
    var metricName: String; var value: Double
    init(metricName: String, value: Double) { self.metricName = metricName; self.value = value }
}

@Model final class WatchMetricDef {
    var name: String; var unit: String
    init(name: String, unit: String) { self.name = name; self.unit = unit }
}

// MARK: - Shared model container for Watch

private func watchModelContainer() -> ModelContainer? {
    let schema = Schema([WatchHabit.self, WatchActivityLog.self, WatchLogPoint.self, WatchMetricDef.self])
    // Use App Group store if available; fall back to default
    if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.samsahsch.Trabit") {
        let storeURL = groupURL.appendingPathComponent("default.store")
        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try? ModelContainer(for: schema, configurations: [config])
    }
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    return try? ModelContainer(for: schema, configurations: [config])
}

// MARK: - Root Content View

struct ContentView: View {
    var body: some View {
        if let container = watchModelContainer() {
            WatchTodayView()
                .modelContainer(container)
        } else {
            Text("Could not load habits")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Today View

struct WatchTodayView: View {
    @Query(sort: \WatchHabit.sortOrder) private var allHabits: [WatchHabit]
    @Environment(\.modelContext) private var modelContext

    var habits: [WatchHabit] { allHabits.filter { !$0.isArchived } }
    var completed: Int { habits.filter { $0.isCompleted(on: Date()) }.count }

    var body: some View {
        NavigationStack {
            List {
                // Progress header
                Section {
                    HStack {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.15), lineWidth: 5)
                            Circle()
                                .trim(from: 0, to: habits.isEmpty ? 0 : Double(completed) / Double(habits.count))
                                .stroke(Color.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(completed) of \(habits.count)")
                                .font(.headline)
                            Text("habits done")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                // Habit rows
                ForEach(habits) { habit in
                    WatchHabitRow(habit: habit)
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Habit Row

struct WatchHabitRow: View {
    let habit: WatchHabit
    @State private var showLog = false
    @Environment(\.modelContext) private var modelContext

    var isDone: Bool { habit.isCompleted(on: Date()) }

    var body: some View {
        Button {
            if habit.definedMetrics.isEmpty {
                withAnimation {
                    habit.logs.append(WatchActivityLog(date: Date()))
                }
            } else {
                showLog = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: habit.iconSymbol)
                    .foregroundStyle(watchColor(habit.hexColor))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(habit.name)
                        .font(.body)
                        .strikethrough(isDone)
                        .foregroundStyle(isDone ? .secondary : .primary)
                    if !habit.definedMetrics.isEmpty {
                        Text(habit.definedMetrics.map { $0.unit }.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDone ? .green : Color.white.opacity(0.3))
                    .font(.callout)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showLog) {
            WatchLogSheet(habit: habit)
        }
    }

    // Minimal hex color helper for watchOS (no UIColor dependency)
    private func watchColor(_ hex: String) -> Color {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Quick Log Sheet (with Digital Crown)

struct WatchLogSheet: View {
    let habit: WatchHabit
    @Environment(\.dismiss) private var dismiss
    @State private var values: [Double] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: habit.iconSymbol)
                    Text(habit.name).font(.headline)
                }

                ForEach(habit.definedMetrics.indices, id: \.self) { i in
                    VStack(spacing: 4) {
                        Text(habit.definedMetrics[i].name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(formatValue(values.indices.contains(i) ? values[i] : 0)) \(habit.definedMetrics[i].unit)")
                            .font(.title3).bold()
                            .focusable()
                            .digitalCrownRotation(
                                Binding(
                                    get: { values.indices.contains(i) ? values[i] : 0 },
                                    set: { v in
                                        if values.indices.contains(i) { values[i] = max(0, v) }
                                        else { while values.count <= i { values.append(0) }; values[i] = max(0, v) }
                                    }
                                ),
                                from: 0, through: 999, by: 0.5,
                                sensitivity: .medium,
                                isContinuous: false
                            )
                    }
                    .padding()
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button("Log") {
                    let log = WatchActivityLog(date: Date())
                    for (i, m) in habit.definedMetrics.enumerated() {
                        let v = values.indices.contains(i) ? values[i] : 0
                        if v > 0 { log.entries.append(WatchLogPoint(metricName: m.name, value: v)) }
                    }
                    habit.logs.append(log)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .onAppear {
            values = habit.definedMetrics.map { _ in 0 }
        }
    }

    private func formatValue(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }
}
