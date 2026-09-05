import SwiftUI
import SenseUI

/// The extension's entry point, and the first of the two places the display face
/// gets registered in this process.
///
/// **Why `init()` exists at all.** `SenseFont.register()` passes
/// `CTFontManagerScope.process`, which Core Text documents as lasting exactly the
/// lifetime of the calling process. A widget extension is a different process from
/// `SenseWatchApp`, so the app's launch-time registration does nothing here.
/// Skipping the call does not crash and does not warn: `Font.custom` falls back to
/// the system face silently, the layout still fits, and the screenshot still looks
/// plausible — the failure is invisible unless you set the same word twice and
/// compare. A `WidgetBundle`'s `init()` runs before anything else in extension
/// start-up, so this is the earliest hook available.
///
/// `StartCindyProvider.placeholder(in:)` registers a second time as belt and
/// braces. Nothing documents an ordering guarantee between the two, and neither
/// call is expensive: `register()` guards on its own `isRegistered` flag, so
/// whichever runs first is the one that does the work.
@main
struct SenseComplicationBundle: WidgetBundle {
    init() { SenseFont.register() }

    var body: some Widget { StartCindyComplication() }
}
