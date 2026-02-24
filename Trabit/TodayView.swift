import SwiftUI
import SwiftData
import FoundationModels

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.sortOrder) private var allHabits: [Habit]
    var habits: [Habit] { allHabits.filter { !$0.isArchived } }
    
    @State private var showingAddSheet = false
    @State private var habitToEdit: Habit?
    @State private var selectedHabitForLog: Habit?
    @State private var smartInputText = ""
    @State private var selectedDate = Date()
    @State private var toastMessage: String?
    @State private var isProcessingAI = false
    
    private var model = SystemLanguageModel.default
    private let aiLogger = AILoggerService()
    
    let placeholders = ["Try: '20 pushups'", "Try: '4km run'", "Try: 'drank 3L water'", "Try: 'floss'"]
    @State private var phIndex = 0
    @State private var phTimer: Timer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Date navigation
                HStack {
                    Button { moveDate(by: -1) } label: { Image(systemName: "chevron.left.circle.fill").font(.title2) }
                    Spacer()
                    Text(dateLabel).font(.headline).foregroundStyle(Calendar.current.isDateInToday(selectedDate) ? .blue : .primary)
                    Spacer()
                    Button { moveDate(by: 1) } label: { Image(systemName: "chevron.right.circle.fill").font(.title2) }.disabled(Calendar.current.isDateInToday(selectedDate))
                }.padding().background(Color(uiColor: .systemBackground))
                
                // AI Logger input bar
                VStack(spacing: 0) {
                    HStack {
                        if model.availability == .available {
                            Image(systemName: "apple.intelligence").foregroundStyle(.purple)
                        } else {
                            Image(systemName: "text.magnifyingglass").foregroundStyle(.secondary)
                        }
                        TextField(placeholders[phIndex], text: $smartInputText)
                            .onSubmit { processSmartLog() }
                            .disabled(isProcessingAI)
                        if isProcessingAI {
                            ProgressView().controlSize(.small)
                        }
                    }.padding()
                    
                    if let toast = toastMessage {
                        Text(toast)
                            .font(.caption).foregroundStyle(.white).padding(6)
                            .background(toast.contains("Logged") ? Color.green : (toast.contains("Opened") ? Color.blue : Color.red))
                            .clipShape(Capsule()).padding(.bottom, 8)
                            .onAppear {
                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(3))
                                    withAnimation { toastMessage = nil }
                                }
                            }
                    }
                }.background(Color(uiColor: .secondarySystemBackground))
                
                // Habit list
                List {
                    ForEach(habits) { habit in
                        Button(action: { handleTap(for: habit) }) {
                            HabitRow(habit: habit, date: selectedDate).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { habitToEdit = habit } label: { Label("Edit Habit", systemImage: "pencil") }
                            Button { habit.isArchived = true } label: { Label("Archive Habit", systemImage: "archivebox") }
                            Button(role: .destructive) { modelContext.delete(habit) } label: { Label("Delete", systemImage: "trash") }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { modelContext.delete(habit) } label: { Label("Delete", systemImage: "trash") }
                            Button { habit.isArchived = true } label: { Label("Archive", systemImage: "archivebox") }.tint(.orange)
                            Button { habitToEdit = habit } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                        }
                    }.onMove(perform: moveHabits)
                }
            }
            .navigationTitle("Dashboard").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Load Demo") { DemoData.inject(context: modelContext) }
                        Button("Reset All", role: .destructive) { DemoData.clear(context: modelContext) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) { Button(action: { showingAddSheet = true }) { Image(systemName: "plus") } }
            }
            .sheet(isPresented: $showingAddSheet) { AddEditHabitView() }
            .sheet(item: $habitToEdit) { habit in AddEditHabitView(habitToEdit: habit) }
            .sheet(item: $selectedHabitForLog) { habit in CelebrationView(habit: habit, selectedDate: selectedDate).presentationDetents([.height(500), .large]) }
            .onAppear { startPlaceholderRotation() }
            .onDisappear { phTimer?.invalidate() }
        }
    }
    
    // MARK: - Helpers
    
    var dateLabel: String {
        Calendar.current.isDateInToday(selectedDate) ? "Today" :
        (Calendar.current.isDateInYesterday(selectedDate) ? "Yesterday" :
            selectedDate.formatted(date: .abbreviated, time: .omitted))
    }
    
    func moveDate(by days: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            withAnimation { selectedDate = d }
        }
    }
    
    func handleTap(for habit: Habit) {
        if habit.definedMetrics.isEmpty {
            withAnimation { habit.logs.append(ActivityLog(date: selectedDate)) }
        } else {
            selectedHabitForLog = habit
        }
    }
    
    func startPlaceholderRotation() {
        phTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            if smartInputText.isEmpty {
                withAnimation { phIndex = (phIndex + 1) % placeholders.count }
            }
        }
    }
    
    func moveHabits(from source: IndexSet, to destination: Int) {
        var s = allHabits
        s.move(fromOffsets: source, toOffset: destination)
        for (i, h) in s.enumerated() { h.sortOrder = i }
    }
    
    // MARK: - Smart Log Processing
    
    func processSmartLog() {
        let input = smartInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        
        if model.availability == .available {
            processWithAI(input)
        } else {
            processWithRegex(input)
        }
    }
    
    /// AI-powered logging using FoundationModels
    func processWithAI(_ input: String) {
        isProcessingAI = true
        smartInputText = ""
        
        Task {
            do {
                let parsed = try await aiLogger.parseInput(input, habits: habits)
                
                guard let habit = habits.first(where: { $0.name.lowercased() == parsed.habitName.lowercased() }) else {
                    toastMessage = "Could not find habit '\(parsed.habitName)'"
                    isProcessingAI = false
                    return
                }
                
                let log = ActivityLog(date: selectedDate)
                var loggedData = ""
                
                if let value = parsed.value {
                    // Try to match the AI-returned unit to a defined metric
                    if let matchedMetric = habit.definedMetrics.first(where: {
                        $0.unit.lowercased() == (parsed.unit ?? "").lowercased() ||
                        $0.name.lowercased() == (parsed.unit ?? "").lowercased()
                    }) {
                        log.entries.append(LogPoint(metricName: matchedMetric.name, value: value))
                        loggedData = "\(UnitHelpers.format(value)) \(matchedMetric.unit)"
                    } else if let firstMetric = habit.definedMetrics.first {
                        // Default to primary metric
                        log.entries.append(LogPoint(metricName: firstMetric.name, value: value))
                        loggedData = "\(UnitHelpers.format(value)) \(firstMetric.unit)"
                    }
                }
                
                if !log.entries.isEmpty || habit.definedMetrics.isEmpty {
                    habit.logs.append(log)
                    toastMessage = "Logged \(habit.name) \(loggedData)"
                } else {
                    toastMessage = "Opened \(habit.name) to log manually."
                    selectedHabitForLog = habit
                }
            } catch {
                // Fall back to regex on AI failure
                processWithRegex(input)
            }
            isProcessingAI = false
        }
    }
    
    /// Regex fallback for devices without Apple Intelligence
    func processWithRegex(_ input: String) {
        guard let result = RegexLogParser.parse(input, habits: habits) else {
            toastMessage = "Could not find a matching habit"
            smartInputText = ""
            return
        }
        
        let log = ActivityLog(date: selectedDate)
        var loggedData = ""
        
        for (metricName, value) in result.entries {
            log.entries.append(LogPoint(metricName: metricName, value: value))
            let unit = result.habit.definedMetrics.first(where: { $0.name == metricName })?.unit ?? ""
            loggedData += "\(UnitHelpers.format(value))\(unit) "
        }
        
        if !result.entries.isEmpty || result.habit.definedMetrics.isEmpty {
            result.habit.logs.append(log)
            toastMessage = "Logged \(result.habit.name) \(loggedData)"
        } else {
            toastMessage = "Opened \(result.habit.name) to log manually."
            selectedHabitForLog = result.habit
        }
        smartInputText = ""
    }
}

