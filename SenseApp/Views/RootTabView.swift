import SwiftUI
import SwiftData
import SenseKit
import SenseUI

/// Root navigation shell: Timer, Tracker, Trend, Settings.
struct RootTabView: View {
    @State private var selection: Tab = .timer

    enum Tab: String { case timer, tracker, trend, settings }

    var body: some View {
        TabView(selection: $selection) {
            TimerTabView()
                .tabItem {
                    Label("Timer", systemImage: "timer")
                }
                .tag(Tab.timer)

            TrackerTabView()
                .tabItem {
                    Label("Tracker", systemImage: "checklist")
                }
                .tag(Tab.tracker)

            TrendTabView()
                .tabItem {
                    Label("Trend", systemImage: "chart.xyaxis.line")
                }
                .tag(Tab.trend)

            SettingsTabView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(Tab.settings)
        }
        .tint(SenseColor.accentInk)
        .task { selectPreviewTabIfRequested() }
    }

    /// Opens a given tab at launch, so each one can be screenshotted on a
    /// simulator without UI automation. DEBUG-only and opt-in:
    ///
    ///     xcrun simctl launch <udid> com.senseapp.ios -SenseUIPreview settings
    private func selectPreviewTabIfRequested() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-SenseUIPreview"),
              arguments.index(after: flagIndex) < arguments.endIndex,
              let tab = Tab(rawValue: arguments[arguments.index(after: flagIndex)])
        else { return }
        selection = tab
        #endif
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: CindySession.self, inMemory: true)
}
