import SwiftUI
import WatchKit

/// Size constants for a live-workout screen that must fit without scrolling.
///
/// The binding constraint is the 40mm display — Series 4/5/6 and every SE
/// generation — at **162 × 197 points**. That is both the narrowest and the
/// shortest screen any watchOS 10+ device has, so a layout that fits there fits
/// everywhere. Apple publishes these in pixels; points are pixels ÷ 2, because
/// `WKInterfaceDevice.screenScale` is documented as exactly 2.0 on Apple Watch.
///
/// Apple publishes **no** safe-area inset numbers for watchOS, and
/// `screenBounds`' own documentation warns that it "may be different from the
/// rectangle used to display your app's content". The rounded corners and the
/// system time band both eat into it, so the working figure below is deliberately
/// pessimistic: roughly 163 pt of usable height at 40mm, not the 175 pt a naive
/// 197 − 22 would suggest.
///
/// Sizes are chosen by measured screen height rather than by
/// `containerRelativeFrame`, on purpose. `containerRelativeFrame` divides
/// whatever container it happens to land in, and on watchOS that container is not
/// reliably the padded content area — a horizontal `count:` over a padded row
/// silently overflows because it measures the unpadded screen. Branching on a
/// number the system reports removes the ambiguity entirely.
enum WatchLayout {
    static var screenSize: CGSize { WKInterfaceDevice.current().screenBounds.size }

    /// 40mm (197 pt tall) and nothing else. Every other supported size is ≥ 215 pt.
    static var isCompact: Bool { screenSize.height < 205 }

    /// Pessimistic usable content height, after the system time band.
    static var usableHeight: CGFloat { screenSize.height - 34 }

    static var clockFontSize: CGFloat { isCompact ? 30 : 34 }

    static var movementFontSize: CGFloat { isCompact ? 17 : 20 }

    /// The one control the athlete hits blind, so it grows with the glass while
    /// the readouts stay put — muscle memory wants the numbers in the same place
    /// on every watch, and the thumb wants as much target as the screen can give.
    /// Never below 44 pt, watchOS's minimum touch target.
    static var actionHeight: CGFloat {
        let height = screenSize.height
        if height < 205 { return 56 }   // 40mm
        if height < 235 { return 64 }   // 41 / 42 / 44mm
        return 74                       // 45 / 46 / 49mm
    }

    static var pipHeight: CGFloat { isCompact ? 7 : 9 }

    /// Diameter of the Start screen's circular primary action.
    ///
    /// Bounded by height, not width. The Start screen still has to carry the
    /// movement sequence and the auto-count toggle under the button, so the circle
    /// gets what is left after those, capped so it never crowds the 162 pt width.
    static var startDiameter: CGFloat {
        let height = screenSize.height
        if height < 205 { return 92 }    // 40mm
        if height < 235 { return 104 }   // 41 / 42 / 44mm
        return 116                       // 45 / 46 / 49mm
    }

    /// Kept at or above `SenseFont.minimumDisplaySize` on every screen size: the
    /// display face loses its counters below 13 pt on a dark ground.
    static var startLabelSize: CGFloat { isCompact ? 20 : 24 }

    /// Apple's HIG for watchOS: "Design your content to extend from one edge of
    /// the screen to the other… consider minimizing the padding between
    /// elements." At 162 pt wide, every point spent on a margin is a point the
    /// numbers do not get.
    static let horizontalMargin: CGFloat = 4
}
