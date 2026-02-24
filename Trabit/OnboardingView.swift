import SwiftUI
import HealthKit

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    
    var body: some View {
        TabView(selection: $currentPage) {
            WelcomePage(currentPage: $currentPage).tag(0)
            FeaturesPage(currentPage: $currentPage).tag(1)
            AILoggerPage(currentPage: $currentPage).tag(2)
            PermissionsPage(hasCompletedOnboarding: $hasCompletedOnboarding).tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .interactiveDismissDisabled()
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    @Binding var currentPage: Int
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
            
            Text("Welcome to Trabit")
                .font(.largeTitle).bold()
            
            Text("Track any habit, log your progress,\nand reach your goals.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button("Get Started") {
                withAnimation { currentPage = 1 }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 60)
        }
        .padding()
    }
}

// MARK: - Page 2: Key Features

private struct FeaturesPage: View {
    @Binding var currentPage: Int
    
    var body: some View {
        VStack(spacing: 25) {
            Spacer()
            Text("Built for You")
                .font(.largeTitle).bold()
            
            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(icon: "chart.xyaxis.line", color: .blue,
                          title: "Visual Progress",
                          subtitle: "Charts, heatmaps, and pace tracking")
                FeatureRow(icon: "trophy.fill", color: .yellow,
                          title: "Goals & Milestones",
                          subtitle: "Set targets and celebrate when you reach them")
                FeatureRow(icon: "bell.fill", color: .orange,
                          title: "Smart Reminders",
                          subtitle: "Never miss a habit with custom notifications")
                FeatureRow(icon: "square.and.arrow.up", color: .green,
                          title: "Share Progress",
                          subtitle: "Export charts and share achievements")
            }
            .padding(.horizontal)
            
            Spacer()
            
            Button("Next") {
                withAnimation { currentPage = 2 }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 60)
        }
        .padding()
    }
}

private struct FeatureRow: View {
    let icon: String; let color: Color; let title: String; let subtitle: String
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Page 3: AI Logger

private struct AILoggerPage: View {
    @Binding var currentPage: Int
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            Image(systemName: "apple.intelligence")
                .font(.system(size: 60))
                .foregroundStyle(.purple)
            
            Text("AI-Powered Logging")
                .font(.largeTitle).bold()
            
            Text("Just type naturally to log your activities.\nTrabit uses on-device AI to understand\nwhat you mean.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                ExampleBubble(text: "\"20 pushups\"")
                ExampleBubble(text: "\"ran 5km in 25 min\"")
                ExampleBubble(text: "\"drank 3L water\"")
            }
            .padding(.top)
            
            Text("Also works with Siri!")
                .font(.callout).foregroundStyle(.secondary)
            
            Spacer()
            
            Button("Next") {
                withAnimation { currentPage = 3 }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 60)
        }
        .padding()
    }
}

private struct ExampleBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.body)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.purple.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Page 4: Permissions

private struct PermissionsPage: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var healthKitRequested = false
    @State private var notificationsRequested = false
    
    var body: some View {
        VStack(spacing: 25) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            
            Text("Permissions")
                .font(.largeTitle).bold()
            
            Text("These are optional. You can\nenable them later in Settings.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 15) {
                if HKHealthStore.isHealthDataAvailable() {
                    PermissionButton(
                        icon: "heart.fill",
                        color: .red,
                        title: "Health Data",
                        subtitle: "Import steps, running distance, and more",
                        isGranted: healthKitRequested
                    ) {
                        Task {
                            try? await HealthKitManager.shared.requestAuthorization()
                            healthKitRequested = true
                        }
                    }
                }
                
                PermissionButton(
                    icon: "bell.fill",
                    color: .orange,
                    title: "Notifications",
                    subtitle: "Get reminders for your habits",
                    isGranted: notificationsRequested
                ) {
                    Task {
                        _ = try? await NotificationManager.shared.requestAuthorization()
                        notificationsRequested = true
                    }
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            Button("Start Tracking") {
                hasCompletedOnboarding = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 60)
        }
        .padding()
    }
}

private struct PermissionButton: View {
    let icon: String; let color: Color; let title: String; let subtitle: String
    let isGranted: Bool; let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isGranted {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isGranted)
    }
}
