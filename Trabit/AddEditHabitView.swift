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
    
    @State private var metrics: [MetricDefinition] = []
    @State private var tempMetricName = ""
    @State private var tempMetricUnit = ""
    
    @State private var goals: [GoalDefinition] = []
    @State private var showGoalSheet = false
    
    @State private var tKind: GoalKind = .targetValue
    @State private var tName = ""
    @State private var tVal = ""
    @State private var tDate = Date()
    @State private var tDiff: ConsistencyDifficulty = .medium
    @State private var tMetric = ""
    @State private var requireThreshold = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Habit Name", text: $name)
                    Picker("Frequency", selection: $freqType) { ForEach(FrequencyType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    
                    if freqType == .interval {
                        Stepper("Every \(freqInterval) Days", value: $freqInterval, in: 2...30)
                    } else if freqType == .weekdays {
                        HStack {
                            ForEach(1..<8, id: \.self) { d in
                                Text(["S","M","T","W","T","F","S"][d-1])
                                    .font(.caption).bold().frame(width: 30, height: 30)
                                    .background(freqDays.contains(d) ? Color.blue : Color.gray.opacity(0.2))
                                    .foregroundStyle(freqDays.contains(d) ? .white : .primary)
                                    .clipShape(Circle())
                                    .onTapGesture { if freqDays.contains(d) { freqDays.remove(d) } else { freqDays.insert(d) } }
                            }
                        }
                    }
                    
                    ColorIconPicker(selectedColor: $selectedColor, selectedIcon: $selectedIcon)
                }
                
                Section("Metrics") {
                    ForEach(metrics) { m in
                        HStack { Text(m.name); Spacer(); Text(m.unit).font(.callout).padding(6).background(Color.secondary.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 6)) }
                    }.onDelete { metrics.remove(atOffsets: $0) }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            TextField("Name", text: $tempMetricName)
                            TextField("Unit", text: $tempMetricUnit).frame(width: 60)
                            Button("Add") { guard !tempMetricName.isEmpty, !tempMetricUnit.isEmpty else { return }; metrics.append(MetricDefinition(name: tempMetricName, unit: tempMetricUnit)); tempMetricName = ""; tempMetricUnit = "" }.buttonStyle(.bordered)
                        }
                        if let suggestions = UnitHelpers.quickSuggestions[tempMetricName.capitalized] {
                            HStack {
                                Text("Quick Unit:").font(.caption).foregroundStyle(.secondary)
                                ForEach(suggestions, id: \.self) { sug in Button(sug) { tempMetricUnit = sug }.font(.caption).buttonStyle(.bordered) }
                            }
                        }
                    }
                }
                
                Section("Goals") {
                    ForEach(goals) { g in
                        HStack { VStack(alignment: .leading) { Text(g.name ?? g.kind.rawValue).bold(); if let m = g.metricName { Text("Tracks: \(m)").font(.caption) } }; Spacer() }
                    }.onDelete { goals.remove(atOffsets: $0) }
                    Button("Add Goal") { showGoalSheet = true }
                }
            }
            .navigationTitle(habitToEdit == nil ? "New Habit" : "Edit Habit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.isEmpty) }
            }
            .sheet(isPresented: $showGoalSheet) {
                NavigationStack {
                    Form {
                        TextField("Goal Name (e.g. Marathon)", text: $tName)
                        Picker("Type", selection: $tKind) { ForEach(GoalKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        
                        if tKind == .targetValue {
                            if !metrics.isEmpty { Picker("Based on Metric", selection: $tMetric) { Text("Select...").tag(""); ForEach(metrics) { m in Text(m.name).tag(m.name) } } }
                            TextField("Target Value", text: $tVal).keyboardType(.decimalPad)
                        } else if tKind == .deadline { DatePicker("Deadline", selection: $tDate, displayedComponents: .date) }
                        else if tKind == .consistency {
                            Picker("Difficulty", selection: $tDiff) { ForEach(ConsistencyDifficulty.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                            if !metrics.isEmpty {
                                Toggle("Require Minimum Threshold?", isOn: $requireThreshold)
                                if requireThreshold {
                                    Picker("Based on Metric", selection: $tMetric) { Text("Select...").tag(""); ForEach(metrics) { m in Text(m.name).tag(m.name) } }
                                    TextField("Daily Minimum to Count", text: $tVal).keyboardType(.decimalPad)
                                }
                            }
                        }
                    }.navigationTitle("Add Goal").toolbar {
                        Button("Add") {
                            let g = GoalDefinition(kind: tKind); g.name = tName.isEmpty ? nil : tName; g.targetDate = tDate; g.targetValue = Double(tVal); g.consistencyDifficulty = tDiff; g.metricName = tMetric.isEmpty ? nil : tMetric; goals.append(g); showGoalSheet = false
                        }
                    }
                }.presentationDetents([.medium])
            }
        }.onAppear { if let h = habitToEdit { load(h) } }
    }
    
    func load(_ h: Habit) { name = h.name; selectedColor = h.hexColor; selectedIcon = h.iconSymbol; freqType = h.frequencyType; freqInterval = h.frequencyInterval ?? 2; freqDays = Set(h.frequencyWeekdays ?? [2,4,6]); metrics = h.definedMetrics; goals = h.goals }
    
    func save() { let h = habitToEdit ?? Habit(name: name, icon: selectedIcon, color: selectedColor); h.name = name; h.hexColor = selectedColor; h.iconSymbol = selectedIcon; h.frequencyType = freqType; h.frequencyInterval = freqInterval; h.frequencyWeekdays = Array(freqDays); h.definedMetrics = metrics; h.goals = goals; if habitToEdit == nil { modelContext.insert(h) }; dismiss() }
}

struct ColorIconPicker: View {
    @Binding var selectedColor: String; @Binding var selectedIcon: String
    var body: some View {
        // THE FIX: This missing VStack caused the "FormStyleConfiguration" crash!
        VStack {
            ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(UnitHelpers.allColors, id: \.self) { c in Circle().fill(Color(hex: c)).frame(width: 30).overlay(Circle().stroke(.black, lineWidth: selectedColor == c ? 2 : 0)).onTapGesture { selectedColor = c } } }.padding(.vertical, 4) }
            ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(UnitHelpers.allIcons, id: \.self) { i in Image(systemName: i).frame(width: 30, height: 30).background(selectedIcon == i ? Color.gray.opacity(0.3) : .clear).clipShape(RoundedRectangle(cornerRadius: 5)).onTapGesture { selectedIcon = i } } }.padding(.vertical, 4) }
        }
    }
}
