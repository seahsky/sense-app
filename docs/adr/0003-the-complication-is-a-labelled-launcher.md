# 3. The complication is a labelled launcher

Date: 2026-09-05

## Status

Accepted

## Context

SENSE gained a watchOS complication: a tile on the watch face that starts a Cindy.

Every fitness complication a reader has ever seen shows a number.
Rings show today's progress, run trackers show last week's distance, and the reflex is to assume a complication that shows none is unfinished.
This one shows none, and it shows a word instead.
The reasons are structural, and without them written down the next person to open `SenseComplication/` will read the design as laziness and start "fixing" it.

Three constraints set the shape of the whole feature.

**A widget extension cannot start a workout.**
It is a separate process from `SenseWatch`, it has no `com.apple.developer.healthkit` entitlement, and it has no `WKBackgroundModes = workout-processing`.
`CMBatchedSensorManager` delivers no motion samples without an active `HKWorkoutSession`, and only the app can own one.
So a tap cannot *be* the start; it can only be an instruction to the app to start.

**A widget extension cannot read this app's data.**
The watch's SwiftData store lives in the app's own container, and this repo has no App Group.
HealthKit is not a back door either: the extension has no HealthKit entitlement to read with, and the `HKWorkout` the app writes carries per-movement metadata (movement identity plus the round an activity belongs to) rather than the finished rounds-plus-reps score.
The score `17+8` exists in exactly one place, and the extension cannot reach it.

**watchOS has no complication configuration UI.**
Apple states it plainly: "watchOS doesn't offer a dedicated user interface to configure data that appears on a complication. Use intent recommendations in watchOS to offer preconfigured complications."
There is no parameter editor on the wrist, no "Edit Complication" sheet, and no way to change a complication's configuration after it is on a face.
Whatever the athlete picks in the face gallery is what that tile does forever.

## Decision

Ship one WidgetKit complication in a new `SenseComplication` app-extension target, with no App Group, no shared storage, no SwiftData and a single-entry timeline on `.never`.
One tap means launch-then-auto-start: one `widgetURL` at the root of the entry view produces `sense://start?variant=<rawValue>`, and `ContentView.onOpenURL` parses it and consumes it through one guarded function.

**The tile shows what the tap will start, not what the athlete last scored.**
This is a storage boundary, not an omission.
Buying a score line means an App Group, a container migration for the existing store, and a second SwiftData reader in a second process contending with the app while a workout is running.
That is a permanent architectural cost for one subtitle, and the subtitle would still be wrong for phone-logged sessions, which never reach the watch's store at all.
Apple's own guidance sanctions an app-mark launcher when there is nothing honest to show, and there is nothing honest to show.
The trigger to revisit is the first time something *else* in the product needs shared storage, not this feature on its own.
The rectangular family's second row is deliberately built as a slot, so the day an App Group arrives `Last 17+8 · 6d` drops into it with no relayout.

**The widget is an `AppIntentConfiguration` even though watchOS has no configuration UI.**
`recommendations()` *is* the configuration UI on watchOS.
It is also a protocol requirement of `AppIntentTimelineProvider` with no default implementation, verified at `WidgetKit.swiftinterface:1117`, so an `AppIntentConfiguration` widget has to write the function either way.
Returning five preconfigured rows and returning `[]` cost the same number of lines, and one of them is useless.
So the face gallery lists one row per `CindyVariant` in `allCases` order, Rx first, and the athlete picks Rx or Baby Cindy when they add the tile.
The tile then says which Cindy the tap will start: `CINDY` / `SCALED` / `BABY` / `VEST` / `HARD` on the bezel, the variant name and cap in the rectangular and inline families.

**The intent's parameter is a `String` raw value, not an `AppEnum`.**
This looks like a shortcut and is the opposite of one.
Conforming the imported `SenseKit.CindyVariant` to `AppEnum` retroactively is not a warning to silence, it is a hard build failure, reproduced in full:

```
error: Type '(CindyVariant)' cases not found, enums implemented in an imported framework or library are not supported
error: The property 'allCases' must be implemented when conforming to 'AppIntents.AppEnum', and a compile-time static value must be provided
error: The property 'typeDisplayRepresentation' must have a compile-time static value and cannot be computed or dynamic
```

Rewriting the statics as stored `static var`s does not help.
The usual workaround is a local mirror enum in the extension target, which duplicates all five cases in a target the SenseKit test bundle cannot import, so nothing guards the drift.
A plain `String` round-trips through `CindyVariant(rawValue:)` and needs no mirror, and the picker rows come from `recommendations()` rather than from a parameter editor that does not exist on this platform.
Verified that the `String` form extracts `StartCindyIntent`, `variantRawValue` and the `"rx"` default into the extension's `Metadata.appintents`, and that no AppIntents metadata leaks into `SenseWatch` or `SenseApp`.
**Anyone who "fixes" this into an `AppEnum` breaks CI.**

