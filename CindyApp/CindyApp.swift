import SwiftUI
import SwiftData
import CindyKit

/// iOS app entry point. Owns the phone's own local (non-CloudKit) `ModelContainer`
/// — per the architecture spec, each device keeps an independent SwiftData store;
/// nothing here bridges to the Watch's storage directly, only finished sessions
/// arriving over `WatchConnectivityBridge` do.
@main
struct CindyApp: App {
    private let modelContainer: ModelContainer
    private let connectivityHandler: PhoneConnectivityHandler

    init() {
        let container: ModelContainer
        do {
            container = try SessionSchema.makeLocalContainer()
        } catch {
            fatalError("Failed to create local Cindy ModelContainer: \(error)")
        }
        modelContainer = container

        // `WatchConnectivityBridge.delegate` is `weak`, so this handler must be
        // retained for the app's lifetime — held here as a stored property.
        let handler = PhoneConnectivityHandler(modelContext: container.mainContext)
        connectivityHandler = handler
        WatchConnectivityBridge.shared.delegate = handler
        WatchConnectivityBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(modelContainer)
    }
}
