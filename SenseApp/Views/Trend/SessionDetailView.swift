import SwiftUI
import SwiftData
import SenseKit

/// Full detail for one selected session — date, variant, score, duration, HR,
/// energy, notes. Reachable from `TrendTabView`'s history list or via
/// `chartXSelection` tap-to-inspect on `ScoreTrendChart`.
struct SessionDetailView: View {
    let session: CindySession

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Result") {
                LabeledContent("Score", value: session.scoreString)
                LabeledContent("Total Reps", value: "\(session.totalReps)")
                LabeledContent("Variant", value: session.variant.displayName)
                LabeledContent("Date", value: Formatting.sessionDate.string(from: session.date))
                LabeledContent("Duration", value: Formatting.clock(session.durationSeconds))
                LabeledContent("Source", value: sourceLabel)
            }

            if session.averageHeartRate != nil || session.activeEnergyBurned != nil {
                Section("Health") {
                    if let heartRate = session.averageHeartRate {
                        LabeledContent("Avg Heart Rate", value: "\(Int(heartRate.rounded())) bpm")
                    }
                    if let energy = session.activeEnergyBurned {
                        LabeledContent("Active Energy", value: "\(Int(energy.rounded())) kcal")
                    }
                }
            }

            if !session.notes.isEmpty {
                Section("Notes") {
                    Text(session.notes)
                }
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Text("Delete Session")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(session.variant.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                ManualSessionEntryView(session: session)
            }
        }
        .confirmationDialog(
            "Delete this session?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.delete(session)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var sourceLabel: String {
        switch session.source {
        case .watch: return "Apple Watch"
        case .iPhone: return "iPhone"
        case .manual: return "Manual Entry"
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: CindySession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let sample = CindySession(
        variant: .rx,
        durationSeconds: 1200,
        completedRounds: 21,
        partialReps: 5,
        averageHeartRate: 162,
        activeEnergyBurned: 310,
        notes: "Felt strong on the squats today.",
        source: .watch
    )
    container.mainContext.insert(sample)
    return NavigationStack {
        SessionDetailView(session: sample)
    }
    .modelContainer(container)
}
