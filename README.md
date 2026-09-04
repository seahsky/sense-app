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

The detector is never allowed to close a movement. It can log four of your five
pull-ups, nine of ten push-ups, fourteen of fifteen air squats — the rep that
moves the sequence on always comes from you. Published accuracy for these three
movements runs 80–88% of sets within ±1 rep (the air squat is the worst), which
means a counter you cannot audit would be useless: you would have to count in
your head to notice an error, which is the whole labour the feature removes. You
always know whether you have *finished*, so the app asks only that, once per
movement: **keep tapping "+1 REP" until it moves on.** A round costs three taps
instead of thirty.

Every rep records where it came from, and the live screen shows it — green pips
for reps you asserted, orange for the watch's guesses. Undo strikes the trailing
run of automatic reps in one press without touching anything you logged by hand.
Auto-count can be switched off before a session, and everything still works: the
manual "+1 REP" button and the Digital Crown remain the ground truth, exactly as
before.

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
cindy-app/
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
│   │   │                            RestDetection (sensor-free, pure)
│   │   ├── Sensing/                 The rep counter, all pure and Foundation-only:
│   │   │                            Bandpass (Butterworth biquads), PrincipalAxis (PCA),
│   │   │                            RepPeakCounter (RecoFit's three passes),
│   │   │                            RepDetectionEngine (rolling buffer, stateless recount),
│   │   │                            MotionSample + Decimator
│   │   ├── Connectivity/            SessionPayload (Codable DTO), WatchConnectivityBridge (WCSession)
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
   and installs `SenseWatch` as its companion Watch app.
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

[![Build](https://github.com/seahsky/cindy-app/actions/workflows/build.yml/badge.svg?branch=claude/cindy-workout-tracker-app-u7ahnz)](https://github.com/seahsky/cindy-app/actions/workflows/build.yml)

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