**A tap starts the clock when HealthKit is already authorized, and lands on the Start screen when it is not.**
`consumePendingStart()` asks `HealthKitAuthManager.needsAuthorizationPrompt()` before starting anything.
When the answer is yes, the link is consumed and dropped, and the athlete arrives on the Start screen with the tapped variant already in the chip.
Starting a countdown behind a permission modal the athlete cannot see past is worse than not starting at all: the clock runs, the reps do not get logged, and the first thing they see is a sheet.
This costs one tap, once per install.

The gap in this, recorded rather than hidden: `requestAuthorization` does not throw when the athlete *denies* sharing.
A denied install therefore looks identical to an authorized one at start, runs the full cap, and fails only at save.
That is true of the Start button today and this feature does not change it, but a permanent wrist-mounted trigger raises how often anyone meets it.

**An untouched complication-started attempt is discarded, and after two minutes abandoned outright.**
A complication is a one-tap trigger that lives on a wrist, so it will fire against a doorframe and inside a bag.
Two pure rules in `SenseKit/Tracking/UnattendedStart.swift` decide what that costs.
If the athlete notices and presses End having never asserted a rep, the attempt goes through `HKWorkoutBuilder.discardWorkout()` instead of `finishWorkout()`, no `HKWorkout` is written, no history row is inserted, and the app returns to the Start screen.
If the athlete never notices, the app ends the attempt itself after 120 seconds of nothing asserted.
That second rule is the one that matters: every design that only fires on End lets an unnoticed sleeve tap run a silent full 20:00 into Health.
Both rules are scoped to `StartTrigger.complication`; an attempt begun on the Start button had the athlete's eyes on it and is never torn down behind their back, however empty.

Both rules read `RoundRepTracker.hasAssertedARep` rather than the score's own `totalRepsLogged`, and that distinction is the one correctness trap here.
The count is `events.count`, which the undo button and a backwards Digital Crown both drive down; an athlete who logs three reps, corrects a miscount back to zero and then ends is at a score of `0+0` while having plainly been at their watch.
`hasAssertedARep` is set by the athlete's own reps and never cleared, so it answers the question these rules are actually asking — was anybody here — rather than the question the score answers.

The 120 seconds is a judgement call about which mistake is worse.
`RoundRepTracker`'s detected-rep gate refuses to open a movement block until the athlete asserts a rep, so an untouched attempt means nothing has been tapped at all, and a real Cindy round runs 60 to 70 seconds.
Two silent minutes is not a session anybody is doing.
The window is generous on purpose, because killing a real attempt is worse than leaving a stray sample in Health.
Revisit only if a real session is ever killed.

**`ContentView.selectedVariant` becomes persisted.**
It moves from `@State` to `@AppStorage("selectedVariant")`, and a consumed deep link writes the tapped variant back into it.
This is a user-visible change beyond the complication: an athlete who only does Baby Cindy no longer re-picks it on every launch.
It is also what stops the complication becoming a second source of truth, because the tile and the Start screen chip converge on one stored value instead of drifting apart.

## Consequences

The complication costs no timeline budget and no battery.
One entry on `.never` never refreshes, because there is nothing that can go stale.

Two complications of the same family on one face are visually identical in `accessoryCircular`, which has no room for a word.
Both work and both carry their own variant in their own `widgetURL`, but the athlete cannot tell them apart by looking.
For Rx and Baby Cindy side by side, use two different families: corner carries the curved word, rectangular the sub-line, inline the text.

`discardWorkout()` does not undo everything.
HealthKit's own documentation is explicit that samples already added to the workout are not deleted, so a discarded attempt leaves behind whatever heart-rate and active-energy samples were collected before it ended.
For a sub-two-minute untouched attempt that is a handful of samples and no workout, which is the best outcome available without deleting objects this app did not create.

Apple's HIG warns that "a static complication that doesn't display meaningful data may be less likely to remain in a prominent position on the watch face."
That cost is accepted knowingly, and it is the thing an App Group would buy back if one ever arrives for another reason.

Smart Stack relevance is unblocked but not wired.
Choosing `AppIntentConfiguration` is what makes `RelevantIntentManager.shared.updateRelevantIntents(...)` possible later, since `RelevantIntent.init` refuses a `StaticConfiguration` widget.
The concrete next step, when someone wants it, is to compile `StartCindyIntent.swift` into the watch app as well as the extension and accept AppIntents metadata extraction in that target.

**One thing in this design is unverified, and it is the load-bearing one.**
Whether a complication tap reaches `.onOpenURL` on watchOS cannot be settled off-device.
`xcrun simctl openurl` is unsupported on the watchOS simulator and fails with `LSApplicationWorkspaceErrorDomain` 115 even for `music://`, so no simulator run proves anything either way.
Two Apple Developer Forums threads report `.onOpenURL` never firing from a complication tap, the more recent one with `CFBundleURLTypes` correctly registered and no replies, while Apple's own watchOS tutorials teach the pattern as working.
The hardware tap is therefore the first task in the implementation order, before any complication view is written.
If it fails, the fallback is confined to one file, because `SenseDeepLink.init(url:)` takes a bare `URL`: add `@WKApplicationDelegateAdaptor` to `SenseWatchApp` and implement `handleActivity(_:)`.
That fallback is degraded rather than equivalent, since the delivered `NSUserActivity` carries the widget kind and family but no variant, and recovering the variant would need `WidgetCenter.shared.getCurrentConfigurations` plus `WidgetInfo.widgetConfigurationIntent(of:)`.

