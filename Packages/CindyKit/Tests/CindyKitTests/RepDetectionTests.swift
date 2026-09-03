import XCTest
@testable import CindyKit

/// Synthetic-signal tests for the RecoFit counting pipeline.
///
/// The signals below are idealized, and that is the point: they check that the
/// algorithm is *implemented* correctly, not that it is *tuned* correctly. Real
/// accuracy can only come from fatigued attempts on a wrist, as the research
/// notes say repeatedly — nothing here is evidence about that.
final class RepDetectionTests: XCTestCase {
    private let sampleRateHz = 50.0

    // MARK: - Signal generators

    /// A pull-up-like signal: a large translation along one axis, plus gravity.
    private func translationSignal(
        reps: Int,
        periodSeconds: Double,
        amplitude: Double = 0.5,
        noise: Double = 0.01
    ) -> [(x: Double, y: Double, z: Double)] {
        let total = Int(Double(reps) * periodSeconds * sampleRateHz)
        return (0..<total).map { index in
            let t = Double(index) / sampleRateHz
            let phase = 2 * Double.pi * t / periodSeconds
            return (
                x: amplitude * sin(phase) + deterministicNoise(index, scale: noise),
                y: deterministicNoise(index &* 7, scale: noise),
                z: 1.0 + deterministicNoise(index &* 13, scale: noise)
            )
        }
    }

    /// An air-squat-like signal: two acceleration bursts per repetition, matching
    /// RecoFit's Figure 2b, which shows squats producing a "double peak" per rep.
    private func doublePeakSignal(
        reps: Int,
        periodSeconds: Double,
        burstSeparation: Double,
        noise: Double = 0.01
    ) -> [(x: Double, y: Double, z: Double)] {
        let total = Int(Double(reps) * periodSeconds * sampleRateHz)
        return (0..<total).map { index in
            let t = Double(index) / sampleRateHz
            let phaseInRep = t.truncatingRemainder(dividingBy: periodSeconds)
            let first = gaussianBurst(phaseInRep, center: periodSeconds * 0.25, width: 0.12)
            let second = gaussianBurst(phaseInRep, center: periodSeconds * 0.25 + burstSeparation, width: 0.12)
            return (
                x: deterministicNoise(index, scale: noise),
                y: deterministicNoise(index &* 7, scale: noise),
                z: 1.0 + 0.6 * first + 0.55 * second + deterministicNoise(index &* 13, scale: noise)
            )
        }
    }

    /// A push-up-like signal: the accelerometer stays at 1 g the whole time while
    /// the gravity *direction* swings. RecoFit: "Some exercises, e.g. pushups,
    /// result in almost no translation of an arm-worn sensor… the primary
    /// observable phenomenon in these cases is not energy on any sensed axis, but
    /// a repetitive change in the gravity axis observed by the accelerometer."
    private func gravityRotationSignal(
        reps: Int,
        periodSeconds: Double,
        swingRadians: Double = 0.5,
        noise: Double = 0.005
    ) -> [(x: Double, y: Double, z: Double)] {
        let total = Int(Double(reps) * periodSeconds * sampleRateHz)
        return (0..<total).map { index in
            let t = Double(index) / sampleRateHz
            let angle = swingRadians * sin(2 * Double.pi * t / periodSeconds)
            return (
                x: sin(angle) + deterministicNoise(index, scale: noise),
                y: deterministicNoise(index &* 7, scale: noise),
                z: cos(angle) + deterministicNoise(index &* 13, scale: noise)
            )
        }
    }

    private func gaussianBurst(_ t: Double, center: Double, width: Double) -> Double {
        let d = (t - center) / width
        return exp(-0.5 * d * d)
    }

    /// Reproducible pseudo-noise. A seeded generator rather than `Double.random`
    /// so a failure is always reproducible.
    private func deterministicNoise(_ index: Int, scale: Double) -> Double {
        guard scale != 0 else { return 0 }
        let x = sin(Double(index) * 12.9898) * 43758.5453
        return (x - x.rounded(.down) - 0.5) * 2 * scale
    }

