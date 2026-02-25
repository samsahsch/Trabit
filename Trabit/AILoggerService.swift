import Foundation
import FoundationModels
import SwiftData

// MARK: - Generable Types for Structured AI Output

/// A single metric value extracted from user input
@Generable(description: "A single metric value extracted from the user's input")
struct ParsedMetricEntry {
    @Guide(description: "The numeric value, e.g. 5 or 30")
    var value: Double
    @Guide(description: "The unit, e.g. km, min, reps, L, hours")
    var unit: String
}

@Generable(description: "A parsed habit log entry extracted from natural language input")
struct ParsedHabitLog {
    @Guide(description: "The exact name of the matched habit from the habits list")
    var habitName: String

    @Guide(description: "All numeric values and their units extracted from the input. For example '5km 30min run' returns [{value:5,unit:'km'},{value:30,unit:'min'}]. Empty array if habit has no metrics.")
    var entries: [ParsedMetricEntry]
}

// MARK: - AI Logger Service

@MainActor
final class AILoggerService {
    // Cache session per unique habit-list fingerprint to avoid re-initialisation cost
    private var cachedSession: LanguageModelSession?
    private var cachedHabitFingerprint: String = ""

    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Parse natural language input into a structured habit log using on-device AI.
    /// Reuses the session when the habit list hasn't changed to avoid cold-start latency.
    func parseInput(_ input: String, habits: [Habit]) async throws -> ParsedHabitLog {
        let habitDescriptions = habits.map { habit -> String in
            let metrics = habit.definedMetrics.map { "\($0.name) (\($0.unit))" }.joined(separator: ", ")
            if metrics.isEmpty {
                return "- \(habit.name): completion-only (no metrics)"
            }
            return "- \(habit.name): metrics are \(metrics)"
        }

        let habitList = habitDescriptions.joined(separator: "\n")
        let fingerprint = habitList

        if cachedSession == nil || fingerprint != cachedHabitFingerprint {
            let instructions = """
                You are a habit logging assistant for the Trabit app. \
                Extract the habit name and ALL numeric values with their units from the input. \
                Match habitName to exactly one habit from the list below (use the exact name shown). \
                Map synonyms: "ran"→Running, "swam"→Swimming, "drank"→Water, "biked"→Biking, etc. \
                For each number+unit pair in the input, add an entry. \
                Example: "ran 5km in 30min" → entries:[{value:5,unit:"km"},{value:30,unit:"min"}]. \
                If the habit has no metrics, return an empty entries array. \
                If no numbers are given, return an empty entries array.

                Habits:
                \(habitList)
                """
            cachedSession = LanguageModelSession(instructions: instructions)
            cachedHabitFingerprint = fingerprint
        }

        let response = try await cachedSession!.respond(
            to: input,
            generating: ParsedHabitLog.self
        )

        return response.content
    }
}

// MARK: - Regex Fallback for Unsupported Devices

struct RegexLogParser {
    static func parse(_ input: String, habits: [Habit]) -> (habit: Habit, entries: [(String, Double)])? {
        let lowered = input.lowercased()
        var matchedHabit: Habit?

        for habit in habits {
            let hName = habit.name.lowercased()
            if lowered.contains(hName) || lowered.contains(String(hName.prefix(4))) {
                matchedHabit = habit; break
            }
            if let syns = UnitHelpers.synonyms[hName] {
                for syn in syns where lowered.contains(syn) { matchedHabit = habit; break }
            }
            if matchedHabit != nil { break }
        }

        guard let habit = matchedHabit else { return nil }

        var entries: [(String, Double)] = []
        for m in habit.definedMetrics {
            let pattern = "([0-9]*\\.?[0-9]+)\\s*\(m.unit.lowercased())"
            let loosePattern = "([0-9]*\\.?[0-9]+)\\s*\(m.name.lowercased())"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: lowered, range: NSRange(location: 0, length: lowered.utf16.count)),
               let val = Double((lowered as NSString).substring(with: match.range(at: 1))) {
                entries.append((m.name, val))
            } else if let regex = try? NSRegularExpression(pattern: loosePattern, options: .caseInsensitive),
                      let match = regex.firstMatch(in: lowered, range: NSRange(location: 0, length: lowered.utf16.count)),
                      let val = Double((lowered as NSString).substring(with: match.range(at: 1))) {
                entries.append((m.name, val))
            }
        }

        return (habit, entries)
    }
}
