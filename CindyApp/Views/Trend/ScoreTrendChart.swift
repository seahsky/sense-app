import SwiftUI
import Charts
import CindyKit

/// Plots `session.date` (x) against the rounds+reps score (y) across sessions.
///
/// Swift Charts needs one continuous numeric quantity for the y-axis, so this uses
/// `CindySession.totalReps` (= `completedRounds * variant.repsPerRound + partialReps`)
/// — a strictly performance-ordered numeric encoding of the same "rounds+reps"
/// score `scoreString` formats for display, and exactly the quantity
/// `CindySession`'s own `Comparable` conformance is built from. The PR point is
/// styled distinctly and annotated, with a `RuleMark` reference line at its value,
/// per the architecture spec.
struct ScoreTrendChart: View {
    let sessions: [CindySession]
    @Binding var selectedSession: CindySession?

    @State private var selectedDate: Date?

    private var chronological: [CindySession] {
        sessions.sorted { $0.date < $1.date }
    }

    /// All sessions passed in are expected to share one variant (the caller
    /// filters by `filterVariant` before handing sessions to this chart), so any
    /// session's `variant` is representative for the PR lookup.
    private var personalRecord: CindySession? {
        guard let variant = sessions.first?.variant else { return nil }
        return TrendAnalytics.personalRecord(among: sessions, variant: variant)
    }

    var body: some View {
        Chart {
            if let personalRecord {
                RuleMark(y: .value("Personal Record", personalRecord.totalReps))
                    .foregroundStyle(.orange.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("PR \(personalRecord.scoreString)")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    }
            }

            ForEach(chronological) { session in
                LineMark(
                    x: .value("Date", session.date),
                    y: .value("Score", session.totalReps)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.blue)

                PointMark(
                    x: .value("Date", session.date),
                    y: .value("Score", session.totalReps)
                )
                .foregroundStyle(session.id == personalRecord?.id ? Color.orange : Color.blue)
                .symbolSize(session.id == personalRecord?.id ? 130 : 45)
            }

            if let selectedDate {
                RuleMark(x: .value("Selected", selectedDate))
                    .foregroundStyle(.gray.opacity(0.3))
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYAxisLabel("Total Reps")
        .onChange(of: selectedDate) { _, newValue in
            guard let newValue else { return }
            selectedSession = chronological.min { lhs, rhs in
                abs(lhs.date.timeIntervalSince(newValue)) < abs(rhs.date.timeIntervalSince(newValue))
            }
        }
    }
}