    private func counted(
        _ samples: [(x: Double, y: Double, z: Double)],
        as movement: Movement
    ) -> Int {
        let filter = Bandpass.repCounting(sampleRateHz: sampleRateHz)
        let filtered = zip(
            zip(filter.filtering(samples.map(\.x)), filter.filtering(samples.map(\.y))),
            filter.filtering(samples.map(\.z))
        ).map { (pair, z) in (x: pair.0, y: pair.1, z: z) }

        return RepPeakCounter.count(
            in: PrincipalAxis.reduce(filtered),
            sampleRateHz: sampleRateHz,
            profile: movement.repCountingProfile
        )
    }

    // MARK: - Counting

    func testCountsCleanTranslationReps() {
        let count = counted(translationSignal(reps: 10, periodSeconds: 2.0), as: .pullUp)
        XCTAssertEqual(Double(count), 10, accuracy: 1, "expected ~10 pull-ups, got \(count)")
    }

    func testCountsSlowFatiguedReps() {
        // Round 15 of Cindy: the same movement at nearly half the tempo. The wide
        // `maxPeriod` bracket and the relative amplitude floor exist for this case.
        let count = counted(translationSignal(reps: 6, periodSeconds: 3.5, amplitude: 0.25), as: .pullUp)
        XCTAssertEqual(Double(count), 6, accuracy: 1, "expected ~6 slow pull-ups, got \(count)")
    }

    func testDoublePeakSquatsAreCountedOncePerRep() {
        // Two bursts 0.4 s apart, inside the 0.7 s air-squat `minPeriod`, so pass
        // one must collapse them. Counting local maxima naively would return ~16.
        let samples = doublePeakSignal(reps: 8, periodSeconds: 2.0, burstSeparation: 0.4)
        let count = counted(samples, as: .airSquat)
        XCTAssertEqual(Double(count), 8, accuracy: 1, "double peaks should collapse to 8 reps, got \(count)")
    }

    /// The regression test for the single most important correction in the
    /// research fact-check: RecoFit counts on the first principal component, not
    /// on accelerometer magnitude, and push-ups are precisely where that matters.
    func testGravityRotationIsCountableByProjectionButNotByMagnitude() {
        let samples = gravityRotationSignal(reps: 12, periodSeconds: 1.25)

        let projectedCount = counted(samples, as: .pushUp)
        XCTAssertEqual(Double(projectedCount), 12, accuracy: 1, "projection should find ~12 push-ups, got \(projectedCount)")

        let filter = Bandpass.repCounting(sampleRateHz: sampleRateHz)
        let magnitude = filter.filtering(samples.map { ($0.x * $0.x + $0.y * $0.y + $0.z * $0.z).squareRoot() })
        let magnitudeCount = RepPeakCounter.count(
            in: magnitude,
            sampleRateHz: sampleRateHz,
            profile: Movement.pushUp.repCountingProfile
        )

        XCTAssertGreaterThan(
            abs(magnitudeCount - 12), 2,
            "magnitude counting is expected to fail on a pure gravity rotation (got \(magnitudeCount)); if it starts succeeding, this test's premise needs revisiting"
        )
    }

    func testStillWristCountsNothing() {
        let still = (0..<(50 * 20)).map { index in
            (x: deterministicNoise(index, scale: 0.004),
             y: deterministicNoise(index &* 7, scale: 0.004),
             z: 1.0 + deterministicNoise(index &* 13, scale: 0.004))
        }
        XCTAssertLessThanOrEqual(counted(still, as: .pullUp), 1, "a still wrist must not manufacture reps")
    }

    func testEmptyAndTinySignalsAreSafe() {
        let profile = Movement.pullUp.repCountingProfile
        XCTAssertEqual(RepPeakCounter.count(in: [], sampleRateHz: sampleRateHz, profile: profile), 0)
        XCTAssertEqual(RepPeakCounter.count(in: [1, 2], sampleRateHz: sampleRateHz, profile: profile), 0)
        XCTAssertEqual(RepPeakCounter.count(in: [1, 2, 3], sampleRateHz: 0, profile: profile), 0)
    }

