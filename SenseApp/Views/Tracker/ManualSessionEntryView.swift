import SwiftUI
import SwiftData
import SenseKit

/// Add a new session by hand, or edit an existing one — pass `session: nil` to add
/// a backfilled past session, or an existing `CindySession` to edit it in place.
/// Reachable from `TrackerTabView` (add) and `SessionDetailView` (edit).
struct ManualSessionEntryView: View {
    private let existingSession: CindySession?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var variant: CindyVariant
    @State private var completedRounds: Int
    @State private var partialReps: Int
    @State private var durationMinutes: Int
    @State private var durationSecondsRemainder: Int
    @State private var averageHeartRateText: String
    @State private var activeEnergyText: String
    @State private var notes: String

    init(session: CindySession? = nil) {
        existingSession = session
        _date = State(initialValue: session?.date ?? .now)
        _variant = State(initialValue: session?.variant ?? .rx)
        _completedRounds = State(initialValue: session?.completedRounds ?? 0)
        _partialReps = State(initialValue: session?.partialReps ?? 0)

        let durationSeconds = Int((session?.durationSeconds ?? 0).rounded())
        _durationMinutes = State(initialValue: durationSeconds / 60)
        _durationSecondsRemainder = State(initialValue: durationSeconds % 60)

        _averageHeartRateText = State(initialValue: session?.averageHeartRate.map { String(Int($0.rounded())) } ?? "")
        _activeEnergyText = State(initialValue: session?.activeEnergyBurned.map { String(Int($0.rounded())) } ?? "")
        _notes = State(initialValue: session?.notes ?? "")
    }

    private var isEditing: Bool { existingSession != nil }

    /// Partial reps can never reach a full round's worth of reps — that would just
    /// be another completed round — so the stepper is bounded one below it.
    private var maxPartialReps: Int {
        max(0, variant.repsPerRound - 1)
    }

    var body: some View {
        Form {
            Section("When") {
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
            }

            Section("Variant") {
                VariantPickerView(selection: $variant)
            }

            Section("Score") {
                Stepper("Rounds: \(completedRounds)", value: $completedRounds, in: 0...999)
                Stepper("Partial reps: \(partialReps)", value: $partialReps, in: 0...maxPartialReps)
                LabeledContent("Score", value: "\(completedRounds)+\(partialReps)")
                    .foregroundStyle(.secondary)
            }

            Section("Duration") {
                Stepper("Minutes: \(durationMinutes)", value: $durationMinutes, in: 0...60)
                Stepper("Seconds: \(durationSecondsRemainder)", value: $durationSecondsRemainder, in: 0...59)
            }

            Section("Health (optional)") {
                TextField("Average heart rate (bpm)", text: $averageHeartRateText)
                    .keyboardType(.numberPad)
                TextField("Active energy (kcal)", text: $activeEnergyText)
                    .keyboardType(.numberPad)
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle(isEditing ? "Edit Session" : "Add Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onChange(of: variant) { _, _ in
            partialReps = min(partialReps, maxPartialReps)
        }
    }

    private func save() {
        let durationSeconds = TimeInterval(durationMinutes * 60 + durationSecondsRemainder)
        let averageHeartRate = Double(averageHeartRateText)
        let activeEnergy = Double(activeEnergyText)

        if let existingSession {
            // Deliberately does NOT touch `sourceRawValue`: editing a Watch- or
            // iPhone-tracked session's notes/score correction shouldn't relabel it
            // as a manual entry — only brand-new sessions created here are `.manual`.
            existingSession.date = date
            existingSession.variantRawValue = variant.rawValue
            existingSession.durationSeconds = durationSeconds
            existingSession.completedRounds = completedRounds
            existingSession.partialReps = partialReps
            existingSession.averageHeartRate = averageHeartRate
            existingSession.activeEnergyBurned = activeEnergy
            existingSession.notes = notes
        } else {
            let newSession = CindySession(
                date: date,
                variant: variant,
                durationSeconds: durationSeconds,
                completedRounds: completedRounds,
                partialReps: partialReps,
                averageHeartRate: averageHeartRate,
                activeEnergyBurned: activeEnergy,
                notes: notes,
                source: .manual
            )
            modelContext.insert(newSession)
        }

        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ManualSessionEntryView()
    }
    .modelContainer(for: CindySession.self, inMemory: true)
}
