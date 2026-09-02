import Foundation
import WatchConnectivity

public protocol CindyConnectivityDelegate: AnyObject {
    func connectivity(_ bridge: WatchConnectivityBridge, didReceiveCompletedSession session: CindySession)
}

public final class WatchConnectivityBridge: NSObject {
    public static let shared = WatchConnectivityBridge()

    /// Posted (main thread) whenever `session(_:didReceiveApplicationContext:)` fires,
    /// with the raw context dictionary as `userInfo`. The public API surface here is
    /// deliberately kept to what the spec lists (`isReachable` + the single completed-
    /// session delegate callback); this notification is the minimal additive hook that
    /// lets a consumer (e.g. `TimerTabView`, owned outside this package) observe the
    /// "latest state only" live mirror described in the data-flow spec without widening
    /// `CindyConnectivityDelegate`'s contract.
    public static let liveContextDidUpdateNotification = Notification.Name("CindyKit.WatchConnectivityBridge.liveContextDidUpdate")

    public weak var delegate: CindyConnectivityDelegate?
    public private(set) var isReachable: Bool = false

    /// The most recently received application-context payload, if any — mirrors
    /// `WCSession.default.receivedApplicationContext`, the system's own cache of the
    /// last context delivered to `session(_:didReceiveApplicationContext:)`. Lets a
    /// late observer (e.g. `TimerTabView` attaching its notification loop after a
    /// context already arrived, such as on a cold launch) seed itself synchronously
    /// instead of waiting for the next `liveContextDidUpdateNotification` post.
    public var latestLiveContext: [String: Any]? {
        guard WCSession.isSupported() else { return nil }
        return WCSession.default.receivedApplicationContext
    }

    private override init() {
        super.init()
    }

    public func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Wraps `WCSession.default.transferUserInfo(_:)` — FIFO-queued and delivered by
    /// the system even while the counterpart app isn't foregrounded, unlike
    /// `sendMessage` (requires live reachability, fails otherwise) or
    /// `updateApplicationContext` alone (each call replaces the previous payload, so a
    /// second finished session before the first is delivered would silently clobber
    /// it). This is the only method used to deliver a completed session.
    public func sendCompletedSession(_ session: CindySession) {
        guard WCSession.isSupported() else { return }
        let payload = SessionPayload(session: session)
        WCSession.default.transferUserInfo(payload.asDictionary())
    }

    /// Wraps `WCSession.default.updateApplicationContext(_:)` — a cheap "latest state
    /// only" mirror of an in-progress workout. Never used for the completed-session
    /// event itself; each call replaces whatever context was previously published.
    public func publishLiveContext(elapsedSeconds: TimeInterval, completedRounds: Int, partialReps: Int) throws {
        guard WCSession.isSupported() else { return }
        let context: [String: Any] = [
            "elapsedSeconds": elapsedSeconds,
            "completedRounds": completedRounds,
            "partialReps": partialReps
        ]
        try WCSession.default.updateApplicationContext(context)
    }
}

extension WatchConnectivityBridge: WCSessionDelegate {
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let payload = SessionPayload(dictionary: userInfo) else { return }
        #if os(iOS)
        let source = SessionSource.watch
        #else
        let source = SessionSource.iPhone
        #endif
        let receivedSession = payload.makeSession(source: source)
        DispatchQueue.main.async {
            self.delegate?.connectivity(self, didReceiveCompletedSession: receivedSession)
        }
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: WatchConnectivityBridge.liveContextDidUpdateNotification,
                object: self,
                userInfo: applicationContext
            )
        }
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif
}
