// RecapsView.swift — Weekly, Monthly, Quarterly, and Yearly habit reviews.
// Shown as a sheet from StatsView. Automatically selects the most recent completed period.

import SwiftUI
import SwiftData
import Charts

// MARK: - Recap Period

enum RecapPeriod: String, CaseIterable {
    case weekly = "Week"
    case monthly = "Month"
    case quarterly = "Quarter"
    case halfYear = "Half Year"
    case yearly = "Year"

    var icon: String {
        switch self {
        case .weekly: return "calendar.badge.checkmark"
        case .monthly: return "calendar"
        case .quarterly: return "calendar.badge.plus"
        case .halfYear: return "chart.line.uptrend.xyaxis"
        case .yearly: return "rosette"
        }
    }
}

// MARK: - Recap Data Model

struct RecapData {
    let period: RecapPeriod
    let startDate: Date
    let endDate: Date
    let habits: [Habit]

    // Per-habit stats
    struct HabitStat: Identifiable {
        let id: String
        let habit: Habit
        let completionRate: Double   // 0–1
        let totalLogs: Int
        let longestStreak: Int
        let bestDay: Date?
        let totalMetricValues: [String: Double] // metricName → total
    }

    var habitStats: [HabitStat] {
        habits.map { habit in
            let days = daysBetween(startDate, endDate)
            let logs = habit.logs.filter { $0.date >= startDate && $0.date <= endDate }
            let loggedDays = Set(logs.map { Calendar.current.startOfDay(for: $0.date) })
            let rate = days > 0 ? Double(loggedDays.count) / Double(days) : 0

            // Longest streak in period
            var longest = 0
            var current = 0
            var cursor = startDate
            let cal = Calendar.current
            while cursor <= endDate {
                if loggedDays.contains(cal.startOfDay(for: cursor)) {
                    current += 1
                    longest = max(longest, current)
                } else {
                    current = 0
                }
                cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
            }

            // Best day (day with most metric total or most logs)
            let bestDay = loggedDays.max(by: { a, b in
                let aLogs = logs.filter { cal.isDate($0.date, inSameDayAs: a) }
                let bLogs = logs.filter { cal.isDate($0.date, inSameDayAs: b) }
                return aLogs.count < bLogs.count
            })

            // Metric totals
            var totals: [String: Double] = [:]
            for log in logs {
                for entry in log.entries {
                    totals[entry.metricName, default: 0] += entry.value
                }
            }

            return HabitStat(
                id: habit.name,
                habit: habit,
                completionRate: rate,
                totalLogs: loggedDays.count,
                longestStreak: longest,
                bestDay: bestDay,
                totalMetricValues: totals
            )
        }
        .sorted { $0.completionRate > $1.completionRate }
    }

    var overallCompletionRate: Double {
        let stats = habitStats
        guard !stats.isEmpty else { return 0 }
        return stats.map { $0.completionRate }.reduce(0, +) / Double(stats.count)
    }

    var mvpHabit: HabitStat? { habitStats.first }

    var mostImproved: HabitStat? {
        // Habit with biggest improvement vs previous period
        habitStats.max(by: { $0.totalLogs < $1.totalLogs })
    }

    var totalLogsAllHabits: Int {
        habitStats.map { $0.totalLogs }.reduce(0, +)
    }

    var title: String {
        let fmt = DateFormatter()
        switch period {
        case .weekly:
            fmt.dateFormat = "MMM d"
            return "Week of \(fmt.string(from: startDate))"
        case .monthly:
            fmt.dateFormat = "MMMM yyyy"
            return fmt.string(from: startDate)
        case .quarterly:
            let q = Calendar.current.component(.month, from: startDate) / 3 + 1
            let year = Calendar.current.component(.year, from: startDate)
            return "Q\(q) \(year)"
        case .halfYear:
            fmt.dateFormat = "MMM"
            let yearStr = Calendar.current.component(.year, from: startDate).description
            return "\(fmt.string(from: startDate))–\(fmt.string(from: endDate)) \(yearStr)"
        case .yearly:
            fmt.dateFormat = "yyyy"
            return fmt.string(from: startDate)
        }
    }

