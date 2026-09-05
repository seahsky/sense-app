# S.E.N.S.E.

SENSE (Sets, Effort, Notes, Streaks, Elapsed) is a local-only iOS + watchOS app for
tracking the CrossFit benchmark workout **"Cindy"**:
a 20-minute AMRAP (As Many Rounds As Possible) of 5 pull-ups, 10 push-ups, and 15 air
squats, scored as rounds-plus-reps (e.g. `17+8`). The app runs the countdown, lets you
log each rep round-by-round, and — on the Watch — records heart rate and active energy
through HealthKit and saves the attempt as a workout in Health.

**SENSE is the app; Cindy is the workout.** That distinction is deliberate and it is
visible in the code: the shell is named `SenseApp` / `SenseWatch` / `SenseKit`, while the
domain types that model the workout keep their name (`CindySession`, `CindyVariant`).
See [CONTEXT.md](CONTEXT.md) for the glossary and
[docs/adr/0001](docs/adr/0001-sense-is-the-product-cindy-is-the-workout.md) for why.

Everything is local: there is no backend, no account, and no CloudKit sync. Each
device (iPhone and Watch) keeps its own independent on-device store; a finished
Watch session is relayed to the iPhone over Watch Connectivity, not through shared
storage.

## What tracking is actually automatic, and what's manual

**Automatic, with the athlete closing every set: reps on the Watch.** The Watch
counts reps from wrist motion while you work, using a classical signal-processing
pipeline (band-pass → principal-component projection → autocorrelation-refined
peak counting) run only for the movement the app already knows you are on. No
machine-learning model, no training, no server — see
[docs/research/automatic-rep-detection.md](docs/research/automatic-rep-detection.md)
for why a trained model is the wrong first step here.

The detector is never allowed to open a movement or to close one. It can log
three of your five pull-ups, eight of ten push-ups, thirteen of fifteen air
squats — the rep that starts a block and the rep that moves the sequence on both
come from you. Published accuracy for these three movements runs 80–88% of sets
within ±1 rep (the air squat is the worst), which means a counter you cannot
audit would be useless: you would have to count in your head to notice an error,
which is the whole labour the feature removes. You always know whether you have
*started* and whether you have *finished*, so the app asks only that: **keep
tapping "+1 REP" until it moves on.** A round costs six taps instead of thirty.

Requiring the opening tap is what stops the detector counting while you are still
walking from the bar to the floor, which is where nearly every phantom rep came
from — see
[docs/research/rep-detection-precision.md](docs/research/rep-detection-precision.md).
It is also the only defence that reaches the air squat, because two of the three
movements anchor your wrist to something that does not move and the squat does
not:
[docs/research/posture-aware-rep-detection.md](docs/research/posture-aware-rep-detection.md).

Every rep records where it came from, and the live screen shows it — solid pips
for reps you asserted, hollow for the watch's guesses, in the order they actually
happened. A long press on undo strikes every automatic rep in the movement you
are on, without touching anything you logged by hand and without reaching back
into a movement you already finished. Auto-count can be switched off before a
session, and everything still works: the manual "+1 REP" button is the ground
truth, and the Digital Crown becomes available as a second manual input.

**Automatic: rest detection.** No sensor involved. Every rep is already a
timestamped event, so rest is just "twelve seconds since the last one" — no
motion classifier to tune, no false positives from sensor noise.

**Automatic: the workout session, heart rate, and energy — on the Watch.** Starting a
session on the Watch starts a real `HKWorkoutSession` + `HKLiveWorkoutBuilder`
(activity type `.crossTraining`), which the OS keeps running in the background for the
full 20:00 cap without any extra code to keep the app alive. That session is also
what makes motion sensing possible at all — `CMBatchedSensorManager` delivers no
data without one. Each movement is recorded into the saved workout as its own
`HKWorkoutActivity`, so Health shows per-movement timing and heart rate. While it runs, live heart
rate streams in automatically and is shown on screen; average heart rate and total
active energy burned are computed automatically when the session ends and are saved
with the session. The finished workout is written to Health automatically too. None of
this happens on the iPhone-only flows (Tracker tab, manual backfill) — those compute
duration from the app's own timer and have no heart rate or energy data unless you
type it in by hand.

**One tap, from the watch face.** A SENSE complication starts a session with the
variant that complication was configured with when it was added to the face — Rx and
Baby Cindy are two different tiles, not one tile in two moods, because watchOS offers
no way to edit a complication's configuration afterwards.
The tap is meant to launch the app and start the clock, with everything after that
the normal flow — but whether a complication tap reaches the app at all on watchOS is
unverified off-device, so treat check 5 below as the gate.
An attempt started this way that you never touch is discarded rather than saved — when
you end it, or by itself after two minutes if you never noticed the tap.
No workout is written; the heart-rate and energy samples HealthKit had already
collected stay in Health, because `discardWorkout()` does not delete them.
See [docs/adr/0003](docs/adr/0003-the-complication-is-a-labelled-launcher.md).

