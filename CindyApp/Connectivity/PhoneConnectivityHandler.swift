import Foundation
import SwiftData
import CindyKit

/// Receives completed-session events forwarded from the Watch and inserts them
/// into the iPhone's own local `ModelContext`.
///
/// NOTE on the architecture spec vs. the implemented `CindyKit`: the spec's file
/// tree describes this type as a "WCSessionDelegate impl: decodes payload, inserts
/// into iPhone ModelContext". In the `CindyKit` package as actually built,
/// `WatchConnectivityBridge` itself is the `WCSessionDelegate` and already does the
/// `SessionPayload` decoding internally (in `session(_:didReceiveUserInfo:)`); the
/// only public hook it exposes to app code is `CindyConnectivityDelegate`. So this
/// type conforms to `CindyConnectivityDelegate` instead of `WCSessionDelegate`
/// directly and receives an already-decoded `CindySession` — the "insert into the
/// iPhone ModelContext" half of the job is still exactly this type's
/// responsibility, just one layer up from raw payload bytes.
final class PhoneConnectivityHandler: CindyConnectivityDelegate {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// `WatchConnectivityBridge` always dispatches this callback onto the main
    /// thread (see its `didReceiveUserInfo` implementation), so it's safe to touch
    /// `modelContext` — the app's main `ModelContext` — directly here.
    func connectivity(_ bridge: WatchConnectivityBridge, didReceiveCompletedSession session: CindySession) {
        modelContext.insert(session)
        try? modelContext.save()
    }
}
