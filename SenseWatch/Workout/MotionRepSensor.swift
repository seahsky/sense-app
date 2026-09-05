import CoreMotion
import Foundation
import Observation
import SenseKit

/// Streams wrist motion into `SenseKit`'s ``RepDetectionEngine`` and reports the
/// repetitions it finds.
///
/// This is the only file in the project that imports Core Motion. Everything that
/// decides *whether something is a rep* lives in `SenseKit` as pure, testable
/// value types; this type does nothing but acquire samples, hand them over, and
/// deliver the answer to the main actor. That split is what lets the whole
/// counting algorithm be exercised on an iOS simulator with synthetic signals.
///
/// It never classifies. Cindy's movement sequence is fixed, so `RoundRepTracker`
/// already knows which movement is active — the single most expensive part of
/// general exercise recognition, which this app gets for free by design.
@Observable
final class MotionRepSensor {
    /// Which acquisition path is live.
    enum Tier: Equatable {
        /// `CMBatchedSensorManager` — one-second batches at the system's own rate,
        /// decimated to the analysis rate. Apple stated at WWDC23 that the
        /// high-rate modes are on Series 8 and Ultra; the SDK carries no hardware
        /// annotation, so this is chosen by capability flag, never by model.
        case batched
        /// `CMMotionManager` at 50 Hz — the universal fallback, and already
        /// sufficient: RecoFit counted at 50 Hz.
        case standard
        case unavailable
    }

    enum Status: Equatable {
        case idle
        case running(Tier)
        /// Sensing is off and will not recover this session. The manual "+1 REP"
        /// path is unaffected — it is, and remains, the ground truth.
        case failed(String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    private(set) var status: Status = .idle

    /// Called on the main actor with the number of repetitions that just became
    /// certain — almost always 1.
    var onRepsDetected: ((Int) -> Void)?

    private let analysisRateHz: Double = 50
    private let processor: RepDetectionProcessor
    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.senseapp.motion-rep-sensor"
        // Serial: the processor is an actor, but ordering still has to be
        // preserved, and `stopAccelerometerUpdates` cancels every operation on the
        // queue it was given — so this queue must not be shared with anything else.
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var batchedTask: Task<Void, Never>?
    private var isStopped = true

    /// Bumped on every batched attempt so a stream that throws *after* the sensor
    /// moved on cannot resurrect itself.
    ///
    /// Without this, a batched task that fails a moment after `pause()` — or
    /// after the athlete started a whole new workout — would run
    /// `handleBatchedFailure` and quietly bring the `CMMotionManager` stream up
    /// underneath the current state, logging reps during a rest break or into the
    /// wrong session.
    private var batchedGeneration = 0

    init(movement: Movement = .pullUp) {
        processor = RepDetectionProcessor(
            movement: movement,
            analysisRateHz: analysisRateHz
        )
    }

    /// Starts sensing for `movement`.
    ///
    /// Must be called only while an `HKWorkoutSession` is active:
    /// `CMBatchedSensorManager` produces no data at all without one ("Because this
    /// is a workout-centric API, you need to have an active HealthKit workout
    /// session to get data"), and the workout session is also what keeps the app
    /// alive in the background for the full AMRAP.
    @MainActor
    func start(movement: Movement) {
        guard !status.isRunning else {
            setMovement(movement)
            return
        }

        isStopped = false
        Task { await processor.beginSegment(movement: movement) }

        // Core Motion has no requestAuthorization API for accelerometer data —
        // the only one in the framework is on CMFallDetectionManager — so there is
        // nothing to prompt with. Read the status, start, and degrade on error.
        if CMBatchedSensorManager.isAccelerometerSupported,
           CMBatchedSensorManager.authorizationStatus != .denied {
            startBatched()
        } else {
            startStandard()
        }
    }

    @MainActor
    func setMovement(_ movement: Movement) {
        Task { await processor.beginSegment(movement: movement) }
    }

    /// Suspends sensing without tearing the session down — used when the athlete
    /// pauses the AMRAP clock, so a walk to the water fountain cannot log reps.
    @MainActor
    func pause() {
        stopStreams()
        if status.isRunning { status = .idle }
    }

    @MainActor
    func resume(movement: Movement) {
        guard !isStopped, !status.isRunning else { return }
        start(movement: movement)
    }

    @MainActor
    func stop() {
        isStopped = true
        stopStreams()
        status = .idle
    }

    // MARK: - Acquisition

    @MainActor
    private func startBatched() {
        status = .running(.batched)
        batchedGeneration &+= 1
        let generation = batchedGeneration

        // The task inherits this method's `@MainActor` isolation, which is what
        // makes the generation and stopped flags safe to read inside it without
        // any further synchronization. Only `consume` hops off, and it is where
        // all the real work happens.
        batchedTask = Task { [weak self] in
            guard let self else { return }
            let manager = CMBatchedSensorManager()
            do {
                for try await batch in manager.accelerometerUpdates() {
                    if Task.isCancelled { break }
                    if self.batchedGenerationIsStale(generation) { break }
                    // The batched manager reports its rate rather than accepting
                    // one — `accelerometerDataFrequency` is read-only, with no
                    // setter anywhere on the class — so decimation to the analysis
                    // rate has to happen here. That is a stability requirement,
                    // not a nicety: watchOS suspends background apps that use
                    // excessive CPU, and a suspended app loses the workout.
                    let rate = Double(manager.accelerometerDataFrequency)
                    let samples = batch.map {
                        MotionSample(
                            timestamp: $0.timestamp,
                            x: $0.acceleration.x,
                            y: $0.acceleration.y,
                            z: $0.acceleration.z
                        )
                    }
                    await self.consume(samples, sourceRateHz: rate > 0 ? rate : self.analysisRateHz)
                }
            } catch {
                // The capability flag is not a reliable proxy for "data will
                // actually arrive", so the error path is a real path, not a
                // formality — fall back rather than losing rep detection.
                self.handleBatchedFailure(generation: generation)
            }
        }
    }

    @MainActor
    private func handleBatchedFailure(generation: Int) {
        // Only the attempt that is still current may fall back. A stale one has
        // already been superseded by a stop, a pause, or a newer start.
        guard !isStopped, generation == batchedGeneration, status == .running(.batched) else { return }
        batchedTask = nil
        startStandard()
    }

    @MainActor
    private func startStandard() {
        guard motionManager.isAccelerometerAvailable else {
            status = .failed("This watch can't provide motion data. Log reps with the button or crown.")
            return
        }

        status = .running(.standard)
        motionManager.accelerometerUpdateInterval = 1 / analysisRateHz
        motionManager.startAccelerometerUpdates(to: motionQueue) { [weak self] data, _ in
            guard let self, let data else { return }
            let sample = MotionSample(
                timestamp: data.timestamp,
                x: data.acceleration.x,
                y: data.acceleration.y,
                z: data.acceleration.z
            )
            Task { await self.consume([sample], sourceRateHz: self.analysisRateHz) }
        }
    }

    @MainActor
    private func stopStreams() {
        batchedGeneration &+= 1
        batchedTask?.cancel()
        batchedTask = nil
        if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
        }
    }

