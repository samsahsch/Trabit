import SwiftUI
import SwiftData
import Combine

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.sortOrder) private var allHabits: [Habit]
    var habits: [Habit] { allHabits.filter { !$0.isArchived } }
    
    @State private var showingAddSheet = false; @State private var habitToEdit: Habit?; @State private var selectedHabitForLog: Habit?
    @State private var smartInputText = ""; @State private var selectedDate = Date()
    @State private var toastMessage: String?
    
    let placeholders = ["Hold Siri button to log...", "20 pushups", "4km run", "Bedtime"]
    @State private var phIndex = 0; let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button { moveDate(by: -1) } label: { Image(systemName: "chevron.left.circle.fill").font(.title2) }
                    Spacer()
                    Text(dateLabel).font(.headline).foregroundStyle(Calendar.current.isDateInToday(selectedDate) ? .blue : .primary)
                    Spacer()
                    Button { moveDate(by: 1) } label: { Image(systemName: "chevron.right.circle.fill").font(.title2) }.disabled(Calendar.current.isDateInToday(selectedDate))
                }.padding().background(Color(uiColor: .systemBackground))
                
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "apple.intelligence").foregroundStyle(.purple)
                        TextField(placeholders[phIndex], text: $smartInputText)
                            .onSubmit { processSmartLog() }
                            .onReceive(timer) { _ in if smartInputText.isEmpty { withAnimation { phIndex = (phIndex + 1) % placeholders.count } } }
                    }.padding()
                    
                    if let toast = toastMessage {
                        Text(toast).font(.caption).foregroundStyle(.white).padding(6).background(toast.contains("✅") ? Color.green : Color.red).clipShape(Capsule()).padding(.bottom, 8)
                            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { toastMessage = nil } } }
                    }
                }.background(Color(uiColor: .secondarySystemBackground))
                
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
                ToolbarItem(placement: .topBarLeading) { Menu("Demo") { Button("Load Demo") { DemoData.inject(context: modelContext) }; Button("Reset All", role: .destructive) { DemoData.clear(context: modelContext) } } }
                ToolbarItem(placement: .primaryAction) { Button(action: { showingAddSheet = true }) { Image(systemName: "plus") } }
            }
            .sheet(isPresented: $showingAddSheet) { AddEditHabitView() }
            .sheet(item: $habitToEdit) { habit in AddEditHabitView(habitToEdit: habit) }
            .sheet(item: $selectedHabitForLog) { habit in CelebrationView(habit: habit, selectedDate: selectedDate).presentationDetents([.height(500), .large]) }
        }
    }
    
    var dateLabel: String { Calendar.current.isDateInToday(selectedDate) ? "Today" : (Calendar.current.isDateInYesterday(selectedDate) ? "Yesterday" : selectedDate.formatted(date: .abbreviated, time: .omitted)) }
    func moveDate(by days: Int) { if let d = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) { withAnimation { selectedDate = d } } }
    func handleTap(for habit: Habit) { if habit.definedMetrics.isEmpty { withAnimation { habit.logs.append(ActivityLog(date: selectedDate)) } } else { selectedHabitForLog = habit } }
    
    func processSmartLog() {
        let input = smartInputText.lowercased()
        var matchedHabit: Habit? = nil
        for habit in habits {
            let hName = habit.name.lowercased()
            if input.contains(hName) || input.contains(String(hName.prefix(4))) { matchedHabit = habit; break }
            if let syns = UnitHelpers.synonyms[hName] { for syn in syns { if input.contains(syn) { matchedHabit = habit; break } } }
            if matchedHabit != nil { break }
        }
        guard let h = matchedHabit else { toastMessage = "❌ Couldn't find habit. Tap a row to log."; smartInputText = ""; return }
        
        let log = ActivityLog(date: selectedDate); var found = false; var loggedData = ""
        for m in h.definedMetrics {
            let pattern = "([0-9]*\\.?[0-9]+)\\s*\(m.unit.lowercased())"
            let loosePattern = "([0-9]*\\.?[0-9]+)\\s*\(m.name.lowercased())"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let match = regex.firstMatch(in: input, range: NSRange(location: 0, length: input.utf16.count)) {
                if let val = Double((input as NSString).substring(with: match.range(at: 1))) { log.entries.append(LogPoint(metricName: m.name, value: val)); loggedData += "\(UnitHelpers.format(val))\(m.unit) "; found = true }
            } else if let regex = try? NSRegularExpression(pattern: loosePattern, options: .caseInsensitive), let match = regex.firstMatch(in: input, range: NSRange(location: 0, length: input.utf16.count)) {
                if let val = Double((input as NSString).substring(with: match.range(at: 1))) { log.entries.append(LogPoint(metricName: m.name, value: val)); loggedData += "\(UnitHelpers.format(val))\(m.unit) "; found = true }
            }
        }
        if found || h.definedMetrics.isEmpty { h.logs.append(log); toastMessage = "✅ Logged \(h.name): \(loggedData)" }
        else { toastMessage = "📝 Opened \(h.name) to log manually."; selectedHabitForLog = h }
        smartInputText = ""
    }
    func moveHabits(from source: IndexSet, to destination: Int) { var s = allHabits; s.move(fromOffsets: source, toOffset: destination); for (i, h) in s.enumerated() { h.sortOrder = i } }
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
