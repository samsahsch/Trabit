import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "checklist") }
            
            // CHANGED THIS LINE:
            StatsView()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
                
            GoalsView()
                .tabItem { Label("Goals", systemImage: "trophy.fill") }
        }
    }
}