    // MARK: - Principal axis

    func testDominantAxisFindsTheAxisOfGreatestVariation() {
        let samples = (0..<200).map { index -> (x: Double, y: Double, z: Double) in
            let t = Double(index) / sampleRateHz
            return (x: 0.02 * sin(t), y: sin(2 * Double.pi * t), z: 0.02 * cos(t))
        }
        let axis = PrincipalAxis.dominant(of: samples)
        XCTAssertNotNil(axis)
        XCTAssertEqual(abs(axis?.y ?? 0), 1.0, accuracy: 0.02, "variation is on y, so the principal axis should be y")
    }

    func testDominantAxisIsNilForADegenerateSignal() {
        let flat = Array(repeating: (x: 0.0, y: 0.0, z: 1.0), count: 100)
        XCTAssertNil(PrincipalAxis.dominant(of: flat))
        // ...but `reduce` must still return a usable series rather than nothing.
        XCTAssertEqual(PrincipalAxis.reduce(flat).count, 100)
    }

    func testProjectionSignIsStableAcrossOverlappingWindows() {
        // A recount over a sliding buffer must not flip peaks into troughs.
        let samples = translationSignal(reps: 10, periodSeconds: 2.0, noise: 0)
        let whole = PrincipalAxis.reduce(samples)
        let tail = PrincipalAxis.reduce(Array(samples.dropFirst(100)))

        let overlapWhole = Array(whole.dropFirst(100).prefix(200))
        let overlapTail = Array(tail.prefix(200))
        let correlation = zip(overlapWhole, overlapTail).reduce(0) { $0 + $1.0 * $1.1 }
        XCTAssertGreaterThan(correlation, 0, "overlapping projections must agree in sign")
    }

    // MARK: - Filtering

    func testBandpassRemovesGravityOffset() {
        let filter = Bandpass.repCounting(sampleRateHz: sampleRateHz)
        let constant = Array(repeating: 1.0, count: 2000)
        let filtered = filter.filtering(constant)
        // Settled tail only: the first samples are the filter's step response.
        let tail = filtered.suffix(500)
        XCTAssertLessThan(tail.map(abs).max() ?? 1, 0.01, "a DC offset must be removed")
    }

    func testBandpassPassesRepFrequenciesAndRejectsTremor() {
        let filter = Bandpass.repCounting(sampleRateHz: sampleRateHz)

        let inBand = (0..<2000).map { sin(2 * Double.pi * 0.5 * Double($0) / sampleRateHz) }
        let inBandAmplitude = filter.filtering(inBand).suffix(1000).map(abs).max() ?? 0
        XCTAssertGreaterThan(inBandAmplitude, 0.7, "0.5 Hz is mid-band and must survive")

        let outOfBand = (0..<2000).map { sin(2 * Double.pi * 22 * Double($0) / sampleRateHz) }
        let outOfBandAmplitude = filter.filtering(outOfBand).suffix(1000).map(abs).max() ?? 0
        XCTAssertLessThan(outOfBandAmplitude, 0.3, "22 Hz is well above the 11 Hz corner")
    }

    func testFilteringIsPureAndRepeatable() {
        let filter = Bandpass.repCounting(sampleRateHz: sampleRateHz)
        let input = (0..<300).map { sin(Double($0) / 10) }
        XCTAssertEqual(filter.filtering(input), filter.filtering(input), "filtering must not carry state between calls")
    }

    // MARK: - Decimation

    func testDecimatorAveragesGroupsAndKeepsRemainder() {
        var decimator = Decimator(factor: 4)
        let samples = (0..<10).map { MotionSample(timestamp: Double($0) * 0.01, x: Double($0), y: 0, z: 0) }

        let output = decimator.decimate(samples)
        XCTAssertEqual(output.count, 2, "10 samples at factor 4 yields 2 outputs and keeps 2 pending")
        XCTAssertEqual(output[0].x, 1.5, accuracy: 1e-9)
        XCTAssertEqual(output[1].x, 5.5, accuracy: 1e-9)
        XCTAssertEqual(output[1].timestamp, 0.07, accuracy: 1e-9, "the group's end time, not its mean")

        // The 2 pending samples must combine with the next batch, not be dropped.
        let more = (10..<12).map { MotionSample(timestamp: Double($0) * 0.01, x: Double($0), y: 0, z: 0) }
        XCTAssertEqual(decimator.decimate(more).count, 1)
    }

