import Foundation
import Observation

/// State machine for a 20:00 (or other capped) AMRAP countdown.
///
/// `activeInterval` exposes a single `ClosedRange<Date>` suitable for
/// `Text(timerInterval:)`/`ProgressView(timerInterval:)`, which read the system
/// clock directly and have no notion of "pause" on their own. To keep them
/// accurate across pause/resume without redrawing every tick ourselves, the
/// range's lower bound is a "virtual start" that gets shifted forward by exactly
/// the paused duration on every `resume(at:)` — so elapsed-since-virtual-start
/// always equals actual active (non-paused) time.
@Observable
public final class AmrapTimerEngine {
    public enum Phase: Equatable {
        case idle
        case running
        case paused
        case finished
    }

    public private(set) var phase: Phase = .idle
    public let capSeconds: TimeInterval

    private var virtualStart: Date?
    private var pauseBeganAt: Date?
    private var frozenElapsed: TimeInterval?

    public init(capSeconds: TimeInterval = 1200) {
        self.capSeconds = capSeconds
    }

    public var activeInterval: ClosedRange<Date>? {
        guard let virtualStart else { return nil }
        return virtualStart...virtualStart.addingTimeInterval(capSeconds)
    }

    public func start(at date: Date = .now) {
        guard phase == .idle else { return }
        virtualStart = date
        pauseBeganAt = nil
        frozenElapsed = nil
        phase = .running
    }

    public func pause(at date: Date = .now) {
        guard phase == .running else { return }
        pauseBeganAt = date
        phase = .paused
    }

    public func resume(at date: Date = .now) {
        guard phase == .paused, let pauseBeganAt, let virtualStart else { return }
        let pausedDuration = date.timeIntervalSince(pauseBeganAt)
        self.virtualStart = virtualStart.addingTimeInterval(pausedDuration)
        self.pauseBeganAt = nil
        phase = .running
    }

    public func finish(at date: Date = .now) {
        guard phase == .running || phase == .paused else { return }
        frozenElapsed = elapsed(at: date)
        phase = .finished
    }

    public func reset() {
        phase = .idle
        virtualStart = nil
        pauseBeganAt = nil
        frozenElapsed = nil
    }

    public var elapsed: TimeInterval {
        elapsed(at: .now)
    }

    public var remaining: TimeInterval {
        max(0, capSeconds - elapsed)
    }

    private func elapsed(at date: Date) -> TimeInterval {
        switch phase {
        case .idle:
            return 0
        case .running:
            guard let virtualStart else { return 0 }
            return min(max(0, date.timeIntervalSince(virtualStart)), capSeconds)
        case .paused:
            guard let virtualStart, let pauseBeganAt else { return 0 }
            return min(max(0, pauseBeganAt.timeIntervalSince(virtualStart)), capSeconds)
        case .finished:
            return frozenElapsed ?? capSeconds
        }
    }
}
