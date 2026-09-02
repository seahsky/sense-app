import SwiftUI
import SwiftData
import CindyKit

/// Manual round/rep logging usable entirely on iPhone — no Watch needed. Owns its
/// own `AmrapTimerEngine` (for an accurate session duration and a live countdown)
/// and `RoundRepTracker` (for the actual rounds+reps score), the same CindyKit
/// types the Watch app uses, so a phone-only Cindy session scores identically to a
/// Watch-tracked one.
struct TrackerTabView: View {
    private enum Stage {
        case setup
        case active
        case summary
    }

    @Environment(\.modelContext) private var modelContext

    @State private var stage: Stage = .setup
    @State private var variant: CindyVariant = .rx
    @State private var timerEngine = AmrapTimerEngine(capSeconds: CindyVariant.rx.timeCapSeconds)
    @State private var tracker = RoundRepTracker(variant: .rx)
    @State private var notes: String = ""
    @State private var showingBackfill = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Tracker")
                .toolbar {
                    if stage == .setup {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showingBackfill = true
                            } label: {
                                Label("Add Past Session", systemImage: "plus")
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingBackfill) {
                    NavigationStack {
                        ManualSessionEntryView()
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .setup:
            setupStage
        case .active:
            activeStage
        case .summary:
            summaryStage
        }
    }

    private var setupStage: some View {
        Form {
            Section("Variant") {
                VariantPickerView(selection: $variant)
                    .pickerStyle(.inline)
            }

            Section {
                Button {
                    startSession()
                } label: {
                    Text("Start")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var activeStage: some View {
        VStack(spacing: 24) {
            if timerEngine.phase == .running, let interval = timerEngine.activeInterval {
                Text(timerInterval: interval, countsDown: true, showsHours: false)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
            } else {
                Text(Formatting.clock(timerEngine.remaining))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            VStack(spacing: 4) {
                Text(tracker.currentMovement.displayName)
                    .font(.title.bold())
                Text("\(tracker.repsInCurrentMovement) / \(currentTargetReps)")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                statTile(title: "Round", value: "\(tracker.completedRounds)")
                statTile(title: "Score", value: tracker.scoreString)
            }

            Button {
                tracker.logRep()
            } label: {
                Text("+1 Rep")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            HStack(spacing: 12) {
                Button("Undo") { tracker.undoLastRep() }
                    .buttonStyle(.bordered)

                if timerEngine.phase == .running {
                    Button("Pause") { timerEngine.pause() }
                        .buttonStyle(.bordered)
                } else if timerEngine.phase == .paused {
                    Button("Resume") { timerEngine.resume() }
                        .buttonStyle(.bordered)
                }

                Button("Finish") { finishSession() }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
        }
        .padding()
    }

    private var summaryStage: some View {
        Form {
            Section("Result") {
                LabeledContent("Score", value: tracker.scoreString)
                LabeledContent("Duration", value: Formatting.clock(timerEngine.elapsed))
                LabeledContent("Variant", value: variant.displayName)
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                Button {
                    saveSession()
                } label: {
                    Text("Save Session")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    discardSession()
                } label: {
                    Text("Discard")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var currentTargetReps: Int {
        let sequence = variant.movementSequence
        guard sequence.indices.contains(tracker.currentStepIndex) else { return 0 }
        return sequence[tracker.currentStepIndex].reps
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func startSession() {
        timerEngine = AmrapTimerEngine(capSeconds: variant.timeCapSeconds)
        tracker = RoundRepTracker(variant: variant)
        notes = ""
        timerEngine.start()
        stage = .active
    }

    private func finishSession() {
        timerEngine.finish()
        stage = .summary
    }

    private func saveSession() {
        // `activeInterval`'s lower bound is the session's real virtual start time
        // and survives `finish()` (only `reset()` clears it), so it's used as the
        // saved session's date rather than "now" (which would be the save time).
        let startDate = timerEngine.activeInterval?.lowerBound ?? .now
        let session = CindySession(
            date: startDate,
            variant: variant,
            durationSeconds: timerEngine.elapsed,
            completedRounds: tracker.completedRounds,
            partialReps: tracker.partialReps,
            notes: notes,
            source: .iPhone
        )
        modelContext.insert(session)
        try? modelContext.save()
        resetToSetup()
    }

    private func discardSession() {
        resetToSetup()
    }

    private func resetToSetup() {
        timerEngine.reset()
        tracker.reset()
        notes = ""
        stage = .setup
    }
}

#Preview {
    TrackerTabView()
        .modelContainer(for: CindySession.self, inMemory: true)
}
