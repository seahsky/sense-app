# Posture-aware rep detection: where the watch is during Cindy

Follow-up to [rep-detection-precision.md](rep-detection-precision.md), which found the detector has no
exercise / non-exercise gate.
This document asks whether the posture of the wrist can supply that gate, movement by movement.

Produced by a fifteen-agent study: three movement dossiers plus an SDK lens and a literature lens, each
adversarially verified; three independent detector architectures; a judge that scored and merged them; and a
completeness critic that re-derived the physics from scratch and re-measured the result.
Both the judge and the critic compiled the repo's real, unmodified `Sensing/` sources and measured against
them; the critic md5-checked all seven files against the repo before trusting its own harness.
Eleven claims were rejected as unverifiable or misattributed and are listed at the end so nobody re-proposes them.

## The answer

**The hypothesis is right, and it is worth about 30 phantom reps per movement block, for two of the three movements.**

The pull-up and the push-up are the same case, not opposite cases.
Both anchor the hand to something that does not move, so the wrist barely translates and the forearm pivots
about a fixed joint.
What the watch sees is the gravity vector sweeping through a large, repeatable arc.
The two postures are antipodal on the one axis the current pipeline throws away: a pull-up keeps the hand
above the elbow, a push-up keeps it below.

The existing comment in `Movement+RepCounting.swift` calling the pull-up "the cleanest signal of the three, a
large, controlled vertical arm excursion against gravity" is wrong about the physics.
The wrist travels about 7.7 cm of arc about the bar, against the 40 to 60 cm the athlete's centre of mass
travels.
Gravity rotation beats linear translation by about 20 to 1 in that block.
The critic re-derived this independently with a two-segment cosine model and got 0.37 G of axial swing
against the judge's measured 0.366 G, so the premise holds.

**The air squat gets nothing.**
The hand is free, so no posture is required and none is forbidden.
An arms-hanging squat reads the same as walking, and no accelerometer statistic separates them.
That is 15 of the 30 reps in every round.

## Do not ship section 3 as written

Three defects, all measured by the critic against the real sources.

**1. The air-squat predicate deletes the whole movement for a common athlete.**
The `.airSquat` branch rejects any hand-above-elbow window with no anchoring clause.
Hands clasped at the chest is one of the two standard CrossFit air-squat arm positions, and it reads axial
-0.866, so the gate is shut in 76 of 76 windows and counts nothing.
Measured: 19 reps ungated becomes 0 gated. Fingertips at temples, the same. Round 15 slow with hands at
chest, the same.
Across a full Cindy that is roughly 200 reps the current detector counts and this one would not, with
nothing in the UI to say why. The pips simply never move.
The design's own sentence describing that branch as "purely exclusionary" is not what the code does.

**2. The push-up gate admits a plank.**
A fatigued athlete resting in a plank reads axial +0.990 with the anchoring clause satisfied, so the gate is
open in 56 of 56 windows and emits 15 phantom push-ups in 30 seconds.
`detectedRepAllowance` for the push-up block is 9, so 20 seconds of plank rest fills the entire block.
The design concedes the equivalent residual on the bar and misses this one.
Also unmodelled and gate-open, all in the pull-up block: a forehead wipe (19 phantoms), a headband adjust
(14), drinking from a bottle (10).

**3. Three bugs in the `RepDetectionEngine` patch.**
The blackout seed is placed before the backwards-clock `reset()`, so after a tier failover mid-set it never
re-arms and the priming transient counts; key it on `emittedThrough == -.infinity` instead and move it just
before the recount.
The seed is guarded by `guard let postureGate`, which makes the cheapest and safest change conditional on
the riskiest one, and it is the only part that helps the air squat.
And `emittedThrough` still advances to `cutoff` while the gate is shut, so a mid-set stream restart silently
deletes the next two seconds of real reps.

## The premise the design rests on, stated plainly

Every number labelled "measured" in section 3 came from a generator that models a rigid forearm rotating
about a named pivot at a named radius.
Anchoring is that generator's assumption, so no test written against it can falsify it.
The critic re-derived the anchoring physics independently and it holds, so the premise is sound.
The four thresholds calibrated against that generator are not validated, and two of them
(`anchorRadius`, `pivotProximalLimit`) are sub-decimetre distances that a loose watch band changes by tens
of percent.
The critic measured `anchorRadius` as within a factor of about 1.2 of deleting fresh push-ups.

## The correlated-miss problem

This is the most important omission, and all four upstream agents inherited it unexamined.

The precision-over-recall rule says a missed rep is harmless because the athlete keeps tapping until the
movement advances.
That is true when misses scatter at random.
A posture gate produces misses that correlate perfectly with a stable property of the athlete: their arm
position, their wrist and crown setting, how tight their band is.
A systematically shut gate turns the app into a tap counter for a whole session and reports nothing.
A veto that can zero a block has to log its decision and its axial value before it is allowed to suppress
anything.

Related: the gate makes a hard veto depend on `RoundRepTracker.currentMovement`, which is a belief, not an
observation. It is wrong exactly when the athlete forgets to tap, which is the commonest real error.
Today a wrong belief swaps three constants. With the gate, it can zero the count silently.

## Build this first instead

Both this study and the previous audit arrived at the same change independently, from different directions.
It is six lines.

```swift
// Packages/SenseKit/Sources/SenseKit/Tracking/RoundRepTracker.swift
public var detectedRepAllowance: Int {
    guard hasAssertedRepInCurrentMovement else { return 0 }
    return max(0, repsRemainingInCurrentMovement - 1)
}
```

Require an asserted rep to OPEN a movement block, exactly as one is already required to close it.
Derivable from `events` plus the existing `RepSource.isUserConfirmed` (`RepEvent.swift:21`), no new state,
`recompute()` untouched, one test.

Why it goes first:

- It hits where the phantoms are.
  All three secondary amplifiers from the previous audit discharge in the first seconds of a segment, when
  the allowance is at its widest 4 / 9 / 14.
- It covers all three movements, including the air squat, which the posture gate cannot help and which is
  half the reps in every round.
- It covers the whole bar-to-floor-to-standing transition, which is 5 to 20 seconds at round 12 and which no
  posture in the gate's model describes.
- Its failure mode is one extra tap per movement: visible, bounded, and the same interaction the athlete
  already knows. The gate's failure mode is silent and unbounded.
- It needs no threshold, no device capture, no new file, and no purity argument, and it composes with
  everything in section 3.

Cost: detectable reps fall from 27 to 24 out of 30 per round, and the design's own 2 s blackout already
spends most of that.

Then, in order: correct the wrong physics comments (zero risk, section 3.6); make the blackout seed
unconditional and fix the three patch bugs; shadow-log the gate's open/shut decision and axial value beside
the ungated count without letting it suppress anything; make `distalSign` self-calibrating from the
pull-up / push-up antipodality, which removes the wrist-setting capture from the critical path entirely;
and ship the gate for the pull-up and push-up only, never for the air squat.

---


The owner's hypothesis is right, and it is worth about 30 phantom repetitions per movement block.
Two of Cindy's three movements anchor the hand to something that does not move, and they are antipodal on the one axis a wrist-worn accelerometer can read without any new sensor.
Measured on the repo's real, unmodified `Sensing/` sources this session: 40 s of a 22 degree / 0.95 Hz free-arm swing emits 33 phantom pull-ups, 37 phantom push-ups and 35 phantom air squats today, and a posture gate takes the first two to zero without costing one repetition in any modelled case, fresh or fatigued.
The air squat gets nothing, and that is a third of the workout.

The winning design is Approach 1.
It is grafted with Approach 2's pivot regression and Approach 3's abstention rule, and it rejects Approach 2's replacement of the counter and Approach 3's move to device motion.

---

## 1. Where the watch actually is

The physical answer is that the pull-up and the push-up are the same case, not opposite cases, and the app's own source comment says the reverse.

