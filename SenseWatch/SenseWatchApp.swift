import SwiftUI
import SwiftData
import SenseKit
import SenseUI

/// watchOS app entry point. Owns the watch's own local (non-CloudKit)
/// `ModelContainer` — per the architecture spec, each device keeps an independent
/// SwiftData store; a finished session reaches the phone only via
/// `WatchConnectivityBridge.sendCompletedSession(_:)`, never through shared storage.
///
/// This is a modern single-target SwiftUI watchOS app (watchOS 10+): there is no
/// WatchKit Extension bundle and no `WKExtensionDelegate` — the `HKWorkoutSession`
/// itself is what keeps the app alive for the full 20:00 AMRAP, per the spec's
/// explicit decision not to use `WKExtendedRuntimeSession`.
@main
struct SenseWatchApp: App {
    private let modelContainer: ModelContainer

    init() {
        // Must run before any view is built: the display face lives in the
        // SenseUI package bundle, which UIAppFonts cannot see.
        SenseFont.register()

        let container: ModelContainer
        do {
            container = try SessionSchema.makeLocalContainer()
        } catch {
            fatalError("Failed to create local SENSE ModelContainer: \(error)")
        }
        modelContainer = container

        WatchConnectivityBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
