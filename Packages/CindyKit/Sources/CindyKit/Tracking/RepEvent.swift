import Foundation

/// How a repetition came to be logged.
///
/// Provenance exists so the athlete can always tell what the app decided versus
/// what they told it. The published accuracy data for these three movements —
/// pull-up 88%, push-up 86%, air squat 80% of sets within ±1 rep — means a
/// motion counter will be wrong roughly once per set, so correction is the
/// common path, not an edge case, and "which of these did I not do?" has to be
/// answerable at a glance.
public enum RepSource: String, Codable, Sendable, CaseIterable {
    /// The "+1 REP" button.
    case manual
    /// A Digital Crown rotation.
    case crown
    /// Inferred by ``RepDetectionEngine`` from wrist motion.
    case detected

    /// Whether the athlete deliberately asserted this rep. Detected reps are the
    /// app's opinion; everything else is ground truth.
    public var isUserConfirmed: Bool { self != .detected }
}

/// One logged repetition.
public struct RepEvent: Sendable, Equatable, Codable {
    public let date: Date
    public let source: RepSource

    public init(date: Date = .now, source: RepSource = .manual) {
        self.date = date
        self.source = source
    }
}
