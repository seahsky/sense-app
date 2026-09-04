import SwiftUI
import SwiftData
import SenseKit
import SenseUI

/// History list of all sessions plus summary stat tiles and Swift Charts trend
/// visualization. Scores across different variants aren't comparable (per
/// `TrendAnalytics`'s own doc comments), so the stat tiles and both charts are
/// scoped to a variant filter; the history list below still shows every session,
/// each tagged with its own variant.
struct TrendTabView: View {
    @Query(sort: \CindySession.date, order: .reverse) private var sessions: [CindySession]

    @State private var filterVariant: CindyVariant = .rx
    @State private var selectedSession: CindySession?

    private var filteredSessions: [CindySession] {
        sessions.filter { $0.variant == filterVariant }
    }

    private var personalRecord: CindySession? {
        TrendAnalytics.personalRecord(among: sessions, variant: filterVariant)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Variant", selection: $filterVariant) {
                        ForEach(CindyVariant.allCases) { variant in
                            Text(variant.displayName).tag(variant)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowSeparator(.hidden)

                if filteredSessions.isEmpty {
                    ContentUnavailableView(
                        "No \(filterVariant.displayName) Sessions",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Finish a Cindy session in this variant to see trends here.")
                    )
                    .listRowSeparator(.hidden)
                } else {
                    Section {
                        statTiles
                    }
                    .listRowSeparator(.hidden)

                    Section("Score") {
                        ScoreTrendChart(sessions: filteredSessions, selectedSession: $selectedSession)
                            .frame(height: 220)
                    }

                    let heartRateSessions = filteredSessions.filter { $0.averageHeartRate != nil }
                    if !heartRateSessions.isEmpty {
                        Section("Heart Rate") {
                            HeartRateTrendChart(sessions: heartRateSessions)
                                .frame(height: 180)
                        }
                    }
                }

                if !sessions.isEmpty {
                    Section("History") {
                        ForEach(sessions) { session in
                            Button {
                                selectedSession = session
                            } label: {
                                sessionRow(session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .senseBackground(.full)
            .navigationTitle("Trend")
            .sheet(item: $selectedSession) { session in
                NavigationStack {
                    SessionDetailView(session: session)
                }
            }
        }
    }

    private var statTiles: some View {
        HStack(spacing: 12) {
            statTile(title: "Sessions", value: "\(filteredSessions.count)")
            statTile(title: "Best", value: personalRecord?.scoreString ?? "—")
            statTile(title: "Most Recent", value: filteredSessions.first?.scoreString ?? "—")
        }
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func sessionRow(_ session: CindySession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.scoreString)
                    .font(.headline)
                Text(session.variant.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Formatting.sessionDate.string(from: session.date))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    TrendTabView()
        .modelContainer(for: CindySession.self, inMemory: true)
}
