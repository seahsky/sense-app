# CindyApp (iOS target) — Info.plist / entitlements notes

Written for whoever owns `project.yml` / target scaffolding. This iOS app target's
Swift sources are implemented under `CindyApp/` (App entry point, `Views/`,
`Connectivity/`); this file only covers what the target's Info.plist and
entitlements need to be, per the architecture spec and what the implemented code
actually touches.

## HealthKit — not needed for this target as implemented

The architecture spec's §6 says `CindyApp/Info.plist` needs
`NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` **only** "if the
phone also touches HealthKit." As implemented here, it doesn't: all HealthKit
interaction (`HKWorkoutSession`, `HKLiveWorkoutBuilder`, `HealthKitAuthManager`,
`WorkoutSessionManager`) lives exclusively in `CindyWatch/Workout/` per the spec's
file tree. `TimerTabView`'s "Watch" mode reads a live mirror over
`WatchConnectivityBridge` (application context), never HealthKit directly, and
`TrackerTabView` computes its own duration from `AmrapTimerEngine` — no
`HKHealthStore` call anywhere in `CindyApp/`.

**So for the current scope: no HealthKit Info.plist keys, no HealthKit capability,
no `com.apple.developer.healthkit` entitlement on the `CindyApp` target.**

If a future iOS-side feature reads HealthKit directly (e.g. showing live heart rate
on the phone without going through the Watch), add at that point:
- `NSHealthShareUsageDescription` (read) and, only if the phone ever writes samples
  itself, `NSHealthUpdateUsageDescription` (write) to `CindyApp/Info.plist`.
- The "HealthKit" capability on the `CindyApp` target in Xcode (adds
  `com.apple.developer.healthkit` to its `.entitlements` file).
- The standard `HKHealthStore.isHealthDataAvailable()` / `requestAuthorization`
  flow before any read/write.

## WatchConnectivity — no extra entitlement needed

`CindyApp.swift` calls `WatchConnectivityBridge.shared.activate()` at launch
(wrapping `WCSession.activate()`). `WatchConnectivity` requires no capability
toggle or Info.plist key by itself — it becomes available automatically once the
iOS target properly embeds the watchOS app as a companion (the `dependencies: -
target: CindyWatch, embed: true` relationship in `project.yml`, §6 of the spec).
Nothing further is needed here for that to work.

## SwiftData / storage — no entitlement needed

`SessionSchema.makeLocalContainer()` explicitly configures
`ModelConfiguration(cloudKitDatabase: .none)` — this target's SwiftData store is
local-only by construction. No CloudKit capability, no `com.apple.developer.icloud-
container-identifiers` / `com.apple.developer.icloud-services` entitlements, no
`aps-environment` (push) entitlement. Do not add the CloudKit capability to this
target — doing so risks SwiftData auto-mirroring the local store depending on
`ModelConfiguration` defaults elsewhere, which would contradict the "local-only, no
backend, no CloudKit" requirement in §0/§1 of the architecture spec.

## Baseline Info.plist keys

Nothing exotic — standard app keys the scaffolding template should already cover:
- `CFBundleDisplayName`: "Cindy"
- Launch screen (`UILaunchScreen` dict, or a launch storyboard) — a plain one is
  fine, no custom launch UI is required by any screen implemented here.
- `UISupportedInterfaceOrientations`: portrait is sufficient; none of the
  implemented views (`TimerTabView`, `TrackerTabView`, `TrendTabView`, and their
  children) require landscape.
- `ITSAppUsesNonExemptEncryption`: `false` is accurate (no custom encryption is
  used anywhere in this target) and avoids an export-compliance prompt at archive
  time; safe to set even though it isn't strictly load-bearing for this task.

No location, motion/fitness (`NSMotionUsageDescription`), microphone, camera,
contacts, or notification usage appears anywhere in `CindyApp/`'s implemented
Swift code — none of those keys are needed on this target.

## Summary

| Item | Needed on `CindyApp` target? |
|---|---|
| `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` | No (not until iOS-side HealthKit reads are added) |
| HealthKit capability / `com.apple.developer.healthkit` entitlement | No |
| Any WatchConnectivity-specific entitlement | No (just needs the watch app embedded per `project.yml`) |
| CloudKit capability / entitlements | No — must stay off; `SessionSchema` is local-only by design |
| `WKBackgroundModes` / "Workout Processing" | N/A — that's a `CindyWatch/Info.plist` concern only, not this target's |
