# Cindy

A local-only iOS + watchOS app for tracking the CrossFit benchmark workout **"Cindy"**:
a 20-minute AMRAP (As Many Rounds As Possible) of 5 pull-ups, 10 push-ups, and 15 air
squats, scored as rounds-plus-reps (e.g. `17+8`). The app runs the countdown, lets you
log each rep round-by-round, and — on the Watch — records heart rate and active energy
through HealthKit and saves the attempt as a workout in Health.

Everything is local: there is no backend, no account, and no CloudKit sync. Each
device (iPhone and Watch) keeps its own independent on-device store; a finished
Watch session is relayed to the iPhone over Watch Connectivity, not through shared
storage.

## What tracking is actually automatic, and what's manual

**Manual: every rep and round.** There is no motion-based rep counter in this app.
HealthKit and Core Motion have no public API that reliably recognizes and counts
individual pull-ups, push-ups, or air squats — the kind of per-rep classification
that exists for the app would require training and shipping a custom motion model,
which is out of scope for a local-only single-repo build. So logging reps is a
deliberate, first-class interaction instead of a guess: tap "+1 REP" on the Watch (or
turn the Digital Crown, which logs/undoes reps one at a time with haptic feedback per
detent) or tap "+1 Rep" in the iPhone Tracker tab. The app turns that tally into the
official rounds+reps score via the fixed 5/10/15 movement sequence — you just have to
tell it when a rep happens.

**Automatic: the workout session, heart rate, and energy — on the Watch.** Starting a
session on the Watch starts a real `HKWorkoutSession` + `HKLiveWorkoutBuilder`
(activity type `.crossTraining`), which the OS keeps running in the background for the
full 20:00 cap without any extra code to keep the app alive. While it runs, live heart
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
├── project.yml                    XcodeGen spec — generates Cindy.xcodeproj
├── .gitignore
├── Packages/CindyKit/              Shared Swift package (iOS 17+ / watchOS 10+)
│   ├── Sources/CindyKit/
│   │   ├── Models/                 CindySession (SwiftData @Model), CindyVariant, Movement
│   │   ├── Tracking/                AmrapTimerEngine (pause-aware countdown), RoundRepTracker (score)
│   │   ├── Connectivity/            SessionPayload (Codable DTO), WatchConnectivityBridge (WCSession)
│   │   ├── Haptics/                 HapticSignal (watchOS-only)
│   │   └── Analytics/                TrendAnalytics (personal records, pace, projections)
│   └── Tests/CindyKitTests/         Unit tests for the above
├── CindyApp/                       iOS app target
│   ├── CindyApp.swift               App entry point, local ModelContainer
│   ├── Connectivity/                 PhoneConnectivityHandler (receives finished Watch sessions)
│   └── Views/
│       ├── RootTabView.swift         Timer / Tracker / Trend tabs
│       ├── Timer/                    Live Watch mirror, or a phone-only AMRAP timer
│       ├── Tracker/                  Full iPhone-only session flow + manual backfill/edit
│       ├── Trend/                    History, personal records, Swift Charts trend lines
│       └── Shared/                   Variant picker, formatting helpers
└── CindyWatch/                     watchOS app target (single-target, no WatchKit Extension)
    ├── CindyWatchApp.swift          App entry point, local ModelContainer
    ├── Info.plist / .entitlements    HealthKit usage strings + capability
    ├── Workout/                      HealthKitAuthManager, WorkoutSessionManager (HKWorkoutSession)
    └── Views/                       Start → Active → Summary flow, rep controls, history
```

`CindyKit` is the single source of truth for the data model, timer/score logic, and
the Watch↔iPhone bridge, so both app targets score and format a session identically.

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
   This reads `project.yml` and produces `Cindy.xcodeproj` (git-ignored — regenerate
   it any time with the same command instead of committing it).
4. Open `Cindy.xcodeproj` in Xcode.
5. Select the **CindyApp** scheme.
6. Choose a run destination: a paired iPhone + Apple Watch simulator (e.g. "iPhone 16
   Pro + Apple Watch Series 10" in the scheme's device list), or a physical
   iPhone paired with a physical Apple Watch. Building `CindyApp` automatically embeds
   and installs `CindyWatch` as its companion Watch app.
7. Build and run (⌘R).
8. On first launch of a session on the Watch, grant the HealthKit permissions when
   prompted:
   - **Share**: Workouts (so a completed Cindy attempt can be saved as an `HKWorkout`)
   - **Read**: Heart Rate, Active Energy Burned, Workouts (so the live workout builder
     can report stats during and after the session)

   No permissions are needed on the iPhone side — `CindyApp` never calls HealthKit
   directly; it only receives already-finished sessions from the Watch over Watch
   Connectivity.

## This repository has not been compiled

This project was generated without access to Xcode or the Swift toolchain — no
`swift build`, `xcodebuild`, or `xcodegen generate` has actually been run against it.
Every file was hand-verified (import lists, brace/paren balance, and every `CindyKit`
symbol cross-checked against its real declaration in `Packages/CindyKit/Sources`), but
that is not a substitute for a real build. Before trusting this as working code, a
developer with Xcode should:

1. Run `xcodegen generate` and confirm it completes without errors.
2. Open the generated `Cindy.xcodeproj` and build the `CindyApp` scheme for a
   Watch-paired simulator — this compiles both `CindyApp` and `CindyWatch` plus the
   `CindyKit` package dependency in one pass, and is the fastest way to catch anything
   a static read-through missed.
3. Run the `CindyKit` package's unit tests (`Packages/CindyKit` → Test navigator, or
   `swift test` from `Packages/CindyKit`) — they cover the timer state machine, the
   round/rep scoring logic, session payload round-tripping, and the trend/PR analytics.
4. Run the app on a Watch-paired simulator and walk through one full flow: start a
   session on the Watch, grant HealthKit permissions, log a few reps (button + Digital
   Crown), pause/resume, let the 20:00 (or use Baby Cindy's 12:00) cap run out or end
   it manually, confirm the Summary screen shows a score/duration, tap Save, and check
   it appears in Watch History and — via the Watch Connectivity relay — in the
   iPhone's Tracker/Trend tabs and Timer tab's Watch-mirror mode.
5. On a physical device, confirm the Health app shows the saved workout with heart
   rate and active energy, since the simulator's HealthKit data is synthetic.
6. Add real app icon artwork — both `AppIcon.appiconset` catalogs currently have an
   empty 1024×1024 slot, which doesn't block a Debug build but should be filled in
   before any TestFlight/App Store submission.
