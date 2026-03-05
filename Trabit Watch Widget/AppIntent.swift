// AppIntent.swift (Watch Widget) — tapping any complication opens the watch app directly.
// The watch app handles all logging; intents from complications just deep-link there.
import AppIntents

struct WatchOpenIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Trabit"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}
