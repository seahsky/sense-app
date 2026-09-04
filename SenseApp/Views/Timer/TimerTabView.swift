import SwiftUI
import SenseKit

/// Timer tab: mirrors the live watch-driven timer (via `WatchConnectivityBridge`'s
/// "latest state only" application-context channel) when a Watch workout is
/// running, and separately supports starting/running the AMRAP countdown directly
/// on the phone — the same `AmrapTimerEngine` used everywhere else — for
/// phone-only use without a paired Watch.
struct TimerTabView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case watch = "Watch"
        case iPhone = "iPhone"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .iPhone
    @State private var variant: CindyVariant = .rx
    @State private var engine = AmrapTimerEngine(capSeconds: CindyVariant.rx.timeCapSeconds)
    @State private var liveContext: WatchLiveContext?
    @State private var showingVariantPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { candidate in
                        Text(candidate.rawValue).tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Spacer(minLength: 0)

                switch mode {
                case .watch:
                    watchMirrorSection
                case .iPhone:
                    phoneTimerSection
                }

                Spacer(minLength: 0)
            }
            .padding(.top)
            .navigationTitle("Timer")
            .toolbar {
                if mode == .iPhone && engine.phase == .idle {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingVariantPicker = true
                        } label: {
                            Label("Variant", systemImage: "slider.horizontal.3")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingVariantPicker) {
                NavigationStack {
                    List {
                        VariantPickerView(selection: $variant)
                            .pickerStyle(.inline)
                    }
                    .navigationTitle("Variant")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingVariantPicker = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
        .onChange(of: variant) { _, newValue in
            guard engine.phase == .idle else { return }
            engine = AmrapTimerEngine(capSeconds: newValue.timeCapSeconds)
        }
        .task {
            // Seed from whatever context WCSession already cached before this view
            // started observing (e.g. the app was cold-launched, or this tab opened,
            // while a Watch workout was already mid-flight and no further
            // `updateApplicationContext` call has fired since) — otherwise a
            // still-live workout would show "No Live Workout" until the next update.
            if let context = WatchLiveContext(userInfo: WatchConnectivityBridge.shared.latestLiveContext) {
                liveContext = context
            }
            // Foundation's async notification sequence (iOS 15+) rather than
            // `NotificationCenter.publisher(for:)`, which lives in Combine and
            // would need a separate import — this keeps the file to `SwiftUI` +
            // `SenseKit` only. The sequence never finishes on its own; `.task`
            // cancels it automatically when this view leaves the hierarchy.
            let updates = NotificationCenter.default.notifications(named: WatchConnectivityBridge.liveContextDidUpdateNotification)
            for await notification in updates {
                if let context = WatchLiveContext(userInfo: notification.userInfo) {
                    liveContext = context
                }
            }
        }
    }

    @ViewBuilder
    private var watchMirrorSection: some View {
        if let liveContext {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(Formatting.clock(liveContext.elapsedSeconds))
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Elapsed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 32) {
                    VStack(spacing: 4) {
                        Text("\(liveContext.completedRounds)")
                            .font(.title.bold())
                        Text("Rounds")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 4) {
                        Text(liveContext.scoreString)
                            .font(.title.bold())
                        Text("Score")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Live from Apple Watch · updated \(Formatting.sessionDate.string(from: liveContext.receivedAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        } else {
            ContentUnavailableView(
                "No Live Workout",
                systemImage: "applewatch.slash",
                description: Text("Start a Cindy session on your Apple Watch to see it mirrored here.")
            )
        }
    }

    private var phoneTimerSection: some View {
        VStack(spacing: 28) {
            if engine.phase == .running, let interval = engine.activeInterval {
                Text(timerInterval: interval, countsDown: true, showsHours: false)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
            } else {
                Text(Formatting.clock(engine.remaining))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            Text("\(variant.displayName) · \(Formatting.clock(variant.timeCapSeconds)) cap")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            controls
        }
        .padding()
    }

    @ViewBuilder
    private var controls: some View {
        switch engine.phase {
        case .idle:
            Button {
                engine.start()
            } label: {
                Text("Start")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)

        case .running:
            HStack(spacing: 12) {
                Button("Pause") { engine.pause() }
                    .buttonStyle(.bordered)
                Button("Finish") { engine.finish() }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }

        case .paused:
            HStack(spacing: 12) {
                Button("Resume") { engine.resume() }
                    .buttonStyle(.borderedProminent)
                Button("Finish") { engine.finish() }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }

        case .finished:
            VStack(spacing: 12) {
                Text("Finished in \(Formatting.clock(engine.elapsed))")
                    .font(.headline)
                Button("Reset") { engine.reset() }
                    .buttonStyle(.bordered)
            }
        }
    }
}

/// Decodes the raw `applicationContext` dictionary posted alongside
/// `WatchConnectivityBridge.liveContextDidUpdateNotification`, matching the keys
/// `WatchConnectivityBridge.publishLiveContext(elapsedSeconds:completedRounds:partialReps:)`
/// writes on the Watch side. Values round-trip a `WCSession` transfer as
/// `NSNumber`, so this reads through `NSNumber` rather than assuming a concrete
/// `Int`/`Double` layout on arrival.
private struct WatchLiveContext {
    let elapsedSeconds: TimeInterval
    let completedRounds: Int
    let partialReps: Int
    let receivedAt: Date

    var scoreString: String { "\(completedRounds)+\(partialReps)" }

    init?(userInfo: [AnyHashable: Any]?) {
        guard
            let userInfo,
            let elapsedNumber = userInfo["elapsedSeconds"] as? NSNumber,
            let roundsNumber = userInfo["completedRounds"] as? NSNumber,
            let repsNumber = userInfo["partialReps"] as? NSNumber
        else { return nil }
        elapsedSeconds = elapsedNumber.doubleValue
        completedRounds = roundsNumber.intValue
        partialReps = repsNumber.intValue
        receivedAt = .now
    }
}

#Preview {
    TimerTabView()
}
