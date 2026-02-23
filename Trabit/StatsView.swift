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
    @State private var hiddenCharts: Set<String> = []
    func isHidden(_ key: String) -> Bool { return hiddenCharts.contains(key) }
    func toggleVis(_ key: String) { if isHidden(key) { hiddenCharts.remove(key) } else { hiddenCharts.insert(key) } }
    
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
                HStack {
                    Text("Consistency").font(.caption2).bold().foregroundStyle(.secondary)
                    Spacer()
                    Button { toggleVis("consistency") } label: { Image(systemName: isHidden("consistency") ? "eye.slash" : "eye").font(.caption).foregroundStyle(.blue) }
                }
                if !isHidden("consistency") {
                    HorizontalHeatmap(habit: habit, consistencyGoal: cGoal)
                    if let g = cGoal { ConsistencyOverTimeChart(habit: habit, goal: g) }
                }
            }
            
            let hasWake = habit.definedMetrics.contains(where: {$0.name == "Wake Time"})
            let hasBed = habit.definedMetrics.contains(where: {$0.name == "Bed Time"})
            if hasWake && hasBed {
                HStack {
                    Text("Sleep Window").font(.caption2).bold().foregroundStyle(.secondary)
                    Spacer()
                    Button { toggleVis("sleep") } label: { Image(systemName: isHidden("sleep") ? "eye.slash" : "eye").font(.caption).foregroundStyle(.blue) }
                }
                if !isHidden("sleep") { SleepRangeChart(habit: habit) }
            }
            
            ForEach(habit.definedMetrics) { metric in
                if metric.name != "Wake Time" && metric.name != "Bed Time" {
                    HStack {
                        Text("\(metric.name) (\(metric.unit))").font(.caption2).bold().foregroundStyle(.secondary)
                        Spacer()
                        Button { toggleVis(metric.name) } label: { Image(systemName: isHidden(metric.name) ? "eye.slash" : "eye").font(.caption).foregroundStyle(.blue) }
                    }
                    if !isHidden(metric.name) { MetricChart(habit: habit, metric: metric) }
                }
            }
            
            let dM = habit.definedMetrics.first(where: {$0.name.lowercased().contains("dist") || $0.name.lowercased().contains("lap")})
            let tM = habit.definedMetrics.first(where: {$0.name.lowercased().contains("time")})
            if let dist = dM, let time = tM {
                HStack {
                    Text("Pace (\(time.unit)/\(dist.unit))").font(.caption2).bold().foregroundStyle(.secondary)
                    Spacer()
                    Button { toggleVis("pace") } label: { Image(systemName: isHidden("pace") ? "eye.slash" : "eye").font(.caption).foregroundStyle(.blue) }
                }
                if !isHidden("pace") { PaceChart(habit: habit, dM: dist, tM: time) }
            }
            
        }.padding().background(Color(uiColor: .secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// THE FIX: Completely naturally maps Evening Times to the top, Morning to the bottom
struct SleepRangeChart: View {
    let habit: Habit
    var body: some View {
        let grouped = Dictionary(grouping: habit.logs) { Calendar.current.startOfDay(for: $0.date) }
        let sleepData = grouped.compactMap { (date, logs) -> (Date, Double, Double)? in
            guard let firstLog = logs.first else { return nil }
            guard let wake = firstLog.entries.first(where: { $0.metricName == "Wake Time" })?.value, let bed = firstLog.entries.first(where: { $0.metricName == "Bed Time" })?.value else { return nil }
            let adjustedBed = bed > 12 ? bed - 24 : bed
            // Negating flips the chart perfectly so PM is up and AM is down!
            return (date, -adjustedBed, -wake)
        }.sorted(by: { $0.0 < $1.0 })
        
        Chart {
            ForEach(sleepData, id: \.0) { date, plotBed, plotWake in
                BarMark(x: .value("Date", date, unit: .day), yStart: .value("Bed", plotBed), yEnd: .value("Wake", plotWake), width: 8).foregroundStyle(Color(hex: habit.hexColor).opacity(0.7)).cornerRadius(4)
                PointMark(x: .value("Date", date, unit: .day), y: .value("Wake", plotWake)).foregroundStyle(Color(hex: habit.hexColor))
                PointMark(x: .value("Date", date, unit: .day), y: .value("Bed", plotBed)).foregroundStyle(Color(hex: habit.hexColor))
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { val in
                if let d = val.as(Double.self) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4]))
                    AxisValueLabel { Text(UnitHelpers.formatTime(-d)) } // Reverses the negation for the label!
                }
            }
        }
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { value in AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4])); AxisValueLabel(format: .dateTime.month().day()) } }
        .chartXScale(range: .plotDimension(padding: 15))
        .frame(height: 150)
    }
}

