import SwiftUI

struct CelebrationView: View {
    let habit: Habit; var selectedDate: Date = Date(); @Environment(\.dismiss) var dismiss
    @State private var inputs: [String: String] = [:]
    @State private var showOverlay = false; @State private var activeGoal: GoalDefinition?; @State private var overlayMsg = ""
    
    @State private var sleepTime = Date(); @State private var wakeTime = Date()
    @FocusState private var isFocused: Bool
    @State private var logBeingEdited: ActivityLog?

    var todaysLogs: [ActivityLog] { habit.logs.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) } }

    var body: some View {
        NavigationStack {
            Form {
                if !todaysLogs.isEmpty {
                    Section("Previous Logs Today") {
                        ForEach(todaysLogs) { log in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(log.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                    ForEach(log.entries, id: \.self) { entry in
                                        HStack {
                                            Text(entry.metricName)
                                            Spacer()
                                            // THE FIX: Uses the helper function to prevent compiler timeouts
                                            Text(formattedValue(for: entry))
                                        }
                                    }
                                    if log.entries.isEmpty { Text("Completed") }
                                }
                                Spacer()
                                Button {
                                    logBeingEdited = log
                                    for entry in log.entries { inputs[entry.metricName] = UnitHelpers.format(entry.value) }
                                    isFocused = true
                                } label: { Image(systemName: "pencil.circle.fill").font(.title2).foregroundStyle(.blue).padding(.leading, 8) }.buttonStyle(.plain)
                            }
                        }.onDelete { offsets in for index in offsets { habit.logs.removeAll(where: { $0.id == todaysLogs[index].id }) } }
                    }
                }
                
                if habit.name.lowercased() == "bedtime" {
                    Section("Log Sleep") {
                        DatePicker("Went to bed", selection: $sleepTime, displayedComponents: .hourAndMinute)
                        DatePicker("Woke up", selection: $wakeTime, displayedComponents: .hourAndMinute)
                    }
                } else if habit.definedMetrics.isEmpty {
                    Section { Text("Mark done on \(selectedDate.formatted(date: .abbreviated, time: .omitted))?") }
                } else {
                    Section(logBeingEdited != nil ? "Editing Log" : "Log New Data") {
                        ForEach(habit.definedMetrics) { m in HStack { Text(m.name); TextField("0", text: Binding(get: { inputs[m.name] ?? "" }, set: { inputs[m.name] = $0 })).keyboardType(.decimalPad).focused($isFocused); Text(m.unit).foregroundStyle(.secondary) } }
                    }
                }
            }
            .navigationTitle(habit.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { processSave() } } }
            .sheet(isPresented: $showOverlay, onDismiss: { dismiss() }) { if let g = activeGoal { CelebrationOverlay(habit: habit, goal: g, message: overlayMsg) } }
            .onAppear { if todaysLogs.isEmpty { isFocused = true } }
        }
    }
    
    // THE FIX: Safely retrieves the unit without crashing the SwiftUI ViewBuilder
    private func formattedValue(for entry: LogPoint) -> String {
        let unit = habit.definedMetrics.first(where: { $0.name == entry.metricName })?.unit ?? ""
        if unit.uppercased() == "AM" || unit.uppercased() == "PM" { return UnitHelpers.formatTime(entry.value) }
        if unit.lowercased() == "hours" { return UnitHelpers.formatDuration(entry.value) }
        return UnitHelpers.format(entry.value)
    }
    
    func processSave() {
        let log = logBeingEdited ?? ActivityLog(date: selectedDate)
        log.entries.removeAll()
        
        if habit.name.lowercased() == "bedtime" {
            var diff = wakeTime.timeIntervalSince(sleepTime) / 3600.0; if diff < 0 { diff += 24.0 }
            log.entries.append(LogPoint(metricName: "Duration", value: diff))
            let wakeH = Double(Calendar.current.component(.hour, from: wakeTime)); let wakeM = Double(Calendar.current.component(.minute, from: wakeTime)) / 60.0
            log.entries.append(LogPoint(metricName: "Wake Time", value: wakeH + wakeM))
            let sleepH = Double(Calendar.current.component(.hour, from: sleepTime)); let sleepM = Double(Calendar.current.component(.minute, from: sleepTime)) / 60.0
            log.entries.append(LogPoint(metricName: "Bed Time", value: sleepH + sleepM))
        } else {
            for m in habit.definedMetrics { if let vStr = inputs[m.name], let v = Double(vStr) { log.entries.append(LogPoint(metricName: m.name, value: v)) } }
        }
        guard !log.entries.isEmpty || habit.definedMetrics.isEmpty else { dismiss(); return }
        var oldTotals: [String: Double] = [:]
        for m in habit.definedMetrics { oldTotals[m.name] = habit.logs.flatMap { $0.entries }.filter { $0.metricName == m.name }.reduce(0) { $0 + $1.value } }
        if logBeingEdited == nil { habit.logs.append(log) }
        
        for g in habit.goals {
            if g.kind == .targetValue, let target = g.targetValue, let metric = g.metricName {
                let isMax = metric.lowercased().contains("weight") || metric.lowercased().contains("mass")
                let unit = habit.definedMetrics.first(where: {$0.name == metric})?.unit ?? ""
                let old = isMax ? (habit.logs.dropLast().flatMap { $0.entries }.filter { $0.metricName == metric }.map { $0.value }.max() ?? 0.0) : (oldTotals[metric] ?? 0.0)
                let new = isMax ? (habit.logs.flatMap { $0.entries }.filter { $0.metricName == metric }.map { $0.value }.max() ?? 0.0) : (habit.logs.flatMap { $0.entries }.filter { $0.metricName == metric }.reduce(0.0) { $0 + $1.value })
                for perc in [0.25, 0.50, 0.75, 1.0] {
                    if old < (target * perc) && new >= (target * perc) {
                        activeGoal = g; overlayMsg = perc == 1.0 ? "You reached your goal of \(UnitHelpers.format(target)) \(unit) for \(habit.name)!" : "You are \(Int(perc*100))% of the way there!"
                        showOverlay = true; if perc == 1.0 { g.isCompleted = true; g.completionDate = Date() }
                        return
                    }
                }
            }
        }
        if !showOverlay { dismiss() }
    }
}

