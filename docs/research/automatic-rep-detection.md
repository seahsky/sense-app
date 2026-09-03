# Automatic rep, exercise, and rest detection — research

Question: can the Watch figure out which movement is happening, count its reps,
and notice rest breaks on its own, so the only manual actions left are starting
and stopping the timer? And if that needs a trained motion model, is training
one worth it?

Researched September 2026 against watchOS 26 / Xcode 26. Sources are linked
inline; anything without a source is this document's own reasoning, labeled as
such.

## Short answer

**No off-the-shelf Apple API does this — the README is right, and still is.**
HealthKit and Core Motion have no rep-count hook of any kind: `HKWorkoutEventType`
has 8 cases (pause/resume/motionPaused/motionResumed/pauseOrResumeRequest/lap/segment/marker),
none of them a repetition or exercise-type event, and no `HKQuantityTypeIdentifier`
counts reps or sets.
[[HKWorkoutEventType]](https://developer.apple.com/documentation/healthkit/hkworkouteventtype)
[[HKQuantityTypeIdentifier]](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier)
watchOS's own Fitness app has never shipped native rep counting either — Traditional
and Functional Strength Training workouts still log only heart rate, calories, and
duration, through watchOS 26.
[[watchOS 9 announcement]](https://www.apple.com/newsroom/2022/06/watchos-9-delivers-new-ways-to-stay-connected-active-and-healthy/)
A commonly repeated claim that "Series 9+ counts reps automatically" turned up in a
couple of low-authority blog posts but is contradicted by every primary source
checked — treat it as misinformation.

**But the question underneath — "should we train a custom model?" — turns out to
have a better answer than the README implies, once you notice something specific
to this app: Cindy's movement sequence is fixed and known (5 pull-ups → 10
push-ups → 15 air squats, repeating). `RoundRepTracker` already derives which of
the three movements is current from the running rep count, with zero sensors
involved.**
[[RoundRepTracker.swift]](../../Packages/CindyKit/Sources/CindyKit/Tracking/RoundRepTracker.swift)
That's the single hardest and most expensive part of general exercise recognition
(academic systems spend most of their model capacity on "which of N exercises is
this?"), and Cindy gets it for free by design. That collapses "auto-detect
exercise + reps + rest" into two much smaller problems, one of which doesn't need
sensors or a model at all:

| Sub-problem | Needs a trained model? | Verdict |
|---|---|---|
| Which movement is active | No — already solved | `RoundRepTracker` derives it from the rep count today |
| Rest detection | No | Timestamp-since-last-rep; see below |
| Rep counting | Not at first | Classical signal processing (peak detection + autocorrelation); a custom model is a fallback for one weak case (push-ups), not a starting point |

So: **don't start by training a model.** Build a plain DSP rep counter first. Only
train something if real testing shows it's not good enough — and even then, scope
it narrowly instead of building the 3-way classifier the README assumed was the
only option.

## Why "which movement" isn't actually an open problem here

General human-activity-recognition (HAR) research — the closest prior art —
assumes it doesn't know what exercise is happening and has to classify it from
the signal. Cindy doesn't have that problem: the sequence is fixed, so
`RoundRepTracker.recompute()` flips `currentMovement` the instant the 5th
pull-up (or 10th push-up) is logged, deterministically, with no sensing
involved. Spending effort on a 3-class exercise classifier would be re-solving a
problem this app's architecture already eliminated, and would add a new failure
mode (misclassifying the current movement) that the app cannot suffer from
today.

This is also why an ML classifier, if one is ever built (see Phase 3 below),
should never be a general "which exercise is this" classifier — that job is
already done for free.

## Rest detection: solved without touching a sensor

Apple's two built-in candidates for "is the user resting" are both a bad fit:

- **Workout auto-pause** (`HKWorkoutEventType.motionPaused`/`.motionResumed`) is
  scoped to outdoor run/cycle workouts — it leans on GPS-confirmed deceleration,
  not accelerometer data alone, and Apple deliberately disables the Auto-Pause
  toggle for Strength, HIIT, and Yoga workout types because the cardio stillness
  heuristic doesn't fit circuit-style rest.
  [[HKWorkoutEventType.motionPaused]](https://developer.apple.com/documentation/healthkit/hkworkouteventtype/motionpaused)
  [[Auto-Pause unavailable for Strength/HIIT/Yoga]](https://www.alibaba.com/product-insights/why-do-my-apple-watch-workouts-sometimes-auto-pause-during-strength-training-and-how-to-prevent-it.html)
- **`CMMotionActivityManager`**'s "stationary" state is a coarse, battery-optimized
  daily-activity classifier with a ~5–10 second confidence ramp per transition —
  built for all-day logging, not sub-15-second exercise-set gaps.
  [[CMMotionActivity confidence ramp]](https://nshipster.com/cmmotionactivity/)

Cindy doesn't need either. Every rep is already a discrete, authoritative,
user-confirmed event — a tap or a Digital Crown detent — not a noisy inferred
one. So rest reduces to: **track the timestamp of the last logged rep; while the
AMRAP timer is running, if N seconds pass with no qualifying rep, the state is
"resting."** No Core Motion, no HealthKit workout events, no variance threshold
to tune against sensor noise. This is also exactly how a shipped ML-based
competitor operationalizes rest: Train Fitness/Motra's own docs say rest starts
"when a set is detected as finished," i.e. time-since-last-confirmed-event, not
a separately trained resting-motion class.
[[Train Fitness rest-timer docs]](https://help.trainfitness.ai/en/articles/9671219-rest-time-and-rest-alarm)

The one gap this can't close: if the user is genuinely still repping but forgets
to tap, the app will wrongly infer rest after N seconds. A cheap corroborating
signal (raw accelerometer variance, or `CMMotionActivityManager`) could suppress
that false positive later, but it's an optional refinement layered on top of the
timer, not a prerequisite — and reintroduces the false-positive-tuning problem
the timer-only design avoids.

Picking N (likely 8–15s) needs empirical tuning against real fatigued WOD
attempts, not research — it trades early rest indication against flagging a
brief mid-set pause (shaking out forearms between pull-ups) as a real break.

## Rep counting: the one place real sensing work is justified

### What's actually available on-device

- **`CMMotionManager`** — universal since watchOS 2.0, real-time delivery, capped
  around 100Hz. Works on every watch this app supports (watchOS 10+, Series 4
  onward).
- **`CMBatchedSensorManager`** — new in watchOS 10 (WWDC23), purpose-built for
  exactly this: up to 800Hz accelerometer / 200Hz device motion, delivered in
  one-second batches at lower power, but it *requires an active `HKWorkoutSession`*
  to produce any data at all — which Cindy already runs — and is hardware-gated
  to Series 8/Ultra and later.
  [[WWDC23: What's new in Core Motion]](https://developer.apple.com/videos/play/wwdc2023/10179/)
  [[Series 8+/Ultra hardware gate]](https://developer.apple.com/forums/thread/733858)
  Series 4–7 and SE need the plain `CMMotionManager` fallback.
- An active `HKWorkoutSession` is a sanctioned watchOS background-execution
  context (like audio or mindfulness sessions) — Apple engineers have told
  developers on the forums that *faking* a background capability just to keep
  raw motion streaming alive risks App Store rejection, but Cindy's workout
  session is genuine, so this isn't a concern here.
  [[Apple DTS on background motion capture]](https://developer.apple.com/forums/thread/765258)

### Classical signal processing works, and is competitive with deep learning specifically for counting

The technique, established by Microsoft Research's **RecoFit** (CHI 2014, shipped
on the Microsoft Band) and confirmed since: filter the accelerometer-magnitude
signal, use **autocorrelation to estimate the current repetition period**, then
**count peaks using a refractory window sized to that period** (naive
peak-counting alone over- or under-counts on non-trivial waveforms — squats in
particular show a "double peak" per rep in RecoFit's own data, one for the
descent and one for standing back up).
[[RecoFit paper, PDF]](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/11/Morris_Workout_CHI_2014.pdf)

Reported accuracy for this style of classical approach is genuinely good and not
obviously beaten by deep learning on the counting sub-task specifically:

- RecoFit: >95% segmentation precision/recall, 96–99% exercise recognition on
  4/7/13-exercise circuits, reps counted within ±1 on 93–97% of sets — using
  hand-crafted-feature SVMs plus autocorrelation-refined peak detection, not
  raw deep learning.
- **uLift** (IEEE 2024) — a fully classical, *training-free* single-wrist system
  (autocorrelation + peak filtering + DTW template matching, no ML model at
  all) — reaches 93.1% workout-detection accuracy, 90.1% classification
  accuracy, and a mean counting error of 0.61 reps.
  [[uLift]](https://ieeexplore.ieee.org/document/10423644/)
- **Soro et al. 2019** (ETH Zurich, *Sensors*) — a CNN trained on wrist+ankle
  smartwatch data across 10 CrossFit movements including pull-ups, push-ups,
  and burpees — gets 99.96% classification accuracy and 91% of sets within ±1
  rep. Deep learning's edge shows up mainly on classification as the exercise
  set grows, not on counting itself.
  [[Soro et al. 2019, DOI]](https://doi.org/10.3390/s19030714)

### Push-ups are the specific weak point — expect that, don't be surprised by it

Two independent sources, one testing a plain wrist/forearm IMU (RecoFit) and one
testing CrossFit movements specifically on the wrist (Soro et al.), reach the
same conclusion for the same physical reason: **a push-up barely translates a
wrist-worn sensor at all.** Unlike a pull-up (large, controlled vertical arm
excursion against gravity — the strongest, cleanest signal of the three) or an
air squat (moderate signal, with that characteristic double-peak), a push-up
moves the whole body together, so the wrist mostly just sees a subtle, repeated
tilt of the gravity vector rather than real acceleration energy. RecoFit states
this outright:

> "Some exercises, e.g. pushups, result in almost no translation of an arm-worn
> sensor... the primary observable phenomenon in these cases is not energy on
> any sensed axis, but a repetitive change in the gravity axis observed by the
> accelerometer."

Soro et al. independently flag push-ups among the hardest of their 10 movements
to recognize from wrist data alone. Plan for push-up auto-counting to be the
least reliable of Cindy's three movements under any approach, and keep manual
correction most visible during that segment of a round.

## Should we train our own model?

**Conditional no — not as a first step, and possibly not at all.**

Training a 3-way exercise classifier would re-solve a problem `RoundRepTracker`
already solves for free, at the cost of a new failure mode (misclassifying the
active movement) the app doesn't currently have. Start instead with:

1. Timestamp-based rest detection (no sensors, no model).
2. A classical DSP rep counter — accelerometer/gyro peak detection refined by
   autocorrelation, run only for whichever single movement `RoundRepTracker`
   says is currently active. This is a bounded, well-precedented DSP problem,
   not a machine-learning problem.

**Only build a custom model if real-world testing on real, fatigued WOD attempts
shows the DSP counter's error rate is unacceptable** — most plausibly for
push-ups specifically, per the section above. If that happens, `Create ML`'s
**Activity Classifier** template (`MLActivityClassifier` — distinct from the
video/pose-based `Action Classifier`, which doesn't apply here since there's no
camera on the wrist) is the right tool: it trains on labeled Core Motion
accelerometer/gyroscope session recordings and exports a Core ML model that runs
entirely on-device.
[[MLActivityClassifier docs]](https://developer.apple.com/documentation/createml/mlactivityclassifier)
Even then, keep it narrow — a single-movement counter or a binary
active-motion/rest confidence gate feeding the same DSP pipeline — not a general
exercise classifier, since exercise identity is never actually in question.

Every Apple Watch since Series 4 has a Neural Engine (2 cores on S4–S8, 4 cores
on S9/S10), so continuous inference for a model this small is well within
established hardware — the same silicon already runs Apple's own always-on
motion classifiers (fall detection, swim stroke counting) today.
[[Neural Engine by device]](https://github.com/hollance/neural-engine/blob/master/docs/supported-devices.md)
A complete, publicly documented pipeline (Core Motion recording → Create ML
Activity Classification → on-watch Core ML inference) exists and has been
walked through end-to-end.
[[Tutorial: Activity Classification for watchOS]](https://medium.com/@tyler.hutcherson/activity-classification-for-watchos-part-1-542d44388c40)

### Overfitting to one user is fine here — that's the point, not a compromise

Wrist-worn activity classifiers trained on one person are documented to
generalize inconsistently to other people (different limb length, tempo, watch
fit, handedness); the standard mitigation in the literature is exactly
per-person personalization.
[[Personalization needed for wrist-IMU generalization]](https://pmc.ncbi.nlm.nih.gov/articles/PMC6639791/)
Cindy has no accounts and no sync — it's a personal, single-user, local app by
design. Training a model on one person's own reps isn't a corner cut here, it's
the literature's recommended approach applied to a project that's already
scoped for exactly one user. It would become a real blocker only if this model
were ever shipped to strangers on the App Store as-is — that would need either
a much larger multi-subject dataset or a real per-user calibration flow, a
materially bigger commitment than the app's current scope.

## Cost — and confirmation this stays scale-to-zero

**Zero ongoing infrastructure cost either way, verified rather than assumed.**
`Create ML` runs as a free local Mac app bundled with Xcode — training is
entirely offline, no cloud GPU rental required.
[[Create ML is a free local Xcode tool]](https://www.createwithswift.com/create-ml-explained-apples-toolchain-to-build-and-train-machine-learning-models/)
On-device Core ML inference has no marginal per-inference cost and no server
dependency — the compiled model ships inside the app bundle like any other
resource and runs on the Watch's own Neural Engine/CPU. This is architecturally
identical to how Cindy already ships (no backend, local SwiftData store); it
adds no new infrastructure surface at all.

Developer-time cost (estimates — not researched, reasoned from the above):

| Piece | Estimate | Why |
|---|---|---|
| Rest detection | ~1 day | A timestamp field, a clock check, UI wiring |
| Classical DSP rep counter (first version) | ~15–30 hours | Signal capture, filtering, autocorrelation/peak detection, wiring into the existing rep-logging pipeline |
| Real-workout tuning | Ongoing, likely the dominant cost | Thresholds/refractory periods only mean anything against real fatigued reps, not fresh-form test data |
| Custom Create ML model (Phase 3, if needed) | Several hours of recording + several more of labeling, spread across multiple real sessions | Training itself is instant and free; realistically 10–20 full Cindy-length sessions to get enough labeled reps per movement, and Apple ships no labeling tool for this step — you write your own |

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
- **Phase 2 — classical DSP rep counting per known movement.** Stream
  `CMMotionManager` (universal fallback) or `CMBatchedSensorManager` (Series
  8/Ultra+) only while a movement is active per `RoundRepTracker`. Compute
  acceleration/gyro magnitude, filter, estimate rep period via autocorrelation,
  count via peak detection with a period-sized refractory window. Feed detected
  reps into the same logging pipeline as manual taps, shown as a live,
  correctable count — never a silent auto-advance. Validate against real,
  fatigued attempts before trusting it; expect push-ups to need the most
  tuning or the lowest confidence threshold.
- **Phase 3 — targeted personalization, only if Phase 2 falls short (optional).**
  If real testing shows an unacceptable miscount rate for a specific movement
  (most likely push-ups), record 10–20 real sessions, hand-label rep/rest
  boundaries, and train a narrow, single-user `MLActivityClassifier` offline —
  scoped to the specific weak case, not a general exercise classifier.
- **Phase 4 — hardware tiering and battery hardening.** Gate sensing tier via
  `isAccelerometerSupported`/`isDeviceMotionSupported`. Only run the
  DSP/inference loop while a movement is actively expected, not during flagged
  rest — and measure real battery/latency impact over a full 20-minute AMRAP
  with Instruments before shipping broadly, since no Watch-specific benchmark
  for this exact workload could be found in this research.

## Risks and limitations

- **Push-ups are structurally the weak movement for any wrist-worn sensor** —
  two independent academic sources agree on this and on why. Don't expect
  parity with pull-up/squat counting regardless of approach.
- **Kipping vs. strict pull-up form changes swing amplitude and rhythm as fatigue
  sets in mid-WOD**, which can break both threshold-based peak detection and a
  model trained only on fresh-form reps. Tune against real fatigued attempts.
- **A mid-set pause to shake out forearms can look like rest, or produce spurious
  peaks** — this is exactly why rest detection is built sensor-free instead of
  motion-based, and why the rep counter should only run while a movement is
  actively expected.
- **Battery drain from continuous high-rate sensing** (especially
  `CMBatchedSensorManager`'s 800Hz/200Hz mode plus any inference) needs empirical
  measurement over a full 20-minute session — no Watch-specific benchmark for
  this workload exists in the sources checked.
- **Hardware tiering is a real fork, not a footnote**: `CMBatchedSensorManager`'s
  high-rate mode needs Series 8/Ultra or later; watchOS 10's supported floor
  (Series 4+) includes older watches that need the plain `CMMotionManager`
  fallback, whose background continuity through screen-off/wrist-down states is
  confirmed only by developer-forum reports and by existing shipping apps, not
  a single explicit Apple guarantee — verify directly on target hardware.
- **State/lifecycle bugs are as real a risk as signal-processing accuracy.** An
  existing hobbyist open-source push-up counter documents double-counting when
  its app is reopened mid-session — a reminder that naive peak-counting is
  fragile to app lifecycle edge cases, not just to noisy motion.
  [[Shakira4242/Motion — documented double-counting bug]](https://github.com/Shakira4242/Motion)

## What this doc doesn't cover

This is a feasibility and planning writeup, not an implementation. Actually
building Phase 1/2 needs testing on real hardware against real, fatigued Cindy
attempts — the accuracy numbers above are from other researchers' exercises and
sensor placements (mostly forearm, not wrist; mostly not this exact 3-movement
sequence), not measurements of this app. Nobody has published a study of this
exact fixed pull-up/push-up/air-squat circuit worn on the wrist — treat every
number above as directional, not as a guarantee for Cindy specifically.

## Further sources

- RecoFit: Morris, Saponas, Guillory, Kelner (Microsoft Research, CHI 2014),
  ["RecoFit: Automatic Segmentation, Recognition and Counting of Repetitive Exercises"](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/11/Morris_Workout_CHI_2014.pdf).
  Public dataset (forearm IMU, 200+ participants, no pull-ups):
  [github.com/microsoft/Exercise-Recognition-from-Wearable-Sensors](https://github.com/microsoft/Exercise-Recognition-from-Wearable-Sensors).
- Soro et al. 2019 (ETH Zurich), ["Recognition and Repetition Counting for Complex Physical Exercises with Deep Learning"](https://doi.org/10.3390/s19030714), *Sensors* 19(3):714.
- uLift (IEEE 2024), classical training-free wrist rep counter:
  [ieeexplore.ieee.org/document/10423644](https://ieeexplore.ieee.org/document/10423644/).
- Apple, [`CMBatchedSensorManager`](https://developer.apple.com/documentation/coremotion/cmbatchedsensormanager) /
  [WWDC23 "What's new in Core Motion"](https://developer.apple.com/videos/play/wwdc2023/10179/).
- Apple, [`MLActivityClassifier`](https://developer.apple.com/documentation/createml/mlactivityclassifier).
- Tyler Hutcherson, ["Activity Classification for watchOS" (3-part series)](https://medium.com/@tyler.hutcherson/activity-classification-for-watchos-part-1-542d44388c40).
- Commercial reference points: [Motra/Train Fitness](https://www.motra.com/) (formerly Train Fitness, "Neural Kinetic Profiling"), reviewed third-party apps summarized at [riven.fit](https://riven.fit/blog/best-automatic-rep-counter-apps-apple-watch).
