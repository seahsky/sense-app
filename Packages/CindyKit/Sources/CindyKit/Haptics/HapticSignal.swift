#if os(watchOS)
import WatchKit

/// Maps app events to `WKHapticType` so the athlete gets tap/round/finish
/// confirmation without looking at the screen. `WKInterfaceDevice.current().play(_:)`
/// is verified to fire even while the app is in the background, specifically
/// because an active `HKWorkoutSession` keeps the extension running.
public enum HapticSignal {
    case repLogged
    case roundCompleted
    case sessionFinished

    public func play() {
        switch self {
        case .repLogged:
            WKInterfaceDevice.current().play(.click)
        case .roundCompleted:
            WKInterfaceDevice.current().play(.success)
        case .sessionFinished:
            WKInterfaceDevice.current().play(.notification)
        }
    }
}
#endif
