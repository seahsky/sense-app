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
    /// The clock has started. Fires once, at t=0, and only when the attempt began
    /// on a complication tap rather than on the Start screen.
    ///
    /// It exists because a complication tap skips the Start screen entirely, so a
    /// cold launch from a watch face is seconds of black screen with nothing to
    /// tell the athlete the tap registered at all.
    ///
    /// **It shares `.start` with `movementChanged`, which breaks this type's own
    /// rule that every case is distinguishable by feel alone.** The exception is
    /// deliberate and it is worth stating rather than leaving to be discovered.
    /// Only two general-purpose `WKHapticType` cases are still unused — `.retry`
    /// and `.stop` — and neither means "started"; `.stop` would say the opposite of
    /// what happened. The collision is harmless because the two cases cannot occur
    /// in the same part of an attempt's timeline: `sessionStarted` fires at t=0,
    /// before any movement block exists, and `movementChanged` cannot fire until
    /// the athlete has closed a movement. There is no instant at which the athlete
    /// has to tell them apart.
    case sessionStarted
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
        case .sessionStarted:
            WKInterfaceDevice.current().play(.start)
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
