// TipManager.swift — Progressive feature discovery tips.
// Each tip appears once, triggered by usage milestones stored in UserDefaults.

import SwiftUI

// MARK: - Tip Model

struct AppTip: Identifiable, Equatable {
    let id: String
    let icon: String
    let color: Color
    let title: String
    let body: String
    let actionLabel: String?
    let actionDeepLink: String?   // e.g. "trabit://settings", "trabit://addwidget"
}

// MARK: - Tip Definitions (shown in order)

extension AppTip {
    static let all: [AppTip] = [
        AppTip(
            id: "tip_siri",
            icon: "waveform",
            color: .purple,
            title: "Log with Siri",
            body: "Say \"Log a habit in Trabit\" to Siri. It will ask which habit and log it instantly — no hands needed.",
            actionLabel: nil,
            actionDeepLink: nil
        ),
        AppTip(
            id: "tip_widget",
            icon: "rectangle.stack.fill",
            color: .blue,
            title: "Add a Home Screen Widget",
            body: "Long-press your home screen, tap + and search for Trabit. See today's habit ring at a glance.",
            actionLabel: nil,
            actionDeepLink: nil
        ),
        AppTip(
            id: "tip_action_button",
            icon: "bolt.circle.fill",
            color: .orange,
            title: "Use the Action Button",
            body: "On iPhone 15 Pro+, go to Settings → Action Button and assign Trabit to log your next habit with one press.",
            actionLabel: nil,
            actionDeepLink: nil
        ),
        AppTip(
            id: "tip_watch",
            icon: "applewatch",
            color: .green,
            title: "Trabit on Apple Watch",
            body: "Open the Trabit app on your Apple Watch to log habits from your wrist. Complications keep your streak visible on any watch face.",
            actionLabel: nil,
            actionDeepLink: nil
        ),
        AppTip(
            id: "tip_ai_logger",
            icon: "apple.intelligence",
            color: .indigo,
            title: "Smart AI Logging",
            body: "Type \"5km 30min run\" in the log bar and Trabit's on-device AI fills in all your metrics automatically.",
            actionLabel: nil,
            actionDeepLink: nil
        ),
    ]
}

// MARK: - TipManager

@MainActor
final class TipManager: ObservableObject {
    static let shared = TipManager()

    @Published var currentTip: AppTip? = nil

    // Seconds of active app usage tracked across sessions
    private let usageKey = "trabit_total_usage_seconds"
    // Set of tip IDs already shown
    private let shownKey = "trabit_shown_tips"
    // Thresholds in seconds at which to show each successive tip
    private let thresholds: [Double] = [120, 300, 600, 1200, 2400]

    private var sessionStart = Date()
    private var timer: Timer?

    private var totalUsage: Double {
        get { UserDefaults.standard.double(forKey: usageKey) }
        set { UserDefaults.standard.set(newValue, forKey: usageKey) }
    }

    private var shownTips: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: shownKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: shownKey) }
    }

    func startSession() {
        sessionStart = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        tick()
    }

    func endSession() {
        timer?.invalidate()
        timer = nil
        totalUsage += Date().timeIntervalSince(sessionStart)
    }

    func dismissCurrentTip() {
        if let tip = currentTip {
            var shown = shownTips
            shown.insert(tip.id)
            shownTips = shown
        }
        currentTip = nil
    }

    private func tick() {
        let elapsed = totalUsage + Date().timeIntervalSince(sessionStart)
        let shown = shownTips

        for (index, tip) in AppTip.all.enumerated() {
            guard !shown.contains(tip.id) else { continue }
            let threshold = index < thresholds.count ? thresholds[index] : thresholds.last! * Double(index)
            if elapsed >= threshold {
                // Only surface a tip if none is already showing
                if currentTip == nil {
                    currentTip = tip
                }
                break
            }
        }
    }
}

// MARK: - Tip Banner View

struct TipBannerView: View {
    @ObservedObject var manager: TipManager = .shared

    var body: some View {
        if let tip = manager.currentTip {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: tip.icon)
                        .font(.title2)
                        .foregroundStyle(tip.color)
                        .frame(width: 36, height: 36)
                        .background(tip.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(tip.title)
                            .font(.subheadline).bold()
                        Text(tip.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        manager.dismissCurrentTip()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                .padding(.horizontal)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { manager.dismissCurrentTip() }
            }
            .animation(.spring(duration: 0.3), value: tip.id)
        }
    }
}