| | Pull-up | Push-up | Air squat |
|---|---|---|---|
| Wrist | Anchored to a fixed bar | Anchored to the floor in wrist extension | Free, travels with the body |
| Watch travel per rep | 0.077 m of arc about the bar (measured on my model at a 40 degree sweep, r = 0.11 m) | 0.029 m of arc about the palm (33 degree sweep, r = 0.05 m) | 0.20 m to 0.45 m of translation, set by arm position, not by the movement |
| What the IMU sees | Gravity rotating 24 to 60 degrees through the body frame | Gravity rotating 5 to 46 degrees through the body frame | Body translation plus whatever the arm happens to do |
| Gravity-direction swing per rep | 40 degrees fresh, 24 degrees at round 15 (physics estimate from the verifier-corrected geometry, not a measurement) | 33 degrees fresh, 13 degrees at round 15 (same status) | 0 degrees arms-tucked in the dossier's model, about 33 degrees once trunk pitch is included (verifier's correction, not remeasured by me) |
| Linear acceleration at the watch | 0.027 G peak at 2.4 s per rep, 0.114 G on a 1.3 s kip (measured) | 0.030 G peak at 1.4 s, 0.126 G at 0.8 s (measured) | 0.05 G to 1.0 G, dominated by the athlete's arm habit |
| Gravity rotation beats translation by | 14x on the dorsal axis (0.559 G against 0.027 G, measured) | 20x (0.600 G against 0.030 G, measured) | It does not; translation is the signal |
| Vector magnitude excursion | 0.068 G peak-to-peak, nearly flat (measured) | 0.058 G, nearly flat (measured) | 0.2 G to 1.0 G |
| Posture signature | Hand **above** elbow all set. Axial reads -0.66 to -1.00 (measured across strict, kipping, butterfly and round-15 forms) | Hand **below** elbow all set. Axial reads +0.85 to +0.95 | None. Axial reads +1.00 arms-hanging, which is identical to walking |
| Posture usable as a gate | Yes, one signed scalar | Yes, but it needs a second clause, because a plank and a hanging arm are the same posture | No |

`Packages/SenseKit/Sources/SenseKit/Sensing/Movement+RepCounting.swift:26-28` says:

> // The cleanest signal of the three — a large, controlled vertical arm
> // excursion against gravity. The wide upper bound covers a fatigued
> // athlete hanging between reps.

"The cleanest signal of the three" holds, and the sentence about the hang and `maxPeriod = 4.0` holds.
"A large, controlled vertical arm excursion" is wrong.
There is no vertical excursion of the sensor.
The hand grips a bar that does not move, the body rises toward the hand, and the watch travels 8 cm on a shallow arc while the athlete's centre of mass travels 40 to 50 cm.
The signal is the gravity vector rotating through the watch body frame.
I measured 0.366 G peak-to-peak on the forearm axis and 0.559 G on the dorsal axis against 0.027 G of linear acceleration from the watch's own arc, and a vector magnitude that stays inside a 0.068 G band, which is only possible if the sensor is not translating.

The same file at lines 32-37 says:

> // The weakest signal physically: a push-up barely translates a
> // wrist-worn sensor, so what the accelerometer sees is mostly the
> // gravity vector tilting.

The mechanism is right and the ranking is wrong, but the important error is structural rather than numeric.
The file presents the pull-up as travelling and the push-up as tilting, so it presents them as opposite cases.
They are the same case with different lever lengths and opposite signs.
That framing is what hides the single most useful discriminator in the application: a pull-up and a push-up are 180 degrees apart on the forearm axis, and a walking arm swing sits with the push-up.

The file header at lines 21-23 makes the same claim a third time ("a push-up genuinely moves the wrist least"), and `PrincipalAxis.swift:16` completes the picture by asserting that "PCA also buys rotation invariance for free".
It is not free.
Yurtman and Barshan measure the concession at 7.56% and 15.54% accuracy against a known-orientation reference (carried from the literature lens, verified by its verifier, not refetched by me).
The right fix is not to remove PCA, which every one of the three approaches agrees must stay, but to put the orientation information back on a separate channel that only ever suppresses.

---

## 2. What that buys

The air squat has no usable posture gate, and it is 15 of the 30 repetitions in a Cindy round.
The hand is free, so no posture is required and none is forbidden.
An arms-hanging squat reads axial +1.00 and so does walking, and I could find no accelerometer statistic separating them, which is also what all three approaches concluded independently and what RecoFit states outright.
Everything below applies to two movements out of three.

What the gate does buy is the exercise/non-exercise gate the previous audit found missing, obtained from posture, with no classifier, no training data and no new sensor.
Measured end to end this session on the real `Bandpass` / `PrincipalAxis` / `RepPeakCounter` chain, with each phantom source streamed into a fresh segment exactly as the watch streams it:

**Killed outright, pull-up block:** walking at 22 degrees / 0.95 Hz 32 to 0, at 35 degrees / 1.15 Hz 42 to 0, a 0.8 Hz shuffle 23 to 0, standing elbow shake-out 18 to 0 and 30 to 0, chalking 25 to 0, weighted-vest adjustment 11 to 0, hands on knees 16 to 0, and push-up bleed across the boundary tap 27 to 0.

**Killed outright, push-up block:** walking 34 to 0, 43 to 0 and 60 to 0, chalking 24 to 0, vest 32 to 0, hands on knees 17 to 0, pull-up bleed 16 to 0, bar hang bleed 16 to 0, bar rest-swing bleed 28 to 0, and the faster standing elbow shake-out 31 to 0.

**Not killed, pull-up block:** a rest swing on the bar stays at 28 phantoms, a still hang at 8, and shaking the forearms out while still hanging at 26.
All three are genuine rotations about the bar in the genuine pull-up posture, and the gate correctly says so.
This is the largest single admission in the design, and it is worst exactly at round 15, when hanging is most of what the athlete does.

**Not killed, push-up block:** a very slow standing elbow flexion at 3.0 s stays at 12 phantoms, and a 2.0 s one drops from 18 to 3.
Both are rotations about the elbow at 0.22 m in the same posture as a push-up, and only the pivot regression reaches them at all.

The cross-movement bleed is the cleanest win and nothing else in the pipeline can reach it.
A pull-up reads axial -0.80 to -0.91 and a push-up +0.91 to +0.95, so the batch that straddles the athlete's boundary tap, which the audit named as cause 3, is rejected on the one channel `Bandpass` deletes as DC and `PrincipalAxis` is built to ignore.

Recall cost from the gate itself is zero.
In every modelled repetition case, strict, 50 degree, kipping at 1.3 s and 1.6 s, butterfly at 1.1 s with a 25 degree hang floor, round-15 at 28 and 24 degrees, fresh push-up, fast push-up at 1.0 s and 0.8 s, round-15 push-up, near-collapse push-up, and a watch worn high on the forearm, the gated count equals the ungated count exactly.
All measured recall loss belongs to the 2 s segment-start blackout, which costs about one repetition per block against a `detectedRepAllowance` of 4 / 9 / 14.

---

## 3. The design

One new Foundation-only file, about ten lines inside `RepDetectionEngine.ingest`, one line in `MotionRepSensor`, and two comment corrections.
`Bandpass`, `PrincipalAxis` and `RepPeakCounter` are untouched.
The gate only ever suppresses; it never counts, never advances the sequence and never closes a movement.

### 3.1 The channel

The gate reads the raw `MotionSample` buffer `RepDetectionEngine` already holds, before band-passing.
Over a window spanning a whole repetition the body returns where it started, so the mean user acceleration is near zero and the arithmetic mean of the raw vector is the mean gravity vector.
The channels lens measured that at 1.66 degrees mean and 3.24 degrees worst error under a 0.5 G air-squat bob at a 3 s window; the predicates below discriminate tens of degrees.
No Core Motion change, no gyroscope, no device motion, no new acquisition tier, no plist change.
One `Double` crosses the watch boundary, which is the pattern `MotionSample`'s own doc comment already establishes.

### 3.2 `Packages/SenseKit/Sources/SenseKit/Sensing/PostureGate.swift` (new)

