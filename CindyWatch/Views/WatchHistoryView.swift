import SwiftUI
import SwiftData
import CindyKit

/// Compact list of recent sessions (date + score), queried live from the watch's
/// own local `ModelContainer` — separate from the iPhone's store, per the
/// architecture spec.
struct WatchHistoryView: View {
    @Query(sort: \CindySession.date, order: .reverse) private var sessions: [CindySession]

    var body: some View {
        List {
            if sessions.isEmpty {
                Text("No sessions yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions) { session in
                    row(for: session)
                }
            }
        }
        .navigationTitle("History")
    }

    private func row(for session: CindySession) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(session.scoreString)
                    .font(.headline)
                Spacer()
                Text(session.variant.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(session.date, style: .date)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