struct HabitRow: View {
    let habit: Habit; let date: Date
    var body: some View {
        HStack(spacing: 12) { // FIX: Explicit spacing aligns Floss perfectly
            Image(systemName: habit.iconSymbol).foregroundStyle(Color(hex: habit.hexColor)).frame(width: 30).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name).font(.headline).strikethrough(isDone).foregroundStyle(isDone ? .secondary : .primary)
                
                let showMetrics = !habit.definedMetrics.isEmpty
                let showLeft = remainingText != nil
                if showMetrics || showLeft {
                    HStack {
                        if showMetrics { Text(habit.definedMetrics.map { $0.unit }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                        if showLeft { Text("• \(remainingText!)").font(.caption).bold().foregroundStyle(Color(hex: habit.hexColor)) }
                    }
                }
            }
            Spacer()
            if isDone { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) } else { Image(systemName: "circle").foregroundStyle(.secondary.opacity(0.3)) }
        }.padding(.vertical, 4).opacity(isDone ? 0.6 : 1.0)
    }
    
    var todaysLogs: [ActivityLog] { habit.logs.filter { Calendar.current.isDate($0.date, inSameDayAs: date) } }
    
    // THE FIX: Single day tasks strike out instantly!
    var isDone: Bool {
        if habit.dailyGoalCount == 1 { return todaysLogs.count >= 1 }
        if let cGoal = habit.goals.first(where: { $0.kind == .consistency }), let target = cGoal.targetValue, let metric = cGoal.metricName {
            let current = todaysLogs.flatMap { $0.entries }.filter { $0.metricName == metric }.reduce(0) { $0 + $1.value }
            return current >= target
        }
        return todaysLogs.count >= habit.dailyGoalCount
    }
    
    // THE FIX: Never shows "0.2 left" for Bedtime.
    var remainingText: String? {
        if isDone { return nil }
        if habit.dailyGoalCount == 1 { return nil } // Only multi-day tasks show countdown
        
        if let cGoal = habit.goals.first(where: { $0.kind == .consistency }), let target = cGoal.targetValue, let metric = cGoal.metricName {
            let current = todaysLogs.flatMap { $0.entries }.filter { $0.metricName == metric }.reduce(0) { $0 + $1.value }
            let left = target - current
            if left > 0 { let unit = habit.definedMetrics.first(where: { $0.name == metric })?.unit ?? ""; return "\(UnitHelpers.format(left)) \(unit) left" }
        } else if habit.dailyGoalCount > 1 {
            let left = habit.dailyGoalCount - todaysLogs.count
            if left > 0 { return "\(left) times left" }
        }
        return nil
    }
}
