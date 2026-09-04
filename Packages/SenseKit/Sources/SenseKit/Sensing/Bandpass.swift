import Foundation

/// One second-order IIR section, in direct form II transposed.
///
/// Transposed form is the standard choice for `Double` audio-rate filtering
/// because it keeps the two state variables in the same numeric range as the
/// signal, which matters here: the high-pass corner is 0.15 Hz against a 50 Hz
/// sample rate, a normalized frequency of 0.003, where a direct-form-I
/// difference equation loses precision fastest.
public struct Biquad: Sendable, Equatable {
    public let b0: Double
    public let b1: Double
    public let b2: Double
    public let a1: Double
    public let a2: Double

    private var z1: Double = 0
    private var z2: Double = 0

    public init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    public mutating func reset() {
        z1 = 0
        z2 = 0
    }

    /// Sets the state to the steady-state response for a constant input, so the
    /// filter starts already settled instead of ringing.
    ///
    /// This matters far more here than it would in an offline pipeline. Zero
    /// state means the first sample looks like a step from 0 to roughly 1 G —
    /// gravity — and the 0.15 Hz high-pass corner gives that step a ~1 s time
    /// constant, so several seconds of the filtered signal are dominated by a
    /// transient an order of magnitude larger than any repetition. Because the
    /// detection engine re-filters its entire rolling buffer on every tick, that
    /// transient does not just contaminate the first few seconds once; it sits at
    /// the buffer's leading edge and marches through the analysis window forever.
    ///
    /// The algebra: for a constant input `c`, direct form II transposed is at
    /// steady state when `z1 = y - b0*c` and `z2 = b2*c - a2*y`, where `y` is the
    /// filter's DC gain times `c` — 0 for the high-pass, `c` for the low-pass.
    public mutating func prime(constantInput input: Double) {
        let dcGain = (b0 + b1 + b2) / (1 + a1 + a2)
        let output = dcGain.isFinite ? dcGain * input : 0
        z1 = output - b0 * input
        z2 = b2 * input - a2 * output
    }

    public mutating func process(_ input: Double) -> Double {
        let output = b0 * input + z1
        z1 = b1 * input - a1 * output + z2
        z2 = b2 * input - a2 * output
        return output
    }

    /// Butterworth (Q = 1/√2) low-pass via the RBJ audio-EQ cookbook formulas.
    public static func lowPass(cutoffHz: Double, sampleRateHz: Double, q: Double = 0.7071067811865476) -> Biquad {
        let omega = 2 * Double.pi * cutoffHz / sampleRateHz
        let cosOmega = cos(omega)
        let alpha = sin(omega) / (2 * q)
        let a0 = 1 + alpha

        return Biquad(
            b0: ((1 - cosOmega) / 2) / a0,
            b1: (1 - cosOmega) / a0,
            b2: ((1 - cosOmega) / 2) / a0,
            a1: (-2 * cosOmega) / a0,
            a2: (1 - alpha) / a0
        )
    }

    /// Butterworth (Q = 1/√2) high-pass via the RBJ audio-EQ cookbook formulas.
    public static func highPass(cutoffHz: Double, sampleRateHz: Double, q: Double = 0.7071067811865476) -> Biquad {
        let omega = 2 * Double.pi * cutoffHz / sampleRateHz
        let cosOmega = cos(omega)
        let alpha = sin(omega) / (2 * q)
        let a0 = 1 + alpha

        return Biquad(
            b0: ((1 + cosOmega) / 2) / a0,
            b1: (-(1 + cosOmega)) / a0,
            b2: ((1 + cosOmega) / 2) / a0,
            a1: (-2 * cosOmega) / a0,
            a2: (1 - alpha) / a0
        )
    }
}

/// The band-limiting stage of RecoFit's counting pipeline: a 0.15–11 Hz
/// band-pass applied to each accelerometer axis before PCA.
///
/// RecoFit specifies an *elliptical* band-pass. This is a cascaded Butterworth
/// high-pass + low-pass instead — a deliberate, documented substitution. An
/// elliptical design buys a steeper transition band at the cost of passband
/// ripple and a hand-tuned order/ripple pair that Apple's SDK provides no
/// facility to design at runtime. The band here spans nearly two decades
/// (0.15–11 Hz) while every rep frequency of interest sits between roughly
/// 0.25 Hz and 1.7 Hz, dead centre. Transition-band steepness is therefore not
/// load-bearing, and passband flatness — which Butterworth maximizes and
/// elliptical explicitly sacrifices — is, because the next stage is PCA over
/// the filtered axes and ripple would bias the principal direction.
public struct Bandpass: Sendable {
    private var highPass: Biquad
    private var lowPass: Biquad

    public init(lowCutoffHz: Double, highCutoffHz: Double, sampleRateHz: Double) {
        // Guard the low-pass corner against Nyquist: the cookbook formulas go
        // unstable as omega approaches pi. At the universal CMMotionManager
        // fallback rate this never binds (11 Hz against a 25 Hz Nyquist), but a
        // caller decimating to 20 Hz would otherwise silently get a broken filter.
        let nyquist = sampleRateHz / 2
        let safeHigh = min(highCutoffHz, nyquist * 0.9)

        highPass = Biquad.highPass(cutoffHz: lowCutoffHz, sampleRateHz: sampleRateHz)
        lowPass = Biquad.lowPass(cutoffHz: safeHigh, sampleRateHz: sampleRateHz)
    }

    /// RecoFit's stated band, 0.15 Hz to 11 Hz.
    public static func repCounting(sampleRateHz: Double) -> Bandpass {
        Bandpass(lowCutoffHz: 0.15, highCutoffHz: 11, sampleRateHz: sampleRateHz)
    }

    public mutating func reset() {
        highPass.reset()
        lowPass.reset()
    }

    /// Starts both sections already settled for a constant `input`, so the
    /// cascade produces no step transient. See ``Biquad/prime(constantInput:)``.
    public mutating func prime(constantInput input: Double) {
        highPass.prime(constantInput: input)
        // The high-pass rejects DC, so by the time the signal reaches the
        // low-pass its steady-state input is zero, not the original constant.
        lowPass.prime(constantInput: 0)
    }

    public mutating func process(_ input: Double) -> Double {
        lowPass.process(highPass.process(input))
    }

    /// Filters a whole series from a clean initial state.
    ///
    /// Pure by construction — it copies the filter rather than mutating the
    /// receiver — because the detection engine re-filters its entire rolling
    /// buffer on every tick rather than carrying filter state forward. That
    /// statelessness is the direct antidote to the double-counting-on-relaunch
    /// class of bug documented in the research notes: a recount can be wrong,
    /// but it can never drift.
    public func filtering(_ series: [Double]) -> [Double] {
        guard let first = series.first else { return [] }
        var filter = self
        // Primed from the first sample rather than zeroed. Accelerometer series
        // start near 1 G, and a zero-state filter reads that as a step, ringing
        // for seconds at an amplitude that dwarfs any repetition. See
        // `Biquad.prime(constantInput:)` for why that is a correctness problem
        // and not just a cosmetic one.
        filter.prime(constantInput: first)
        return series.map { filter.process($0) }
    }
}