## Variants

| Variant | Time cap | Movements |
|---|---|---|
| Rx | 20:00 | 5 pull-ups / 10 push-ups / 15 air squats |
| Scaled | 20:00 | Same reps, scaled movement execution (e.g. banded pull-ups, box push-ups) |
| Baby Cindy | 12:00 | Same reps, shorter cap |
| Weighted Vest | 20:00 | Same reps, with a vest |
| Hard Cindy | 20:00 | Same reps, heavier/harder standard |

## Repo layout

```
sense-app/
├── project.yml                    XcodeGen spec — generates Sense.xcodeproj
├── CONTEXT.md                     Domain glossary (SENSE vs Cindy, rounds vs sets)
├── docs/adr/                      Architecture decision records
├── Tools/make-icons.py            Regenerates the app icons from SVG
├── .gitignore
├── Packages/SenseUI/               Design system: palette, typography, web motif
│   └── Sources/SenseUI/Resources/  Zilla Slab subset + its OFL licence text
├── Packages/SenseKit/              Shared Swift package (iOS 17+ / watchOS 10+)
│   ├── Sources/SenseKit/
│   │   ├── Models/                 CindySession (SwiftData @Model), CindyVariant, Movement
│   │   ├── Tracking/                AmrapTimerEngine (pause-aware countdown), RoundRepTracker
│   │   │                            (score + rep events + the boundary gate), RepEvent,
│   │   │                            RestDetection (sensor-free, pure), UnattendedStart
│   │   │                            (the two rules for a mis-tapped complication)
│   │   ├── Sensing/                 The rep counter, all pure and Foundation-only:
│   │   │                            Bandpass (Butterworth biquads), PrincipalAxis (PCA),
│   │   │                            RepPeakCounter (RecoFit's three passes),
│   │   │                            RepDetectionEngine (rolling buffer, stateless recount),
│   │   │                            MotionSample + Decimator
│   │   ├── Connectivity/            SessionPayload (Codable DTO), WatchConnectivityBridge (WCSession)
│   │   ├── Routing/                 SenseDeepLink (the sense:// contract) + StartTrigger
│   │   ├── Haptics/                 HapticSignal (watchOS-only)
│   │   └── Analytics/                TrendAnalytics (personal records, pace, projections)
│   └── Tests/SenseKitTests/         Unit tests, incl. synthetic-signal tests for the counter
├── SenseApp/                       iOS app target
│   ├── SenseApp.swift               App entry point, local ModelContainer
│   ├── Connectivity/                 PhoneConnectivityHandler (receives finished Watch sessions)
│   └── Views/
│       ├── RootTabView.swift         Timer / Tracker / Trend tabs
│       ├── Timer/                    Live Watch mirror, or a phone-only AMRAP timer
│       ├── Tracker/                  Full iPhone-only session flow + manual backfill/edit
│       ├── Trend/                    History, personal records, Swift Charts trend lines
│       └── Shared/                   Variant picker, formatting helpers
├── SenseComplication/              watchOS complication, embedded inside the Watch app
│   ├── Info.plist                    NSExtension point identifier, and nothing else
│   ├── SenseComplicationBundle.swift @main; registers the display face in this process
│   ├── StartCindyIntent.swift        Configuration intent — a String variant, never an AppEnum
│   ├── StartCindyComplication.swift  The Widget, its entry, a one-entry never-refresh provider
│   ├── StartCindyEntryView.swift     Per-family layout, the one widgetURL, the spoken labels
│   └── CindyMark.swift               The app mark re-weighted for a 42pt content box
└── SenseWatch/                     watchOS app target (single-target, no WatchKit Extension)
    ├── SenseWatchApp.swift          App entry point, local ModelContainer
    ├── Info.plist / .entitlements    HealthKit usage strings + capability
    ├── Workout/                      HealthKitAuthManager, WorkoutSessionManager (HKWorkoutSession
    │                                 + per-movement HKWorkoutActivity), MotionRepSensor
    │                                 (the only Core Motion file in the repo)
    └── Views/                       Start → Active → Summary flow, all single-screen with no
                                     ScrollView; RepPipRow (rep provenance), WatchLayout, RepLogging
```

`SenseKit` is the single source of truth for the data model, timer/score logic, and
the Watch↔iPhone bridge, so both app targets score and format a session identically.
It also holds the whole rep-detection algorithm: `Sensing/` imports nothing but
Foundation, so the counter is exercised against synthetic signals on an iOS
simulator, and `MotionRepSensor` on the Watch does nothing but acquire samples and
hand them over.

## Setup (macOS)

1. Install Xcode (26 or newer recommended, with iOS 17+ and watchOS 10+ SDKs) from
   the App Store or [developer.apple.com](https://developer.apple.com/xcode/).
2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) via Homebrew:
   ```
   brew install xcodegen
   ```
3. From the repo root, generate the Xcode project:
   ```
   xcodegen generate
   ```
   This reads `project.yml` and produces `Sense.xcodeproj` (git-ignored — regenerate
   it any time with the same command instead of committing it).
