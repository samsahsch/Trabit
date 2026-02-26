// BackfillView.swift — Log past data retroactively for selected habits.
// Presented as a sheet. User picks a date range and the habits to fill in.
// A log entry is created for each day in the range that doesn't already have one.

import SwiftUI
import SwiftData

struct BackfillView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Habit.sortOrder) private var allHabits: [Habit]

    private var habits: [Habit] { allHabits.filter { !$0.isArchived } }

    // MARK: State

    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var endDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var selectedHabitIDs: Set<PersistentIdentifier> = []
    @State private var showQuickPresets = false
    @State private var doneMessage: String?
    @State private var showConfirm = false

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private var daysInRange: Int {
        max(0, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0) + 1
    }

    private var logsToCreate: Int {
        // Estimate: days × habits (minus already-existing)
        let range = dateRange
        var count = 0
        for habit in selectedHabits {
            for day in range {
                if !habit.isCompleted(on: day) { count += 1 }
            }
        }
        return count
    }

    private var selectedHabits: [Habit] {
        habits.filter { selectedHabitIDs.contains($0.persistentModelID) }
    }

    private var dateRange: [Date] {
        var dates: [Date] = []
        let cal = Calendar.current
        var d = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)
        while d <= end {
            dates.append(d)
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return dates
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Quick presets
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            PresetChip(label: "Past week") { applyPreset(days: 7) }
                            PresetChip(label: "Past month") { applyPreset(days: 30) }
                            PresetChip(label: "Since Jan 1") { applyPresetFromJan1() }
                            PresetChip(label: "Past 25 days") { applyPreset(days: 25) }
                            PresetChip(label: "Past 90 days") { applyPreset(days: 90) }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Quick presets")
                }

                // MARK: Date range
                Section("Date Range") {
                    DatePicker("From", selection: $startDate, in: ...endDate, displayedComponents: .date)
                        .onChange(of: startDate) { _, new in
                            if new > endDate { endDate = new }
                        }
                    DatePicker("To", selection: $endDate,
                               in: startDate...Calendar.current.date(byAdding: .day, value: -1, to: today)!,
                               displayedComponents: .date)
                    HStack {
                        Text("Total days")
                        Spacer()
                        Text("\(daysInRange)")
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: Habit selection
                Section {
                    Button {
                        if selectedHabitIDs.count == habits.count {
                            selectedHabitIDs = []
                        } else {
                            selectedHabitIDs = Set(habits.map { $0.persistentModelID })
                        }
                    } label: {
                        Label(
                            selectedHabitIDs.count == habits.count ? "Deselect All" : "Select All",
                            systemImage: selectedHabitIDs.count == habits.count ? "checkmark.circle.fill" : "circle"
                        )
                        .foregroundStyle(.blue)
                    }

                    ForEach(habits) { habit in
                        let isSelected = selectedHabitIDs.contains(habit.persistentModelID)
                        Button {
                            if isSelected { selectedHabitIDs.remove(habit.persistentModelID) }
                            else { selectedHabitIDs.insert(habit.persistentModelID) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: habit.iconSymbol)
                                    .foregroundStyle(Color(hex: habit.hexColor))
                                    .frame(width: 26)
                                Text(habit.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Color.blue : Color.secondary.opacity(0.4))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Habits to fill in")
                } footer: {
                    Text("Days that already have a log will be skipped.")
                }

                // MARK: Summary
                if !selectedHabitIDs.isEmpty {
                    Section {
                        HStack {
                            Text("New logs to create")
                            Spacer()
                            Text("\(logsToCreate)")
                                .foregroundStyle(logsToCreate == 0 ? .secondary : .blue)
                                .bold()
                        }
                    } footer: {
                        if logsToCreate == 0 {
                            Text("All selected habits already have logs for every day in this range.")
                        }
                    }
                }
            }
            .navigationTitle("Log Past Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fill In") {
                        if logsToCreate > 20 {
                            showConfirm = true
                        } else {
                            applyBackfill()
                        }
                    }
                    .disabled(selectedHabitIDs.isEmpty || logsToCreate == 0)
                    .bold()
                }
            }
            .alert("Fill in \(logsToCreate) logs?", isPresented: $showConfirm) {
                Button("Fill In", role: .destructive) { applyBackfill() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will create \(logsToCreate) completion logs across \(daysInRange) days for \(selectedHabitIDs.count) habit\(selectedHabitIDs.count == 1 ? "" : "s"). You can delete individual logs from the Today view.")
            }
            .overlay {
                if let msg = doneMessage {
                    VStack {
                        Spacer()
                        Text(msg)
                            .font(.subheadline).bold()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.green)
                            .clipShape(Capsule())
                            .padding(.bottom, 40)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func applyPreset(days: Int) {
        let cal = Calendar.current
        endDate = cal.date(byAdding: .day, value: -1, to: today) ?? today
        startDate = cal.date(byAdding: .day, value: -(days - 1), to: endDate) ?? endDate
    }

    private func applyPresetFromJan1() {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        startDate = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        endDate = cal.date(byAdding: .day, value: -1, to: today) ?? today
    }

    private func applyBackfill() {
        let range = dateRange
        var created = 0
        for habit in selectedHabits {
            for day in range {
                guard !habit.isCompleted(on: day) else { continue }
                habit.logs.append(ActivityLog(date: day))
                created += 1
            }
        }
        try? modelContext.save()
        withAnimation {
            doneMessage = "Added \(created) log\(created == 1 ? "" : "s") successfully"
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            dismiss()
        }
    }
}

// MARK: - Quick Preset Chip

private struct PresetChip: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.blue.opacity(0.1))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
