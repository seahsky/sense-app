# CindyWatch target config — for whoever wires `project.yml`

This app target's Swift sources are done. Everything below is what the
`CindyWatch` target in `project.yml` needs to build them correctly — for the
XcodeGen keys already sketched in the architecture spec's §6, plus the two
gaps the spec flagged as not itemized (HealthKit capability / entitlements and
inline Info.plist generation). All values reference physical files that
already exist in this directory.

## Files already in place

- `CindyWatch/Info.plist` — hand-authored, **not** relying on
  `GENERATE_INFOPLIST_FILE`. It supplies the full base key set itself
  (`CFBundleExecutable`, `CFBundleIdentifier`, `CFBundleName`, etc., via the
  usual `$(EXECUTABLE_NAME)` / `$(PRODUCT_BUNDLE_IDENTIFIER)` / `$(PRODUCT_NAME)`
  build-setting substitutions) plus:
  - `WKApplication` = `true` and `WKRunsIndependentlyOfCompanionApp` = `true`
    — required so this is recognized as a modern single-target watchOS app.
  - `WKCompanionAppBundleIdentifier` = `com.cindyapp.ios` — required whenever a
    watch app has a companion iOS app (this one does: `CindyApp`, embedded via
    `project.yml`'s `dependencies: - target: CindyWatch, embed: true`).
    `WKRunsIndependentlyOfCompanionApp` only means the phone doesn't need to be
    reachable at runtime; it doesn't remove the need to declare the pairing.
  - `WKBackgroundModes` = `["workout-processing"]` — the only value this key
    accepts; it's what keeps the app (and the active `HKWorkoutSession`) alive
    in the background for the full AMRAP cap.
  - `UIBackgroundModes` = `["audio"]` — background audio/haptic confirmation
    (`WKInterfaceDevice.play`) is declared via this key, not `WKBackgroundModes`
    (whose only allowed value is `workout-processing`).
  - `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription`.
- `CindyWatch/CindyWatch.entitlements` — `com.apple.developer.healthkit` = `true`.
- `CindyWatch/Assets.xcassets/` — catalog skeleton with an `AppIcon.appiconset`
  (single 1024×1024 "universal"/watchos slot, no image assigned yet — add a
  real icon before shipping; an empty slot doesn't block a Debug/Release build).

## What `project.yml` needs to set on the `CindyWatch` target

1. **`INFOPLIST_FILE`**: `CindyWatch/Info.plist` (already the spec's plan —
   keep it). Do **not** also set `GENERATE_INFOPLIST_FILE: YES` or any
   `INFOPLIST_KEY_*` settings for this target — the physical file above is
   the complete plist; generating on top of it would conflict/duplicate keys.

2. **`CODE_SIGN_ENTITLEMENTS`**: `CindyWatch/CindyWatch.entitlements`. This is
   the one build setting that actually wires the HealthKit entitlement in —
   equivalent to ticking "HealthKit" under the target's Signing & Capabilities
   tab in Xcode. XcodeGen does have a first-class target-level `entitlements:`
   key (which can generate the `.entitlements` file itself from inline
   `properties:`), but this project intentionally uses the already-authored
   `CindyWatch/CindyWatch.entitlements` file instead, so point
   `CODE_SIGN_ENTITLEMENTS` at it directly rather than having XcodeGen
   generate one inline.

3. **No separate "Background Modes" capability/entitlement is needed.**
   Unlike HealthKit, `WKBackgroundModes` is Info.plist-driven only (already
   set in the file above) — there's no matching entitlement key to add.

4. **No location entitlement/capability of any kind is needed.** The workout
   configuration's `HKWorkoutSessionLocationType.indoor` is a HealthKit
   workout-classification enum case, not a Core Location request — this app
   never touches Core Location, so skip `NSLocationWhenInUseUsageDescription`
   and the location capability entirely.

5. Everything else in the spec's §6 `project.yml` sketch for this target —
   `type: application`, `platform: watchOS`, `deploymentTarget: "10.0"`,
   `sources: [CindyWatch]`, `PRODUCT_BUNDLE_IDENTIFIER: com.cindyapp.watchkitapp`,
   and the `package: CindyKit` dependency — is unchanged; nothing above
   replaces it, only adds the entitlements wiring and the plist note.

## One HealthKit implementation note for whoever reviews the Swift side

`WorkoutSessionManager` (in `CindyWatch/Workout/`) uses
`HKQuantityType.quantityType(forIdentifier:)` rather than the newer
`HKQuantityType(_:)` convenience initializer shown in the architecture spec's
illustrative `§5` code block — that initializer's SDK availability floor is
above watchOS 10, so it won't compile against this target's
`deploymentTarget: "10.0"`. `quantityType(forIdentifier:)` returns the same
`HKQuantityType` instances and has been available since the first HealthKit
release, so this is a drop-in, deployment-target-safe substitute; nothing
about the actual HealthKit configuration (`.crossTraining` / `.indoor` /
the `stopActivity` → `.stopped` → `endCollection` → `finishWorkout` →
`session.end()` chain) changed from what the spec describes.