Related and also unverified off-device: whether the face gallery renders a distinct preview per recommendation row.
Apple's wording, "preconfigured complications", only makes sense if it does, but nothing documents how a row's caption composes with `configurationDisplayName`.
If the five rows turn out to render identically, the install story in the README needs rewriting.

## Alternatives considered

**`StaticConfiguration`.**
Simpler by one file and one protocol conformance, and it was the first shape considered.
Rejected because it forfeits two things permanently: the tile can never say which Cindy it starts, so a Baby Cindy athlete taps a tile that reads the same as an Rx one, and `RelevantIntent.init` refuses a `StaticConfiguration` widget, which closes the Smart Stack door at watchOS 10 for good.
The saving it buys is not real: `recommendations()` is a required member with no default, so the configurable version's only extra cost is the five lines that fill it in.

**A local mirror `AppEnum` in the extension target.**
This is the standard workaround for the retroactive-conformance failure, and it compiles.
Rejected because it duplicates all five `CindyVariant` cases in a target that `SenseKitTests` cannot import, so a sixth variant added in `SenseKit` leaves the complication silently one case short with nothing in CI to catch it.
A `String` parameter has no second list to keep in step.

**An App Group, with a shared snapshot of the last session.**
The rich version of this feature: a sub-line reading `Last 17+8 · 6d`, which is what a reader expects a fitness complication to show.
Rejected on cost and on honesty.
The cost is a shared container, a migration of the existing store into it, and a second SwiftData reader in a second process contending with the app mid-workout, for one line of text.
The honesty problem is worse: the watch's store never sees a session logged on the phone, so the days-since number would be knowingly wrong for anyone who backfills on the iPhone, and CI cannot see an entitlement at all so nothing would test it.

**`Button(intent:)` starting the workout inside the extension.**
It compiles at watchOS 10, and it is the shape people reach for when they want a tap to *do* something rather than open something.
Rejected because the extension physically cannot do the thing.
No HealthKit entitlement means no `HKWorkoutSession`, no `workout-processing` background mode means nothing survives the tap, and `CMBatchedSensorManager` yields no samples without a session, so the intent could at best set a flag and hope.
Apple's interactivity guidance lists no watchOS family as supporting interactive widgets and says verbatim that an interaction whose job is to open the app should use `Link` and `widgetURL(_:)`.
`ForegroundContinuableIntent`, the API that would let an intent hand off to the app, is `@available(watchOSApplicationExtension, unavailable)`, so this route has no graceful fallback either.
The weaker version of the same idea, an intent whose only job is to bring the app forward through `openAppWhenRun`, adds a process hop and still has to carry the variant somewhere.
The URL already carries it, in the shape Apple's own guidance names.

**Multiple `Link`s for multiple tap targets, instead of one `widgetURL`.**
Attractive for the rectangular family: tap the word for Rx, tap the mark for the last variant.
Rejected because three of the four watchOS families are single-glyph slots with no room for two targets, and nothing in the SDK states that the system creates separate tap regions in accessory families on watchOS at all.
Apple documents the behaviour of a second `widgetURL` in the same hierarchy as undefined, so the choice is one reliable target or an untestable guess.

**Five separate `Widget` types, one per variant.**
It removes the intent entirely and gives the face gallery five obviously distinct entries.
Rejected because it multiplies the widget kind by five, puts five SENSE entries in the gallery competing with each other, and makes adding a sixth variant a target-configuration change rather than a `CindyVariant` change.
`recommendations()` produces the same five rows from one widget and one enum.

**Reusing `WebMotif` for the mark.**
The app already draws its own identity in `SenseUI/SenseMotif.swift`, and reusing it is the DRY answer.
Rejected on measurement, not on taste.
Apple's complication guidance sets a 2 pt floor on line width; the app icon's stroke is 2.5% of its width, which is 1.05 pt inside a 42 pt circular content box, and `WebMotif` is thinner still at 0.9 pt rings and 0.6 pt radials.
Both render as sub-pixel dotted noise on a watch display.
`CindyMark` therefore re-weights the mark instead of scaling it, which is `WebIntensity`'s own rule applied one surface further out: how much web gets drawn is a property of the surface, and a complication is a surface where contrast is scarce.

**Two-letter variant tags (RX / SC / BC / WV / HC) in the circular dial.**
The direct fix for two identical circular tiles on one face.
Rejected because the tags are invented vocabulary appearing nowhere else in the product, and because they replace the mark's centre disc.
That makes every athlete with a single dial pay a permanent recognition cost to disambiguate a second dial they never installed.
The variant word went to `widgetLabel` instead, where it is free on the faces that render it and absent on the ones that do not.
