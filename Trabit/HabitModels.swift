import Foundation
import SwiftData
import SwiftUI

enum FrequencyType: String, Codable, CaseIterable {
    case daily = "Daily"; case weekly = "Weekly"; case monthly = "Monthly"
    case interval = "Every X Days"; case weekdays = "Specific Days"
}

enum GoalKind: String, Codable, CaseIterable {
    case targetValue = "Reach Value"; case deadline = "Deadline"; case consistency = "Consistency"
}

enum ConsistencyDifficulty: String, Codable, CaseIterable {
    case easy, medium, hard
    var targetOccurrences: Int { switch self { case .easy: return 14; case .medium: return 28; case .hard: return 42 } }
    var penalty: Int { switch self { case .easy: return 2; case .medium: return 4; case .hard: return 6 } }
}

struct UnitHelpers {
    static let quickSuggestions: [String: [String]] = [
        "Distance": ["km", "miles", "m", "laps"], "Time": ["min", "hours", "sec"],
        "Weight": ["kg", "lbs"], "Volume": ["L", "ml"], "Count": ["reps", "times"], "Sleep": ["hours"]
    ]
    
    static let allIcons = [
        "figure.run", "figure.walk", "figure.pool.swim", "bicycle", "dumbbell.fill", "figure.strengthtraining.traditional",
        "flame.fill", "drop.fill", "book.fill", "bed.double.fill", "brain.head.profile", "sparkles",
        "leaf.fill", "heart.fill", "star.fill", "moon.zzz.fill", "scalemass.fill", "chart.line.uptrend.xyaxis",
        "cup.and.saucer.fill", "music.note", "fork.knife", "pawprint.fill", "sun.max.fill"
    ]
    static let allColors = ["007AFF", "FF3B30", "34C759", "FF9500", "AF52DE", "FF2D55", "5856D6", "5AC8FA", "4CD964", "FFCC00", "8E8E93", "2D3436"]
    
    static func format(_ value: Double) -> String {
        return value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
    
    static func formatTime(_ value: Double) -> String {
        var val = value
        while val < 0 { val += 24 }
        while val >= 24 { val -= 24 }
        let h = Int(val)
        let m = Int(round((val - Double(h)) * 60))
        let period = h >= 12 ? "PM" : "AM"
        let displayH = h > 12 ? h - 12 : (h == 0 ? 12 : h)
        return String(format: "%d:%02d %@", displayH, m, period)
    }
    
    static func formatDuration(_ value: Double) -> String {
        let h = Int(value); let m = Int(round((value - Double(h)) * 60))
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }
}

@Model final class Habit {
    var name: String; var iconSymbol: String; var hexColor: String; var createdDate: Date; var sortOrder: Int
    var frequencyType: FrequencyType; var frequencyInterval: Int?; var frequencyWeekdays: [Int]?
    var isArchived: Bool = false
    
    @Relationship(deleteRule: .cascade) var definedMetrics: [MetricDefinition] = []
    @Relationship(deleteRule: .cascade) var logs: [ActivityLog] = []
    @Relationship(deleteRule: .cascade) var goals: [GoalDefinition] = []
    
    init(name: String, icon: String, color: String, freqType: FrequencyType = .daily, order: Int = 0) {
        self.name = name; self.iconSymbol = icon; self.hexColor = color; self.frequencyType = freqType; self.sortOrder = order; self.createdDate = Date()
    }
    
    func isCompleted(on date: Date) -> Bool { return logs.contains { Calendar.current.isDate($0.date, inSameDayAs: date) } }
    
    func isConsistencyMet(on date: Date, for goal: GoalDefinition?) -> Bool {
        let logsOnDate = logs.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
        if logsOnDate.isEmpty { return false }
        if let metric = goal?.metricName, let threshold = goal?.targetValue, goal?.kind == .consistency {
            let isMax = metric.lowercased().contains("weight") || metric.lowercased().contains("mass")
            let entries = logsOnDate.flatMap { $0.entries }.filter { $0.metricName == metric }
            let val = isMax ? (entries.map { $0.value }.max() ?? 0.0) : entries.reduce(0.0) { $0 + $1.value }
            return val >= threshold
        }
        return true
    }
    
    func consistencyScore(for goal: GoalDefinition, upTo targetDate: Date = Date()) -> Int {
        guard let diff = goal.consistencyDifficulty else { return 0 }
        let startDate = logs.map({$0.date}).min() ?? createdDate
        let days = Calendar.current.dateComponents([.day], from: startDate, to: targetDate).day ?? 0
        if days < 0 { return 0 }
        var score = 0
        for i in (0...days).reversed() {
            let dateToCheck = Calendar.current.date(byAdding: .day, value: -i, to: targetDate)!
            if isConsistencyMet(on: dateToCheck, for: goal) { score = min(score + 1, diff.targetOccurrences) }
            else { score = max(0, score - diff.penalty) }
        }
        return score
    }
}

@Model final class MetricDefinition {
    var name: String; var unit: String; var isVisible: Bool = true
    init(name: String, unit: String) { self.name = name; self.unit = unit }
}

@Model final class GoalDefinition {
    var kind: GoalKind; var name: String?; var targetValue: Double?; var targetDate: Date?
    var consistencyDifficulty: ConsistencyDifficulty?; var metricName: String?
    var isArchived: Bool = false; var isCompleted: Bool = false; var completionDate: Date?
    init(kind: GoalKind) { self.kind = kind }
}

@Model final class ActivityLog: Identifiable {
    var date: Date
    @Relationship(deleteRule: .cascade) var entries: [LogPoint] = []
    init(date: Date) { self.date = date }
}

@Model final class LogPoint {
    var metricName: String; var value: Double
    init(metricName: String, value: Double) { self.metricName = metricName; self.value = value }
}

// Global UI Helper to prevent Simulator UI sharing crashes
func presentShareSheet(items: [Any]) {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let root = windowScene.windows.first?.rootViewController else { return }
    var topController = root
    while let presented = topController.presentedViewController { topController = presented }
    let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
    topController.present(av, animated: true)
}