4. Open `Sense.xcodeproj` in Xcode.
5. Select the **SenseApp** scheme.
6. Choose a run destination: a paired iPhone + Apple Watch simulator (e.g. "iPhone 16
   Pro + Apple Watch Series 10" in the scheme's device list), or a physical
   iPhone paired with a physical Apple Watch. Building `SenseApp` automatically embeds
   and installs `SenseWatch` as its companion Watch app, and `SenseWatch` in turn
   embeds `SenseComplication` in its `PlugIns/` folder — so the complication ships
   with the Watch app and needs no scheme or run destination of its own.
7. Build and run (⌘R).
8. On first launch of a session on the Watch, grant the HealthKit permissions when
   prompted:
   - **Share**: Workouts (so a completed Cindy attempt can be saved as an `HKWorkout`)
   - **Read**: Heart Rate, Active Energy Burned, Workouts (so the live workout builder
     can report stats during and after the session)

   No permissions are needed on the iPhone side — `SenseApp` never calls HealthKit
   directly; it only receives already-finished sessions from the Watch over Watch
   Connectivity.

## Build status

[![Build](https://github.com/seahsky/sense-app/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/seahsky/sense-app/actions/workflows/build.yml)

This project was generated without local access to Xcode or the Swift toolchain, so
`.github/workflows/build.yml` runs `xcodegen generate`, then `xcodebuild build` for the
`SenseApp` scheme (which compiles and embeds `SenseWatch`, plus the `SenseKit` package
dependency, in one pass) against a real iOS Simulator on a macOS GitHub Actions runner —
and it's green: the whole app compiles clean, and all `SenseKit` unit tests (timer state
machine, round/rep scoring, session payload round-tripping, trend/PR analytics) pass via
`xcodebuild test` run directly against the package.

That covers compilation and business-logic correctness, not the on-device/simulator
experience. Before trusting this as a finished app, still:

1. Run the app on a Watch-paired simulator and walk through one full flow: start a
   session on the Watch, grant HealthKit permissions, log a few reps (button + Digital
   Crown), pause/resume, let the 20:00 (or use Baby Cindy's 12:00) cap run out or end
   it manually, confirm the Summary screen shows a score/duration, tap Save, and check
   it appears in Watch History and — via the Watch Connectivity relay — in the
   iPhone's Tracker/Trend tabs and Timer tab's Watch-mirror mode.
2. On a physical device, confirm the Health app shows the saved workout with heart
   rate and active energy, since the simulator's HealthKit data is synthetic.
3. Check the app icon on a physical device. Both catalogs are filled (iOS carries
   light, dark and tinted variants; the Watch carries a composition pulled inside
   its circular mask), and `Tools/make-icons.py` regenerates all four from SVG.
4. Add the SENSE complication to a real watch face and confirm the picker lists all
   five variants — Rx, Scaled, Baby Cindy, Weighted Vest, Hard Cindy — each drawn as
   its own row.
   Whether a row renders its own configuration is inferred from Apple's wording
   ("preconfigured complications") rather than verified; if the five rows come out
   identical, the install story above needs rewriting.
5. With the app **not running**, tap that complication and confirm the clock starts,
   and that a Baby Cindy tile counts down from 12:00 rather than 20:00.
   Nothing else can stand in for this one: `xcrun simctl openurl` is unsupported on
   the watchOS simulator and fails with `LSApplicationWorkspaceErrorDomain` 115 even
   for `music://`, so a simulator failure proves nothing either way.
   Whether a complication tap reaches `.onOpenURL` on watchOS is genuinely unsettled,
   and the fallback if it does not is written down in
   [docs/adr/0003](docs/adr/0003-the-complication-is-a-labelled-launcher.md).
6. Tap the complication, log nothing, and confirm no Cross Training workout appears
   in Health and no row appears in Watch History — both when you end the attempt by
   hand and when you put the watch down and let the app end it by itself at about two
   minutes.
   A tile on a wrist gets pressed by doorframes, and this is what stops that becoming
   a phantom 20:00 in your Health data.
7. Put all four families on at least two faces — one multicolour Infograph and one
   with an accent colour, plus X-Large if you have it — so the mark is seen in both
   `.fullColor` and `.accented`.
   Accented rendering discards colour and paints from the alpha channel, and which of
   the two groups gets the accent flips between faces, so both assignments have to
   read as a ring around a dot.
   `CindyMark` draws its ring into a `Canvas`, and whether a rasterised canvas
   contributes the alpha that pass expects is unverified — if the ring fills into a
   disc or vanishes, redraw it as five `Circle().trim(from:to:).stroke()` shapes at
   the same geometry.
8. On the same face, confirm "CINDY" in the rectangular family is really Zilla Slab
   and not the system fallback.
   `SenseFont.register()` is process-scoped and a failed registration in the
   extension produces no error and no crash, so compare against a build with a
   deliberately wrong PostScript name; if the two look identical, registration is not
   working.