struct CelebrationOverlay: View {
    let habit: Habit; let goal: GoalDefinition; let message: String
    @Environment(\.dismiss) var dismiss; @Environment(\.displayScale) var displayScale
    @State private var showingAddSheet = false
    
    @MainActor func generateSnapshot() -> UIImage? {
        let view = VStack(spacing: 20) { Image(systemName: "star.circle.fill").font(.system(size: 80)); Text("I reached MY goal for \(habit.name)!").font(.title).bold().multilineTextAlignment(.center) }.padding(40).frame(width: 400, height: 400).background(Color(hex: habit.hexColor)).foregroundStyle(.white)
        let renderer = ImageRenderer(content: view); renderer.scale = displayScale; return renderer.uiImage
    }
    
    var body: some View {
        ZStack {
            Color(hex: habit.hexColor).ignoresSafeArea()
            VStack(spacing: 30) {
                Spacer()
                Image(systemName: "star.circle.fill").font(.system(size: 100)).foregroundStyle(.white).symbolEffect(.bounce, value: true)
                VStack(spacing: 15) { Text(goal.name ?? "Milestone!").font(.largeTitle).bold().foregroundStyle(.white); Text(message.replacingOccurrences(of: "I reached", with: "You reached").replacingOccurrences(of: "my goal", with: "your goal")).font(.title3).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.9)).padding(.horizontal) }
                Spacer()
                
                if goal.isCompleted {
                    VStack(spacing: 15) {
                        Button("Archive Habit") { habit.isArchived = true; dismiss() }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(Color(hex: habit.hexColor))
                        Button("Set a New Goal") { showingAddSheet = true }.foregroundStyle(.white)
                        Button("Continue for Fun") { dismiss() }.foregroundStyle(.white.opacity(0.7))
                    }
                } else { Button("Close") { dismiss() }.foregroundStyle(.white).padding() }
                
                Button(action: {
                    Task { @MainActor in
                        var items: [Any] = [message.replacingOccurrences(of: "You", with: "I").replacingOccurrences(of: "your", with: "my"), URL(string: "https://trabit.app")!]
                        if let img = generateSnapshot(), let data = img.pngData() { let tURL = FileManager.default.temporaryDirectory.appendingPathComponent("TShare.png"); try? data.write(to: tURL); items.append(tURL) }
                        presentShareSheet(items: items)
                    }
                }) { Label("Share", systemImage: "square.and.arrow.up").padding().background(Material.regular).clipShape(Capsule()).foregroundStyle(.primary) }.padding(.bottom, 50)
            }
        }
        .sheet(isPresented: $showingAddSheet, onDismiss: { dismiss() }) { AddEditHabitView(habitToEdit: habit) }
    }
}
