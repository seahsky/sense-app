import Foundation

/// Streams accelerometer samples in, emits detected repetitions out, for one
/// movement at a time.
///
/// The engine is a value type holding a rolling buffer, and every tick recounts
/// that buffer from scratch — filter, project, count — rather than accumulating
/// incrementally. That is deliberate: the research notes cite a shipped
/// open-source push-up counter that double-counts when its app is reopened
/// mid-session, which is the signature failure of incremental peak counting. A
/// stateless recount can be *wrong*, but it cannot *drift*, and a wrong recount
/// self-corrects on the next tick.
///
/// Only ever run for the movement `RoundRepTracker` says is currently active.
/// Cindy's sequence is fixed, so movement identity is never in question — the
/// engine deliberately does no classification, which is the single most
/// expensive part of general exercise recognition and the part this app gets for
/// free by design.
public struct RepDetectionEngine: Sendable {
    public struct Configuration: Sendable, Equatable {
        /// Rate the buffer is analysed at. RecoFit ran at 50 Hz on a forearm IMU,
        /// so the universal `CMMotionManager` tier is already sufficient and the
        /// 800 Hz batched stream is decimated down to this before analysis —
        /// which is a stability requirement, not an optimization, because the
        /// documented background failure mode is watchOS suspending the app for
        /// excessive CPU.
        public let analysisRateHz: Double

        /// How much of a segment is kept. Bounds per-tick cost, so a long
        /// grinding set cannot make the recount progressively more expensive.
        ///
        /// 30 s is ample context: it holds fifteen reps at a 2 s cadence, or seven
        /// at the slowest tempo any profile allows, where autocorrelation needs
        /// only two periods. Peaks that age out have already been reported, so
        /// nothing is lost by forgetting them.
        ///
        /// The number is set from measurement, not caution. A release build costs
        /// 0.78 ms per recount at a 90 s buffer and 0.39 ms at 30 s, against a
        /// 200 ms recount interval — so even an order of magnitude slower on a
        /// watch this is a low-single-digit-percent duty cycle, comfortably clear
        /// of the excessive-background-CPU threshold that gets a workout app
        /// suspended. Halving it anyway is free.
        public let maxBufferSeconds: TimeInterval

        /// Minimum stream time between recounts. RecoFit re-runs its whole
        /// counting process every 200 ms, reporting "no fundamental latency in
        /// counting new repetitions".
        public let recountInterval: TimeInterval

        public init(
            analysisRateHz: Double = 50,
            maxBufferSeconds: TimeInterval = 30,
            recountInterval: TimeInterval = 0.2
        ) {
            self.analysisRateHz = analysisRateHz
            self.maxBufferSeconds = maxBufferSeconds
            self.recountInterval = recountInterval
        }
    }

    public let configuration: Configuration
    public private(set) var movement: Movement

    private var buffer: [MotionSample] = []
    private var lastRecountAt: TimeInterval?

    /// Peaks at or before this stream time have already been reported. Carrying a
    /// time rather than a count is what lets a recount revise its own recent
    /// history without ever re-emitting an older repetition.
    private var emittedThrough: TimeInterval = -.infinity

    public init(movement: Movement, configuration: Configuration = Configuration()) {
        self.movement = movement
        self.configuration = configuration
    }

    /// Number of samples currently buffered. Exposed for diagnostics and tests.
    public var bufferedSampleCount: Int { buffer.count }

    /// Switches to a new movement and discards everything about the old one.
    ///
    /// Called at every boundary `RoundRepTracker` reports. Nothing carries over,
    /// because a pull-up's signal has no bearing on a push-up's, and the timing
    /// profile changes underneath.
    public mutating func beginSegment(movement: Movement) {
        self.movement = movement
        reset()
    }

    public mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
        lastRecountAt = nil
        emittedThrough = -.infinity
    }

    /// Feeds already-decimated samples in and returns the repetitions that became
    /// certain as a result — usually zero, occasionally one.
    ///
    /// A repetition is only reported once its peak is at least one `minPeriod`
    /// old, so a following sample has had the chance to revise it. That costs
    /// sub-second latency on the haptic and buys immunity to the spurious-peak
    /// double count that a "report immediately" design would inflict every time
    /// an athlete shakes out their forearms mid-set.
    public mutating func ingest(_ samples: [MotionSample]) -> Int {
        guard !samples.isEmpty else { return 0 }

        // Core Motion's timestamp is monotonic within one stream, but a stream
        // restart — the batched manager failing over to CMMotionManager mid-set —
        // can hand over a clock that starts somewhere else entirely. A backwards
        // jump would leave `emittedThrough` stranded in the future, silently
        // disabling detection for the rest of the segment, so treat it as the new
        // stream it is.
        if let previous = buffer.last?.timestamp, let incoming = samples.first?.timestamp,
           incoming < previous {
            reset()
        }

        buffer.append(contentsOf: samples)
        guard let latest = buffer.last?.timestamp else { return 0 }

        trimBuffer(latest: latest)

        if let lastRecountAt, latest - lastRecountAt < configuration.recountInterval {
            return 0
        }
        lastRecountAt = latest

        let profile = movement.repCountingProfile

        // Autocorrelation is meaningless until there is more than one repetition
        // of context, and a premature count is worse than a late one.
        guard let earliest = buffer.first?.timestamp,
              latest - earliest >= profile.minPeriod * 2
        else { return 0 }

        let peakTimes = detectedPeakTimes(profile: profile)
        guard !peakTimes.isEmpty else { return 0 }

        let cutoff = latest - profile.minPeriod
        let confirmed = peakTimes.filter { $0 > emittedThrough && $0 <= cutoff }

        if cutoff > emittedThrough {
            emittedThrough = cutoff
        }
        return confirmed.count
    }

    /// The full RecoFit pipeline over the current buffer, returned as stream
    /// timestamps rather than indices so the caller never has to reason about
    /// buffer offsets that shift as it slides.
    private func detectedPeakTimes(profile: RepCountingProfile) -> [TimeInterval] {
        let filter = Bandpass.repCounting(sampleRateHz: configuration.analysisRateHz)
        let filtered = zip(
            zip(filter.filtering(buffer.map(\.x)), filter.filtering(buffer.map(\.y))),
            filter.filtering(buffer.map(\.z))
        ).map { (pair, z) in (x: pair.0, y: pair.1, z: z) }

        let projected = PrincipalAxis.reduce(filtered)
        guard projected.count == buffer.count else { return [] }

        return RepPeakCounter
            .peakIndices(in: projected, sampleRateHz: configuration.analysisRateHz, profile: profile)
            .map { buffer[$0].timestamp }
    }

    private mutating func trimBuffer(latest: TimeInterval) {
        let oldestAllowed = latest - configuration.maxBufferSeconds
        guard let first = buffer.first, first.timestamp < oldestAllowed else { return }

        // A binary search would be tidier, but the buffer is time-ordered and this
        // only ever drops a handful of samples per tick once steady state is reached.
        if let keepFrom = buffer.firstIndex(where: { $0.timestamp >= oldestAllowed }) {
            buffer.removeFirst(keepFrom)
        } else {
            buffer.removeAll(keepingCapacity: true)
        }
    }
}
