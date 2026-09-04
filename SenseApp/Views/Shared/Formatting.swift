import Foundation

/// Small formatting helpers shared across the Timer/Tracker/Trend screens. Not
/// part of `SenseKit`'s public API — purely app-local presentation plumbing.
enum Formatting {
    /// "MM:SS" — used for both countdown remaining-time and elapsed/duration
    /// display, since every Cindy variant's time cap is under an hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    static let sessionDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