struct MetricChart: View {
    let habit: Habit; let metric: MetricDefinition
    var body: some View {
        let isMax = metric.name.lowercased().contains("weight") || metric.name.lowercased().contains("mass")
        
        // THE FIX: Sums up 1L + 1L + 1L -> 3L for a single day!
        let grouped = Dictionary(grouping: habit.logs) { Calendar.current.startOfDay(for: $0.date) }
        let aggregated = grouped.compactMap { (date, logs) -> (Date, Double)? in
            let vals = logs.flatMap { $0.entries }.filter { $0.metricName == metric.name }.map { $0.value }
            if vals.isEmpty { return nil }
            return (date, isMax ? (vals.max() ?? 0) : vals.reduce(0, +))
        }.sorted(by: { $0.0 < $1.0 })
        
        let minVal = aggregated.map { $0.1 }.min() ?? 0; let maxVal = aggregated.map { $0.1 }.max() ?? 10
        let padding = minVal == maxVal ? 5.0 : (maxVal - minVal) * 0.1
        let isHours = metric.unit.lowercased() == "hours"
        
        Chart {
            ForEach(aggregated, id: \.0) { date, value in
                LineMark(x: .value("Date", date, unit: .day), y: .value(metric.unit, value)).foregroundStyle(Color(hex: habit.hexColor))
                PointMark(x: .value("Date", date, unit: .day), y: .value(metric.unit, value)).foregroundStyle(Color(hex: habit.hexColor))
            }
        }
        .chartYAxis { AxisMarks(values: .automatic) { val in if let d = val.as(Double.self) { AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4])); if isHours { AxisValueLabel { Text(UnitHelpers.formatDuration(d)) } } else { AxisValueLabel { Text(UnitHelpers.format(d)) } } } } }
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { value in AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4])); AxisValueLabel(format: .dateTime.month().day()) } }
        .chartYScale(domain: (minVal - padding)...(maxVal + padding))
        .chartXScale(range: .plotDimension(padding: 15))
        .frame(height: 120)
    }
}

struct PaceChart: View {
    let habit: Habit; let dM: MetricDefinition; let tM: MetricDefinition
    var body: some View {
        let grouped = Dictionary(grouping: habit.logs) { Calendar.current.startOfDay(for: $0.date) }
        let aggregatedPace = grouped.compactMap { (date, logs) -> (Date, Double)? in
            let totalDist = logs.flatMap { $0.entries }.filter { $0.metricName == dM.name }.reduce(0) { $0 + $1.value }
            let totalTime = logs.flatMap { $0.entries }.filter { $0.metricName == tM.name }.reduce(0) { $0 + $1.value }
            if totalDist > 0 && totalTime > 0 { return (date, totalTime / totalDist) }
            return nil
        }.sorted(by: { $0.0 < $1.0 })
        
        Chart {
            ForEach(aggregatedPace, id: \.0) { date, pace in
                LineMark(x: .value("Date", date, unit: .day), y: .value("Pace", pace)).foregroundStyle(.purple)
                PointMark(x: .value("Date", date, unit: .day), y: .value("Pace", pace)).foregroundStyle(.purple)
            }
        }
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { value in AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4])); AxisValueLabel(format: .dateTime.month().day()) } }
        .chartXScale(range: .plotDimension(padding: 15))
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
    var body: some View { Chart { ForEach(days, id: \.self) { day in let target = Double(goal.consistencyDifficulty?.targetOccurrences ?? 1); let score = Double(habit.consistencyScore(for: goal, upTo: day)); let percentage = (score / target) * 100.0; LineMark(x: .value("Date", day, unit: .day), y: .value("Score", percentage)).foregroundStyle(Color(hex: habit.hexColor)) } }
        .chartYAxis { AxisMarks { AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4])); AxisValueLabel() } }
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { value in AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4])); AxisValueLabel(format: .dateTime.month().day()) } }
        .chartYScale(domain: 0...100).chartXScale(range: .plotDimension(padding: 15)).frame(height: 100)
    }
}

struct ShareChartButton: View {
    let habit: Habit; @Environment(\.displayScale) var displayScale
    @MainActor func generateSnapshot() -> UIImage? {
        let view = VStack(alignment: .leading, spacing: 15) { HStack { Image(systemName: habit.iconSymbol); Text(habit.name).font(.largeTitle).bold() }.foregroundStyle(Color(hex: habit.hexColor)); Text("Logged \(habit.logs.count) sessions!").font(.title2).foregroundStyle(.primary); if let cGoal = habit.goals.first(where: { $0.kind == .consistency }) { Text("Consistency Progress").font(.headline); ConsistencyOverTimeChart(habit: habit, goal: cGoal) }; ForEach(habit.definedMetrics.filter { $0.isVisible }) { metric in Text("\(metric.name) (\(metric.unit))").font(.headline); MetricChart(habit: habit, metric: metric) } }.padding(30).frame(width: 400).background(Color(uiColor: .systemBackground))
        let renderer = ImageRenderer(content: view); renderer.scale = displayScale; return renderer.uiImage
    }
    var body: some View { Button(action: { Task { @MainActor in var items: [Any] = ["My progress for \(habit.name)!", URL(string: "https://trabit.app")!]; if let image = generateSnapshot(), let data = image.pngData() { let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("TrabitChart.png"); try? data.write(to: tempURL); items.append(tempURL) }
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene, let root = scene.windows.first?.rootViewController {
            var top = root; while let p = top.presentedViewController { top = p }; top.present(av, animated: true)
        }
    } }) { Image(systemName: "square.and.arrow.up").font(.subheadline).bold() } }
}
