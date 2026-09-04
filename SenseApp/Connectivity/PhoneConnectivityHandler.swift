import Foundation
import SwiftData
import SenseKit

/// Receives completed-session events forwarded from the Watch and inserts them
/// into the iPhone's own local `ModelContext`.
///
/// NOTE on the architecture spec vs. the implemented `SenseKit`: the spec's file
/// tree describes this type as a "WCSessionDelegate impl: decodes payload, inserts
/// into iPhone ModelContext". In the `SenseKit` package as actually built,
/// `WatchConnectivityBridge` itself is the `WCSessionDelegate` and already does the
/// `SessionPayload` decoding internally (in `session(_:didReceiveUserInfo:)`); the
/// only public hook it exposes to app code is `SenseConnectivityDelegate`. So this
/// type conforms to `SenseConnectivityDelegate` instead of `WCSessionDelegate`
/// directly and receives an already-decoded `CindySession` — the "insert into the
/// iPhone ModelContext" half of the job is still exactly this type's
/// responsibility, just one layer up from raw payload bytes.
final class PhoneConnectivityHandler: SenseConnectivityDelegate {
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
