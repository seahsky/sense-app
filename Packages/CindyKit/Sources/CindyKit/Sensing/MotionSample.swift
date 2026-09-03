import Foundation

/// One tri-axial accelerometer reading, in the units Core Motion delivers.
///
/// Deliberately framework-free: `CMAccelerometerData` lives in Core Motion,
/// which does not exist on iOS-simulator test hosts for the watch target and
/// would drag a platform dependency into `CindyKit`. The watch app converts
/// `CMAccelerometerData` / `CMDeviceMotion` into this type at the boundary, so
/// every signal-processing type below stays pure and unit-testable.
public struct MotionSample: Sendable, Equatable {
    /// Seconds on Core Motion's monotonic clock (`CMLogItem.timestamp`). The SDK
    /// documents this only as "time at which the item is valid" — it is *not*
    /// documented as boot-relative, so treat it as monotonic and comparable
    /// within one stream, never as a wall-clock date.
    public let timestamp: TimeInterval

    /// Acceleration in G, including gravity, exactly as `CMAcceleration` reports it.
    public let x: Double
    public let y: Double
    public let z: Double

    public init(timestamp: TimeInterval, x: Double, y: Double, z: Double) {
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.z = z
    }
}

/// Reduces a high-rate stream to a target rate by averaging consecutive samples.
///
/// `CMBatchedSensorManager` reports its rate rather than accepting one
/// (`accelerometerDataFrequency` is read-only), so decimation has to happen in
/// software — and it has to happen, because the documented failure mode for a
/// background workout app is watchOS suspending it for excessive CPU, not merely
/// draining the battery.
///
/// Averaging each group is a box FIR, whose first null sits at the source rate
/// divided by the group size. That is a cruder anti-alias filter than a designed
/// low-pass, but the band it protects (0.15–11 Hz after
/// ``Bandpass/repCounting(sampleRateHz:)``) can only be polluted by source energy
/// near multiples of the target rate, and human limb motion carries no meaningful
/// energy at 39 Hz and above. The tradeoff is documented rather than hidden.
public struct Decimator: Sendable {
    public let factor: Int

    private var pending: [MotionSample] = []

    /// - Parameter factor: samples averaged per output sample. Values below 1 are
    ///   clamped to 1, which makes the decimator a pass-through.
    public init(factor: Int) {
        self.factor = max(1, factor)
    }

    /// The factor that takes `sourceRateHz` closest to `targetRateHz` without
    /// going below it, so the decimated stream is never slower than requested.
    public static func factor(sourceRateHz: Double, targetRateHz: Double) -> Int {
        guard sourceRateHz > 0, targetRateHz > 0, sourceRateHz > targetRateHz else { return 1 }
        return max(1, Int((sourceRateHz / targetRateHz).rounded(.down)))
    }

    /// Consumes `samples` and returns whatever whole groups completed. A partial
    /// group is retained until the next call, so no sample is dropped or counted
    /// twice across batch boundaries.
    public mutating func decimate(_ samples: [MotionSample]) -> [MotionSample] {
        guard factor > 1 else { return samples }

        pending.append(contentsOf: samples)
        guard pending.count >= factor else { return [] }

        var output: [MotionSample] = []
        output.reserveCapacity(pending.count / factor)

        var index = 0
        while index + factor <= pending.count {
            let group = pending[index..<(index + factor)]
            let count = Double(factor)
            output.append(
                MotionSample(
                    // The group's last timestamp, not its mean: this marks when the
                    // averaged window *ended*, which is what a causal detector should
                    // report as the moment a rep became observable.
                    timestamp: group[group.endIndex - 1].timestamp,
                    x: group.reduce(0) { $0 + $1.x } / count,
                    y: group.reduce(0) { $0 + $1.y } / count,
                    z: group.reduce(0) { $0 + $1.z } / count
                )
            )
            index += factor
        }

        pending.removeFirst(index)
        return output
    }

    public mutating func reset() {
        pending.removeAll(keepingCapacity: true)
    }
}