    func testDecimatorFactorMath() {
        XCTAssertEqual(Decimator.factor(sourceRateHz: 800, targetRateHz: 50), 16)
        XCTAssertEqual(Decimator.factor(sourceRateHz: 200, targetRateHz: 50), 4)
        XCTAssertEqual(Decimator.factor(sourceRateHz: 50, targetRateHz: 50), 1)
        XCTAssertEqual(Decimator.factor(sourceRateHz: 25, targetRateHz: 50), 1, "never up-sample")
        XCTAssertEqual(Decimator.factor(sourceRateHz: 0, targetRateHz: 50), 1)
    }

    func testDecimatorFactorOneIsAPassThrough() {
        var decimator = Decimator(factor: 1)
        let samples = (0..<5).map { MotionSample(timestamp: Double($0), x: 1, y: 2, z: 3) }
        XCTAssertEqual(decimator.decimate(samples), samples)
    }

    // MARK: - Engine

    private func feed(
        _ engine: inout RepDetectionEngine,
        _ samples: [(x: Double, y: Double, z: Double)],
        batchSize: Int = 25
    ) -> Int {
        var emitted = 0
        var index = 0
        while index < samples.count {
            let upper = min(index + batchSize, samples.count)
            let batch = (index..<upper).map { position in
                MotionSample(
                    timestamp: Double(position) / sampleRateHz,
                    x: samples[position].x,
                    y: samples[position].y,
                    z: samples[position].z
                )
            }
            emitted += engine.ingest(batch)
            index = upper
        }
        return emitted
    }

    func testEngineEmitsRepsIncrementally() {
        var engine = RepDetectionEngine(movement: .pullUp)
        let emitted = feed(&engine, translationSignal(reps: 12, periodSeconds: 2.0))
        // Warm-up (two periods) and the confirmation lag both hold back a rep or
        // two by design, so this is a range, not an equality.
        XCTAssertGreaterThanOrEqual(emitted, 8, "expected most of 12 reps, got \(emitted)")
        XCTAssertLessThanOrEqual(emitted, 12, "the engine must never over-report, got \(emitted)")
    }

    func testEngineNeverEmitsFromAStillWrist() {
        var engine = RepDetectionEngine(movement: .pushUp)
        let still = (0..<(50 * 30)).map { index in
            (x: deterministicNoise(index, scale: 0.004),
             y: deterministicNoise(index &* 7, scale: 0.004),
             z: 1.0 + deterministicNoise(index &* 13, scale: 0.004))
        }
        XCTAssertEqual(feed(&engine, still), 0)
    }

    func testBeginSegmentDiscardsThePreviousMovement() {
        var engine = RepDetectionEngine(movement: .pullUp)
        _ = feed(&engine, translationSignal(reps: 6, periodSeconds: 2.0))
        XCTAssertGreaterThan(engine.bufferedSampleCount, 0)

        engine.beginSegment(movement: .pushUp)
        XCTAssertEqual(engine.movement, .pushUp)
        XCTAssertEqual(engine.bufferedSampleCount, 0, "a pull-up's signal must not leak into push-up counting")
    }

    func testEngineTrimsItsBuffer() {
        var engine = RepDetectionEngine(
            movement: .pullUp,
            configuration: .init(analysisRateHz: sampleRateHz, maxBufferSeconds: 5, recountInterval: 0.2)
        )
        _ = feed(&engine, translationSignal(reps: 20, periodSeconds: 2.0))
        XCTAssertLessThanOrEqual(engine.bufferedSampleCount, Int(5 * sampleRateHz) + 25)
    }

