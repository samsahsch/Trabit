// Watch ContentView — friction-free habit logging on the wrist.
// Design philosophy: the watch is where you ARE when you do the habit.
// Tap once to log. Digital Crown for values. Done in under 3 seconds.

import SwiftUI
import WatchKit
import WidgetKit
import CloudKit

// MARK: - Shared App Group store URL

private let watchAppGroupID = "group.com.samsahsch.Trabit"

// MARK: - Lightweight watch-side models (read directly from App Group UserDefaults)
// The watch reads habit snapshots written by the iOS app's WidgetCache so we never
// need to open a SwiftData container on-watch (too slow, same-process constraint).

struct WatchHabitItem: Identifiable, Codable {
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

struct WatchCache {
    static let suiteName = watchAppGroupID
    static let habitsKey  = "watch_habits_v2"
    static let completedKey = "watch_completed"
    static let totalKey = "watch_total"

    static func loadHabits() -> [WatchHabitItem] {
        let d = UserDefaults(suiteName: suiteName) ?? .standard
        guard let data = d.data(forKey: habitsKey),
              let items = try? JSONDecoder().decode([WatchHabitItem].self, from: data)
        else { return [] }
        return items
    }

    static func saveHabits(_ items: [WatchHabitItem]) {
        let d = UserDefaults(suiteName: suiteName) ?? .standard
        if let data = try? JSONEncoder().encode(items) {
            d.set(data, forKey: habitsKey)
        }
        let completed = items.filter(\.isDone).count
        d.set(completed, forKey: completedKey)
        d.set(items.count, forKey: totalKey)
        d.set(items.first(where: { !$0.isDone })?.name ?? "", forKey: "watch_nextHabit")
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Root View

struct ContentView: View {
    @State private var habits: [WatchHabitItem] = []
    @State private var selectedHabit: WatchHabitItem?
    @State private var toastText: String?
    @State private var showFriends = false

    var completedCount: Int { habits.filter(\.isDone).count }
    var progress: Double { habits.isEmpty ? 0 : Double(completedCount) / Double(habits.count) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    // Progress ring header
                    progressHeader

                    // Habit list
                    if habits.isEmpty {
                        Text("Open Trabit on iPhone to add habits")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    } else {
                        ForEach($habits) { $habit in
                            WatchHabitRow(habit: $habit) { logged in
                                handleLog(habit: habit, valueLogged: logged)
                            }
                        }
                    }

                    // Toast
                    if let t = toastText {
                        Text(t)
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.green))
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFriends = true
                    } label: {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .sheet(isPresented: $showFriends) {
            WatchFriendsView()
        }
        .onAppear { reload() }
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: progress)
                VStack(spacing: 0) {
                    Text("\(completedCount)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("of \(habits.count)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                if completedCount == habits.count && !habits.isEmpty {
                    Text("All done!")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("Great work today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let next = habits.first(where: { !$0.isDone }) {
                    Text("Up next")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(next.name)
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    Text("No habits yet")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
    }

    // MARK: - Actions

    private func handleLog(habit: WatchHabitItem, valueLogged: Double?) {
        if let idx = habits.firstIndex(where: { $0.id == habit.id }) {
            habits[idx].isDone = true
            if let v = valueLogged {
                habits[idx].currentValue += v
            }
        }
        WatchCache.saveHabits(habits)
        withAnimation {
            toastText = valueLogged != nil
                ? "Logged \(UnitFormatter.format(valueLogged!)) \(habit.metricUnit)"
                : "\(habit.name) done!"
        }
        WKInterfaceDevice.current().play(.success)
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { toastText = nil }
        }
    }

    private func reload() {
        habits = WatchCache.loadHabits()
    }
}

// MARK: - Watch Habit Row

struct WatchHabitRow: View {
    @Binding var habit: WatchHabitItem
    var onLog: (Double?) -> Void

    @State private var showInput = false
    @State private var inputValue: Double = 0

    var body: some View {
        Button {
            if habit.isDone {
                // Already done — no action
                WKInterfaceDevice.current().play(.click)
            } else if habit.isMetric {
                showInput = true
            } else {
                onLog(nil)
            }
        } label: {
            HStack(spacing: 10) {
                // Icon with color
                ZStack {
                    Circle()
                        .fill(Color(hex: habit.color).opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: habit.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(hex: habit.color))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.system(size: 15, weight: habit.isDone ? .regular : .semibold))
                        .foregroundStyle(habit.isDone ? .secondary : .primary)
                        .lineLimit(1)
                        .strikethrough(habit.isDone)

                    if habit.isMetric && habit.dailyTarget > 0 {
                        ProgressView(value: min(habit.currentValue / habit.dailyTarget, 1))
                            .tint(Color(hex: habit.color))
                            .frame(width: 80)
                    }
                }

                Spacer()

                Image(systemName: habit.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(habit.isDone ? Color.green : Color.secondary.opacity(0.4))
            }
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(habit.isDone ? Color.green.opacity(0.08) : Color.white.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showInput) {
            WatchMetricInput(
                habitName: habit.name,
                unit: habit.metricUnit,
                currentValue: habit.currentValue,
                targetValue: habit.dailyTarget
            ) { value in
                onLog(value)
            }
        }
    }
}

// MARK: - Metric Input Sheet (Digital Crown)

struct WatchMetricInput: View {
    let habitName: String
    let unit: String
    let currentValue: Double
    let targetValue: Double
    var onSubmit: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: Double = 1
    @FocusState private var focused: Bool

    // Crown step: 1 for integers, 0.5 for small units
    private var step: Double { unit.lowercased().contains("km") ? 0.5 : 1 }
    private var maxVal: Double { targetValue > 0 ? targetValue * 2 : 100 }

    var body: some View {
        VStack(spacing: 8) {
            Text(habitName)
                .font(.headline)
                .lineLimit(1)

            // Big number display
            Text("\(UnitFormatter.format(value)) \(unit)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.blue)
                .focusable()
                .digitalCrownRotation($value, from: step, through: maxVal, by: step, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                .focused($focused)
                .onAppear { focused = true }

            if targetValue > 0 {
                Text("Target: \(UnitFormatter.format(targetValue)) \(unit)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button("Log") {
                onSubmit(value)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding()
        .onAppear {
            // Start at a sensible default
            value = step
        }
    }
}

// MARK: - Watch Friends View (CloudKit live data)

struct WatchFriendsView: View {
    @State private var friends: [WatchFriendSnapshot] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                } else if friends.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Add friends\nin the iPhone app")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    List(friends) { friend in
                        WatchFriendRow(friend: friend)
                    }
                }
            }
            .navigationTitle("Friends")
        }
        .task { await loadFriends() }
    }

    private func loadFriends() async {
        let d = UserDefaults(suiteName: watchAppGroupID) ?? .standard
        if let data = d.data(forKey: "watch_friends"),
           let cached = try? JSONDecoder().decode([WatchFriendSnapshot].self, from: data) {
            friends = cached
        }
        isLoading = false
    }
}

struct WatchFriendSnapshot: Identifiable, Codable {
    var id: String
    var name: String
    var completedToday: Int
    var totalToday: Int
    var topGoalName: String
    var topGoalProgress: Double
    var topGoalColor: String
}

struct WatchFriendRow: View {
    let friend: WatchFriendSnapshot

    var progress: Double { friend.totalToday > 0 ? Double(friend.completedToday) / Double(friend.totalToday) : 0 }

    var body: some View {
        HStack(spacing: 8) {
            // Mini ring
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text("\(friend.completedToday)/\(friend.totalToday) today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Minimal number formatter (no Foundation dependency on watch)

private enum UnitFormatter {
    static func format(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        return String(format: "%.1f", v)
    }
}

// MARK: - Color hex extension (duplicated here; watch target can't import main app)

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

// MARK: - WatchProgressCache (shared with complications)

struct WatchProgressCache {
    static let suiteName = watchAppGroupID
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
