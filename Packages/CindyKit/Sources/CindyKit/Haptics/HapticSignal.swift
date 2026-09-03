#if os(watchOS)
import WatchKit

/// Maps app events to `WKHapticType` so the athlete gets tap/round/finish
/// confirmation without looking at the screen. `WKInterfaceDevice.current().play(_:)`
/// is verified to fire even while the app is in the background, specifically
/// because an active `HKWorkoutSession` keeps the extension running.
///
/// The set is deliberately small and each case is deliberately distinguishable by
/// feel alone, because mid-AMRAP the wrist is the only channel that reliably
/// works — the athlete is hanging from a bar or face-down on the floor and cannot
/// see the screen. The distinction that matters most is `repLogged` versus
/// `repDetected`: "I told the watch" must not feel like "the watch decided".
public enum HapticSignal {
    /// The athlete asserted a rep, by tap or crown.
    case repLogged
    /// A rep was removed. Deliberately the mirror of `repLogged` rather than the
    /// same signal: adding and removing a rep are opposite corrections and must
    /// not feel identical on a wrist that is not being looked at.
    case repUndone
    /// The motion detector inferred a rep. Softer and directional, so an
    /// unexpected one is noticeable without being alarming.
    case repDetected
    /// The sequence moved on to the next movement. Always fires, whoever caused
    /// the rep that triggered it — a movement change the athlete did not expect
    /// is exactly the event they most need to feel.
    case movementChanged
    case roundCompleted
    case sessionFinished
    /// Automatic detection stopped working mid-session. Fires once, never
    /// repeatedly: losing the assistant is worth one interruption, not a nag.
    case detectionLost

    public func play() {
        switch self {
        case .repLogged:
            WKInterfaceDevice.current().play(.click)
        case .repUndone:
            WKInterfaceDevice.current().play(.directionDown)
        case .repDetected:
            WKInterfaceDevice.current().play(.directionUp)
        case .movementChanged:
            WKInterfaceDevice.current().play(.start)
        case .roundCompleted:
            WKInterfaceDevice.current().play(.success)
        case .sessionFinished:
            WKInterfaceDevice.current().play(.notification)
        case .detectionLost:
            WKInterfaceDevice.current().play(.failure)
        }
    }
}
#endif