    func testEngineIsIdempotentUnderEmptyInput() {
        var engine = RepDetectionEngine(movement: .airSquat)
        XCTAssertEqual(engine.ingest([]), 0)
        XCTAssertEqual(engine.bufferedSampleCount, 0)
    }

    // MARK: - Profiles

    func testEveryMovementHasACoherentProfile() {
        for movement in Movement.allCases {
            let profile = movement.repCountingProfile
            XCTAssertGreaterThan(profile.minPeriod, 0, "\(movement) minPeriod")
            XCTAssertGreaterThan(profile.maxPeriod, profile.minPeriod, "\(movement) bracket must be ordered")
            XCTAssertLessThanOrEqual(profile.maxPeriod, 6, "\(movement) maxPeriod is implausibly slow")
            // Comfortably clear of resting sensor noise (~0.005 G RMS) but far
            // below any real repetition's excursion.
            XCTAssertGreaterThan(profile.activityFloor, 0.01, "\(movement) floor is inside the noise")
            XCTAssertLessThan(profile.activityFloor, 0.1, "\(movement) floor would reject real reps")
        }
    }

    /// The period estimator must pick the fundamental, not one of its harmonics.
    /// Getting this wrong is silent: a 2P estimate makes the 0.75*P refractory
    /// reject every second genuine rep, halving the count with no error anywhere.
    func testPeriodEstimationPicksTheFundamentalNotTheHarmonic() {
        let periodic = (0..<1000).map { sin(2 * Double.pi * Double($0) / 100.0) }
        let count = RepPeakCounter.count(
            in: periodic,
            sampleRateHz: sampleRateHz,
            profile: RepCountingProfile(minPeriod: 0.8, maxPeriod: 4.0, activityFloor: 0.03)
        )
        XCTAssertEqual(Double(count), 10, accuracy: 1, "1000 samples of a 100-sample period is 10 reps, got \(count)")
    }

    func testActivityFloorRejectsSubThresholdMovement() {
        // Same shape, a twentieth of the amplitude: a wrist twitch, not a rep.
        let tiny = (0..<1000).map { 0.001 * sin(2 * Double.pi * Double($0) / 100.0) }
        XCTAssertEqual(
            RepPeakCounter.count(
                in: tiny,
                sampleRateHz: sampleRateHz,
                profile: Movement.pullUp.repCountingProfile
            ),
            0
        )
    }
}

// MARK: - Rest inside a segment
//
// The regression suite for the worst defect found in review: both amplitude gates
// were computed globally over the whole buffer, so once any real motion entered it
// the absolute floor was unlocked and the relative floor collapsed to noise level.
// Five real pull-ups followed by eighty seconds of a motionless wrist produced 42
// detected reps, 37 of them phantom. A single bump then stillness produced 40.

final class RestWithinSegmentTests: XCTestCase {
    private let sampleRateHz = 50.0

    private func deterministicNoise(_ index: Int, scale: Double) -> Double {
        guard scale != 0 else { return 0 }
        let x = sin(Double(index) * 12.9898) * 43758.5453
        return (x - x.rounded(.down) - 0.5) * 2 * scale
    }

    /// `reps` repetitions, then `restSeconds` of a still wrist, streamed through
    /// the engine in the same 25-sample batches the watch delivers.
    private func emittedReps(
        reps: Int,
        periodSeconds: Double,
        restSeconds: Double,
        movement: Movement,
        amplitude: Double = 0.5
    ) -> Int {
        var engine = RepDetectionEngine(movement: movement)
        let repSamples = Int(Double(reps) * periodSeconds * sampleRateHz)
        let restSamples = Int(restSeconds * sampleRateHz)

        var emitted = 0
        var batch: [MotionSample] = []
        for index in 0..<(repSamples + restSamples) {
            let t = Double(index) / sampleRateHz
            let motion = index < repSamples ? amplitude * sin(2 * Double.pi * t / periodSeconds) : 0
            batch.append(
                MotionSample(
                    timestamp: t,
                    x: motion + deterministicNoise(index, scale: 0.006),
                    y: deterministicNoise(index &* 7, scale: 0.006),
                    z: 1.0 + deterministicNoise(index &* 13, scale: 0.006)
                )
            )
            if batch.count == 25 {
                emitted += engine.ingest(batch)
                batch.removeAll(keepingCapacity: true)
            }
        }
        if !batch.isEmpty { emitted += engine.ingest(batch) }
        return emitted
    }

