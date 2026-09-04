import Foundation

/// The per-movement timing bracket RecoFit's first counting pass needs: "an
/// estimate of the minimum possible time needed to perform one repetition"
/// ("it is nearly impossible for a situp to take less than 0.75s or more than 4s").
///
/// These are timing brackets, not thresholds on the signal, which is why they can
/// be set from knowledge of the movement rather than from calibration. They still
/// need tuning against real, fatigued attempts — the values in
/// ``Movement/repCountingProfile`` are starting points, not measurements.
public struct RepCountingProfile: Sendable, Equatable {
    /// Fastest plausible repetition, in seconds. Doubles as the refractory floor
    /// that collapses the air squat's characteristic double peak (RecoFit Fig. 2b
    /// shows "two bursts of acceleration per repetition") into one count.
    public let minPeriod: TimeInterval

    /// Slowest plausible repetition, in seconds. Bounds the autocorrelation lag
    /// search in pass two.
    public let maxPeriod: TimeInterval

    /// Smallest peak excursion, in G, that counts as movement at all.
    ///
    /// This is the one absolute threshold in the pipeline, and it exists because
    /// this app has no equivalent of RecoFit's segmenter. RecoFit only ever
    /// counts inside a window its classifier has already decided contains an
    /// exercise; SENSE knows *which* movement is expected but not *whether* the
    /// athlete is currently doing it. Without a floor, the relative amplitude
    /// threshold in pass three happily ranks sensor noise against sensor noise
    /// and manufactures a steady stream of repetitions from a motionless wrist —
    /// measured at 10 phantom reps in 20 seconds before this was added.
    ///
    /// It gates only "is anything happening"; the peak-versus-peak decision stays
    /// relative, which is what tolerates amplitude fading as the athlete tires.
    public let activityFloor: Double

    public init(minPeriod: TimeInterval, maxPeriod: TimeInterval, activityFloor: Double) {
        self.minPeriod = minPeriod
        self.maxPeriod = maxPeriod
        self.activityFloor = activityFloor
    }
}

/// RecoFit's counting stage: three ordered passes over candidate local maxima of
/// a 1-D signal.
///
/// Two details are copied verbatim from the paper because they are what make it
/// survive a fatigued athlete, and both are easy to "simplify" into
/// uselessness:
///
/// 1. The refractory window is `0.75 * P` using each candidate's *own* locally
///    estimated period, not one global period for the set. Tempo decays badly
///    over a 20-minute AMRAP; a global period fitted to fresh reps rejects
///    genuine slow ones at the end.
/// 2. The amplitude floor is *relative* — half the 40th-percentile peak — which
///    the authors "found much more robust than absolute thresholds". An absolute
///    threshold tuned on fresh, crisp reps silently stops counting as amplitude
///    fades.
///
/// The whole thing is a pure function of its input. The engine recounts an entire
/// buffer on every tick rather than incrementally accumulating, so a recount can
/// be wrong but can never drift.
public enum RepPeakCounter {
    /// Indices into `signal` of the accepted repetition peaks, ascending.
    public static func peakIndices(
        in signal: [Double],
        sampleRateHz: Double,
        profile: RepCountingProfile
    ) -> [Int] {
        guard sampleRateHz > 0, signal.count >= 3 else { return [] }

        let minPeriodSamples = max(1, Int((profile.minPeriod * sampleRateHz).rounded()))
        let maxPeriodSamples = max(minPeriodSamples + 1, Int((profile.maxPeriod * sampleRateHz).rounded()))
        guard signal.count > minPeriodSamples else { return [] }

        // Pass 0 — is anything happening at all? See `activityFloor`.
        let excursion = signal.reduce(0.0) { max($0, abs($1)) }
        guard excursion >= profile.activityFloor else { return [] }

        let candidates = localMaxima(in: signal)
        guard !candidates.isEmpty else { return [] }

        // Pass 1 — greedy, amplitude-first, with a fixed per-movement refractory.
        let firstPass = greedilyThinned(
            candidates: candidates,
            signal: signal,
            spacing: { _ in minPeriodSamples }
        )
        guard !firstPass.isEmpty else { return [] }

        // Pass 2 — re-thin using each surviving peak's own locally estimated period.
        var localPeriods: [Int: Int] = [:]
        for index in firstPass {
            localPeriods[index] = estimatedPeriodSamples(
                in: signal,
                centeredOn: index,
                minLag: minPeriodSamples,
                maxLag: maxPeriodSamples
            )
        }
        let secondPass = greedilyThinned(
            candidates: firstPass,
            signal: signal,
            spacing: { index in
                let period = localPeriods[index] ?? minPeriodSamples
                return max(1, Int((0.75 * Double(period)).rounded()))
            }
        )
        guard !secondPass.isEmpty else { return [] }

        // Pass 3a — absolute floor, per peak.
        //
        // This has to run BEFORE the percentile, and the ordering is the whole
        // fix for a measured, severe failure. The buffer spans a whole movement
        // segment, so it routinely holds real reps *and* a rest — an athlete
        // shaking out their forearms mid-set, or simply hanging on the bar. A
        // single global amplitude check passes as soon as any real rep is in the
        // buffer, and the relative floor below is then computed over a peak set
        // dominated by rest-period noise, which drags the 40th percentile down to
        // noise level and lets every noise peak through.
        //
        // Measured before this fix: five real pull-ups followed by eighty seconds
        // of a motionless wrist produced 42 detected reps, 37 of them phantom.
        // One 0.5 G bump followed by ninety seconds of stillness produced 40.
        // Culling sub-threshold peaks first makes the percentile describe real
        // repetitions instead of noise.
        let plausible = secondPass.filter { signal[$0] >= profile.activityFloor }
        guard !plausible.isEmpty else { return [] }

        // Pass 3b — RecoFit's relative amplitude floor, at half the
        // 40th-percentile peak, over the peaks that survived the absolute cull.
        // Relative is what tolerates amplitude fading as the athlete tires;
        // absolute is what stops noise being ranked against noise. Both are
        // needed, and neither substitutes for the other.
        let amplitudes = plausible.map { signal[$0] }.sorted()
        let percentileIndex = min(amplitudes.count - 1, Int((0.4 * Double(amplitudes.count - 1)).rounded()))
        let floor = amplitudes[percentileIndex] / 2

        return plausible.filter { signal[$0] >= floor }.sorted()
    }

