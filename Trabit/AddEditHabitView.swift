import SwiftUI
import SwiftData

struct AddEditHabitView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var habitToEdit: Habit?
    
    @State private var name = ""
    @State private var selectedColor = "007AFF"
    @State private var selectedIcon = "figure.run"
    
    @State private var freqType: FrequencyType = .daily
    @State private var freqInterval = 2
    @State private var freqDays: Set<Int> = [2, 4, 6]
    @State private var dailyGoalCount = 1
    
    @State private var metrics: [MetricDefinition] = []
    @State private var tempMetricName = ""
    @State private var tempMetricUnit = ""
    
    @State private var goals: [GoalDefinition] = []
    @State private var showGoalSheet = false
    
    @State private var reminderEnabled = false
    @State private var reminderTime = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()

    var body: some View {
        NavigationStack {
            List {
                IdentitySection(name: $name, selectedColor: $selectedColor, selectedIcon: $selectedIcon, freqType: $freqType, freqInterval: $freqInterval, freqDays: $freqDays, dailyGoalCount: $dailyGoalCount, metrics: $metrics)
                MetricsSection(metrics: $metrics, tempMetricName: $tempMetricName, tempMetricUnit: $tempMetricUnit)
                ReminderSection(reminderEnabled: $reminderEnabled, reminderTime: $reminderTime)
                GoalsSection(goals: $goals, showGoalSheet: $showGoalSheet)
            }
            .listStyle(.insetGrouped)
            .navigationTitle(habitToEdit == nil ? "New Habit" : "Edit Habit").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.isEmpty) } }
            .sheet(isPresented: $showGoalSheet) { GoalSheetView(metrics: metrics, goals: $goals, showGoalSheet: $showGoalSheet) }
            .onAppear { if let h = habitToEdit { load(h) } }
        }
    }
    
    func load(_ h: Habit) {
        name = h.name; selectedColor = h.hexColor; selectedIcon = h.iconSymbol
        freqType = h.frequencyType; freqInterval = h.frequencyInterval ?? 2
        freqDays = Set(h.frequencyWeekdays ?? [2,4,6]); dailyGoalCount = h.dailyGoalCount
        metrics = h.definedMetrics; goals = h.goals
        reminderEnabled = h.reminderEnabled
        reminderTime = Calendar.current.date(from: DateComponents(hour: h.reminderHour, minute: h.reminderMinute)) ?? Date()
    }
    
    func save() {
        let h = habitToEdit ?? Habit(name: name, icon: selectedIcon, color: selectedColor)
        h.name = name; h.hexColor = selectedColor; h.iconSymbol = selectedIcon
        h.frequencyType = freqType; h.frequencyInterval = freqInterval
        h.frequencyWeekdays = Array(freqDays); h.dailyGoalCount = dailyGoalCount
        h.definedMetrics = metrics; h.goals = goals
        h.reminderEnabled = reminderEnabled
        h.reminderHour = Calendar.current.component(.hour, from: reminderTime)
        h.reminderMinute = Calendar.current.component(.minute, from: reminderTime)
        if habitToEdit == nil { modelContext.insert(h) }
        NotificationManager.shared.scheduleReminder(for: h)
        dismiss()
    }
}

struct IdentitySection: View {
    @Binding var name: String; @Binding var selectedColor: String; @Binding var selectedIcon: String
    @Binding var freqType: FrequencyType; @Binding var freqInterval: Int; @Binding var freqDays: Set<Int>
    @Binding var dailyGoalCount: Int; @Binding var metrics: [MetricDefinition]
    let dayLetters = ["S", "M", "T", "W", "T", "F", "S"]
    
    var body: some View {
        Section("Identity") {
            // AUTOMATED SLEEP TEMPLATE
            Button("✨ Use Bedtime Template") {
                name = "Bedtime"; selectedIcon = "moon.zzz.fill"; selectedColor = "5856D6"; freqType = .daily
                metrics = [MetricDefinition(name: "Duration", unit: "hours"), MetricDefinition(name: "Wake Time", unit: "AM"), MetricDefinition(name: "Bed Time", unit: "PM")]
            }.foregroundStyle(.purple).bold()
            
            TextField("Habit Name", text: $name)
            Picker("Frequency", selection: $freqType) { ForEach(FrequencyType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Stepper("Times per day: \(dailyGoalCount)", value: $dailyGoalCount, in: 1...10)
            
            if freqType == .interval { Stepper("Every \(freqInterval) Days", value: $freqInterval, in: 2...30) }
            else if freqType == .weekdays { HStack { ForEach(1..<8, id: \.self) { d in Text(dayLetters[d-1]).font(.caption).bold().frame(width: 30, height: 30).background(freqDays.contains(d) ? Color.blue : Color.gray.opacity(0.2)).foregroundStyle(freqDays.contains(d) ? .white : .primary).clipShape(Circle()).onTapGesture { if freqDays.contains(d) { freqDays.remove(d) } else { freqDays.insert(d) } } } } }
            ColorIconPicker(selectedColor: $selectedColor, selectedIcon: $selectedIcon)
        }
    }
}

struct MetricsSection: View {
    @Binding var metrics: [MetricDefinition]; @Binding var tempMetricName: String; @Binding var tempMetricUnit: String
    var body: some View {
        Section("Metrics") {
            ForEach(metrics) { m in HStack { Text(m.name); Spacer(); Text(m.unit).font(.callout).padding(6).background(Color.secondary.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 6)) }.swipeActions(edge: .trailing) { Button(role: .destructive) { if let idx = metrics.firstIndex(where: { $0 === m }) { metrics.remove(at: idx) } } label: { Label("Delete", systemImage: "trash") } } }
            VStack(alignment: .leading) { HStack { TextField("Name", text: $tempMetricName); TextField("Unit", text: $tempMetricUnit).frame(width: 60); Button("Add") { guard !tempMetricName.isEmpty, !tempMetricUnit.isEmpty else { return }; metrics.append(MetricDefinition(name: tempMetricName, unit: tempMetricUnit)); tempMetricName = ""; tempMetricUnit = "" }.buttonStyle(.bordered) }; if let suggestions = UnitHelpers.quickSuggestions[tempMetricName.capitalized] { HStack { Text("Quick Unit:").font(.caption).foregroundStyle(.secondary); ForEach(suggestions, id: \.self) { sug in Button(sug) { tempMetricUnit = sug }.font(.caption).buttonStyle(.bordered) } } } }
        }
    }
}

struct ReminderSection: View {
    @Binding var reminderEnabled: Bool
    @Binding var reminderTime: Date
    
