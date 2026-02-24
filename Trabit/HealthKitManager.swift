import Foundation
import HealthKit
import SwiftData
import Observation

/// Manages HealthKit read access for syncing health data into Trabit habits.
/// Supports: Steps, Walking/Running Distance, Active Energy, Swimming Distance, Cycling Distance.
@MainActor
@Observable
final class HealthKitManager {

    static let shared = HealthKitManager()

    var isAuthorized = false
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let healthStore = HKHealthStore()

    // The HealthKit data types Trabit can read
    static let supportedTypes: [(identifier: HKQuantityTypeIdentifier, name: String, unit: HKUnit, displayUnit: String, icon: String, color: String)] = [
        (.stepCount, "Steps", .count(), "steps", "figure.walk", "34C759"),
        (.distanceWalkingRunning, "Walking + Running Distance", .meterUnit(with: .kilo), "km", "figure.run", "FF9500"),
        (.activeEnergyBurned, "Active Energy", .kilocalorie(), "kcal", "flame.fill", "FF3B30"),
        (.distanceSwimming, "Swimming Distance", .meterUnit(with: .kilo), "km", "figure.pool.swim", "007AFF"),
        (.distanceCycling, "Cycling Distance", .meterUnit(with: .kilo), "km", "bicycle", "5AC8FA"),
    ]

    private var readTypes: Set<HKObjectType> {
        Set(Self.supportedTypes.compactMap { HKQuantityType($0.identifier) })
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
        isAuthorized = true
    }

    // MARK: - Fetch Today's Data

    /// Fetch today's cumulative value for a given quantity type
    func fetchTodayValue(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double {
        let quantityType = HKQuantityType(identifier)
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Sync HealthKit Data into Trabit Habits

    /// Syncs today's HealthKit data into matching Trabit habits.
    /// Creates the habit if it doesn't exist and the user has enabled that type.
    func syncToday(context: ModelContext, enabledTypes: Set<HKQuantityTypeIdentifier>) async {
        guard isAuthorized else { return }

        let descriptor = FetchDescriptor<Habit>()
        guard let allHabits = try? context.fetch(descriptor) else { return }

        for typeInfo in Self.supportedTypes {
            guard enabledTypes.contains(typeInfo.identifier) else { continue }

            let value: Double
            do {
                value = try await fetchTodayValue(for: typeInfo.identifier, unit: typeInfo.unit)
            } catch {
                continue
            }

            guard value > 0 else { continue }

            // Find or skip existing habit with this name
            let habitName = typeInfo.name
            var habit = allHabits.first(where: { $0.name == habitName })

            if habit == nil {
                // Auto-create a HealthKit-synced habit
                let newHabit = Habit(name: habitName, icon: typeInfo.icon, color: typeInfo.color)
                newHabit.definedMetrics = [MetricDefinition(name: habitName, unit: typeInfo.displayUnit)]
                newHabit.sortOrder = allHabits.count
                context.insert(newHabit)
                habit = newHabit
            }

            guard let h = habit else { continue }

            // Check if we already have a log for today
            let today = Date()
            let existingLog = h.logs.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) })

            if let log = existingLog {
                // Update the existing entry
                if let entry = log.entries.first(where: { $0.metricName == habitName }) {
                    entry.value = value
                } else {
                    log.entries.append(LogPoint(metricName: habitName, value: value))
                }
            } else {
                // Create a new log
                let log = ActivityLog(date: today)
                log.entries.append(LogPoint(metricName: habitName, value: value))
                h.logs.append(log)
            }
        }
    }
}