```swift
import Foundation

/// Whether the wrist is in the posture the expected movement requires.
///
/// Cindy anchors the hand in two of its three movements: a pull-up grips a bar
/// that does not move, and a push-up plants a palm on a floor that does not
/// move. In both, the forearm spends the whole set near vertical, and they are
/// ANTIPODAL on that axis, because a pull-up puts the hand above the elbow and a
/// push-up puts it below. That one bit is unreachable anywhere else in the
/// pipeline: `Bandpass` removes gravity as DC, and `PrincipalAxis` is
/// rotation-invariant by construction, which is exactly why it cannot see it.
///
/// This type only ever suppresses. The athlete's tap remains ground truth.
public struct PostureGate: Sendable, Equatable {
    /// +1 when the watch's hardware +Y axis, the case long axis, points
    /// distally along the forearm toward the hand. -1 otherwise.
    ///
    /// MEASURED ON DEVICE, NO DEFAULT. Apple documents the axis convention and
    /// documents `WKInterfaceDevice.wristLocation` and `.crownOrientation`
    /// (WKInterfaceDevice.h:48-50 and :84-85, watchOS 3.0, verified by me in
    /// WatchOS26.5.sdk), but nowhere documents the mapping between them. Getting
    /// this backwards does not degrade detection, it deletes it, so the gate is
    /// `nil` until a five-minute capture settles it. See section 4, step 4.
    public let distalSign: Double

    /// Trailing window the posture is judged over.
    ///
    /// DERIVED, not measured by me. Approach 1 swept 1.5 / 2.0 / 4.0 s and found
    /// 4.0 s blanks 1.7 of the five repetitions in a pull-up block for no
    /// measured gain, and 1.5 s leaves the windowed mean too contaminated by the
    /// repetition itself. I reused 2.0 s and did not re-sweep it.
    public let window: TimeInterval

    /// How far the forearm may lie from vertical and still count, as a cosine.
    /// 0.45 is about 63 degrees.
    ///
    /// MEASURED on synthetic geometry, and it sits mid-plateau rather than on a
    /// cliff. Worst-case repetition margins over 2 s windows: pull-up -0.66
    /// (60 degree kip), -0.72 (butterfly, 25 degree hang floor), -0.77
    /// (50 degree kip), -0.87 to -0.91 (strict and round 15); push-up +0.85
    /// (0.8 s), +0.91 (fresh), +0.95 (round 15). Confounders that must fall
    /// between the two thresholds: chalking +0.37, hands on knees +0.34, vest
    /// adjustment -0.15. The nearest real repetition is 0.21 clear of the
    /// threshold and the nearest confounder is 0.08 clear on the other side.
    /// A device trace should re-derive it from the butterfly case, which is the
    /// one that comes closest.
    public let axialThreshold: Double

    /// Effective pivot radius, metres, above which the wrist is judged to be
    /// travelling rather than turning about something it sits beside.
    ///
    /// PLACEHOLDER awaiting a device trace, and APPLIED TO THE PUSH-UP ONLY.
    /// Measured, this clause rejects fast and deep pull-ups: a 50 degree strict
    /// rep at 2.0 s, a 50 degree kip at 1.3 s, a butterfly at 1.1 s and a
    /// 60 degree kip at 1.6 s all fail it, taking 18, 20, 25 and 17 real
    /// repetitions to zero. Approach 1 reached the same conclusion on its own
    /// geometry and dropped the clause from the pull-up for the same reason.
    public let anchorRadius: Double
    public let anchorNoise: Double

    /// Signed pivot distance, metres, beyond which a PROXIMAL pivot (an elbow at
    /// about 0.22 m, a shoulder at about 0.60 m) is not a Cindy repetition.
    ///
    /// PLACEHOLDER. Measured separation at a 2 s window: planted palm -0.046 m
    /// against a true -0.050, elbow +0.175 m against a true +0.220 at a 2.0 s
    /// tempo and +0.516 m at 1.2 s. The threshold sits between them and the
    /// estimator attenuates with tempo, so it is the number most in need of a
    /// trace.
    public let pivotProximalLimit: Double

    /// Coefficient of determination the pivot fit must reach before the clause
    /// is allowed to act at all.
    ///
    /// PLACEHOLDER, and the SHAPE is the point rather than the value. Measured
    /// fit quality: 0.78 to 0.95 on fresh anchored repetitions, 0.39 to 0.80 on
    /// the elbow cases this clause exists to reject, and 0.00 to 0.09 on every
    /// round-15 case. Below the floor the clause ABSTAINS rather than rejects,
    /// which is what makes it structurally incapable of deleting a fatigued
    /// repetition: a slow rep excites no arc, and neither does any confounder
    /// slow enough to be confused with one.
    public let pivotConfidence: Double

    public init(distalSign: Double,
                window: TimeInterval = 2.0,
                axialThreshold: Double = 0.45,
                anchorRadius: Double = 0.12,
                anchorNoise: Double = 0.06,
                pivotProximalLimit: Double = 0.10,
                pivotConfidence: Double = 0.30) { /* ... */ }
}
```

### 3.3 The reading

```swift
public extension PostureGate {
    /// The posture summary for one window. Four scalars, three linear passes.
    struct Reading: Sendable, Equatable {
        /// Cosine of the angle between the forearm's distal direction and DOWN.
        /// +1 is hand directly below elbow, -1 is hand directly above it.
        public let axial: Double

        /// mean | |a| - 1 |, in G, and the mean squared angular rate of the
        /// gravity direction, in rad^2/s^2.
        public let magnitudeRipple: Double
        public let angularRateSquared: Double

        /// Signed distance from the watch to whatever it is turning about.
        /// Positive is PROXIMAL (elbow, shoulder), negative DISTAL (bar, palm).
        public let pivotRadius: Double
        public let pivotFit: Double

        /// True when the implied pivot is inside `radius` of the watch.
        ///
        /// A sensor turning at rate w about a pivot r away feels a centripetal
        /// term r*w^2 along the radius, which shows up directly in |a|. Written
        /// as a product rather than a quotient so it cannot divide by a
        /// near-zero rate when a fatigued athlete slows down.
        public func isAnchored(radius: Double, noiseFloor: Double) -> Bool {
            magnitudeRipple * 9.80665 <= radius * angularRateSquared + noiseFloor
        }
    }
}
```

The pivot term is the graft from Approach 2, re-derived so it needs no gyroscope.

