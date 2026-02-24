import Foundation
import FoundationModels
import SwiftData

// MARK: - Generable Types for Structured AI Output

@Generable(description: "A parsed habit log entry extracted from natural language input")
struct ParsedHabitLog {
    @Guide(description: "The exact name of the matched habit")
    var habitName: String

    @Guide(description: "The numeric value logged, e.g. 20 for '20 pushups'")
    var value: Double?

    @Guide(description: "The unit of measurement, e.g. reps, km, min, L")
    var unit: String?
}

// MARK: - Tool for Habit Lookup

struct LookupHabitsTool: Tool {
    let name = "lookupHabits"
    let description = "Returns the list of habit names and their metrics that exist in the user's app"

    @Generable
    struct Arguments {
        @Guide(description: "Search term from user input")
        var searchTerm: String
    }

    var habitSummaries: [String]

    func call(arguments: Arguments) async throws -> String {
        return habitSummaries.joined(separator: "\n")
    }
}

// MARK: - AI Logger Service

@MainActor
final class AILoggerService {
    private var session: LanguageModelSession?

    /// Whether FoundationModels is available on this device
    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    var availabilityReason: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    /// Parse natural language input into a structured habit log using on-device AI
    func parseInput(_ input: String, habits: [Habit]) async throws -> ParsedHabitLog {
        let habitDescriptions = habits.map { habit -> String in
            let metrics = habit.definedMetrics.map { "\($0.name) (\($0.unit))" }.joined(separator: ", ")
            if metrics.isEmpty {
                return "- \(habit.name): completion-only (no metrics)"
            }
            return "- \(habit.name): metrics are \(metrics)"
        }

        let habitList = habitDescriptions.joined(separator: "\n")

        let instructions = """
            You are a habit logging assistant for the Trabit app. \
            The user will describe an activity in natural language. \
            Extract the habit name, numeric value, and unit. \
            You MUST match habitName to one of the existing habits below. \
            Use the exact habit name as listed. \
            If the user says a synonym (e.g. "ran" for "Running", "swam" for "Swimming", "drank" for "Water"), \
            map it to the correct habit name. \
            If no value is given, leave value as nil. \
            If the habit has no metrics, leave value and unit as nil.

            Existing habits:
            \(habitList)
            """

        let lookupTool = LookupHabitsTool(habitSummaries: habitDescriptions)

        let session = LanguageModelSession(
            tools: [lookupTool],
            instructions: instructions
        )

        let response = try await session.respond(
            to: input,
            generating: ParsedHabitLog.self
        )

        return response.content
    }
}

// MARK: - Regex Fallback for Unsupported Devices

struct RegexLogParser {
    /// The original regex-based parser as a fallback for devices without Apple Intelligence
    static func parse(_ input: String, habits: [Habit]) -> (habit: Habit, entries: [(String, Double)])? {
        let lowered = input.lowercased()
        var matchedHabit: Habit?

        for habit in habits {
            let hName = habit.name.lowercased()
            if lowered.contains(hName) || lowered.contains(String(hName.prefix(4))) {
                matchedHabit = habit
                break
            }
            if let syns = UnitHelpers.synonyms[hName] {
                for syn in syns {
                    if lowered.contains(syn) {
                        matchedHabit = habit
                        break
                    }
                }
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
