# Automatic rep, exercise, and rest detection — research

Question: can the Watch figure out which movement is happening, count its reps,
and notice rest breaks on its own, so the only manual actions left are starting
and stopping the timer? And if that needs a trained motion model, is training
one worth it?

Researched September 2026 against watchOS 26 / Xcode 26.
Sources are linked inline; anything without a source is this document's own reasoning, labeled as such.

> **Revision, 2026-09-03.** Every claim below was re-checked against primary sources — Apple's own headers in the locally installed `WatchOS26.5.sdk`, Apple documentation, and the original papers — and the corrections were folded in.
> Four things changed materially: RecoFit's counting signal is **not** accelerometer magnitude; the **air squat**, not the push-up, is the weakest movement in the only published data covering all three of Cindy's movements; HealthKit **does** offer per-movement *recording* APIs the app should use; and the real background risk is **CPU-based suspension**, not battery.
> See [Corrections from the fact-check](#corrections-from-the-fact-check) for the full list.

## Short answer

**No off-the-shelf Apple API detects or counts these reps — the README is right, and still is.**
Nothing in HealthKit or Core Motion senses a pull-up, push-up, or air squat.
`HKWorkoutEventType` has exactly 8 cases (`pause`, `resume`, `lap`, `marker`, `motionPaused`, `motionResumed`, `segment`, `pauseOrResumeRequest`), none of them a repetition or exercise-type event, and none of the 120 `HKQuantityTypeIdentifier` constants counts strength reps or sets.
[[HKWorkoutEventType]](https://developer.apple.com/documentation/healthkit/hkworkouteventtype)
[[HKQuantityTypeIdentifier]](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier)
Both counts were verified directly in `WatchOS26.5.sdk/System/Library/Frameworks/HealthKit.framework/Headers/`.
HealthKit does auto-count repetitions for other movement classes — `pushCount` is recorded automatically in wheelchair mode, and `swimmingStrokeCount` and `cyclingCadence` are likewise repetition measures — but none of them applies here.

watchOS's own Fitness app has never shipped native rep counting, and watchOS 26 did not add it.
The watchOS 26 Workout app changes are a layout and navigation redesign, automatic media selection, and Workout Buddy (Apple Intelligence spoken motivation), which covers Functional and Traditional Strength Training but only as voice encouragement.
[[watchOS 26 preview]](https://www.apple.com/newsroom/2025/06/watchos-26-delivers-more-personalized-ways-to-stay-active-and-connected/)
Strength Training workouts log heart rate, calories, duration, and — since watchOS 11 — a Workout Effort score, which Apple auto-estimates only for popular cardio types, so for strength training the user still enters it by hand.
A commonly repeated claim that "Series 9+ counts reps automatically" turned up in a couple of low-authority blog posts but is contradicted by every primary source checked — treat it as misinformation.

**But the question underneath — "should we train a custom model?" — turns out to
have a better answer than the README implies, once you notice something specific
to this app: Cindy's movement sequence is fixed and known (5 pull-ups → 10
push-ups → 15 air squats, repeating). `RoundRepTracker` already derives which of
the three movements is current from the running rep count, with zero sensors
involved.**
[[RoundRepTracker.swift]](../../Packages/SenseKit/Sources/SenseKit/Tracking/RoundRepTracker.swift)
That's the single hardest and most expensive part of general exercise recognition
(academic systems spend most of their model capacity on "which of N exercises is
this?"), and Cindy gets it for free by design.
That collapses "auto-detect exercise + reps + rest" into two much smaller problems, one of which doesn't need sensors or a model at all:

| Sub-problem | Needs a trained model? | Verdict |
|---|---|---|
| Which movement is active | No — already solved | `RoundRepTracker` derives it from the rep count today |
| Rest detection | No | Timestamp-since-last-rep; see below |
| Rep counting | Not at first | Classical signal processing (bandpass → PCA → autocorrelation-refined peak counting); a custom model is a fallback, not a starting point |

So: **don't start by training a model.**
Build a plain DSP rep counter first.
Only train something if real testing shows it's not good enough — and even then, scope it narrowly instead of building the 3-way classifier the README assumed was the only option.

There is also a **third sub-problem the original version of this document missed**: even with no sensing at all, HealthKit can *record* the per-movement structure the app already knows.
See [What HealthKit can record today](#what-healthkit-can-record-today-with-no-sensors-at-all).

## Why "which movement" isn't actually an open problem here

General human-activity-recognition (HAR) research — the closest prior art —
assumes it doesn't know what exercise is happening and has to classify it from
the signal.
Cindy doesn't have that problem: the sequence is fixed, so `RoundRepTracker.recompute()` flips `currentMovement` the instant the 5th pull-up (or 10th push-up) is logged, deterministically, with no sensing involved.
Spending effort on a 3-class exercise classifier would be re-solving a problem this app's architecture already eliminated, and would add a new failure mode (misclassifying the current movement) that the app cannot suffer from today.

This is also why an ML classifier, if one is ever built (see Phase 3 below),
should never be a general "which exercise is this" classifier — that job is
already done for free.

## What HealthKit can record today, with no sensors at all

HealthKit has no rep *detection* hook, but it has first-class APIs for *recording*
per-movement structure — and Cindy already derives that structure deterministically.
All of these are available at the app's watchOS 10.0 deployment floor:

- **`HKWorkoutActivity`** (watchOS 9.0) — a sub-activity inside a workout, with its
  own start/end dates, duration, statistics, and arbitrary metadata.
  [[HKWorkoutActivity]](https://developer.apple.com/documentation/healthkit/hkworkoutactivity)
- **`HKWorkoutSession.beginNewActivity(configuration:date:metadata:)`** and
  **`endCurrentActivity(on:)`** (watchOS 9.0) — start and end one live, from the
  session the app already runs.
- **`HKWorkoutBuilder.addWorkoutEvents(_:)`** — emit `.segment` and `.marker`
  events, a lighter-touch alternative.

Apple documents this exact shape as the intended use:
"you can divide interval training into active and rest periods… you may want to
add custom metadata to indicate whether the activity is an active or resting
interval."
[[Dividing a HealthKit workout into activities]](https://developer.apple.com/documentation/healthkit/dividing-a-healthkit-workout-into-activities)

The one constraint: `HKWorkoutActivityType` has only 84 cases and no pull-up /
push-up / air-squat granularity, so movement identity has to live in metadata
(`NSString` / `NSNumber` / `NSDate` values only), with
`.functionalStrengthTraining` as the activity type.

This is the cheapest win in the whole document — per-movement timing and
per-movement heart-rate and energy statistics in the saved workout, with zero new
sensors and zero new failure modes. It is scheduled as Phase 1.5.

## Rest detection: solved without touching a sensor

Apple's two built-in candidates for "is the user resting" are both a bad fit:

- **Workout auto-pause** (`HKWorkoutEventType.motionPaused` / `.motionResumed`) is
  out of scope for Cindy.
  Apple's API reference scopes the event to running: "During running workout
  sessions, Apple Watch can automatically generate motion pause events when the
  user stops moving."
  [[HKWorkoutEventType.motionPaused]](https://developer.apple.com/documentation/healthkit/hkworkouteventtype/motionpaused)
  In the built-in Workout app the behaviour covers outdoor running and cycling,
  controlled by a single global Settings → Workout → Auto-Pause toggle.
  [[Apple Support: change workout settings]](https://support.apple.com/guide/watch/change-workout-settings-apda13d25f9a/watchos)
  Apple does not document *how* the decision is made, so any claim about which
  sensors it leans on is speculation.
- **`CMMotionActivityManager`**'s "stationary" state is a coarse,
  battery-optimized daily-activity classifier, not a set-gap timer.
  Apple's Core Motion session describes a 2.5-second batch cadence and a
  low → medium → high confidence ramp per transition, framed explicitly as an
  accuracy-versus-latency tradeoff, with quoted detection latencies of 3–5 seconds
  for running and 5–10 seconds for walking.
  [[WWDC14 Session 612: Motion Tracking with Core Motion]](https://developer.apple.com/videos/play/wwdc2014/612/)
  Apple publishes no latency figure for *entering* the stationary state, none for
  wrist-worn watchOS, and neither the API reference nor the SDK headers document
  any timing guarantee at all — so there is nothing to tune against.

Cindy doesn't need either.
Every rep is already a discrete, user-initiated event with no sensor inference anywhere in the codebase — verified: `grep -rn "CMMotion\|accelerometer\|CoreMotion" --include="*.swift"` over the whole repo returns zero hits, and every mutation of rep state flows through `RoundRepTracker.logRep()` / `undoLastRep()`, whose only callers are UI controls.
So rest reduces to: **track the timestamp of the last logged rep; while the AMRAP timer is running, if N seconds pass with no qualifying rep, the state is "resting."**
No Core Motion, no HealthKit workout events, no variance threshold to tune against sensor noise.
This is also exactly how a shipped ML-based competitor operationalizes rest: Train Fitness/Motra's own docs say rest starts "when a set is detected as finished," i.e. time-since-last-confirmed-event, not a separately trained resting-motion class.
[[Train Fitness rest-timer docs]](https://help.trainfitness.ai/en/articles/9671219-rest-time-and-rest-alarm)

The one gap this can't close: if the user is genuinely still repping but forgets
to tap, the app will wrongly infer rest after N seconds.
A cheap corroborating signal could suppress that false positive later, but it's an optional refinement layered on top of the timer, not a prerequisite — and reintroduces the false-positive-tuning problem the timer-only design avoids.
If it is ever built, prefer raw accelerometer variance, whose timing is known, over `CMMotionActivityManager`, whose timing is not.

Picking N (likely 8–15s) needs empirical tuning against real fatigued WOD
attempts, not research — it trades early rest indication against flagging a
brief mid-set pause (shaking out forearms between pull-ups) as a real break.

## Rep counting: the one place real sensing work is justified

### What's actually available on-device

- **`CMMotionManager`** — available on watchOS since 2.0, real-time per-sample
  delivery, capped at 100 Hz.
  Apple states the cap twice in WWDC23 session 10179: "The maximum supported
  frequency is 100 Hz" and "CMMotionManager vends data at a maximum of 100 Hz on
  a per-sample basis."
  The API reference itself names no number — it says only that the interval is
  "capped to minimum and maximum values" and instructs you to read the delivered
  timestamps to learn the true rate.
  Works on every watch this app supports.
- **`CMBatchedSensorManager`** — new in watchOS 10 (WWDC23), purpose-built for
  exactly this: up to 800 Hz accelerometer / 200 Hz device motion, delivered in
  one-second batches at lower power.
  [[WWDC23: What's new in Core Motion]](https://developer.apple.com/videos/play/wwdc2023/10179/)
  Three details that matter for the build:
  - It **requires an active `HKWorkoutSession`** to produce any data at all —
    "Because this is a workout-centric API, you need to have an active HealthKit
    workout session to get data." Cindy already runs one.
  - **The rate is reported, not requested.** `accelerometerDataFrequency` and
    `deviceMotionDataFrequency` are read-only `NSInteger` properties with no
    setter. There is no down-rate knob; decimate in software instead.
  - **There is no hardware annotation in the SDK.** The class is annotated only
    `API_AVAILABLE(watchos(10.0))`. Apple stated at WWDC23 that the high-rate
    modes are available on Apple Watch Series 8 and Ultra and has published no
    broader list since. Do not encode a model list — query
    `CMBatchedSensorManager.isAccelerometerSupported` /
    `.isDeviceMotionSupported` at runtime *and* handle an error on the update
    stream, because the flag alone is not a reliable proxy for "data will
    actually arrive."
- An active `HKWorkoutSession` is a sanctioned watchOS background-execution
  context, and Apple documents the continuity explicitly: the app "continues to
  run throughout the entire workout session, even when the user lowers their
  wrist or interacts with a different app," and "continues to receive data from
  HealthKit and Apple Watch's sensors in the background."
  [[Running workout sessions]](https://developer.apple.com/documentation/healthkit/running-workout-sessions)
  The documented risk is **CPU, not screen state**: "If your app uses an
  excessive amount of CPU while in the background, watchOS may suspend it."

### Permissions and capabilities

- **No new entitlement.** `SenseWatch.entitlements` stays HealthKit-only. Apple's
  entitlements index lists exactly one Core Motion entitlement,
  `com.apple.developer.coremotion.head-pose` (spatial audio head tracking), which
  is unrelated.
- **No request API.** Core Motion has exactly one `requestAuthorization` method
  framework-wide, on `CMFallDetectionManager`. `CMBatchedSensorManager` exposes
  only a read-only class property, `authorizationStatus: CMAuthorizationStatus`.
  So the app cannot pre-prompt: it must start the stream and degrade when the
  status is `.denied` or the stream errors.
- **`NSMotionUsageDescription` should be added defensively.** `CMMotionManager`
  itself does not need it — Apple DTS: "The system doesn't require
  NSMotionUsageDescription for CMMotionManager and never has."
  `CMBatchedSensorManager` is undocumented on this point (its reference page has
  no prose at all). Add the key anyway: Apple's key page is explicitly
  non-exhaustive, and Apple made `CMAltimeter` require the key in iOS 17.4 without
  ever adding it to that list. Cost of adding it is one string; cost of omitting
  it if the gate moves is a crash on first sensor read mid-workout.
  `SenseWatch/Info.plist` is hand-authored, so the key goes in the file directly,
  not via an `INFOPLIST_KEY_*` build setting.

### Classical signal processing works, and is competitive with deep learning specifically for counting

The technique was established by Microsoft Research's **RecoFit** (CHI 2014,
shipped on the Microsoft Band) and confirmed since.
**The original version of this document described RecoFit's method incorrectly**, in a way that would have led the implementation straight into its worst failure mode. The actual algorithm, quoted from the paper:

> "First, an elliptical bandpass filter (0.15 Hz – 11 Hz) removes high- and
> low-frequency components. We then subtract the mean from the data, apply
> Principal Component Analysis (PCA), and project the data onto its first PC. By
> projecting onto this axis — the axis of highest variation during this exercise —
> we simplify counting repetitions to the problem of counting peaks on a 1d
> signal."

So the counting signal is **the first principal component of the 3-axis
accelerometer**, not the vector magnitude. The paper warns that "Magnitude alone
is rarely informative," and uses magnitude (`aXmag`) only as one of several
*segmentation* signals. It also reports that "Empirically, we did not find the
gyroscope helpful for counting."

Counting then runs **three ordered passes** over candidate local maxima:

1. Sort candidates by amplitude and greedily accept a peak only if it is at least
   `minPeriod` from the nearest already-accepted peak, where `minPeriod` is a
   fixed per-exercise constant — "an estimate of the minimum possible time needed
   to perform one repetition."
2. For each survivor, compute the autocorrelation in a window centred on that
   peak; the lag of the largest autocorrelation value within
   `[minPeriod, maxPeriod]` is that candidate's **local** period `P`. Re-sort and
   re-filter, rejecting peaks closer to a neighbour than `0.75 · P`.
3. Reject peaks whose amplitude is below half that of the 40th-percentile peak —
   a relative threshold the authors "found much more robust than absolute
   thresholds."

Period estimation is **local and per-candidate**, not one global period, and the
autocorrelation runs on already-found candidates rather than before peak-finding.
Online, the whole process re-runs on a buffer every 200 ms, so "there is no
fundamental latency in counting new repetitions."
RecoFit's sensor was a SparkFun Razor IMU on the right forearm at 50 Hz — so
50 Hz is enough; the 800 Hz batched stream is not required.
[[RecoFit paper, PDF]](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/11/Morris_Workout_CHI_2014.pdf)

Reported accuracy for this style of classical approach is genuinely good and not
obviously beaten by deep learning on the counting sub-task specifically:

- **RecoFit**: >95% segmentation precision/recall, 96–99% exercise recognition on
  4/7/13-exercise circuits, reps counted within ±1 on 97% of sets with actual
  boundaries and 93% with the automatic segmenter — using hand-crafted-feature
  SVMs plus autocorrelation-refined peak detection, not raw deep learning.
- **uLift** (IEEE Access 2024), "Adaptive Workout Tracker Using a Single
  Wrist-Worn Accelerometer" — a fully classical, *training-free* single-wrist
  system, 15 multi-joint workouts, 35 participants — reaches 93.1%
  workout-detection accuracy, 90.1% classification accuracy, and a mean counting
  error of 0.61 reps. It segments with a softmax-weighted sum of per-axis
  autocorrelations, then counts peaks on the single axis with the largest
  amplitude in the segment — so, like RecoFit, it avoids vector magnitude.
  Its exercise list is paywalled; whether it includes pull-ups is unverified.
  [[uLift]](https://ieeexplore.ieee.org/document/10423644/)
- **Soro et al. 2019** (ETH Zurich, *Sensors*) — CNNs over 10 CrossFit movements
  including all three of Cindy's — get 99.96% classification accuracy with both
  watches and 98.91% from the wrist alone, and 91% of sets within ±1 rep overall.
  Deep learning's edge shows up mainly on classification as the exercise set
  grows, not on counting itself.
  [[Soro et al. 2019, DOI]](https://doi.org/10.3390/s19030714)

### Which movement is actually the weak one — the air squat, not the push-up

The original version of this document claimed two independent sources agreed that
push-ups are the structural weak point. **That framing does not survive checking.**

The physics half is real and correctly quoted. RecoFit says:

> "Some exercises, e.g. pushups, result in almost no translation of an arm-worn
> sensor… the primary observable phenomenon in these cases is not energy on any
> sensed axis, but a repetitive change in the gravity axis observed by the
> accelerometer."

But that sentence motivates RecoFit's choice of *segmenter*; RecoFit publishes no
per-exercise counting breakdown, so it never establishes push-ups as its own
weakest movement. And its sensor was a forearm armband, not a wrist device.

Soro et al. — the only published study covering all three Cindy movements —
measure close to the opposite. In their wrist-only confusion matrix (Figure 7a),
**push-ups are recognized at 1.000, tied for the best of the ten movements**; the
only wrist-only confusion they report is kettlebell thruster (0.816) versus
kettlebell press (0.852).

Push-ups are a problem only in *counting*, and there the ranking is:

| Movement | Mean abs. error | Exact | Within ±1 |
|---|---|---|---|
| Pull-up | 0.91 | 65.1% | 88.4% |
| Push-up | 1.22 | 58.0% | 86.0% |
| **Air squat** | **1.82** | **54.5%** | **79.5%** |
| (all 10 movements) | 0.70 | 73.5% | 91% |

*Soro et al. 2019, Table 7, 54 participants.*

The **air squat is the worst counter of all ten movements they tested** — worse
than the push-up. All three of Cindy's movements land below the headline
"91% within ±1."

One caveat in the other direction: in their small unconstrained test (Table 8,
5 participants) push-ups are worst of the three, but the authors attribute that
to vibration-cued training data breaking the flow between reps, not to weak wrist
signal.

**What to plan for:** budget tuning effort for air squats at least as heavily as
for push-ups, and keep the correction affordance equally prominent in all three
segments rather than emphasising one. Expect roughly one rep of error per set on
every movement — correction is the common path, not an edge case.

## Should we train our own model?

**Conditional no — not as a first step, and possibly not at all.**

Training a 3-way exercise classifier would re-solve a problem `RoundRepTracker`
already solves for free, at the cost of a new failure mode (misclassifying the
active movement) the app doesn't currently have.
Start instead with:

1. Timestamp-based rest detection (no sensors, no model).
2. A classical DSP rep counter — bandpass → PCA projection → autocorrelation-refined
   peak counting, run only for whichever single movement `RoundRepTracker` says is
   currently active. This is a bounded, well-precedented DSP problem, not a
   machine-learning problem.

**Only reach for a model if real-world testing on real, fatigued WOD attempts
shows the DSP counter's error rate is unacceptable.** Soro et al.'s per-movement
figures give that gate an actual threshold instead of a judgement call: if the DSP
counter lands near 88% (pull-up), 86% (push-up), 80% (air squat) within ±1, it is
already performing at published-CNN level and further ML work is unlikely to pay.

If it does fall short, there are two options, and the original version of this
document only listed the more expensive one:

- **`Create ML`'s Activity Classifier** (`MLActivityClassifier` — distinct from
  the video/pose-based `Action Classifier`, which doesn't apply since there's no
  camera on the wrist). It trains on labelled multivariate time-series recordings
  — CSV, JSON, or text files with a timestamp column plus arbitrarily named
  numeric feature columns — and exports a Core ML model that runs entirely
  on-device. Labels come from the enclosing directory name
  (`labeledDirectories(at:)`) or from a separate annotation file with start and
  end time columns (`directoryWithDataAndAnnotation(...)`). That second form
  means the labelling tool only has to emit one small CSV of
  `(recordingFile, label, startTime, endTime)` rows — much less work than the
  original cost estimate assumed.
  [[MLActivityClassifier docs]](https://developer.apple.com/documentation/createml/mlactivityclassifier)
- **A few-shot / class-agnostic exemplar counter** (CaRaCount-style, TPAMI 2024),
  which counts from a handful of exemplar reps instead of a labelled training
  corpus. This fits Cindy's shape well — one user, a trivially collectable
  personal exemplar set — and removes the largest stated cost of the Create ML
  path. **Caveats, stated plainly:** the paper is paywalled, so its error rates,
  model size, and on-device feasibility could not be verified; no public code or
  weights exist; and it is not an Apple API, so it would be a hand-ported model,
  not an `MLActivityClassifier` drop-in. Worth evaluating before committing to a
  labelled training run; not worth changing the plan for today.

Either way, keep it narrow — a single-movement counter or a binary
active-motion/rest confidence gate feeding the same DSP pipeline — not a general
exercise classifier, since exercise identity is never actually in question.

Every Apple Watch since Series 4 has a Neural Engine.
[[watchOS 6 newsroom]](https://www.apple.com/newsroom/2019/09/watchos-6-is-available-today/)
Apple documents 2 cores on the S8 SiP and 4 cores on the S9 and S10 SiPs; it has
never published a core count for S4 through S7, so the widely repeated "2 cores"
figure for those is community-sourced, not an Apple fact.
Apple Watch already runs Apple's own on-device ML motion classifiers — Apple
states that "ML-based models trained on thousands of hours of data identify
movement patterns associated with different activities (for example, swimming,
cycling, or running)," and lists automatic workout detection among its
Neural-Engine-enabled features. Apple has never said which of these execute on the
Neural Engine specifically, so do not assert that fall detection or swim stroke
counting run there.
A complete, publicly documented pipeline (Core Motion recording → Create ML
Activity Classification → on-watch Core ML inference) exists and has been
walked through end-to-end.
[[Tutorial: Activity Classification for watchOS]](https://medium.com/@tyler.hutcherson/activity-classification-for-watchos-part-1-542d44388c40)

### Overfitting to one user is fine here — that's the point, not a compromise

Wrist-worn activity classifiers trained on **other** people generalize
inconsistently to a new user, because they are trained without any of that user's
data.
[[Mannini and Intille, personalization for wrist-IMU generalization]](https://pmc.ncbi.nlm.nih.gov/articles/PMC6639791/)
The same paper reports that classifiers trained on a single subject's own data
give the best accuracy for that subject — with the caveat that a *large* amount of
that person's labelled data is needed, and that its validated recipe is "start
from a general model, then add a few of the user's labels," not "train from
scratch on one person."
Cindy has no accounts and no sync — it's a personal, single-user, local app by
design, so a single-user model is the right shape.
But be precise about what the citation supports: for Cindy there is no general
Cindy model to start from, so a from-scratch single-user model is an *untested-by-this-citation*
approach, not a literature-endorsed one.
It would become a real blocker only if this model were ever shipped to strangers
on the App Store as-is.

## Cost — and confirmation this stays scale-to-zero

**Zero ongoing infrastructure cost either way, verified rather than assumed.**
`Create ML` runs as a free local Mac app bundled with Xcode — training is
entirely offline, no cloud GPU rental required.
[[Create ML is a free local Xcode tool]](https://www.createwithswift.com/create-ml-explained-apples-toolchain-to-build-and-train-machine-learning-models/)
On-device Core ML inference has no marginal per-inference cost and no server
dependency — the compiled model ships inside the app bundle like any other
resource and runs on the Watch's own Neural Engine/CPU.
This is architecturally identical to how Cindy already ships (no backend, local SwiftData store); it adds no new infrastructure surface at all.

Developer-time cost (estimates — not researched, reasoned from the above):

| Piece | Estimate | Why |
|---|---|---|
| Rest detection | ~1 day | A timestamp field, a clock check, UI wiring |
| HealthKit workout activities | ~half a day | `beginNewActivity` / `endCurrentActivity` at boundaries the app already computes |
| Classical DSP rep counter (first version) | ~15–30 hours | Signal capture, bandpass filter, PCA projection, three-pass peak counting, wiring into the existing rep-logging pipeline |
| Real-workout tuning | Ongoing, likely the dominant cost | Thresholds/refractory periods only mean anything against real fatigued reps, not fresh-form test data |
| Custom model (Phase 3, if needed) | Several hours of recording plus labelling, spread across multiple real sessions | Training itself is instant and free; `directoryWithDataAndAnnotation` means the labelling tool is one CSV writer, not a full app |

No recurring cost follows from any of this once built, in either the DSP or the
ML path.

## Recommended plan

Built entirely inside the existing `HKWorkoutSession`/`HKLiveWorkoutBuilder`
session, which is already the sanctioned background-execution context for
continued Core Motion delivery.

- **Phase 0 — baseline.** Keep manual `+1 REP` / Digital Crown logging as the
  permanent ground truth and correction path. Every phase below adds automation
  on top of it, never replaces it outright — every commercial competitor
  surveyed (Motra/Train Fitness, Gymatic, Rep Up, the CrossFit-specific Atlon
  app) pairs automatic detection with a manual review/correction step, and
  independent reviews consistently call similar apps "not yet reliable enough to
  replace intentional logging."
  [[Gymatic review: promising, not yet reliable]](https://riven.fit/blog/best-automatic-rep-counter-apps-apple-watch)
- **Phase 1 — sensor-free rest detection.** Timestamp-since-last-rep, as above.
  Lowest risk, ships first.
- **Phase 1.5 — HealthKit workout activities.** Record a per-movement
  `HKWorkoutActivity` at boundaries `RoundRepTracker` already computes. No
  sensors, no new failure modes, and it gives the saved workout per-movement
  timing and statistics the app currently throws away.
- **Phase 2 — classical DSP rep counting per known movement.** Stream
  `CMMotionManager` (universal fallback) or `CMBatchedSensorManager`
  (`isAccelerometerSupported`, with an error path back to `CMMotionManager`) only
  while a movement is active per `RoundRepTracker`. Decimate to ~50 Hz, bandpass
  0.15–11 Hz, subtract the mean, project onto the first principal component, then
  run RecoFit's three-pass count with per-movement `minPeriod`/`maxPeriod`.
  Re-run the whole stateless count every 200 ms over a rolling buffer and emit the
  delta — that statelessness is also the direct antidote to the
  double-counting-on-relaunch bug noted below. Feed detected reps into the same
  logging path as manual taps, shown as a live, correctable count — never a silent
  auto-advance. Validate against real, fatigued attempts.
- **Phase 3 — targeted personalization, only if Phase 2 falls short (optional).**
  Gate on Soro et al.'s per-movement figures (88% / 86% / 80% within ±1). If the
  counter is materially worse, evaluate a few-shot exemplar counter before
  committing to recording and hand-labelling sessions for a narrow, single-user
  `MLActivityClassifier` — scoped to the specific weak case, not a general
  exercise classifier.
- **Phase 4 — hardware tiering and battery hardening.** Gate sensing tier via
  `isAccelerometerSupported` / `isDeviceMotionSupported` *plus* a stream-error
  fallback. Only run the DSP loop while a movement is actively expected, not
  during flagged rest — this is a stability requirement, not just a battery
  optimisation, because the documented failure mode is CPU-based suspension.
  Measure with Instruments over a full 20-minute AMRAP and check for
  CPU-exceeded logs on device.

## Risks and limitations

- **Every movement will miscount by roughly a rep per set.** Soro et al.'s
  per-movement figures put all three of Cindy's movements below the headline
  accuracy, with the **air squat worst** (79.5% within ±1). Design correction as
  the common path.
- **Push-ups barely translate a wrist-worn sensor** — RecoFit's physical
  reasoning is sound even though it does not make push-ups the worst case
  empirically. Projecting onto the first principal component rather than using
  vector magnitude is what makes this case tractable at all: during a slow
  push-up the accelerometer reads ~1 g throughout, so ‖a‖ is nearly flat while the
  gravity *direction* swings.
- **Kipping vs. strict pull-up form changes swing amplitude and rhythm as fatigue
  sets in mid-WOD**, which can break both threshold-based peak detection and a
  model trained only on fresh-form reps. RecoFit's relative amplitude threshold
  (a fraction of the 40th-percentile peak) and its `0.75 · P` refractory are the
  two details that tolerate this; copy them verbatim rather than using absolute
  thresholds.
- **A mid-set pause to shake out forearms can look like rest, or produce spurious
  peaks** — this is exactly why rest detection is built sensor-free instead of
  motion-based, and why the rep counter should only run while a movement is
  actively expected.
- **Background CPU suspension is the binary failure mode**, not battery drain.
  Apple documents that continuity survives wrist-down and screen-off during an
  active workout session, but also that "if your app uses an excessive amount of
  CPU while in the background, watchOS may suspend it" — which would kill the
  workout mid-AMRAP. Decimate before autocorrelation, run the counter only during
  expected movement, and check for CPU-exceeded logs after test sessions.
- **Hardware tiering is a real fork, not a footnote**: `CMBatchedSensorManager`'s
  high-rate mode is stated by Apple to be Series 8 and Ultra. The SDK carries no
  hardware annotation, so runtime capability checks plus a stream-error fallback
  are the only sanctioned gate — never a model list.
- **State/lifecycle bugs are as real a risk as signal-processing accuracy.** An
  existing hobbyist open-source push-up counter documents double-counting when
  its app is reopened mid-session — a reminder that naive peak-counting is
  fragile to app lifecycle edge cases, not just to noisy motion.
  [[Shakira4242/Motion — documented double-counting bug]](https://github.com/Shakira4242/Motion)

## What this doc doesn't cover

This is a feasibility and planning writeup, not an implementation.
Actually building Phase 1/2 needs testing on real hardware against real, fatigued Cindy attempts — the accuracy numbers above are from other researchers' exercises and sensor setups, not measurements of this app.
RecoFit's numbers are from a right-forearm IMU on an exercise set containing no pull-ups; uLift's are from a single wrist accelerometer; **Soro et al.'s per-movement counting figures come from CNNs fed both a wrist *and* an ankle watch** — their wrist-only results (98.91% and 95.90%) are exercise-recognition accuracy, not rep counting, and Appendix Table A2 shows every counting model used all six sensors from both watches.
Soro et al. is the closest match, but nobody has published wrist-only counting numbers for these three movements, and nobody has studied them as a fatigued 20-minute AMRAP sequence.
Treat every number above as directional, not as a guarantee for Cindy specifically.

## Corrections from the fact-check

Every claim in the original draft was re-checked against primary sources on
2026-09-03. Sixty-six claims were checked; thirty-four held as written at high
confidence. The corrections that changed something:

| # | Original claim | Correction |
|---|---|---|
| 1 | RecoFit "filters the accelerometer-magnitude signal" | **Wrong signal.** RecoFit bandpasses 0.15–11 Hz, subtracts the mean, runs PCA, and projects onto the first principal component. The paper says "Magnitude alone is rarely informative" and "we did not find the gyroscope helpful for counting." Magnitude appears only as a *segmentation* signal. |
| 2 | "autocorrelation to estimate the period, then count peaks with a refractory window" | Lossy. It is **three ordered passes**, with a **per-candidate local** period, and the autocorrelation runs *on already-found candidates*, not before peak-finding. Full recipe restated above. |
| 3 | "Soro et al. flag push-ups among the hardest to recognize from wrist data alone" | **Inverted.** Wrist-only push-up recognition is **1.000**, tied best of ten. Push-ups are a *counting* problem, and the **air squat** is the worst counter (MAE 1.82) of all ten movements. The "two independent sources agree" framing is dropped. |
| 4 | Soro's numbers are wrist data | Their **counting** models used wrist **and ankle**. Wrist-only figures are recognition, not counting. |
| 5 | "mostly forearm, not wrist" sensor placements | Only RecoFit is forearm; uLift is single-wrist; Soro is wrist+ankle. |
| 6 | RecoFit paper title | Actual title: "RecoFit: **Using a Wearable Sensor to Find, Recognize, and Count** Repetitive Exercises." |
| 7 | RecoFit dataset "200+ participants" | The released `.mat` files contain **94** subject rows, matching the paper's cohort. The repo README's "over 200" is not borne out. |
| 8 | HealthKit "has no rep-count hook of any kind" | True for *detection*; **false for recording**. `HKWorkoutActivity` + `beginNewActivity` (watchOS 9) is Apple's documented API for exactly this shape. Added as Phase 1.5. |
| 9 | Auto-pause "leans on GPS-confirmed deceleration" and is "deliberately disabled for Strength/HIIT/Yoga" | **Unsupported / false.** Apple documents neither. It is one global toggle, scoped to outdoor running and cycling. The alibaba.com citation is removed. |
| 10 | `CMMotionActivityManager` "~5–10 second confidence ramp" | Number not in the cited source. Apple's own figures are 3–5 s (running) / 5–10 s (walking), with **nothing published for the stationary transition** or for watchOS. |
| 11 | `CMBatchedSensorManager` "hardware-gated to Series 8/Ultra **and later**" | No hardware annotation exists in the SDK. Apple named Series 8 and Ultra at WWDC23 and nothing since. The cited forum thread is an early-beta error report that never mentions hardware; it is removed. |
| 12 | Background continuity "confirmed only by developer-forum reports, not an Apple guarantee" | **Apple documents it explicitly** in "Running workout sessions." The real risk is **CPU-based suspension**. |
| 13 | (not addressed) | **Permissions section added**: no entitlement, no request API, add `NSMotionUsageDescription` defensively. |
| 14 | Neural Engine "2 cores on S4–S8, 4 on S9/S10" | Apple documents **2 on S8** and **4 on S9/S10** only; S4–S7 counts are community-sourced. |
| 15 | "the same silicon already runs fall detection and swim stroke counting" | Apple has never said these run on the Neural Engine. Replaced with automatic workout detection, which Apple does list. |
| 16 | Personalization citation | The paper validates "general model + a few user labels," not "train from scratch on one person." Cindy has no general model to start from. |
| 17 | Phase 3 as a binary (DSP now, or label 10–20 sessions) | Adds the **few-shot exemplar** option, and notes `directoryWithDataAndAnnotation` makes labelling one CSV writer rather than a bespoke tool. |
| 18 | (not addressed) | `WKBackgroundModes` accepts **six** values, not one — corrected in `SenseWatch/entitlements-and-plist-notes.md` too. |
| 19 | watchOS 26 status | Confirmed: no native rep counting. Workout Buddy is voice encouragement only. |

## Further sources

- RecoFit: Morris, Saponas, Guillory, Kelner (Microsoft Research, CHI 2014),
  ["RecoFit: Using a Wearable Sensor to Find, Recognize, and Count Repetitive Exercises"](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/11/Morris_Workout_CHI_2014.pdf),
  pp. 3225–3234, DOI 10.1145/2556288.2557116.
  Public dataset (forearm IMU at 50 Hz, 94 participants, 75 activity labels, no pull-ups):
  [github.com/microsoft/Exercise-Recognition-from-Wearable-Sensors](https://github.com/microsoft/Exercise-Recognition-from-Wearable-Sensors).
- Soro et al. 2019 (ETH Zurich), ["Recognition and Repetition Counting for Complex Physical Exercises with Deep Learning"](https://doi.org/10.3390/s19030714), *Sensors* 19(3):714.
- uLift (IEEE Access 2024), ["Adaptive Workout Tracker Using a Single Wrist-Worn Accelerometer"](https://ieeexplore.ieee.org/document/10423644/).
- Apple, [`CMBatchedSensorManager`](https://developer.apple.com/documentation/coremotion/cmbatchedsensormanager) /
  [WWDC23 "What's new in Core Motion"](https://developer.apple.com/videos/play/wwdc2023/10179/).
- Apple, [Running workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions) /
  [Dividing a HealthKit workout into activities](https://developer.apple.com/documentation/healthkit/dividing-a-healthkit-workout-into-activities).
- Apple, [`MLActivityClassifier`](https://developer.apple.com/documentation/createml/mlactivityclassifier).
- Tyler Hutcherson, ["Activity Classification for watchOS" (3-part series)](https://medium.com/@tyler.hutcherson/activity-classification-for-watchos-part-1-542d44388c40).
- Commercial reference points: [Motra/Train Fitness](https://www.motra.com/) (formerly Train Fitness, "Neural Kinetic Profiling"), reviewed third-party apps summarized at [riven.fit](https://riven.fit/blog/best-automatic-rep-counter-apps-apple-watch).