```swift
/// Signed pivot distance, from the accelerometer alone.
///
/// For a rigid segment turning about a pivot that is instantaneously fixed, the
/// watch's own acceleration is `R * (psi'' * u_perp - psi'^2 * u)`, so to first
/// order in R the reported magnitude obeys
///
///     |a| - 1 = -(R / g0) * ( psi'' * u_z - psi'^2 * u_y )
///
/// with `psi = atan2(-u_z, distalSign * u_y)` the forearm angle recovered from
/// the gravity DIRECTION, which rotates with the body exactly. Every term on the
/// right is built from the accelerometer's own unit vector, so this is a plain
/// linear regression of one measured scalar on another.
///
/// Approach 3 argued this quantity needs the gyroscope. It does not. Measured
/// against known radii: planted palm -0.046 m (true -0.050), bar -0.095 to
/// -0.107 m (true -0.110), elbow +0.175 m at a 2.0 s tempo and +0.516 m at 1.2 s
/// (true +0.220). The SIGN, which is what separates a palm from an elbow, comes
/// out of the same fit.
///
/// `psi'` and `psi''` come from a local QUADRATIC least-squares fit over +/- 5
/// samples, not from central differences. That is not a refinement: a two-point
/// second difference multiplies 0.005 G of sensor noise by 1/dt^2 = 2500 at
/// 50 Hz, and with central differences the same estimator returned -0.027 m for
/// a true -0.110 m bar pivot with a fit of 0.14. The quadratic fit returns
/// -0.095 m at 0.64.
static func pivotRadius(_ samples: ArraySlice<MotionSample>,
                        distalSign: Double,
                        sampleRateHz: Double) -> (radius: Double, fit: Double)
```

### 3.4 The predicate, per movement

```swift
public func isOpen(for movement: Movement, in samples: [MotionSample],
                   endingAt endIndex: Int, sampleRateHz: Double) -> Bool {
    // No window, no judgement, and under precision over recall, no repetition.
    guard let r = reading(in: samples, endingAt: endIndex, sampleRateHz: sampleRateHz)
    else { return false }

    // Only a CONFIDENT fit is allowed to reject. An unresolvable window means
    // the motion is too slow to excite the arc, which is the state every
    // round-15 repetition is in (measured fit 0.00 to 0.09 on all four).
    let proximalPivot = r.pivotFit >= pivotConfidence
        && !r.pivotRadius.isNaN
        && r.pivotRadius > pivotProximalLimit

    switch movement {
    case .pullUp:
        // Hand above elbow, and no amplitude term at all. The forearm sweeps
        // 35-50 deg fresh and 24-32 deg at round 15, and a rest swing on the bar
        // measured a LARGER sweep (76 deg peak to peak) than a genuine round-15
        // repetition, so no threshold on sweep separates them. The sign does not
        // fade with the athlete: measured axial is -0.87 fresh and -0.91 at
        // round 15, that is, it gets STRONGER as the athlete tires, because a
        // tired athlete spends more of the window hanging.
        //
        // No anchoring clause here. Measured, it deletes fast and deep
        // repetitions: 18, 20, 25 and 17 real reps to zero across a 50 deg
        // strict set, a 1.3 s kip, a butterfly and a 1.6 s 60 deg kip.
        return r.axial <= -axialThreshold && !proximalPivot

    case .pushUp:
        // Hand below elbow AND the wrist is not travelling. The sign clause
        // alone is not enough, and this asymmetry is the whole reason the two
        // predicates differ in kind: a push-up plank and an arm hanging at the
        // side are the SAME posture, measured +0.91 and +1.00. The anchoring
        // clause is what separates a planted palm from a shoulder-swung arm and
        // it is the only thing that rejects the walk from the bar to the floor.
        // The pivot clause is what separates a planted palm from an ELBOW, which
        // the anchoring clause admits and which is what a resting athlete's arm
        // actually does.
        return r.axial >= axialThreshold
            && r.isAnchored(radius: anchorRadius, noiseFloor: anchorNoise)
            && !proximalPivot

    case .airSquat:
        // The hand is free, so no posture is required and none is forbidden.
        // Purely exclusionary: it rejects the two anchored Cindy postures
        // bleeding across a boundary tap and nothing else. This does NOT reject
        // walking, and no accelerometer posture rule can.
        return !(r.axial <= -axialThreshold)
            && !(r.axial >= axialThreshold
                 && r.isAnchored(radius: anchorRadius, noiseFloor: anchorNoise))
    }
}
```

### 3.5 `RepDetectionEngine` (edit, about 12 lines)

```swift
    /// Suppresses repetitions found while the wrist is not in the posture the
    /// movement requires. `nil` restores the previous behaviour exactly, which
    /// is the fail-open path when the watch cannot establish which way its +Y
    /// axis points along the forearm.
    private let postureGate: PostureGate?

    // ... inside ingest(_:), immediately after the empty guard:

        // The gate cannot judge a window it does not have, so the first `window`
        // seconds of a segment are uncountable by construction. Seeding the
        // watermark makes that explicit, and it closes two known phantom sources
        // at the same time: on the batched tier the 1 s batch containing the
        // athlete's boundary tap arrives AFTER `beginSegment` has reset the
        // engine, and `Bandpass.filtering` primes from `series.first`, so at a
        // segment start the priming transient IS the analysis window. Both now
        // fall inside the blackout, which is where they belong, because
        // `detectedRepAllowance` is at its widest in exactly those seconds.
        if buffer.isEmpty, let postureGate, let first = samples.first {
            emittedThrough = first.timestamp + postureGate.window
        }

    // ... and the emission filter becomes:

        let peakIndices = detectedPeakIndices(profile: profile)
        let cutoff = latest - profile.minPeriod
        let confirmed = peakIndices.filter { index in
            let time = buffer[index].timestamp
            guard time > emittedThrough, time <= cutoff else { return false }
            guard let postureGate else { return true }
            // The window ends at the PEAK, not at the head of the buffer: the
            // question is what posture the athlete was in while the repetition
            // happened, not where they are two seconds later. A gate evaluated
            // over the whole 30 s buffer stays open for 22 of 25 evaluations
            // after the athlete has walked away from the bar; at 4 s, 2 of 25.
            return postureGate.isOpen(for: movement, in: buffer, endingAt: index,
                                      sampleRateHz: configuration.analysisRateHz)
        }

        if cutoff > emittedThrough { emittedThrough = cutoff }
        return confirmed.count
```

`detectedPeakTimes` becomes `detectedPeakIndices` so the gate can slice the buffer without a second search.
Nothing else moves: not the recount cadence, not the trim, not the backwards-clock reset, not the stateless-recount doctrine.
A peak the gate suppresses is lost permanently rather than re-litigated, because `emittedThrough` still advances to `cutoff` on every recount.
That is the correct trade under precision over recall and it is what keeps the recount stateless.

### 3.6 Comment corrections

`Movement+RepCounting.swift`, pull-up case, constants unchanged:

```swift
        case .pullUp:
            // Anchored, not travelling. The hand grips a bar that does not move,
            // so the watch stays within about 12 cm of the bar for the whole set
            // while the athlete's centre of mass travels 40-50 cm. Per repetition
            // the forearm sweeps roughly 35-50 degrees from the hang (a physics
            // estimate from segment geometry, not a measurement, and the first
            // thing a device trace should replace), so what the accelerometer
            // sees is the gravity vector rotating through that angle: measured
            // 0.37 G peak-to-peak on the forearm axis and 0.56 G on the dorsal
            // axis, against 0.027 G of linear acceleration from the watch's own
            // 8 cm arc, with vector magnitude flat to 0.068 G.
            //
            // This is RecoFit's push-up mechanism at larger amplitude, not its
            // opposite. The pull-up and the push-up are the SAME case, both hands
            // anchored, and they differ only in SIGN on the forearm axis. That
            // one bit is what `PostureGate` reads. The wide upper bound still
            // covers a fatigued athlete hanging between reps.
            return RepCountingProfile(minPeriod: 0.8, maxPeriod: 4.0, activityFloor: 0.030)
```

`PrincipalAxis.swift:16` loses "for free" and gains the measured cost, with a pointer to where the discarded orientation information is put back.

---

## 4. What to build, in order

Steps 1 to 3 need no data that does not exist.
Step 4 is a five-minute capture and everything after it depends on that capture.

**Step 1. Correct the three comments.**
`Movement+RepCounting.swift` pull-up and header, `PrincipalAxis.swift:16`.
*Test:* the suite passes unchanged; no behaviour changes.
*Rollback:* revert the file.

**Step 2. Seed `emittedThrough` on an empty buffer.**
`emittedThrough = first.timestamp + 2.0` instead of `-.infinity`, gated on the gate being present so the change is inert without it.
*Test:* `testEmittedThroughIsSeededNotNegativeInfinity`, asserting no peak inside the first 2 s of a segment is ever emitted, plus `testSegmentStartBlackoutCostsAtMostOneRep`.
Measured: a cold-start pull-up block goes 7 to 6 against a truth of 5, and a push-up block 13 to 12 against a truth of 10.
*Rollback:* one line.

**Step 3. Ship the push-up gate, sign-free.**
`PostureGate` with the anchoring clause only, wired for `.pushUp` and nothing else.
The anchoring statistic is a magnitude, so it does not need `distalSign` and can ship before the capture.
Measured: walking in the push-up block goes 34, 43 and 60 to zero at three cadences, and every real push-up survives, including 0.8 s, 1.0 s, round 15, near-collapse and a watch worn high on the forearm.
*Test:* `testWalkingArmSwingIsNotCountedAsPushUp` (40 s at 22 degrees / 0.95 Hz, assert 0; no test under `Tests/` currently contains the string "walking", which I checked), `testFreshAndFatiguedPushUpsStillCount`, and `testNilGateMatchesUngatedCountExactly`.
*Rollback:* construct the engine with `postureGate: nil`, which restores today's behaviour byte for byte.

**Step 4. The device capture. This gates everything below.**
Ten seconds of a static dead hang and ten of a static plank, in all four `wristLocation` / `crownOrientation` configurations, printing the mean raw vector.
Four numbers settle `distalSign` permanently.
Measured cost of guessing wrong: it is a total-failure mode, not a degradation, and it deletes every repetition of the affected movement for the whole session.

**Step 5. Turn on the axial clause for all three movements.**
This is where most of the value is, and it cannot come earlier.
Measured: pull-up walking 32, 42 and 23 to zero, chalking 25 to 0, vest 11 to 0, hands on knees 16 to 0, push-up bleed 27 to 0, pull-up bleed into the push-up block 16 to 0, bar-hang bleed 16 to 0, and every real repetition unchanged in every form tested.
*Test:* `testPullUpBleedIsNotCountedAsPushUp`, `testRoundFifteenPullUpsStillCount` (24 degrees at 4.0 s, assert within 1 of truth; this is the test that would have failed a tilt-amplitude design), `testAxialIsInvariantToForearmPronation`, `testInvertedDistalSignInvertsAxial`, and `testAxialThresholdPlateau` asserting every repetition fixture stays open from 0.35 to 0.60.
*Rollback:* set `distalSign` unavailable, which drops back to step 3.

**Step 6. Add the pivot regression as a second push-up clause.**
*Test:* `testRecoversPalmPivotForPushUp` and `testRecoversElbowPivotForStandingArmShake`, asserting the returned radius is negative for the palm and positive for the elbow, which is the estimator's own contract independent of any threshold; `testPivotAbstainsOnFatiguedReps`, asserting the fit is below the confidence floor for a 13 degree / 2.8 s push-up; `testStandingElbowFlexionIsNotCountedAsPushUp`.
Measured gain over step 5: a 2.0 s standing elbow shake-out goes 18 to 3, and no real repetition in any case changes.
That is one row of the table.
It is worth building because it is the only instrument that reads the proximal/distal sign of the pivot, but it should not be sold as more than it is.
*Rollback:* set `pivotConfidence` to 2.0, which makes the clause unreachable.

**Step 7. Shadow-log the symmetry statistic. Do not act on it.**
Approach 2's symmetry clause is the only proposed instrument that reaches the pull-up's on-bar residual, and I reproduced its power: measured 0.000 to 0.005 on real repetitions against 0.998 for a bar rest swing, 1.077 for an on-bar shake-out and 0.944 for a still hang, which would take 28, 26 and 8 phantoms to zero.
It is also a knife edge.
Sweeping a kip's arch/pull ratio from 0.0 to 1.0 on a set of 15 real repetitions, the statistic tracks the ratio linearly (0.005, 0.194, 0.388, 0.585, 0.788, 0.891, 0.997) while the shipped counter finds 15 of 15 at every ratio.
Any ceiling that rejects a rest swing sits inside the range a real heavy kip occupies, and nobody has measured where a real fatigued athlete lands.
Compute it, log it beside the ungated count, and set the ceiling from a trace or not at all.

**Step 8. Replay against a labelled corpus.**
Soro et al.'s CrossFit dataset covers pull-up, push-up and air squat on a right-wrist smartwatch at about 100 Hz, 54 participants, 5461 labelled repetitions, and its `goo.gl/28w4FF` link was confirmed live by two independent lenses this session.
It needs `Codable` on `MotionSample`, a `LabelledTrace` type, and an Android-to-Apple axis re-derivation before any angle threshold transfers.
It would replace every placeholder in section 3 with a measured value.

---

## 5. The three approaches, scored

| Criterion | A1 forearm-axis sign gate | A2 anchored-pivot detectors | A3 device-motion pivot solve |
|---|---|---|---|
| Precision on the measured failure (a 0.9 Hz free-arm swing, 33 phantoms per 40 s) | 33 to 0, verified by me | 38 to 0, their measurement | 26 to 0, their measurement |
| Recall at round 15 | Zero cost. Verified: every real repetition row identical to ungated, including 24 degrees at 4.0 s and 13 degrees at 2.8 s | 76% pull-up, 85% push-up, with two cliffs: a symmetric kip 1 of 15, a collapsing push-up 0 of 8 | Zero measured, but on a sensor fusion nobody has run on a wrist |
| Risk of deleting working tested code | None. The counting path is untouched | High. Removes `Bandpass`, `PrincipalAxis` and `RepPeakCounter` from two of three movements | Moderate. Replaces both acquisition tiers and changes `MotionSample`'s contract |
| CPU against the 0.39 ms recount | +3.6% of a recount per candidate peak, verified by me. Their 0.1% claim does not reproduce | Net cheaper, about 7x less on two of three movements | +5% per emitted peak, plus a fusion cost Apple documents only qualitatively |
| `Sensing/` stays Foundation-only | Yes, one `Double` at the boundary | Yes, one `Double` at the boundary | Yes, but `MotionSample` grows by six `Double`s and the buffer by 2.5x |
| Ships this week | Partly. The anchoring clause ships now; the axial clause, which is most of the value, waits on a five-minute capture | No. Two movements should not be rewritten before the corpus replay | No. Needs an on-device power and fusion check that has no substitute |

**Approach 1 wins**, and it wins on the criteria that carry the most weight here: it costs no recall in any modelled case, it deletes nothing, and its failure mode is a `nil` that restores today's behaviour exactly.
It is also the only one of the three whose central claim I could reproduce without adopting its framing: the axial sign separates every anchored posture from every free-wrist posture in my model, and it gets stronger with fatigue rather than weaker, which is the one property the previous audit's `activityFloor` sweep proved an amplitude threshold cannot have.

**Grafted from Approach 2:** the least-squares pivot regression, moved out of the counter and into the gate.
Approach 2's own use of it, as the discriminator inside a replacement detector, is rejected along with the detector.
The estimator itself is the best single idea in the set, and I improved it: driving `psi'` and `psi''` from a local quadratic fit instead of central differences took the recovered bar radius from -0.027 m to -0.095 m against a true -0.110 m, and the fit quality from 0.14 to 0.64.

**Grafted from Approach 3:** the abstention rule, which is what makes the pivot clause safe at round 15.
Approach 3's insight is that a veto must fire only when the window carries enough motion for the estimate to mean something, so the gate gets stricter on confounders and looser on repetitions as fatigue advances.
That is the opposite direction from every amplitude threshold, and it is why the pivot clause returns a fit of 0.00 to 0.09 on all four round-15 cases and never touches them.
Approach 3's channel change is rejected: its own measurements show device motion's separated gravity buys 0.2 to 0.5 degrees over a raw boxcar, its own harness shows the band-pass priming transient is unchanged by removing the gravity DC, and the fusion's power cost is the one number Apple does not publish.
I also show that the pivot's proximal/distal sign, which Approach 3 said required the gyroscope, is recoverable from the accelerometer alone.

**What each got wrong.**
Approach 1 understated its own CPU by a factor of 70 (0.0005 ms claimed against 0.0125 ms measured for a full gate, 3.6% of a recount, matching the pull-up verifier's independent correction of the same claim), and it conceded the standing elbow-flexion case as unfixable when the pivot regression fixes most of it.
Approach 2 replaced a tested counting path on synthetic evidence, and its own measurements show the cost: a heavy symmetric kip, which is what a round-15 pull-up looks like, collapses to 1 rep in 15 at an arch/pull ratio its own source data puts a real athlete at.
Approach 3 built the strongest physics on the weakest foundation, spending the whole acquisition layer and an unquantified power budget for a discriminator that turns out to be available for free, and it left a third of Cindy untouched while also having to explicitly disarm itself there to avoid deleting 14 of 14 genuine squats.

One graft I tried and broke myself: a ceiling on linear-acceleration energy, which looked like it would kill the pull-up's on-bar residual.
Measured 95th-percentile energy per 2 s window: a 0.8 s push-up reads 0.155 G, louder than a shuffle walk at 0.092 G, a bar rest swing at 0.094 G and an on-bar shake-out at 0.103 G.
No ceiling separates them.
Energy works as a confidence term and fails as a veto, which is exactly the shape Approach 3 gave it.

---

## 6. What this cannot fix without a device trace

**The air squat, and it is not close.**
Fifteen of thirty repetitions per round get the boundary rejection and nothing else.
Walking during the squat block, hands-on-knees breathing during the squat block, and chalking during the squat block are all unchanged, and the squat block has the widest `detectedRepAllowance` of the three at 14.
The fix there is structural rather than signal-processing: require an asserted repetition to OPEN a block, as one is already required to close it.
That change needs no trace and no threshold, and on the evidence in front of me it is worth more to the air squat than everything in section 3.

**Everything the athlete does while still hanging on the bar.**
A rest swing at 28 phantoms, an on-bar shake-out at 26, and a still hang at 8, all unchanged.
The posture is genuinely a pull-up's and the gate says so correctly.
At round 15 these behaviours are most of what the athlete does, so the pull-up residual is worst exactly where the athlete is most tired.
The symmetry statistic is the only candidate and it needs the arch/pull distribution of a real fatigued kipper, which nobody has.

**Slow standing elbow flexion in the push-up block.**
12 phantoms at a 3.0 s tempo, unchanged by any clause, because at that tempo the arc is too weak to fit and the clause correctly abstains.
The wrist-to-elbow radius ratio is only about 4x and the estimator attenuates with tempo, so there is not much margin to build on.

**Every threshold in section 3 marked placeholder.**
`anchorRadius`, `anchorNoise`, `pivotProximalLimit` and `pivotConfidence` come from a rigid-body model with segment lengths taken from the two dossiers where their verifiers agreed.
Not one sample in this document came from a wrist.
`axialThreshold` is the exception in kind rather than in status: it discriminates a sign rather than a magnitude, and the measured margin on either side is 0.08 or more, so it is the one number I would expect a trace to confirm rather than move.

**`distalSign`.**
Undocumented, and getting it wrong deletes a movement rather than degrading it.

**The cheapest first trace, in order of value per minute.**
Five minutes with a phone-tethered debug build: hold a static dead hang for ten seconds and a static plank for ten seconds, in each of the four wrist and crown configurations, and print the mean raw vector.
That settles `distalSign` permanently, unlocks step 5, and is the single highest-value piece of data named anywhere in this document.
Second, a shadow-mode build that computes the gate and logs open or shut alongside the ungated count for one real Cindy, before the gate suppresses anything.
That gives the on-bar residual, the round-15 axial distribution and the real arch/pull ratio in one workout.
Third, the Soro corpus replay, which is a day of conversion work and replaces every placeholder at once.

---

## 7. Sources and verification status

**Verified by me this session, in the SDK on this machine** (`/Applications/Xcode.app/Contents/Developer/Platforms/WatchOS.platform/Developer/SDKs/WatchOS26.5.sdk`):
`WKInterfaceDevice.h:48-50` declares `WKInterfaceDeviceWristLocation`, and `:84-85` declare `wristLocation` and `crownOrientation`, both `WK_AVAILABLE_WATCHOS_ONLY(3.0)` and both readonly.
`CMBatchedSensorManager.h:93` declares `isDeviceMotionSupported` as a class property distinct from `isAccelerometerSupported`, and `:101` declares `deviceMotionDataFrequency` readonly.
`CMDeviceMotion.h:103` and `:114` both carry "the total acceleration of the device is equal to gravity plus userAcceleration".
`CMDeviceMotion.h:26-30` declares `CMDeviceMotionSensorLocation` with exactly three cases, none of which is a wrist.

**Measured by me this session** on the repo's real, unmodified `Bandpass.swift`, `MotionSample.swift`, `PrincipalAxis.swift`, `RepDetectionEngine.swift`, `RepPeakCounter.swift`, `Movement+RepCounting.swift` and `Models/Movement.swift`, compiled with `xcrun swiftc -O`.
Harness and full output at `/private/tmp/claude-501/-Users-kyseah-Documents-GitHub-cindy-app/8e761d8c-9c93-4a62-909f-06d050f988f2/scratchpad/judge/` (`main.swift`, `part2.swift` to `part10.swift`, `run.txt`).
The gated column comes from a replica of `ingest` that differs only in the emission filter and the warm-up seed; the replica agrees with the shipped engine exactly on every ungated case tested, which is the check on the replica.
My recount timing of 0.3439 ms brackets the 0.39 ms documented at `RepDetectionEngine.swift:38`, which is the check on the build.
The generator is my own forward kinematics: a rigid forearm turning about a named pivot at a named distance, with the watch's world position differentiated twice numerically and the result rotated into the body frame, so the linear-acceleration term is derived rather than assumed.
Every angle, cadence and pivot radius in it is a physics estimate from segment geometry, taken from the two dossiers where their verifiers agreed and from the verifiers where they disagreed.
I did not model the air squat at all, so every air-squat statement in this document is carried from the air-squat dossier and its verifier and is marked as such.

**Repo facts verified by me:** `RoundRepTracker.swift:107-109` defines `detectedRepAllowance` as `max(0, repsRemainingInCurrentMovement - 1)`.
`MotionRepSensor.swift` uses `accelerometerUpdates()` and `startAccelerometerUpdates` only, at lines 105, 155, 164, 195, 201, 202, 219 and 220, plus comments naming those APIs at 59 and 159.
No file under `Packages/SenseKit/Tests/` contains the string "walking".

**Carried from the lenses, verified by their verifiers, not refetched by me:**
Morris et al., RecoFit, CHI 2014, DOI 10.1145/2556288.2557116, for the anchored-wrist physics and for the walking result.
Soro et al., Sensors 19(3):714, 2019, DOI 10.3390/s19030714, Table 7, for the per-movement counting accuracy and for the corpus.
Yurtman and Barshan, Sensors 17(8):1838, 2017, for the 7.56% and 15.54% cost of orientation invariance.
Kasahara et al., Journal of Human Kinetics 93:29-39, 2024, for squat depth and trunk range of motion.
Apple Developer Forums thread 683486 for the Apple Watch axis convention.

**Rejected, and named here so they are not re-proposed.**
`CMBatchedSensorManager.accelerometerUpdates(from: .device)` does not exist; the shipped overlay declares `accelerometerUpdates()` with no arguments, and the WWDC23 session 10179 transcript does not contain that code line.
"The maximum supported frequency is 100 Hz" is not a WWDC quote; the retrievable sentence is "CMMotionManager vends data at a maximum of 100 Hz on a per-sample basis".
`testWalkingArmSwingIsNotCounted` does not exist in this repo.
Soro et al. Table A2 contains no per-exercise channel or sensor selection; it is architecture hyperparameters over the same 18 channels, and all ten counting models consumed both the wrist and the ankle watch.
The wrist is ExerSense's third-best sensor position, not its worst; the ear is worst.
arXiv:2004.10026v1 and Sensors 21(1):91 are different papers with different author lists, and the F1-by-position table exists only in the latter.
The RecoFit dataset does carry a licence, the Community Data License Agreement Permissive 2.0, which permits commercial use.
The pull-up dossier's 70 to 80 degree forearm sweep is refuted; the corrected figure is 35 to 50 degrees fresh, and every amplitude figure derived from the larger sweep falls with it.
The pull-up dossier's claim that reaching up and hanging on the bar is rejected by its gate is refuted; that motion opens the gate.
The push-up dossier's 0.225 G projected peak at 2.0 s per rep, its claim that a 15 to 20 degree sweep produces "approximately 0 G", and its 30x userAcceleration loss figure all fail to reproduce.
The air-squat dossier's 45 degree gate threshold and its return-to-mean clause were never implemented or measured, and its 36 degree fatigued reach is a hard-coded model constant reported back as a finding.
Approach 1's gate cost of 0.0005 ms per evaluation does not reproduce; a full gate costs 0.0125 ms, which is 3.6% of a recount.
---

## Appendix A: the completeness review, verbatim

The critic re-derived the physics independently, re-measured every headline number against the real
sources, and grepped the SDK headers itself.
Its corrections are folded into the head of this document; this is the full text.

## Verdict

The physics is right and the provenance discipline is unusually good — I re-derived the load-bearing claims independently and they hold, and every SDK line it cites is exact. Its failures are coverage failures, and one of them silently deletes half of Cindy for a common athlete.

My harness: `/private/tmp/claude-501/-Users-kyseah-Documents-GitHub-cindy-app/8e761d8c-9c93-4a62-909f-06d050f988f2/scratchpad/critic/` (`main.swift`, `part2.swift`, `part3.swift`). It compiles the same seven `Sensing/` + `Models/Movement.swift` files; I md5-checked all seven against the repo — byte-identical, so the judge's "real, unmodified sources" claim is true.

---

## 1. Physics

**Re-derived independently, and it holds.** Two-segment cosine rule, hand fixed at the bar, forearm 0.28 m bar-to-elbow, upper arm 0.32 m, shoulder at the top 0.22 m below and 0.10 m lateral of the grip: elbow included angle 46.6°, forearm 50.9° from vertical at the top, ~0° at the hang. So the sweep is ~50°, the corrected 35-50° band is right, and the dossier's 70-80° is correctly refuted. Axial swing follows: −1.00 → −cos(50.9°) = −0.63, i.e. **0.37 G peak-to-peak**, against the document's measured 0.366 G. Peak tangential acceleration at r = 0.11 m, amplitude 0.444 rad, T = 2.4 s: rω²A = 0.335 m/s² = **0.034 G**, the document's 0.027 G at its smaller sweep. Independent agreement on every number that matters. The wrist **is** anchored in both movements and the source comment **is** wrong. The shared premise of the upstream agents survives.

**Errors and soft spots found:**

- **Mislabelled ratio.** "Gravity rotation beats translation by 14x on the dorsal axis (0.559 G against 0.027 G)" — that quotient is 20.7. 14x is 0.366/0.027, the *forearm* axis. Cosmetic, but it is in the table that carries the argument.
- **r = 0.05 m palm-to-watch is too small, and it is the one number step 3 rests on.** The bar sits across the palm; palm-centre to wrist crease is ~0.05-0.06 m and a watch sits a further 0.02-0.04 m proximal, so 0.08-0.10 m is at least as plausible. Measured sweep (section E of my run):

  | palm→watch r | fresh 33° 1.4 s: lhs vs rhs | verdict |
  |---|---|---|
  | 0.05 (doc) | 0.094 vs 0.188 | open, 2.0x margin |
  | 0.09 | 0.158 vs 0.205 | open, 1.3x margin |
  | 0.11 | 0.193 vs 0.214 | **shut in 20 of 76 windows** |

  `anchorRadius = 0.12` is within a factor of ~1.2 of deleting fresh push-ups, and the segment length it depends on is explicitly unmeasured. The document calls `axialThreshold` "mid-plateau"; it does not make the same check for the only clause it says can ship this week.
- **r = 0.11 m bar-to-watch is also low** (same reasoning, likely 0.12-0.14 m). This does not flip the axial sign, but it means the true bar pivot radius probably *exceeds* `anchorRadius`, which makes dropping the anchoring clause from the pull-up more necessary than the document argues, not less.
- **Push-up sweep of 33° is softer than presented.** My geometry (shoulder at the bottom 0.17 m above and 0.10 m forward of the planted hand) gives 57° from vertical, not 33°. The 2 s window mean saves the axial clause either way, but the figure is stated with more confidence than segment geometry supports.
- **The air-squat row is imported from a lens that modelled something else.** "0 degrees arms-tucked … about 33 degrees once trunk pitch is included" — trunk pitch is irrelevant to a free wrist; the arm does what the athlete chose, not what the trunk does. That row is where the failure in §3 hides: the document asks how much the squat axial *oscillates* and never asks what value it *sits at*.
- **One worry I had and disproved.** The 2 s boxcar gravity estimate under a real 0.40 m squat bob: mean error 0.02-0.33°, worst 0.33°. Better than the 1.66°/3.24° the document carries from a different window and a different movement. That channel is sound.

## 2. APIs and thresholds

Every SDK claim verified by me, line for line, in `WatchOS26.5.sdk`: `WKInterfaceDevice.h:48-50` (`WKInterfaceDeviceWristLocation`), `:53-55` (`CrownOrientation`), `:84-85` (both properties, readonly); `CMBatchedSensorManager.h:37/53/93/101`; `CMDeviceMotion.h:26-30` (three cases, none a wrist), `:103-104` and `:114-115` (the gravity-plus-user sentence, twice). `grep -ril walking Packages/SenseKit/Tests/` returns nothing. **No invented API, no invented citation, no threshold presented as measured that is not.** Provenance labels are accurate throughout.

The real problem is one level up: **every "measured" number came from a generator that asserts the hypothesis.** `judge/main.swift` builds a rigid forearm rotating about a *named pivot at a named radius* — anchoring is a modelling assumption, not a finding. No test written against it can falsify the premise, and the four thresholds it calibrates inherit that. This is why the Soro replay belongs near the front, not at step 8.

**Three bugs in the proposed patch:**
1. The blackout seed goes "immediately after the empty guard", which is **before** the backwards-clock `reset()`. After a batched→`CMMotionManager` failover mid-set, `reset()` puts `emittedThrough` back to `-.infinity` and the buffer is non-empty on the next `ingest`, so the blackout never re-arms and the `Bandpass` priming transient counts. Key the seed on `emittedThrough == -.infinity` and place it just before the recount.
2. The seed is `guard let postureGate` — the cheapest, safest, highest-value change in the document is made conditional on the riskiest one, and it is the only part that helps the air squat, whose allowance is 14. Make it unconditional.
3. `emittedThrough` still advances to `cutoff` on every recount while `isOpen` returns `false` for a short window, so a mid-set stream restart silently deletes the next 2 s of *real* reps, permanently.

## 3. The athlete this fails

**A right-handed athlete who does air squats with hands clasped at the chest.** That is one of the two standard CrossFit air-squat arm positions; the other is arms forward. Measured, 40 s, 20 reps of ground truth:

| case | window-mean axial | gate open / shut | ungated reps | gated |
|---|---|---|---|---|
| SQUAT arms forward | +0.005 | 76 / 0 | 19 | 19 |
| SQUAT hands on hips | +0.867 | 76 / 0 | 20 | 20 |
| **SQUAT hands clasped at chest** | **−0.866** | **0 / 76** | 19 | **0** |
| **SQUAT fingertips at temples** | **−0.966** | **0 / 76** | 20 | **0** |
| **SQUAT round-15, slow, hands at chest** | **−0.866** | **0 / 76** | 13 | **0** |

The `.airSquat` predicate rejects any hand-above-elbow window with **no anchoring clause**, unlike the `.pushUp` branch. So the document's own sentence — "purely exclusionary: it rejects the two anchored Cindy postures bleeding across a boundary tap and nothing else" — is factually not what the code does. Follow it through: pull-ups fine, push-ups fine, and every one of 15 squats per round deleted, for 15 rounds, ~200 reps the current detector counts. The athlete taps all of them and has no way to find out why: nothing in the UI says "posture not recognised", the pips just never move. For this person the new detector is worse than the old one by exactly the amount the old one worked.

**Runner-up, and the document lists no push-up residual for it at all: the fatigued athlete resting in a plank.** Measured, 30 s, 3° of sway at 0.3 Hz: axial +0.990, `isAnchored` true, gate open in 56 of 56 windows, **15 phantom push-ups**. `detectedRepAllowance` for the push-up block is 9, so 20 s of plank rest fills the entire block. Plank setup bob: 15 more, gate open 36/36. This is the exact mirror of the on-bar residual the document does concede, and it is missing.

**Also unmodelled, all in the pull-up block, all gate-open:** forehead wipe (axial −0.896, 19 phantoms), hair/headband adjust (−0.984, 14), drinking from a bottle (−0.630, 10). The pull-up residual is not just "things done while still on the bar" — it is every hand-to-head rest gesture in a 20-minute AMRAP.

Knee push-ups pass cleanly (axial +0.946, anchored, 76/76 open), so that scaling is not the worst case. Banded and jumping pull-ups keep the hand on the bar and are fine. A loose band is fine for the axial clause (a 15-20° case tilt against a 63° threshold) but not for `anchorRadius`/`pivotProximalLimit`/`pivotConfidence`, which are sub-decimetre distances a loose band changes by tens of percent — and step 3 ships one of those first.

## 4. What no lens covered

- **The precision-over-recall rule is stated for random misses and applied to correlated ones.** "A missed rep is invisible and harmless, because the athlete keeps tapping until the movement advances" is true when misses scatter. A posture gate produces misses that are 100% correlated with a stable property of the athlete: arm position, a wrist/crown setting, a band. A systematically shut gate turns the app into a tap counter for the whole session with no error. This inverts the premise the entire design rests on, and all four upstream agents inherited it unexamined. It is the most important omission in the document.
- **No observability.** There is no proposed way for anyone — athlete or developer — to see *why* nothing counted. A veto that can zero a block must log its decision and its axial value before it is allowed to suppress anything.
- **Transitions.** The blackout is 2.0 s; a round-12 bar→floor→standing transition is 5-20 s and contains dropping off the bar, walking (rejected, correctly), kneeling and setting up in a plank (**gate open, 15 phantoms/30 s measured**), and standing up off the floor into the squat block (open). The gate covers the walking third of it.
- **The movement is a belief, not an observation.** The gate makes a hard veto depend on `RoundRepTracker.currentMovement`, which is wrong exactly when the athlete forgets to tap — the commonest real error. Today a wrong belief swaps three constants; with the gate it can zero the count and give no feedback that anything is happening.
- **`distalSign` comes from a user setting the app cannot verify.** The document treats the risk as "the SDK mapping is undocumented". The deeper risk is that `wristLocation`/`crownOrientation` are preferences the athlete may never have set to match how they actually wear the watch today, and getting it wrong is total failure for two of three movements for a whole session. The fix removes step 4 from the critical path entirely: by the document's own thesis the pull-up and push-up blocks are antipodal, so the sign is **observable from the data** across one confirmed block of each — no capture, no setting, no undocumented mapping.

## 5. Highest-value next action

**Require an athlete-asserted rep to OPEN each movement block, mirroring the rule that already requires one to close it.**

```swift
public var detectedRepAllowance: Int {
    guard hasAssertedRepInCurrentMovement else { return 0 }
    return max(0, repsRemainingInCurrentMovement - 1)
}
```

Derivable from `events` plus the existing `RepSource.isUserConfirmed` (`Packages/SenseKit/Sources/SenseKit/Tracking/RepEvent.swift:21`), no new state, `recompute()` untouched, ~6 lines and one test.

Why it beats step 1 — which corrects three comments and changes no behaviour — and beats step 3:

- It hits where the phantoms are. All three of the audit's secondary amplifiers discharge in the first seconds of a segment, when the allowance is at its widest 4 / 9 / 14.
- It covers all three movements including the air squat, which the gate cannot help and which is half the reps in every round.
- It covers the whole transition, which no posture in the gate's model describes.
- Its failure mode is one extra tap per movement: visible, bounded, and the interaction the athlete already knows. The gate's failure mode is silent and unbounded.
- No threshold, no device capture, no new file, no purity question, and it composes with everything in section 3.
- Cost: detectable reps go from 27/30 to 24/30 per round, and the document's own 2 s blackout already spends most of that.

The document names this itself in section 6 — "worth more to the air squat than everything in section 3" — and then leaves it out of the build order.

Then, in order: shadow-log the whole gate's open/shut decision and axial value beside the ungated count (extend step 7 from the symmetry statistic to everything); make `distalSign` self-calibrating from the pull-up/push-up antipodality so the capture stops blocking step 5; add a hands-at-chest air squat and a plank rest to the capture; and move the Soro replay forward, because until it runs, every threshold in the design was fitted to a generator that assumes the conclusion.

---

## Appendix B: claims rejected during verification

Recorded so they are not re-proposed. Each was checked by a verifier and failed.

- Median band-passed PCA-projected peak of 0.225 G at 2.0 s/rep for the 8-46 degree push-up. Does not reproduce and is inconsistent with the code the dossier says it ran. I measure 0.341 G for the identical geometry, and I measured the repo's own Bandpass.repCounting gain at 0.999 (1.0 Hz), 0.996 (0.5 Hz) and 0.985 (0.357 Hz) — essentially flat — so no mechanism exists inside the shipped filter for the claimed 37% drop between 1.4 s and 2.0 s. The gravity-rotation signal is displacement-like, so its projected amplitude is close to tempo-independent (I get 0.431 / 0.392 / 0.356 / 0.341 / 0.330 across 0.8-2.8 s). The 1.0 s and 1.4 s figures in the same table DO reproduce, which makes the 2.0 s entry look like a transcription or geometry slip rather than an invention.

- "At a 15-to-20 degree sweep the median band-passed projected peak measures approximately 0 G, so RepPeakCounter's own relative amplitude pass rejects those reps independently. The signal has genuinely gone." Does not reproduce. Through the real pipeline I measure a median accepted peak of 0.0455 G — 2.3x the shipped 0.020 G floor — RepPeakCounter accepts 10 of 10 peaks, and RepDetectionEngine emits 11. This is the claim the dossier uses to argue the gate's round-18 recall loss is free; it is not free.

- "userAcceleration ... Measured median projected peak collapses from 0.359 G (raw) to 0.012 G at 1.4 s/rep, a 30x loss." Does not reproduce. I measure 0.0343 G at 1.4 s/rep — a 10.5x loss, not 30x — and the engine emits 14 of 14 reps on the userAcceleration stream at that tempo rather than being deleted. The dossier's CONCLUSION survives at round-15 tempo (I confirm 0 of 10 emitted at 12-25 deg / 2.8 s), but the stated magnitude and the claim of collapse at normal tempo do not.

- "A 2.5 s plant is rejected outright (0% of windows pass) ... a slow 4 s plant still passes 27% of its windows." Does not reproduce under my model. Modelling the plant as a rotation about the hand once contact is made, I measure 100% pass at every duration from 2.0 s to 5.0 s (lhs 0.009-0.018, tilt +0.75 to +0.98, sweep 16-39 deg). The difference is whether the pre-contact fall is included in the window; the dossier does not say. Either way "rejected outright" is not established.

- A3 attributes the code line "for try await batch in manager.accelerometerUpdates(from: .device)" to the fetched transcript of WWDC23 session 10179. I fetched that page twice; the second fetch, asked directly, reports that the string "from: .device" does not appear anywhere on the page, in transcript or code. The WWDCNotes mirror of 10179 contains no accelerometerUpdates snippet, and a targeted web search for the exact string surfaces no source. Apple forum thread 731467 shows the real usage as accelerometerUpdates() with no arguments. The API point A3 draws from it is nevertheless correct and independently verified from CoreMotion.swiftmodule/arm64_32-apple-watchos.swiftinterface:55, which declares accelerometerUpdates() with no parameters — so the warning stands, the citation does not.

- Lesser, not a fabrication but a misquote worth correcting: A4 presents "The maximum supported frequency is 100 Hz" as a WWDC23 10179 quote. The sentence I could retrieve from that session is "CMMotionManager vends data at a maximum of 100 Hz on a per-sample basis." Same meaning, different words.

- B11 names `testWalkingArmSwingIsNotCounted` as an existing test 'currently pinned to a synthetic arm-swing model'. No such test exists. Packages/SenseKit/Tests/SenseKitTests/RepDetectionTests.swift has 28 test functions and no file under Packages/SenseKit/Tests/ contains the string 'walking' in any case. The test appears only as a proposed row in docs/research/rep-detection-precision.md:471.

- B8 attributes per-exercise sensor/channel subset selection to Soro et al. Table A2. That table exists but contains no channel or sensor selection at all, only convolutional layers, input normalization, input shape (W x 18 against W x 3 x 6, a tensor layout choice over the same 18 channels), batch normalization, activation function, window length, strides and dropout. All ten counting models consume both watches.

- B3 states 'Wrist is ExerSense's worst position'. The paper states the opposite: mean accuracy chest 0.972, upper arm 0.931, wrist 0.835, ear 0.784, and in its own words 'The wrist-mounted smartwatch is third, and the worst one is the ear-mounted sensor.' On push-ups specifically the wrist (0.745) beats the ear (0.700).

- B3 cites 'Ishii, Nkurikiyeyezu, Yokokubo, Lopez, arXiv:2004.10026v1 (preprint of Sensors 21(1):91)'. These are two different papers with different titles and different author lists; Sensors 21(1):91 is by Ishii, Yokokubo, Luimula, Lopez, and the F1-by-position numbers quoted in the finding exist only in the Sensors version, not in the arXiv preprint that is cited for them.

- B12 states 'No licence is stated in the readme, only a contact address' for the RecoFit dataset in a way that implies no licence exists. The repo carries a LICENSE file with the Community Data License Agreement - Permissive, Version 2.0, which permits commercial use.