    var body: some View {
        Section("Reminder") {
            Toggle("Daily Reminder", isOn: $reminderEnabled)
            if reminderEnabled {
                DatePicker("Remind at", selection: $reminderTime, displayedComponents: .hourAndMinute)
            }
        }
    }
}

struct GoalsSection: View {
    @Binding var goals: [GoalDefinition]; @Binding var showGoalSheet: Bool
    var body: some View { Section("Goals") { ForEach(goals) { g in HStack { VStack(alignment: .leading) { Text(g.name ?? g.kind.rawValue).bold(); if let m = g.metricName { Text("Tracks: \(m)").font(.caption) } }; Spacer() }.swipeActions(edge: .trailing) { Button(role: .destructive) { if let idx = goals.firstIndex(where: { $0 === g }) { goals.remove(at: idx) } } label: { Label("Delete", systemImage: "trash") } } }; Button("Add Goal") { showGoalSheet = true } } }
}

struct GoalSheetView: View {
    let metrics: [MetricDefinition]; @Binding var goals: [GoalDefinition]; @Binding var showGoalSheet: Bool
    @State private var tKind: GoalKind = .targetValue; @State private var tName = ""; @State private var tVal = ""; @State private var tDate = Date()
    @State private var tDiff: ConsistencyDifficulty = .medium; @State private var tMetric = ""; @State private var requireThreshold = false

    var body: some View { NavigationStack { Form { TextField("Goal Name (e.g. Marathon)", text: $tName); Picker("Type", selection: $tKind) { ForEach(GoalKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }; if tKind == .targetValue { if !metrics.isEmpty { Picker("Based on Metric", selection: $tMetric) { Text("Select...").tag(""); ForEach(metrics) { m in Text(m.name).tag(m.name) } } }; TextField("Target Value", text: $tVal).keyboardType(.decimalPad) } else if tKind == .deadline { DatePicker("Deadline", selection: $tDate, displayedComponents: .date) } else if tKind == .consistency { Picker("Difficulty", selection: $tDiff) { ForEach(ConsistencyDifficulty.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }; if !metrics.isEmpty { Toggle("Require Minimum Threshold?", isOn: $requireThreshold); if requireThreshold { Picker("Based on Metric", selection: $tMetric) { Text("Select...").tag(""); ForEach(metrics) { m in Text(m.name).tag(m.name) } }; TextField("Daily Minimum to Count", text: $tVal).keyboardType(.decimalPad) } } } }.navigationTitle("Add Goal").toolbar { Button("Add") { let g = GoalDefinition(kind: tKind); g.name = tName.isEmpty ? nil : tName; g.targetDate = tDate; g.targetValue = Double(tVal); g.consistencyDifficulty = tDiff; g.metricName = tMetric.isEmpty ? nil : tMetric; goals.append(g); showGoalSheet = false } } }.presentationDetents([.medium]) }
}

struct ColorIconPicker: View {
    @Binding var selectedColor: String; @Binding var selectedIcon: String
    var body: some View { VStack { ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(UnitHelpers.allColors, id: \.self) { c in Circle().fill(Color(hex: c)).frame(width: 30).overlay(Circle().stroke(.black, lineWidth: selectedColor == c ? 2 : 0)).onTapGesture { selectedColor = c } } }.padding(.vertical, 4) }; ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(UnitHelpers.allIcons, id: \.self) { i in Image(systemName: i).frame(width: 30, height: 30).background(selectedIcon == i ? Color.gray.opacity(0.3) : .clear).clipShape(RoundedRectangle(cornerRadius: 5)).onTapGesture { selectedIcon = i } } }.padding(.vertical, 4) } } }
}
