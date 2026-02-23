import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.sortOrder) private var allHabits: [Habit]
    var habits: [Habit] { allHabits.filter { !$0.isArchived } }
    
    @State private var showingAddSheet = false; @State private var habitToEdit: Habit?; @State private var selectedHabitForLog: Habit?
    @State private var selectedDate = Date()

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
                
                List {
                    ForEach(habits) { habit in
                        Button(action: { handleTap(for: habit) }) {
                            HabitRow(habit: habit, date: selectedDate)
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
    func moveHabits(from source: IndexSet, to destination: Int) { var s = allHabits; s.move(fromOffsets: source, toOffset: destination); for (i, h) in s.enumerated() { h.sortOrder = i } }
}

struct HabitRow: View {
    let habit: Habit; let date: Date
    var body: some View {
        let isDone = habit.isCompleted(on: date)
        let shouldStrike = habit.definedMetrics.isEmpty && isDone
        HStack {
            Image(systemName: habit.iconSymbol).foregroundStyle(Color(hex: habit.hexColor)).frame(width: 30).font(.title3)
            VStack(alignment: .leading) {
                Text(habit.name).font(.headline).strikethrough(shouldStrike).foregroundStyle(shouldStrike ? .secondary : .primary)
                if !habit.definedMetrics.isEmpty { Text(habit.definedMetrics.map { $0.unit }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if isDone { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) } else { Image(systemName: "circle").foregroundStyle(.secondary.opacity(0.3)) }
        }.padding(.vertical, 4).opacity(shouldStrike ? 0.6 : 1.0)
    }
}
