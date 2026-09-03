import Foundation

/// Reduces three band-passed accelerometer axes to the single 1-D signal
/// RecoFit counts peaks on: the projection onto the first principal component.
///
/// This is the step the research notes originally got wrong, and the reason it
/// matters is push-ups. RecoFit: "Some exercises, e.g. pushups, result in almost
/// no translation of an arm-worn sensor… the primary observable phenomenon in
/// these cases is not energy on any sensed axis, but a repetitive change in the
/// gravity axis." A push-up holds the accelerometer near 1 g throughout, so the
/// vector magnitude ‖a‖ is nearly flat while the gravity *direction* swings.
/// Counting on magnitude would see almost nothing; projecting onto the axis of
/// greatest variation sees the swing. RecoFit states it outright: "Magnitude
/// alone is rarely informative."
///
/// PCA also buys rotation invariance for free — how the watch happens to sit on
/// the wrist stops mattering, because the dominant axis is discovered per
/// segment rather than assumed.
public enum PrincipalAxis {
    /// A unit vector in accelerometer space.
    public struct Axis: Sendable, Equatable {
        public let x: Double
        public let y: Double
        public let z: Double

        public init(x: Double, y: Double, z: Double) {
            self.x = x
            self.y = y
            self.z = z
        }
    }

    /// The dominant eigenvector of the samples' covariance matrix, found by power
    /// iteration.
    ///
    /// Power iteration rather than a closed-form 3×3 symmetric eigensolver
    /// because it is short, has no degenerate-discriminant branches to get
    /// wrong, and converges in a handful of iterations for the well-separated
    /// eigenvalues a repetitive movement produces. It is also fully
    /// deterministic here: the seed vector is fixed, so the same input always
    /// yields the same axis.
    ///
    /// Returns `nil` when there is nothing to find — too few samples, or a
    /// covariance matrix that is numerically zero (a perfectly still wrist).
    public static func dominant(of samples: [(x: Double, y: Double, z: Double)]) -> Axis? {
        guard samples.count >= 2 else { return nil }

        let count = Double(samples.count)
        let meanX = samples.reduce(0) { $0 + $1.x } / count
        let meanY = samples.reduce(0) { $0 + $1.y } / count
        let meanZ = samples.reduce(0) { $0 + $1.z } / count

        var cxx = 0.0, cxy = 0.0, cxz = 0.0, cyy = 0.0, cyz = 0.0, czz = 0.0
        for sample in samples {
            let dx = sample.x - meanX
            let dy = sample.y - meanY
            let dz = sample.z - meanZ
            cxx += dx * dx
            cxy += dx * dy
            cxz += dx * dz
            cyy += dy * dy
            cyz += dy * dz
            czz += dz * dz
        }
        cxx /= count; cxy /= count; cxz /= count; cyy /= count; cyz /= count; czz /= count

        let trace = cxx + cyy + czz
        guard trace > 1e-12 else { return nil }

        // Seeded off-axis so it cannot be orthogonal to a dominant eigenvector
        // that lies along a coordinate axis, which is the common case when the
        // movement is mostly vertical.
        var vx = 0.5773502691896258, vy = 0.5773502691896258, vz = 0.5773502691896258

        for _ in 0..<64 {
            let nx = cxx * vx + cxy * vy + cxz * vz
            let ny = cxy * vx + cyy * vy + cyz * vz
            let nz = cxz * vx + cyz * vy + czz * vz

            let norm = (nx * nx + ny * ny + nz * nz).squareRoot()
            guard norm > 1e-12 else { return nil }

            let ux = nx / norm, uy = ny / norm, uz = nz / norm
            let delta = abs(ux - vx) + abs(uy - vy) + abs(uz - vz)
            vx = ux; vy = uy; vz = uz
            if delta < 1e-12 { break }
        }

        return canonicalized(Axis(x: vx, y: vy, z: vz))
    }

    /// An eigenvector is only defined up to sign, and a sign flip turns every
    /// peak into a trough — which changes the count. The rule below pins the sign
    /// so overlapping recounts of a sliding buffer agree.
    ///
    /// The obvious rule — "make the largest component positive" — is subtly
    /// wrong, because "which component is largest" is a discontinuous function of
    /// the axis. An axis sitting near a diagonal, with two components close in
    /// magnitude and opposite in sign, swaps which one is largest as the buffer
    /// shifts by a single sample, and the whole projected signal inverts with it.
    ///
    /// Projecting onto a fixed reference direction is continuous instead: the
    /// sign only changes when the axis genuinely crosses perpendicular to the
    /// reference, and (1,1,1) is deliberately chosen off every coordinate plane so
    /// a movement aligned with any single axis is nowhere near that crossing. The
    /// positional rule survives only as a tiebreak for the rare axis that really
    /// is perpendicular to the reference.
    private static func canonicalized(_ axis: Axis) -> Axis {
        let reference = axis.x + axis.y + axis.z

        let sign: Double
        if abs(reference) > 1e-6 {
            sign = reference < 0 ? -1 : 1
        } else {
            let largest = max(abs(axis.x), max(abs(axis.y), abs(axis.z)))
            if abs(axis.x) == largest {
                sign = axis.x < 0 ? -1 : 1
            } else if abs(axis.y) == largest {
                sign = axis.y < 0 ? -1 : 1
            } else {
                sign = axis.z < 0 ? -1 : 1
            }
        }
        return Axis(x: axis.x * sign, y: axis.y * sign, z: axis.z * sign)
    }

    /// Mean-subtracts the three axes and projects them onto `axis`, yielding the
    /// 1-D signal to count peaks on.
    public static func project(
        _ samples: [(x: Double, y: Double, z: Double)],
        onto axis: Axis
    ) -> [Double] {
        guard !samples.isEmpty else { return [] }

        let count = Double(samples.count)
        let meanX = samples.reduce(0) { $0 + $1.x } / count
        let meanY = samples.reduce(0) { $0 + $1.y } / count
        let meanZ = samples.reduce(0) { $0 + $1.z } / count

        return samples.map { sample in
            (sample.x - meanX) * axis.x + (sample.y - meanY) * axis.y + (sample.z - meanZ) * axis.z
        }
    }

    /// Convenience: find the dominant axis and project onto it in one step.
    /// Falls back to the single highest-variance raw axis when the covariance is
    /// degenerate, so a caller always gets *some* signal rather than an empty
    /// array — matching uLift's cheaper strategy of counting on the
    /// largest-amplitude axis.
    public static func reduce(_ samples: [(x: Double, y: Double, z: Double)]) -> [Double] {
        guard !samples.isEmpty else { return [] }
        if let axis = dominant(of: samples) {
            return project(samples, onto: axis)
        }
        return project(samples, onto: highestVarianceAxis(of: samples))
    }

    private static func highestVarianceAxis(of samples: [(x: Double, y: Double, z: Double)]) -> Axis {
        let count = Double(samples.count)
        let meanX = samples.reduce(0) { $0 + $1.x } / count
        let meanY = samples.reduce(0) { $0 + $1.y } / count
        let meanZ = samples.reduce(0) { $0 + $1.z } / count

        var vx = 0.0, vy = 0.0, vz = 0.0
        for sample in samples {
            vx += (sample.x - meanX) * (sample.x - meanX)
            vy += (sample.y - meanY) * (sample.y - meanY)
            vz += (sample.z - meanZ) * (sample.z - meanZ)
        }

        if vx >= vy && vx >= vz { return Axis(x: 1, y: 0, z: 0) }
        if vy >= vz { return Axis(x: 0, y: 1, z: 0) }
        return Axis(x: 0, y: 0, z: 1)
    }
}
