# SenseWatch target config — for whoever wires `project.yml`

This app target's Swift sources are done. Everything below is what the
`SenseWatch` target in `project.yml` needs to build them correctly — for the
XcodeGen keys already sketched in the architecture spec's §6, plus the two
gaps the spec flagged as not itemized (HealthKit capability / entitlements and
inline Info.plist generation). All values reference physical files that
already exist in this directory.

## Files already in place

- `SenseWatch/Info.plist` — hand-authored, **not** relying on
  `GENERATE_INFOPLIST_FILE`. It supplies the full base key set itself
  (`CFBundleExecutable`, `CFBundleIdentifier`, `CFBundleName`, etc., via the
  usual `$(EXECUTABLE_NAME)` / `$(PRODUCT_BUNDLE_IDENTIFIER)` / `$(PRODUCT_NAME)`
  build-setting substitutions) plus:
  - `WKApplication` = `true` and `WKRunsIndependentlyOfCompanionApp` = `true`
    — required so this is recognized as a modern single-target watchOS app.
  - `WKCompanionAppBundleIdentifier` = `com.senseapp.ios` — required whenever a
    watch app has a companion iOS app (this one does: `SenseApp`, embedded via
    `project.yml`'s `dependencies: - target: SenseWatch, embed: true`).
    `WKRunsIndependentlyOfCompanionApp` only means the phone doesn't need to be
    reachable at runtime; it doesn't remove the need to declare the pairing.
  - `WKBackgroundModes` = `["workout-processing"]` — what keeps the app (and the
    active `HKWorkoutSession`) alive in the background for the full AMRAP cap,
    and the precondition for `CMBatchedSensorManager` delivering any data at all.
    It is **one of six** values the key accepts (`workout-processing`,
    `self-care`, `mindfulness`, `physical-therapy`, `alarm`, `underwater-depth`),
    not the only one — an earlier revision of this file said otherwise and was
    wrong. It is the only one this app needs.
  - `UIBackgroundModes` = `["audio"]` — background audio/haptic confirmation
    (`WKInterfaceDevice.play`) is declared via this key rather than
    `WKBackgroundModes`, since none of that key's six values covers audio.
  - `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription`.
  - `NSMotionUsageDescription` — added for automatic rep detection. Core Motion
    exposes no `requestAuthorization` API for raw accelerometer or device-motion
    data (the only one in the framework is on `CMFallDetectionManager`), so this
    string is the entire permission surface. Apple DTS states `CMMotionManager`
    has never required it and `CMBatchedSensorManager`'s reference page says
    nothing either way, but Apple's usage-key list is explicitly non-exhaustive
    and `CMAltimeter` was made to require the key in iOS 17.4 without ever being
    added to that list. One string is cheaper than a crash on first sensor read
    mid-AMRAP.
  - `CFBundleURLTypes` — registers the `sense` scheme (`CFBundleURLName`
    `com.senseapp.ios.watchkitapp.deeplink`, `CFBundleTypeRole` `Editor`), which is
    how the complication's `widgetURL` reaches this app as
    `sense://start?variant=<rawValue>`.
    The parser is `Packages/SenseKit/Sources/SenseKit/Routing/SenseDeepLink.swift`,
    and it is the only place in the repo that parses an incoming URL.
    Whether `widgetURL` strictly *requires* the scheme to be registered cannot be
    settled locally: `xcrun simctl openurl` is unsupported on the watchOS simulator
    and fails with `LSApplicationWorkspaceErrorDomain` 115 even for `music://`.
    One block ends the argument, and the failure it guards against is only
    reproducible on a wrist.
- `SenseWatch/SenseWatch.entitlements` — `com.apple.developer.healthkit` = `true`.
- `SenseWatch/Assets.xcassets/` — catalog skeleton with an `AppIcon.appiconset`
  (single 1024×1024 "universal"/watchos slot, no image assigned yet — add a
  real icon before shipping; an empty slot doesn't block a Debug/Release build).

## What `project.yml` needs to set on the `SenseWatch` target

1. **`INFOPLIST_FILE`**: `SenseWatch/Info.plist` (already the spec's plan —
   keep it). Do **not** also set `GENERATE_INFOPLIST_FILE: YES` or any
   `INFOPLIST_KEY_*` settings for this target — the physical file above is
   the complete plist; generating on top of it would conflict/duplicate keys.

2. **`CODE_SIGN_ENTITLEMENTS`**: `SenseWatch/SenseWatch.entitlements`. This is
   the one build setting that actually wires the HealthKit entitlement in —
   equivalent to ticking "HealthKit" under the target's Signing & Capabilities
   tab in Xcode. XcodeGen does have a first-class target-level `entitlements:`
   key (which can generate the `.entitlements` file itself from inline
   `properties:`), but this project intentionally uses the already-authored
   `SenseWatch/SenseWatch.entitlements` file instead, so point
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

4b. **No Core Motion entitlement or capability is needed either.** Apple's
   entitlements index lists exactly one Core Motion entitlement,
   `com.apple.developer.coremotion.head-pose` (spatial audio head tracking),
   which is unrelated to accelerometer or device-motion access. Automatic rep
   detection needs only the `NSMotionUsageDescription` string above;
   `SenseWatch.entitlements` stays HealthKit-only.

5. Everything else in the spec's §6 `project.yml` sketch for this target —
   `type: application`, `platform: watchOS`, `deploymentTarget: "10.0"`,
   `sources: [SenseWatch]` and the `package: SenseKit` dependency — is
   unchanged; nothing above replaces it, only adds the entitlements wiring and
   the plist note.
   The one correction is `PRODUCT_BUNDLE_IDENTIFIER`: it must be
   `com.senseapp.ios.watchkitapp`, not `com.senseapp.watchkitapp`.
   iOS rejects the install outright unless the watch app's bundle identifier is
   the companion iOS app's identifier followed by a dot and one more segment
   (`MIInstallerErrorDomain` 101, `WatchKitAppBundleIDNotPrefixed`).

## What `project.yml` needs for the new `SenseComplication` target

The watchOS WidgetKit complication ships as an app extension embedded inside this
watch app.
Everything below is a rule that fails quietly, expensively, or both.

1. **`type: app-extension`, not `watchkit2-extension`.**
   `app-extension` maps to `com.apple.product-type.app-extension`, which is what
   Xcode 26's own watchOS Widget Extension template uses.
   `watchkit2-extension` is the legacy WatchKit Extension product type and is a
   different thing entirely.

2. **`PRODUCT_BUNDLE_IDENTIFIER` must be prefixed by the WATCH app's identifier**,
   so `com.senseapp.ios.watchkitapp.complication` and never
   `com.senseapp.ios.complication`.
   This is the same rule as §5 of the SenseWatch list above, one level deeper, but
   it fails earlier and louder: it is a **build** failure at
   `ValidateEmbeddedBinary`, not an install failure, reading
   `error: Embedded binary's bundle identifier is not prefixed with the parent
   app's bundle identifier.`
   It fires even with `CODE_SIGNING_ALLOWED=NO`, so CI catches a wrong prefix on
   the first push.

3. **Embed on `SenseWatch`, not on `SenseApp`.**
   `- target: SenseComplication` with `embed: true` and `codeSign: true` goes in
   `SenseWatch`'s `dependencies`.
   That is what produces the `PBXCopyFilesBuildPhase` with `dstSubfolderSpec = 13`
   (PlugIns), and the built path to check is
   `SENSE.app/Watch/SENSE Watch.app/PlugIns/SENSE Complication.appex`.

4. **`INFOPLIST_FILE`: `SenseComplication/Info.plist`, with
   `GENERATE_INFOPLIST_FILE` off — and this one has no escape hatch.**
   Xcode 26.6 has no `INFOPLIST_KEY_NSExtension` build setting at all, so a
   generated plist cannot carry the `NSExtension` dictionary in any spelling.
   Turning generation on therefore drops `NSExtensionPointIdentifier` =
   `com.apple.widgetkit-extension` silently.
   The result is not a build error: it is a complication that never appears in the
   face gallery, with nothing to read anywhere explaining why.

5. **No `CODE_SIGN_ENTITLEMENTS`, and no entitlements file to point it at.**
   The extension reads no HealthKit and no Core Motion; it draws a mark and hands
   the app a URL.
   `SenseWatch.entitlements` stays HealthKit-only and is untouched by this target.

6. **No asset catalog, and no `ASSETCATALOG_COMPILER_*` settings.**
   A watch complication takes its tint from the face, so there is nothing for a
   catalog to do here, and a third `AccentColor.colorset` would put a hex literal
   outside `SenseColor` — the design system's one rule.

7. **Do not add `WatchConnectivityBridge.shared.activate()` here for symmetry, and
   do not open a `ModelContainer` here.**
   Linking SenseKit pulls WatchConnectivity and SwiftData symbols into a process
   that uses neither, which is harmless exactly as long as nothing calls them.
   Activating a `WCSession` in an extension with nothing to send, or opening a
   second SwiftData reader against the app's container while a workout is running,
   is a real bug wearing the costume of consistency.

8. **`excludes` on the source paths of all three app targets — this one,
   `SenseWatch`, and `SenseApp`.**
   Every `sources` entry is a whole directory, so without
   `excludes: ["**/*.md"]` every Markdown file in them ships inside the built app
   as a bundle resource — including this one, which it has been doing since the
   watch target was first wired.
   That is the pre-existing bug the line fixes, not a new requirement of the
   complication.
   `SenseApp` had the identical defect and takes the identical line; the note for
   that half belongs in `SenseApp/entitlements-and-plist-notes.md`.
   Verified rather than assumed: a `find` of the built `SENSE.app` for `*.md`
   returns nothing in Debug or Release, while both source files are still on disk.
   If the exclude ever misbehaves, drop it and move these notes into `docs/`
   instead.

9. **CI never signs anything, so automatic signing for this bundle identifier is
   unverified until someone builds to a device.**
   `CODE_SIGNING_ALLOWED=NO` means the Actions build proves the prefix rule in item 2
   and nothing else.
   Xcode normally registers the App ID for
   `com.senseapp.ios.watchkitapp.complication` under team `PGK46N254T` on the first
   device build; a missing App ID will not show up before then.

## One HealthKit implementation note for whoever reviews the Swift side

`WorkoutSessionManager` (in `SenseWatch/Workout/`) uses
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
