import Foundation
import SwiftData

struct DemoData {
    @MainActor static func inject(context: ModelContext) {
        let cal = Calendar.current; let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: Date())!
        
        let bench = Habit(name: "Benchpress", icon: "dumbbell.fill", color: "FF3B30", freqType: .weekdays)
        bench.createdDate = thirtyDaysAgo; bench.definedMetrics = [MetricDefinition(name: "Weight", unit: "kg")]
        for i in [2, 5, 8, 12, 15, 18, 22, 26] {
            let log = ActivityLog(date: cal.date(byAdding: .day, value: -i, to: Date())!)
            log.entries = [LogPoint(metricName: "Weight", value: Double.random(in: 60...85))]
            bench.logs.append(log)
        }
        let gBench = GoalDefinition(kind: .targetValue); gBench.name = "100kg Club"; gBench.targetValue = 100; gBench.metricName = "Weight"; bench.goals.append(gBench)
        context.insert(bench)
        
        let water = Habit(name: "Water", icon: "drop.fill", color: "5AC8FA", freqType: .daily)
        water.createdDate = thirtyDaysAgo; water.definedMetrics = [MetricDefinition(name: "Volume", unit: "L")]
        for i in 0..<20 { let log = ActivityLog(date: cal.date(byAdding: .day, value: -i, to: Date())!); log.entries = [LogPoint(metricName: "Volume", value: Double.random(in: 2.8...3.5))]; water.logs.append(log) }
        let gWater = GoalDefinition(kind: .consistency); gWater.consistencyDifficulty = .easy; gWater.targetValue = 3.0; gWater.metricName = "Volume"; water.goals.append(gWater)
        context.insert(water)

        let swim = Habit(name: "Swimming", icon: "figure.pool.swim", color: "007AFF", freqType: .weekly)
        swim.createdDate = thirtyDaysAgo; swim.definedMetrics = [MetricDefinition(name: "Laps", unit: "laps"), MetricDefinition(name: "Time", unit: "min")]
        for i in stride(from: 1, through: 28, by: 4) { let log = ActivityLog(date: cal.date(byAdding: .day, value: -i, to: Date())!); log.entries = [LogPoint(metricName: "Laps", value: Double(Int.random(in: 30...50))), LogPoint(metricName: "Time", value: Double.random(in: 25...40))]; swim.logs.append(log) }
        let gSwim = GoalDefinition(kind: .deadline); gSwim.name = "Triathlon"; gSwim.targetDate = cal.date(byAdding: .day, value: 45, to: Date()); swim.goals.append(gSwim)
        let gSwimLaps = GoalDefinition(kind: .targetValue); gSwimLaps.name = "Swim 500 Laps"; gSwimLaps.targetValue = 500; gSwimLaps.metricName = "Laps"; swim.goals.append(gSwimLaps)
        context.insert(swim)
        
        let floss = Habit(name: "Floss", icon: "sparkles", color: "FF2D55", freqType: .daily)
        floss.createdDate = thirtyDaysAgo
        for i in 0..<30 { if i == 4 || i == 5 || i == 12 { continue }; floss.logs.append(ActivityLog(date: cal.date(byAdding: .day, value: -i, to: Date())!)) }
        let gFloss = GoalDefinition(kind: .consistency); gFloss.consistencyDifficulty = .hard; floss.goals.append(gFloss)
        context.insert(floss)
        
        let run = Habit(name: "Running", icon: "figure.run", color: "FF9500", freqType: .interval)
        run.createdDate = thirtyDaysAgo; run.definedMetrics = [MetricDefinition(name: "Distance", unit: "km"), MetricDefinition(name: "Time", unit: "min")]
        for i in stride(from: 0, to: 20, by: 2) {
            let log = ActivityLog(date: cal.date(byAdding: .day, value: -i, to: Date())!)
            log.entries = [LogPoint(metricName: "Distance", value: Double.random(in: 4.0...7.5)), LogPoint(metricName: "Time", value: Double.random(in: 20...35))]
            run.logs.append(log)
        }
        let gRun1 = GoalDefinition(kind: .deadline); gRun1.name = "Paris Marathon"; gRun1.targetDate = cal.date(byAdding: .day, value: 30, to: Date()); run.goals.append(gRun1)
        let gRun2 = GoalDefinition(kind: .targetValue); gRun2.name = "Run 100km Total"; gRun2.targetValue = 100; gRun2.metricName = "Distance"; run.goals.append(gRun2)
        context.insert(run)
        
        let push = Habit(name: "Pushups", icon: "figure.strengthtraining.traditional", color: "AF52DE", freqType: .daily)
        push.createdDate = thirtyDaysAgo; push.definedMetrics = [MetricDefinition(name: "Count", unit: "reps")]
        for i in 1...20 { let log = ActivityLog(date: cal.date(byAdding: .day, value: -i, to: Date())!); log.entries = [LogPoint(metricName: "Count", value: Double(Int.random(in: 20...28)))]; push.logs.append(log) }
        let gPush = GoalDefinition(kind: .targetValue); gPush.name = "500 Pushup Challenge"; gPush.targetValue = 500; gPush.metricName = "Count"; push.goals.append(gPush)
        context.insert(push)
        
        // Sleep updated with explicit Bed Time logic
        let sleep = Habit(name: "Bedtime", icon: "moon.zzz.fill", color: "5856D6", freqType: .daily)
        sleep.createdDate = thirtyDaysAgo
        sleep.definedMetrics = [MetricDefinition(name: "Duration", unit: "hours"), MetricDefinition(name: "Wake Time", unit: "AM"), MetricDefinition(name: "Bed Time", unit: "PM")]
        for i in 0..<30 {
            let log = ActivityLog(date: cal.date(byAdding: .day, value: -i, to: Date())!)
            let wake = Double.random(in: 6.0...7.5)
            let dur = Double.random(in: 6.5...8.5)
            let bed = wake - dur // Automatically wraps around via formatTime helper!
            log.entries = [LogPoint(metricName: "Duration", value: dur), LogPoint(metricName: "Wake Time", value: wake), LogPoint(metricName: "Bed Time", value: bed)]
            sleep.logs.append(log)
        }
        let gSleep = GoalDefinition(kind: .consistency); gSleep.consistencyDifficulty = .medium; gSleep.targetValue = 7.0; gSleep.metricName = "Duration"
        sleep.goals.append(gSleep)
        context.insert(sleep)
    }
    @MainActor static func clear(context: ModelContext) { do { try context.delete(model: Habit.self) } catch {} }
}
