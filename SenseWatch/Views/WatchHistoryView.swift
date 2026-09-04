import SwiftUI
import SwiftData
import SenseKit
import SenseUI

/// Compact list of recent sessions (date + score), queried live from the watch's
/// own local `ModelContainer` — separate from the iPhone's store, per the
/// architecture spec.
struct WatchHistoryView: View {
    @Query(sort: \CindySession.date, order: .reverse) private var sessions: [CindySession]

    var body: some View {
        List {
            if sessions.isEmpty {
                Text("No sessions yet")
                    .foregroundStyle(SenseColor.inkSecondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(sessions) { session in
                    row(for: session)
                        .listRowBackground(
                            SenseColor.surface.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .senseBackground(.full)
        .navigationTitle("History")
    }

    private func row(for session: CindySession) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(session.scoreString)
                    .font(SenseFont.clock(size: 16))
                    .foregroundStyle(SenseColor.ink)
                Spacer()
                Text(session.variant.displayName)
                    .font(.caption2)
                    .foregroundStyle(SenseColor.accentInk)
            }
            Text(session.date, style: .date)
                .font(.caption2)
                .foregroundStyle(SenseColor.inkSecondary)
        }
    }
}
