import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    var body: some View {
        if hasCompletedOnboarding {
            TabView {
                TodayView()
                    .tabItem { Label("Today", systemImage: "checklist") }
                StatsView()
                    .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
                GoalsView()
                    .tabItem { Label("Goals", systemImage: "trophy.fill") }
            }
        } else {
            OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
        }
    }
}
