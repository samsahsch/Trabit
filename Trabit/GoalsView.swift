import SwiftUI
import SwiftData

struct GoalsView: View {
    @Query(sort: \Habit.sortOrder) var allHabits: [Habit]
    var habits: [Habit] { allHabits.filter { !$0.isArchived } }
    @State private var showArchivedGoals = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(habits) { habit in
                        let activeGoals = habit.goals.filter { !$0.isArchived && !$0.isCompleted }
                        if !activeGoals.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack { Image(systemName: habit.iconSymbol).foregroundStyle(Color(hex: habit.hexColor)); Text(habit.name).font(.headline).foregroundStyle(.secondary) }.padding(.horizontal)
                                ForEach(activeGoals) { goal in GoalCard(habit: habit, goal: goal) }
                            }
                        }
                    }
                    
                    let archivedGoals = allHabits.flatMap { h in h.goals.filter { $0.isArchived || $0.isCompleted }.map { (h, $0) } }
                    if !archivedGoals.isEmpty {
                        DisclosureGroup(isExpanded: $showArchivedGoals) {
                            VStack(spacing: 15) {
                                ForEach(archivedGoals, id: \.1.id) { (habit, goal) in GoalCard(habit: habit, goal: goal) }
                            }.padding(.top, 10)
                        } label: {
                            Text("Archived Goals").font(.title2).bold().foregroundStyle(.primary)
                        }.padding().background(Color(uiColor: .secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }.padding(.vertical)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Goals")
            .toolbar {
                // THE FIX: Uses native ShareLink to instantly export the CSV with zero crashes
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: getCSVURL(habits: allHabits)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

struct GoalCard: View {
    let habit: Habit; let goal: GoalDefinition
    @Environment(\.displayScale) var displayScale
    @State private var showEditSheet = false
    
    @MainActor func generateGoalSnapshot() -> UIImage? {
        let view = VStack(spacing: 15) { Image(systemName: habit.iconSymbol).font(.system(size: 80)); Text("I'm working on \(goal.name ?? goal.kind.rawValue)!").font(.title).bold().multilineTextAlignment(.center) }.padding(40).frame(width: 400, height: 400).background(Color(hex: habit.hexColor)).foregroundStyle(.white)
        let renderer = ImageRenderer(content: view); renderer.scale = displayScale; return renderer.uiImage
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(goal.name ?? goal.kind.rawValue).font(.headline).bold()
                Spacer()
                if goal.isCompleted { Image(systemName: "checkmark.seal.fill").foregroundStyle(.yellow) }
                Button(action: { Task { @MainActor in var items: [Any] = ["Tracking my goal on Trabit!", URL(string: "https://trabit.app")!]; if let img = generateGoalSnapshot(), let data = img.pngData() { let tURL = FileManager.default.temporaryDirectory.appendingPathComponent("TrabitGoal.png"); try? data.write(to: tURL); items.append(tURL) }
                    let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene, let root = scene.windows.first?.rootViewController {
                        var top = root; while let p = top.presentedViewController { top = p }; top.present(av, animated: true)
                    }
                } }) { Image(systemName: "square.and.arrow.up").foregroundStyle(.blue) }
            }
            
            if goal.kind == .targetValue, let target = goal.targetValue, let metric = goal.metricName {
                let current = calculateCurrentProgress(habit: habit, metric: metric); let isMax = metric.lowercased().contains("weight") || metric.lowercased().contains("mass")
                let unit = habit.definedMetrics.first(where: {$0.name == metric})?.unit ?? ""
                ProgressView(value: min(current, target), total: target).tint(Color(hex: habit.hexColor))
                HStack { Text("\(UnitHelpers.format(current)) / \(UnitHelpers.format(target)) \(unit)").font(.subheadline).bold(); Spacer(); Text(isMax ? "Max Recorded" : "Total").font(.caption).foregroundStyle(.secondary) }
            } else if goal.kind == .deadline, let date = goal.targetDate {
                let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
                HStack { Image(systemName: "calendar.badge.clock").font(.largeTitle).foregroundStyle(Color(hex: habit.hexColor)); VStack(alignment: .leading) { Text("\(max(0, daysLeft)) Days Remaining").font(.title3).bold(); Text("Target: \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) } }
            } else if goal.kind == .consistency, let diff = goal.consistencyDifficulty {
                let score = habit.consistencyScore(for: goal); let target = diff.targetOccurrences
                let percentage = Int((Double(score) / Double(target)) * 100)
                ProgressView(value: Double(score), total: Double(target)).tint(Color(hex: habit.hexColor))
                HStack { Text("\(percentage)% Consistent").font(.subheadline).bold(); Spacer(); Text("\(diff.rawValue.capitalized)").font(.caption).padding(4).background(Color.secondary.opacity(0.2)).clipShape(Capsule()) }
            }
            
            let hasActiveGoal = habit.goals.contains { !$0.isCompleted && !$0.isArchived }
            if goal.isArchived || goal.isCompleted {
                HStack {
                    if !hasActiveGoal {
                        Button("Set New Goal") {
                            habit.isArchived = false // Unarchives habit instantly!
                            showEditSheet = true
                        }.buttonStyle(.borderedProminent)
                    }
                }.padding(.top, 5)
            }
        }
        .padding().background(Color(uiColor: .secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showEditSheet) { AddEditHabitView(habitToEdit: habit) }
    }
    
    private func calculateCurrentProgress(habit: Habit, metric: String) -> Double { let entries = habit.logs.flatMap { $0.entries }.filter { $0.metricName == metric }; let isMax = metric.lowercased().contains("weight") || metric.lowercased().contains("mass"); return isMax ? (entries.map { $0.value }.max() ?? 0) : (entries.reduce(0) { $0 + $1.value }) }
}