    func testRestAfterPullUpsDoesNotManufactureReps() {
        let emitted = emittedReps(reps: 5, periodSeconds: 2.0, restSeconds: 80, movement: .pullUp)
        XCTAssertLessThanOrEqual(emitted, 6, "80s of stillness must not add reps, got \(emitted)")
        XCTAssertGreaterThanOrEqual(emitted, 4, "the 5 real reps must still be found, got \(emitted)")
    }

    func testRestAfterPushUpsDoesNotManufactureReps() {
        let emitted = emittedReps(reps: 10, periodSeconds: 1.5, restSeconds: 48, movement: .pushUp)
        XCTAssertLessThanOrEqual(emitted, 11, "got \(emitted)")
        XCTAssertGreaterThanOrEqual(emitted, 8, "got \(emitted)")
    }

    func testRestAfterAirSquatsDoesNotManufactureReps() {
        let emitted = emittedReps(reps: 15, periodSeconds: 1.8, restSeconds: 60, movement: .airSquat)
        XCTAssertLessThanOrEqual(emitted, 16, "got \(emitted)")
        XCTAssertGreaterThanOrEqual(emitted, 13, "got \(emitted)")
    }

    /// A mid-set shake-out: reps, a pause, then more reps. The pause must not add
    /// to the count, and the reps after it must still be found.
    func testMidSetPauseIsNotCountedButLaterRepsAre() {
        var engine = RepDetectionEngine(movement: .pullUp)
        var emitted = 0
        var batch: [MotionSample] = []
        var index = 0

        func feed(seconds: Double, moving: Bool) {
            let count = Int(seconds * sampleRateHz)
            for _ in 0..<count {
                let t = Double(index) / sampleRateHz
                let motion = moving ? 0.5 * sin(2 * Double.pi * t / 2.0) : 0
                batch.append(
                    MotionSample(
                        timestamp: t,
                        x: motion + deterministicNoise(index, scale: 0.006),
                        y: deterministicNoise(index &* 7, scale: 0.006),
                        z: 1.0 + deterministicNoise(index &* 13, scale: 0.006)
                    )
                )
                if batch.count == 25 {
                    emitted += engine.ingest(batch)
                    batch.removeAll(keepingCapacity: true)
                }
                index += 1
            }
        }

        feed(seconds: 6, moving: true)   // 3 reps
        feed(seconds: 20, moving: false) // shake out the forearms
        feed(seconds: 6, moving: true)   // 3 more
        if !batch.isEmpty { emitted += engine.ingest(batch) }

        XCTAssertLessThanOrEqual(emitted, 7, "the 20s pause must contribute nothing, got \(emitted)")
        XCTAssertGreaterThanOrEqual(emitted, 4, "reps on both sides of the pause must count, got \(emitted)")
    }

    /// A stream restart hands over a clock that starts somewhere else. A backwards
    /// jump must not strand `emittedThrough` in the future and kill detection.
    func testBackwardsTimestampJumpRecovers() {
        var engine = RepDetectionEngine(movement: .pullUp)

        func samples(from start: Double, seconds: Double) -> [MotionSample] {
            (0..<Int(seconds * sampleRateHz)).map { offset in
                let local = Double(offset) / sampleRateHz
                return MotionSample(
                    timestamp: start + local,
                    x: 0.5 * sin(2 * Double.pi * local / 2.0),
                    y: 0,
                    z: 1.0
                )
            }
        }

        _ = engine.ingest(samples(from: 10_000, seconds: 12))
        // New stream, clock restarted near zero.
        let afterRestart = engine.ingest(samples(from: 5, seconds: 12))
        XCTAssertGreaterThan(afterRestart, 0, "detection must survive a stream restart")
    }
}
