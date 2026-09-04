import SwiftUI
import SwiftData
import SenseKit

/// Root navigation shell: three tabs — Timer, Tracker, Trend — per the architecture
/// spec's iOS screens section.
struct RootTabView: View {
    var body: some View {
        TabView {
            TimerTabView()
                .tabItem {
                    Label("Timer", systemImage: "timer")
                }

            TrackerTabView()
                .tabItem {
                    Label("Tracker", systemImage: "checklist")
                }

            TrendTabView()
                .tabItem {
                    Label("Trend", systemImage: "chart.xyaxis.line")
                }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: CindySession.self, inMemory: true)
}