    private func daysBetween(_ a: Date, _ b: Date) -> Int {
        max(1, Calendar.current.dateComponents([.day], from: a, to: b).day ?? 1)
    }
}

// MARK: - Recaps View

struct RecapsView: View {
    let habits: [Habit]
    @State private var selectedPeriod: RecapPeriod = .weekly
    @State private var periodOffset: Int = 0   // 0 = most recent completed period

    private var recapData: RecapData {
        let (start, end) = dateRange(for: selectedPeriod, offset: periodOffset)
        return RecapData(period: selectedPeriod, startDate: start, endDate: end, habits: habits)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Period picker
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(RecapPeriod.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: selectedPeriod) { _, _ in periodOffset = 0 }

                ScrollView {
                    VStack(spacing: 20) {
                        // Navigation header
                        periodNavigator

                        // Hero summary card
                        heroCard

                        // Per-habit cards
                        ForEach(recapData.habitStats) { stat in
                            HabitRecapCard(stat: stat, recapData: recapData)
                        }
                    }
                    .padding()
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Reviews")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Period Navigator

    private var periodNavigator: some View {
        HStack {
            Button {
                withAnimation { periodOffset -= 1 }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(recapData.title)
                    .font(.headline)
                let (start, end) = dateRange(for: selectedPeriod, offset: periodOffset)
                Text("\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation { periodOffset += 1 }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(periodOffset < 0 ? .blue : Color.secondary.opacity(0.3))
            }
            .disabled(periodOffset >= 0)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(spacing: 20) {
            // Big ring
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.15), lineWidth: 16)
                    .frame(width: 130, height: 130)
                Circle()
                    .trim(from: 0, to: recapData.overallCompletionRate)
                    .stroke(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 130, height: 130)
                VStack(spacing: 2) {
                    Text("\(Int(recapData.overallCompletionRate * 100))%")
                        .font(.title).bold()
                    Text("overall")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Key stats row
            HStack(spacing: 0) {
                StatPill(value: "\(recapData.totalLogsAllHabits)", label: "Total Logs")
                Divider().frame(height: 36)
                StatPill(value: "\(recapData.habits.count)", label: "Habits")
                Divider().frame(height: 36)
                if let mvp = recapData.mvpHabit {
                    StatPill(value: mvp.habit.name, label: "Top Habit")
                }
            }

            // Motivational message
            Text(motivationalMessage(rate: recapData.overallCompletionRate))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Helpers

    private func motivationalMessage(rate: Double) -> String {
        switch rate {
        case 0.9...: return "Outstanding. You crushed it this period."
        case 0.75...: return "Strong period. Keep the momentum going."
        case 0.5...: return "Good effort. Push a little harder next time."
        case 0.25...: return "A quiet period — every comeback starts with one good day."
        default: return "New period, fresh start. You've got this."
        }
    }

    // Returns start/end of the period, offset from now (0 = last complete period)
    func dateRange(for period: RecapPeriod, offset: Int) -> (Date, Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        switch period {
        case .weekly:
            // Most recent completed week (Mon–Sun)
            let weekday = cal.component(.weekday, from: today) // 1=Sun
            let daysSinceMonday = (weekday + 5) % 7
            let thisMonday = cal.date(byAdding: .day, value: -daysSinceMonday, to: today)!
            let lastMonday = cal.date(byAdding: .weekOfYear, value: -1 + offset, to: thisMonday)!
            let lastSunday = cal.date(byAdding: .day, value: 6, to: lastMonday)!
            return (lastMonday, min(lastSunday, today))

        case .monthly:
            let comps = cal.dateComponents([.year, .month], from: today)
            let thisMonth = cal.date(from: comps)!
            let start = cal.date(byAdding: .month, value: -1 + offset, to: thisMonth)!
            let end = cal.date(byAdding: .day, value: -1, to: cal.date(byAdding: .month, value: 1, to: start)!)!
            return (start, min(end, today))

        case .quarterly:
            let month = cal.component(.month, from: today) // 1–12
            let qStart = ((month - 1) / 3) * 3 + 1
            let year = cal.component(.year, from: today)
            let thisQStart = cal.date(from: DateComponents(year: year, month: qStart, day: 1))!
            let start = cal.date(byAdding: .month, value: -3 + (offset * 3), to: thisQStart)!
            let end = cal.date(byAdding: .day, value: -1, to: cal.date(byAdding: .month, value: 3, to: start)!)!
            return (start, min(end, today))

        case .halfYear:
            let month = cal.component(.month, from: today)
            let hStart = month <= 6 ? 1 : 7
            let year = cal.component(.year, from: today)
            let thisHStart = cal.date(from: DateComponents(year: year, month: hStart, day: 1))!
            let start = cal.date(byAdding: .month, value: -6 + (offset * 6), to: thisHStart)!
            let end = cal.date(byAdding: .day, value: -1, to: cal.date(byAdding: .month, value: 6, to: start)!)!
            return (start, min(end, today))

        case .yearly:
            let year = cal.component(.year, from: today) + offset
            let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
            let end = cal.date(from: DateComponents(year: year, month: 12, day: 31))!
            return (start, min(end, today))
        }
    }
}

// MARK: - Stat Pill

private struct StatPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline).bold()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Habit Recap Card

private struct HabitRecapCard: View {
    let stat: RecapData.HabitStat
    let recapData: RecapData
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: stat.habit.iconSymbol)
                        .foregroundStyle(Color(hex: stat.habit.hexColor))
                        .frame(width: 28)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.habit.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(Int(stat.completionRate * 100))% — \(stat.totalLogs) day\(stat.totalLogs == 1 ? "" : "s") logged")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Mini completion ring
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: stat.completionRate)
                            .stroke(Color(hex: stat.habit.hexColor), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 32, height: 32)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal)

                VStack(alignment: .leading, spacing: 14) {
                    // Streak + best day
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("\(stat.longestStreak) days", systemImage: "flame.fill")
                                .font(.subheadline).bold()
                                .foregroundStyle(.orange)
                            Text("longest streak")
                                .font(.caption2).foregroundStyle(.secondary)
                        }

                        if let best = stat.bestDay {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(best.formatted(.dateTime.month(.abbreviated).day()),
                                      systemImage: "star.fill")
                                    .font(.subheadline).bold()
                                    .foregroundStyle(.yellow)
                                Text("best day")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Metric totals
                    if !stat.totalMetricValues.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Period Totals")
                                .font(.caption).foregroundStyle(.secondary).fontWeight(.semibold)
                            ForEach(stat.habit.definedMetrics, id: \.name) { metric in
                                if let total = stat.totalMetricValues[metric.name], total > 0 {
                                    HStack {
                                        Text(metric.name)
                                            .font(.subheadline)
                                        Spacer()
                                        Text("\(UnitHelpers.format(total)) \(metric.unit)")
                                            .font(.subheadline).bold()
                                            .foregroundStyle(Color(hex: stat.habit.hexColor))
                                    }
                                }
                            }
                        }
                    }

                    // Sparkline — daily completion over period
                    SparklineChart(habit: stat.habit, startDate: recapData.startDate, endDate: recapData.endDate)
                        .frame(height: 48)
                }
                .padding()
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Sparkline Chart

private struct SparklineChart: View {
    let habit: Habit
    let startDate: Date
    let endDate: Date

    private struct DayPoint: Identifiable {
        let id: Date
        let date: Date
        let done: Bool
    }

    private var points: [DayPoint] {
        var pts: [DayPoint] = []
        let cal = Calendar.current
        var d = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)
        while d <= end {
            pts.append(DayPoint(id: d, date: d, done: habit.isCompleted(on: d)))
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return pts
    }

    var body: some View {
        let color = Color(hex: habit.hexColor)
        Chart(points) { pt in
            RectangleMark(
                x: .value("Day", pt.date, unit: .day),
                y: .value("Done", pt.done ? 1 : 0),
                width: .ratio(0.85),
                height: .ratio(1.0)
            )
            .foregroundStyle(pt.done ? color.opacity(0.85) : Color.secondary.opacity(0.1))
            .cornerRadius(3)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
    }
}
