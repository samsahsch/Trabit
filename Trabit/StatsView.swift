import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \Habit.sortOrder) var allHabits: [Habit]
    var habits: [Habit] { allHabits.filter { !$0.isArchived } }
    var archivedHabits: [Habit] { allHabits.filter { $0.isArchived } }
    @State private var showArchived = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if habits.isEmpty && archivedHabits.isEmpty { ContentUnavailableView("No Data", systemImage: "chart.bar") }
                    ForEach(habits) { habit in HabitStatsCard(habit: habit) }
                    
                    if !archivedHabits.isEmpty {
                        DisclosureGroup("Archived Habits", isExpanded: $showArchived) {
                            ForEach(archivedHabits) { habit in HabitStatsCard(habit: habit).opacity(0.7) }
                        }.padding().background(Color(uiColor: .secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }.padding()
            }.navigationTitle("Progress")
        }
    }
}

struct HabitStatsCard: View {
    let habit: Habit
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: habit.iconSymbol).foregroundStyle(Color(hex: habit.hexColor))
                Text(habit.name).font(.headline)
                Spacer()
                if habit.isArchived { Button("Unarchive") { habit.isArchived = false }.font(.caption).buttonStyle(.bordered) }
                ShareChartButton(habit: habit)
            }
            
            let cGoal = habit.goals.first(where: { $0.kind == .consistency })
            if habit.definedMetrics.isEmpty || cGoal != nil {
                let unit = cGoal?.metricName != nil ? habit.definedMetrics.first(where: {$0.name == cGoal!.metricName!})?.unit ?? "" : ""
                let targetText = (cGoal?.targetValue != nil && cGoal?.metricName != nil) ? "(Reached \(UnitHelpers.format(cGoal!.targetValue!)) \(unit))" : ""
                Text("Consistency \(targetText)").font(.caption2).bold().foregroundStyle(.secondary)
                HorizontalHeatmap(habit: habit, consistencyGoal: cGoal)
                
                if let g = cGoal {
                    Text("Consistency Progress (%)").font(.caption2).bold().foregroundStyle(.secondary)
                    ConsistencyOverTimeChart(habit: habit, goal: g)
                }
            }
            
            ForEach(habit.definedMetrics) { metric in
                HStack {
                    Text("\(metric.name) (\(metric.unit))").font(.caption2).bold().foregroundStyle(.secondary)
                    Spacer()
                    Button { metric.isVisible.toggle() } label: { Image(systemName: metric.isVisible ? "eye.slash" : "eye").font(.caption).foregroundStyle(.blue) }
                }
                if metric.isVisible { MetricChart(habit: habit, metric: metric) }
            }
        }.padding().background(Color(uiColor: .secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MetricChart: View {
    let habit: Habit; let metric: MetricDefinition
    var body: some View {
        let entries = habit.logs.flatMap { log in log.entries.filter { $0.metricName == metric.name }.map { (log.date, $0.value) } }
        let minVal = entries.map { $0.1 }.min() ?? 0; let maxVal = entries.map { $0.1 }.max() ?? 10
        let padding = minVal == maxVal ? 5.0 : (maxVal - minVal) * 0.1
        let isTime = metric.unit.uppercased() == "AM" || metric.unit.uppercased() == "PM"
        let isHours = metric.unit.lowercased() == "hours"
        
        Chart {
            ForEach(entries.sorted(by: { $0.0 < $1.0 }), id: \.0) { date, value in
                LineMark(x: .value("Date", date, unit: .day), y: .value(metric.unit, value)).foregroundStyle(Color(hex: habit.hexColor))
                PointMark(x: .value("Date", date, unit: .day), y: .value(metric.unit, value)).foregroundStyle(Color(hex: habit.hexColor))
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { val in
                if let d = val.as(Double.self) {
                    if isTime { AxisValueLabel { Text(UnitHelpers.formatTime(d)) } }
                    else if isHours { AxisValueLabel { Text(UnitHelpers.formatDuration(d)) } }
                    else { AxisValueLabel { Text(UnitHelpers.format(d)) } }
                }
            }
        }
        .chartYScale(domain: (minVal - padding)...(maxVal + padding))
        .padding(.horizontal, 10) // PERFECTLY prevents cut-off text on the edges
        .frame(height: 120)
    }
}

struct HorizontalHeatmap: View {
    let habit: Habit; let consistencyGoal: GoalDefinition?
    let days: [Date] = (0..<30).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
    var body: some View { ScrollViewReader { proxy in ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { ForEach(days, id: \.self) { day in VStack(spacing: 4) { Text(day.formatted(.dateTime.weekday(.narrow))).font(.system(size: 8)).foregroundStyle(.secondary); RoundedRectangle(cornerRadius: 4).fill(habit.isConsistencyMet(on: day, for: consistencyGoal) ? Color(hex: habit.hexColor) : Color.gray.opacity(0.2)).frame(width: 20, height: 20) }.id(day) } }.padding(.bottom, 4) }.onAppear { proxy.scrollTo(days.last, anchor: .trailing) } } }
}

struct ConsistencyOverTimeChart: View {
    let habit: Habit; let goal: GoalDefinition
    let days: [Date] = (0..<21).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
    var body: some View { Chart { ForEach(days, id: \.self) { day in let target = Double(goal.consistencyDifficulty?.targetOccurrences ?? 1); let score = Double(habit.consistencyScore(for: goal, upTo: day)); let percentage = (score / target) * 100.0; LineMark(x: .value("Date", day, unit: .day), y: .value("Score", percentage)).foregroundStyle(Color(hex: habit.hexColor)) } }.chartYScale(domain: 0...100).padding(.horizontal, 10).frame(height: 100) }
}

struct ShareChartButton: View {
    let habit: Habit; @Environment(\.displayScale) var displayScale
    
    @MainActor func generateSnapshot() -> UIImage? {
        let view = VStack(alignment: .leading, spacing: 15) {
            HStack { Image(systemName: habit.iconSymbol); Text(habit.name).font(.largeTitle).bold() }.foregroundStyle(Color(hex: habit.hexColor))
            Text("Logged \(habit.logs.count) sessions!").font(.title2).foregroundStyle(.primary)
            
            // Includes Consistency explicitly
            if let cGoal = habit.goals.first(where: { $0.kind == .consistency }) {
                Text("Consistency Progress").font(.headline)
                ConsistencyOverTimeChart(habit: habit, goal: cGoal)
            }
            
            // Includes all visible graphs dynamically
            ForEach(habit.definedMetrics.filter { $0.isVisible }) { metric in
                Text("\(metric.name) (\(metric.unit))").font(.headline)
                MetricChart(habit: habit, metric: metric)
            }
        }.padding(30).frame(width: 400).background(Color(uiColor: .systemBackground))
        
        let renderer = ImageRenderer(content: view); renderer.scale = displayScale; return renderer.uiImage
    }
    
    var body: some View {
        Button(action: {
            Task { @MainActor in
                var items: [Any] = ["My progress for \(habit.name)!", URL(string: "https://trabit.app")!]
                if let image = generateSnapshot(), let data = image.pngData() {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("TrabitChart.png")
                    try? data.write(to: tempURL); items.append(tempURL)
                }
                presentShareSheet(items: items) // Uses the safe global helper
            }
        }) { Image(systemName: "square.and.arrow.up").font(.subheadline).bold() }
    }
}