    /// The repetition count for `signal`.
    public static func count(
        in signal: [Double],
        sampleRateHz: Double,
        profile: RepCountingProfile
    ) -> Int {
        peakIndices(in: signal, sampleRateHz: sampleRateHz, profile: profile).count
    }

    /// Strict interior local maxima. Plateaus are represented by their first
    /// sample so a flat top cannot be counted twice.
    private static func localMaxima(in signal: [Double]) -> [Int] {
        var indices: [Int] = []
        var index = 1
        while index < signal.count - 1 {
            let value = signal[index]
            guard value > signal[index - 1] else {
                index += 1
                continue
            }

            var ahead = index + 1
            while ahead < signal.count && signal[ahead] == value {
                ahead += 1
            }
            if ahead < signal.count && signal[ahead] < value {
                indices.append(index)
            }
            index = max(ahead, index + 1)
        }
        return indices
    }

    /// RecoFit's greedy thinning: walk candidates from tallest to shortest and
    /// keep one only if it clears every already-kept peak by that peak's own
    /// required spacing.
    ///
    /// Amplitude-first ordering is what makes this robust — the strongest
    /// evidence claims its ground before weaker, noisier candidates get to.
    private static func greedilyThinned(
        candidates: [Int],
        signal: [Double],
        spacing: (Int) -> Int
    ) -> [Int] {
        // Ties broken by index so the result never depends on sort stability.
        let byAmplitude = candidates.sorted { lhs, rhs in
            signal[lhs] == signal[rhs] ? lhs < rhs : signal[lhs] > signal[rhs]
        }

        var accepted: [Int] = []
        for candidate in byAmplitude {
            let required = spacing(candidate)
            let clashes = accepted.contains { abs($0 - candidate) < max(required, spacing($0)) }
            if !clashes {
                accepted.append(candidate)
            }
        }
        return accepted.sorted()
    }

    /// Pass two's local period estimate: the lag in `[minLag, maxLag]` maximizing
    /// the autocorrelation of a window centred on `index`.
    ///
    /// The window spans two maximum periods, which is the shortest span that can
    /// contain two consecutive repetitions at the slowest tempo the profile
    /// allows — any shorter and the correlation at long lags would be computed
    /// from too few overlapping samples to mean anything.
    private static func estimatedPeriodSamples(
        in signal: [Double],
        centeredOn index: Int,
        minLag: Int,
        maxLag: Int
    ) -> Int {
        let halfWindow = maxLag
        let lower = max(0, index - halfWindow)
        let upper = min(signal.count, index + halfWindow + 1)
        let window = Array(signal[lower..<upper])
        guard window.count > minLag + 1 else { return minLag }

        let mean = window.reduce(0, +) / Double(window.count)
        let centered = window.map { $0 - mean }

        var bestLag = minLag
        var bestCorrelation = -Double.infinity

        let highestLag = min(maxLag, centered.count - 1)
        guard highestLag >= minLag else { return minLag }

        for lag in minLag...highestLag {
            let overlap = centered.count - lag
            guard overlap > 1 else { break }

            var correlation = 0.0
            for position in 0..<overlap {
                correlation += centered[position] * centered[position + lag]
            }
            // Deliberately NOT normalized by overlap.
            //
            // Normalizing looks fairer — long lags correlate fewer sample pairs —
            // but it is what breaks period estimation. For a periodic signal the
            // normalized correlation at 2P equals the one at P, so the winner
            // between a period and its own harmonic is decided by floating-point
            // noise. Measured on a clean 0.5 Hz signal, the normalized form
            // returned 199 samples where the true period is 100, and the
            // resulting 0.75 * 199 refractory then rejected every second genuine
            // rep — a silent 50% undercount. The raw sum shrinks with lag, which
            // is exactly the bias that makes plain autocorrelation pick the
            // fundamental over its harmonics; it returns 98-99 on the same input.
            if correlation > bestCorrelation {
                bestCorrelation = correlation
                bestLag = lag
            }
        }

        return bestLag
    }
}
