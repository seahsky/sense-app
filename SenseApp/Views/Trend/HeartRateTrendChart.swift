import SwiftUI
import Charts
import SenseKit

/// Plots average heart rate over time. Callers typically pre-filter to sessions
/// that actually have a heart rate (Watch-sourced sessions); the empty-state
/// fallback here keeps the view safe to reuse without that guarantee.
struct HeartRateTrendChart: View {
    let sessions: [CindySession]

    private var chronological: [CindySession] {
        sessions
            .filter { $0.averageHeartRate != nil }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        if chronological.isEmpty {
            ContentUnavailableView(
                "No Heart Rate Data",
                systemImage: "heart.slash",
                description: Text("Sessions synced from Apple Watch will show average heart rate here.")
            )
        } else {
            Chart(chronological) { session in
                LineMark(
                    x: .value("Date", session.date),
                    y: .value("Avg HR", session.averageHeartRate ?? 0)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.red)

                PointMark(
                    x: .value("Date", session.date),
                    y: .value("Avg HR", session.averageHeartRate ?? 0)
                )
                .foregroundStyle(.red)
            }
            .chartYAxisLabel("BPM")
        }
    }
}