    @MainActor
    private func batchedGenerationIsStale(_ generation: Int) -> Bool {
        isStopped || generation != batchedGeneration
    }

    private func consume(_ samples: [MotionSample], sourceRateHz: Double) async {
        let detected = await processor.process(samples, sourceRateHz: sourceRateHz)
        guard detected > 0 else { return }
        await MainActor.run {
            guard self.status.isRunning else { return }
            self.onRepsDetected?(detected)
        }
    }
}

/// Serializes access to the detection engine off the main actor.
///
/// The engine recounts its whole buffer several times a second. That is cheap,
/// but it is not free, and it has no business competing with SwiftUI for the main
/// actor while an athlete is watching a countdown.
private actor RepDetectionProcessor {
    private var engine: RepDetectionEngine
    private var decimator = Decimator(factor: 1)
    private var decimatorSourceRateHz: Double = 0
    private let analysisRateHz: Double

    init(movement: Movement, analysisRateHz: Double) {
        self.analysisRateHz = analysisRateHz
        engine = RepDetectionEngine(
            movement: movement,
            configuration: .init(analysisRateHz: analysisRateHz)
        )
    }

    func beginSegment(movement: Movement) {
        engine.beginSegment(movement: movement)
        decimator.reset()
    }

    func process(_ samples: [MotionSample], sourceRateHz: Double) -> Int {
        if sourceRateHz != decimatorSourceRateHz {
            decimatorSourceRateHz = sourceRateHz
            decimator = Decimator(
                factor: Decimator.factor(sourceRateHz: sourceRateHz, targetRateHz: analysisRateHz)
            )
            // Drop the buffer too, not just the decimator. A rate change means a
            // tier failover mid-set, and samples decimated at the old factor sit
            // at a different effective rate from the ones that follow. Every
            // time-based decision downstream — the filter corners, `minPeriod` in
            // samples, the autocorrelation lag search — assumes one rate for the
            // whole buffer, so analysing the splice is undefined rather than
            // merely inaccurate. Losing the warm-up window is the cheaper error.
            engine.reset()
        }
        return engine.ingest(decimator.decimate(samples))
    }
}
