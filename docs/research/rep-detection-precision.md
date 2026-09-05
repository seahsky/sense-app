# Automatic rep detection: why it over-counts, and how to make it precise

Follow-up to [automatic-rep-detection.md](automatic-rep-detection.md), which decided the algorithm.
This document is about why the shipped detector fires too often, and what to change.

Produced by a fourteen-agent audit: six independent lenses over the pipeline, the streaming engine, the
watch integration, the literature and the test suite; one adversarial verifier per lens that re-read the
source and re-checked every citation; one synthesis; one completeness critic.
Thirty findings survived verification and fourteen were refuted.
The refuted ones are listed in section 5 so nobody re-derives them.

## Read this first

**Nothing here has been measured on a wrist.**
Every number below comes from synthetic signals pushed through the real, unmodified `Sensing/` sources.
That is enough to prove a mechanism exists.
It is not enough to prove it is the mechanism the athlete is complaining about.

**So do this before touching any signal processing.**
Log a per-source breakdown of `RepEvent.source` for a real attempt, and add a counter for detected reps
that `RoundRepTracker.logDetectedReps` refused because they exceeded `detectedRepAllowance`.
Both are derivable from `events`, which already holds every repetition with its origin.
`SessionSummaryView` already shows `detectedRepFraction`, so the surface exists.

This is first because it is the only cheap experiment that can falsify the rest of this document.
`RoundRepTracker.swift:125` clamps detected reps to the allowance and silently drops the excess, so
`detectedRepFraction` understates how badly the detector is behaving, and there is no counter anywhere
of how many were refused.
That single instrument would have answered the question already.

If one real attempt comes back with a large `.crown` count, sections 1 to 3 are aimed at the wrong
subsystem, and the fix is two lines in `handleCrown`.
If it comes back mostly `.detected`, the ranking below stands.

## Four things the six lenses missed

The completeness critic found these after the report was written, and each was verified against the
source by hand.
They are not in the ranked list below, and two of them may matter more than anything in it.

**1. The Digital Crown is an ungated, unauditable rep source, and it stays live while the clock is paused.**
`ActiveWorkoutView.swift:98-126` keeps the crown focused for the whole workout and re-asserts focus on
every state change.
`handleCrown` (`:474-487`) turns any positive delta into `RepLogging.logAsserted(delta, source: .crown)`,
and `RepLogging.swift:18-20` states asserted reps are "never gated", so a crown rep can close a movement
and a round.
It renders as a solid asserted pip and `undoTrailingDetectedReps` cannot reach it.
`togglePause` (`:488-508`) calls `repSensor.pause()` with the comment "so a walk to the water fountain
cannot log reps", and then leaves the crown focused and `handleCrown` live, so the one input path that
can close a round still fires during a rest break.
During Cindy the crown is pressed against a bar, a forearm, or the floor for most of the workout.
An athlete who sees their score jump cannot tell a crown rep from a tap from a detection, and
"the auto detect seems too sensitive" is what they would say either way.

**2. Correcting a phantom manufactures more phantoms.**
`undoLastRep` calls `recompute()`, which can change `currentStepIndex`, which fires the
`.onChange(of: tracker.currentStepIndex)` at `ActiveWorkoutView.swift:165-167`, which calls
`repSensor.setMovement`, which calls `beginSegment`, which calls `reset()`.
So undoing back across a movement boundary re-arms the engine at `emittedThrough = -.infinity` with the
allowance at its maximum, mid-motion, while the athlete's hand is on the watch.
That is cause 2 below, triggered by the correction instead of by the boundary tap.
It is why the feature reads as unfixable rather than merely inaccurate.

**3. `RepPipRow` launders detected reps into asserted ones.**
`ActiveWorkoutView.swift:285` passes `detected: min(tracker.trailingDetectedRepCount, tracker.repsInCurrentMovement)`,
and `RepPipRow.swift:68` computes `manualCount = completed - detected` and renders the manual pips first.
Detected reps that are not a trailing run therefore render as solid asserted pips.
Tap, detect three, tap: `completed` is 5, `trailingDetectedRepCount` is 0, and five solid pips appear.
`RepPipRow.swift:12-13` states the requirement this violates: "Provenance has to persist for the life of
the movement or it is not auditable at all."

**4. Session cold start is unguarded.**
`ContentView.swift:116-134` starts the HealthKit session, the sensor and the clock in the same
main-actor turn, with no countdown.
The athlete presses Start and then walks to the bar, five to ten seconds, at
`detectedRepAllowance = 4`.
Fix 2 below blacks out `2 * minPeriod`, which is 1.6 s, so it does not reach this.
It is the first thing the athlete experiences every session.

## Two corrections to the ranked list

**Fix 1 is over-ranked.**
Its evidence is a degenerate input: 1500 constant samples with only sample 0 offset, which is the one
signal where `series.first` is maximally wrong and `mean` is maximally right.
On a realistic rolling buffer (0.5 Hz, 0.3 G sinusoid on 1 G, error against the same filter run from a
settled 40 s prefix, phase swept in 8 steps) the mean-primed filter is barely better and at two of eight
phases is worse.
The residual transient is still about 0.21 G, seven to ten times every `activityFloor`.
The direction of the change is defensible; the claimed magnitude and the number-one ranking are not.

**Fix 2 loses twice as much as it says.**
With `emittedThrough = first + 2 * minPeriod` and `cutoff = latest - minPeriod`
(`RepDetectionEngine.swift:139-140`), the first emissible peak needs `latest >= first + 3 * minPeriod`.
That is 2.4 s for a pull-up against today's 1.6 s.
At an 0.8 s cadence it costs roughly two opening reps per movement block, six per round, not the one and
three the fix claims.

---


## 1. What's actually happening

The detector has no idea whether the athlete is doing the movement, so it counts everything above a small amplitude threshold, and the moment it counts hardest is the moment right after the athlete's boundary tap.
`RepDetectionEngine.ingest` runs the full counting pipeline unconditionally on every batch, and its only defences are two absolute amplitude gates in `RepPeakCounter` (line 76-77 buffer-wide, line 126 per-peak) set at 0.020-0.030 G, which ordinary between-station wrist motion clears by three to twelve times.

Four mechanisms compound, and they all fire in the same few seconds.

**Cause 1 (dominant): no exercise/non-exercise gate.**
`RepPeakCounter.peakIndices` filters candidate peaks on exactly two properties, spacing (passes 1 and 2) and amplitude (passes 3a and 3b).
Nothing asks whether the accepted peaks repeat.
Once any motion clears `activityFloor`, the accepted count is decided by the refractory spacing alone, so it converges to roughly one "rep" every one to three seconds regardless of what the motion looks like.
Measured (synthetic input, real Swift sources compiled unmodified): 40 s of a 0.08 G / 0.9 Hz walking arm swing emits 35 reps on all three profiles; 30 s of arm swing at 1.4 Hz / 0.30 G emits 15 pull-ups, 41 push-ups and 41 air squats; 180 s of non-repetitive band-limited motion emits 59 / 73 / 68.
The counts are flat from 0.06 G to 0.60 G, a factor of ten, which is the saturation signature: amplitude stopped mattering.
No floor value separates this from a fatigued athlete's faded reps; a sweep from 0.030 to 0.250 G had no row where the phantoms are gone and the faded reps survive.

**Cause 2: the segment boundary re-arms the detector at maximum allowance while the athlete is still moving.**
`ActiveWorkoutView.swift:165-167` retargets the sensor on `tracker.currentStepIndex`, which changes on the athlete's boundary tap.
That calls `beginSegment` → `reset()`, which clears the buffer and puts `emittedThrough` back to `-.infinity` (`RepDetectionEngine.swift:90-94`).
The engine then needs only `minPeriod * 2` (1.2 s for a push-up) of buffer before it counts, and on that first qualifying recount every peak in the window is inside `(-infinity, latest - minPeriod]`.
At exactly that instant `RoundRepTracker.detectedRepAllowance` is at its maximum: 4 for pull-ups, 9 for push-ups, 14 for air squats.
So the phantoms front-load.
The athlete taps to finish pull-ups, drops off the bar, walks to the floor, and the push-up row is already several reps deep before their hands touch the ground.

**Cause 3: on the batched tier, the batch containing the just-asserted rep is credited to the next movement.**
`CMBatchedSensorManager` delivers one-second batches and `MotionRepSensor.swift:165-173` maps a whole batch and awaits `consume` once; there is no per-sample movement stamp anywhere.
A boundary tap at t+0.5 enqueues `beginSegment` on the processor actor, and the batch covering [t, t+1] is delivered at ~t+1, after the reset.
The pre-tap half of that batch holds the very rep the athlete just asserted, and it is now the largest excursion in a fresh buffer otherwise full of transition motion, so it survives greedy thinning and sets rather than fails the relative floor.
Verified as roughly +1 phantom per movement boundary, up to 3 per round.
The tap lands strictly inside a 1 s batch window with near-certainty.
The standard tier is safe: `MotionRepSensor.swift:202-211` delivers one sample per callback.

**Cause 4: the band-pass injects its own transient at every segment start.**
`Bandpass.filtering` (Bandpass.swift:155-165) does `filter.prime(constantInput: first)`.
The priming algebra in `Biquad.prime` is correct only if `first` is the DC level, and on a sliding buffer it is a random instant of a moving signal.
Verified in Swift on the real sources: `Bandpass.repCounting(50).filtering` on 1500 constant samples with only sample 0 offset gives max|filtered| of 0.105 / 0.209 / 0.345 / 0.523 G for offsets 0.10 / 0.20 / 0.33 / 0.50 G.
Every one of those clears every `activityFloor`.
This is harmless mid-stream, because the transient sits at the buffer's oldest edge, ~29 s behind `cutoff = latest - minPeriod`, and is never emitted.
It is not harmless at a segment start, where the transient *is* the whole analysis window and `emittedThrough` is `-.infinity`: streaming 40 s through the real engine with a segment start mid-motion emits 3-7 phantom reps, and 0.5 s of genuine half-rep motion at segment start emits 3-5.

**What the athlete sees.**
Cause 1 sets the background rate, but causes 2, 3 and 4 are what make it feel "too sensitive", because they all discharge into the first seconds of a new movement while the allowance is widest.
The visible symptom is the pip row filling to one-short almost immediately after a boundary tap, the status line reading TAP TO FINISH SET, and a run of `.directionUp` haptics for reps the athlete did not do.
Then the correction path fails: the long-press bulk undo is guarded by `guard tracker.trailingDetectedRepCount > 0` (ActiveWorkoutView.swift:141) and `undoTrailingDetectedReps` only walks back while `events.last?.source == .detected` (RoundRepTracker.swift:70-78), so the athlete's first corrective tap breaks the trailing run and cements the phantoms for the rest of the attempt.

Two secondary causes, real but smaller.
The air squat doubles exactly when its two bursts sit near half a rep apart, because `estimatedPeriodSamples` maximises an unnormalized sum that then prefers the sub-harmonic; reproduced on the repo's own `doublePeakSignal` generator at period 1.4 s / separation 0.70 s, 1.6 / 0.80 and 2.0 / 1.00, all returning 16 for 8 true reps.
And the tier failover splices two streams into one buffer without resetting the engine (`MotionRepSensor.swift:263-271` replaces only the `Decimator`), which costs one or two counts at recovery.

## 2. The fixes, ranked

Ranked by expected precision gain per unit of risk.
Type is marked (a) bug fix, (b) parameter retuning, (c) new pipeline stage.

### 1. (a) Prime the band-pass from the buffer mean, not its first sample

**File**: `Packages/SenseKit/Sources/SenseKit/Sensing/Bandpass.swift:155-165`.

```swift
public func filtering(_ series: [Double]) -> [Double] {
    guard !series.isEmpty else { return [] }
    var filter = self
    // Primed from the buffer MEAN, not its first sample. The algebra in
    // `Biquad.prime(constantInput:)` is only correct when the constant is the
    // DC level; on a sliding buffer `series.first` is a random instant of a
    // moving signal, and a wrong constant is a step into a 0.15 Hz high-pass
    // that settles over ~4 s. Measured: a first-sample offset of 0.33 G puts
    // 0.345 G of settling transient into the filtered buffer, an order of
    // magnitude above every `activityFloor`.
    let mean = series.reduce(0, +) / Double(series.count)
    filter.prime(constantInput: mean)
    return series.map { filter.process($0) }
}
```

**Why it works**: the mean of a rolling accelerometer buffer is close to the true DC level (gravity plus the athlete's mean orientation), so the settling step is small.
Measured on a segment-start scenario: the phantom burst falls from 3-7 to exactly 1 for all three movements at every offset tested, with no recall cost (10 synthetic pull-ups still count 10/10 across seeds).

**Risk**: near zero.
One extra O(n) pass over data `PrincipalAxis` already scans.
It changes the filtered signal slightly everywhere, so the exact counts in the existing tests could shift by one; they currently tolerate that.

**Do not** use the trim-the-leading-5-seconds variant instead.
It was tested and it is both ineffective (the burst happens while the buffer is only 1.6-5 s long, so there is no prefix to drop) and harmful (it lost a real rep on clean input).

**How to tell it worked**: `testSegmentStartDoesNotEmitFromPrimingTransient` (section 4) goes from 3-7 emitted to at most 1.

### 2. (a) Give every segment a warm-up floor instead of the `-.infinity` watermark

**File**: `Packages/SenseKit/Sources/SenseKit/Sensing/RepDetectionEngine.swift`, in `ingest`, immediately before `buffer.append(contentsOf: samples)` (currently line 118).

```swift
// A segment opens on the athlete's boundary tap, while they are still hanging
// off the bar or walking to the floor, and on the batched tier the batch that
// straddles that tap arrives AFTER `beginSegment` has reset us. Seeding
// `emittedThrough` to the warm-up horizon rather than -.infinity means nothing
// older than one warm-up window can ever be emitted as a rep of this movement.
// It subsumes the span guard below: the first emissible peak is the first one
// that is genuinely inside this segment.
if buffer.isEmpty, let first = samples.first?.timestamp {
    emittedThrough = first + movement.repCountingProfile.minPeriod * 2
}
```

**Why it works**: it closes causes 2 and 3 with one change and no new state.
`buffer.isEmpty` is true after `beginSegment`, after the backwards-timestamp reset at :113-116, and at session start, which are exactly the three moments the watermark is meaningless.
The blackout is 1.6 s for a pull-up, 1.2 s for a push-up, 1.4 s for an air squat, which is the same span the existing guard at :132-134 already waits for, so emission latency does not change.

**Risk**: the first detected rep of every movement block is lost, so the athlete taps it.
At a 2 s cadence that is one rep per block, three per round, on top of the boundary rep already reserved.
Under the stated precision-over-recall rule that is the intended trade, and it makes the design symmetric: the detector may not open a block, and it already may not close one.

**How to tell it worked**: `testMovementBoundaryDoesNotCreditOutgoingMotion` (section 4) goes from 2 emitted to 0, and the existing `testEngineEmitsRepsIncrementally` drops from 12 to 11 (update the bound and say why in the message).

### 3. (a) Reset the engine when the source rate changes

**File**: `SenseWatch/Workout/MotionRepSensor.swift:263-271`, in `RepDetectionProcessor.process`.

```swift
func process(_ samples: [MotionSample], sourceRateHz: Double) -> Int {
    if sourceRateHz != decimatorSourceRateHz {
        // A rate change means a tier failover: CMBatchedSensorManager threw and
        // CMMotionManager took over. Both read CMLogItem.timestamp, so the clock
        // continues correctly and `ingest`'s backwards-jump guard cannot fire —
        // the buffer would keep pre-failover samples, a delivery hole, and
        // post-failover samples, and the band-pass would run across the splice.
        if decimatorSourceRateHz != 0 { engine.reset() }
        decimatorSourceRateHz = sourceRateHz
        decimator = Decimator(
            factor: Decimator.factor(sourceRateHz: sourceRateHz, targetRateHz: analysisRateHz)
        )
    }
    return engine.ingest(decimator.decimate(samples))
}
```

**Why it works**: it removes a class of undefined behaviour, not only a count.
`RepPeakCounter`'s index arithmetic assumes a uniform time axis, which the hole breaks for the whole 30 s the splice stays buffered.
The count benefit is small: a second-order high-pass answers a step with one large excursion and about one overshoot, so realistically one or two extra counts, and only on a failover, which `handleBatchedFailure` runs at most once per session.

**Risk**: a reset costs the warm-up window of detection.
This happens at most once per session.

**How to tell it worked**: no test today covers it; add `testRateChangeResetsTheEngine` asserting `bufferedSampleCount == 0` after a rate change.

### 4. (a) Scope the bulk undo to the current movement

**Files**: `Packages/SenseKit/Sources/SenseKit/Tracking/RoundRepTracker.swift` and `SenseWatch/Views/ActiveWorkoutView.swift:141`.

```swift
/// Removes every detected repetition logged since the current movement began,
/// leaving the athlete's own taps in place.
///
/// `undoTrailingDetectedReps` only walks back a trailing run, so the athlete's
/// first corrective tap ends the run and silently disables the long press — at
/// exactly the moment a runaway has just filled the movement and the screen is
/// telling them to tap. Scoping to the movement keeps the affordance reachable.
@discardableResult
public func undoDetectedRepsInCurrentMovement() -> Int {
    let start = events.count - repsInCurrentMovement
    guard start >= 0, start < events.count else { return 0 }
    let kept = events[start...].filter { $0.source != .detected }
    let removed = (events.count - start) - kept.count
    guard removed > 0 else { return 0 }
    events.removeSubrange(start...)
    events.append(contentsOf: kept)
    recompute()
    return removed
}
```

Drive the long-press guard and the confirmation dialog's title from a matching `detectedRepCountInCurrentMovement`.

**Why it works**: this creates no phantoms and removes none, but it is what makes them reversible, and irreversibility is a large part of why the feature reads as broken.

**Risk**: the wider undo can reach past a manual rep within the movement, which `undoTrailingDetectedReps` deliberately avoided.
Naming the exact count in the dialog keeps it auditable.

**Do not** ship the "cap detected reps at 0.6 of the movement" idea that was floated alongside this.
It is an unjustified constant and a hard recall ceiling on athletes the detector is tracking correctly.

### 5. (c) Add a per-peak periodicity confidence, computed in the loop that already exists

**File**: `Packages/SenseKit/Sources/SenseKit/Sensing/RepPeakCounter.swift:208-256` and the pass-3 tail.

`estimatedPeriodSamples` already accumulates `bestCorrelation` and throws it away on line 255 (`return bestLag`).
Return it, normalized:

```swift
private static func estimatedPeriod(
    in signal: [Double], centeredOn index: Int, minLag: Int, maxLag: Int
) -> (lagSamples: Int, confidence: Double)
```

Inside the existing `for lag in minLag...highestLag` loop, accumulate `energyA += centered[p] * centered[p]` and `energyB += centered[p + lag] * centered[p + lag]` alongside `correlation`, and when a lag wins, keep its two energies.
Confidence is `bestCorrelation / sqrt(bestEnergyA * bestEnergyB)`, clamped to 0 when either energy is zero.
The winning *lag* is still chosen by the raw sum, so the documented 50% undercount that the non-normalization exists to prevent (comment at lines 237-248) is untouched.

Add `minPeriodicity` to `RepCountingProfile` with a default of 0.5, and filter in pass 3, before the percentile at line 134:

```swift
let plausible = secondPass
    .filter { signal[$0] >= profile.activityFloor }
    .filter { (confidences[$0] ?? 0) >= profile.minPeriodicity }
```

**Why it works**: this is the only quantity in the pipeline that separates a repetitive train from arrhythmic motion, and it is already being computed.
Measured through a streaming replica of the engine at threshold 0.5: 180 s of non-repetitive motion falls from 59 to 34 emitted (pull-up, identical at 0.10 G and 0.60 G) and from 73 to 26 (push-up), with zero recall cost on clean 15 pull-ups (15), a 60 s fading set (25) and 60 s of 1.25 s push-ups (48).
Threshold 0.35 is much weaker (43 and 38).
Direct measurement of separation on 30 s buffers, pull-up bracket: clean reps 1.000, a set fading 0.50 → 0.18 G while slowing 1.8 → 3.2 s scored 0.980, non-repetitive motion 0.119-0.327 across four seeds.

**Cost**: it must be folded into the existing pass-2 loop.
Bolted on as a separate per-peak pass it measured 1.935 ms against a 0.934 ms full-recount baseline, which triples the recount and blows the CPU budget.
Folded in it is a constant factor on a loop already running.

**Risk**: an athlete resting between individual reps late in the AMRAP has no consistent local periodicity and loses reps permanently, because `emittedThrough` advances to `latest - minPeriod` on every tick and a suppressed peak is never re-offered.
The 0.5 threshold comes from synthetics only and must be re-derived from recorded fatigued sets before it is trusted.

**This does not fix walking.**
Walking is highly periodic.
Measured: synthetic walking scores 0.777 on max normalized autocorrelation over the air-squat lag band while a synthetic double-burst air squat scores 0.593, so no threshold admits the squat and rejects the walk.
That is RecoFit's own published finding, and it is why section 3 exists.

**How to tell it worked**: `testWalkingArmSwingIsNotCounted` will still fail (expected); `testFidgetAfterRepsIsNotCounted` should move from 17-21 toward 5-8.

### 6. (a) Reject the sub-harmonic in the air-squat period estimate

**File**: `Packages/SenseKit/Sources/SenseKit/Sensing/RepPeakCounter.swift`, appended to `estimatedPeriodSamples`.

After `bestLag` is chosen by the raw sum, if `2 * bestLag <= highestLag`, compute the zero-lag-normalized correlation at both `bestLag` and `2 * bestLag`, and take the doubled lag only when it exceeds the shorter one by a strict margin of about 0.002.

**Why it works**: measured on the repo's own `doublePeakSignal` generator, the raw sum prefers P/2 for period 1.4 / separation 0.70 (10.383 against 8.992), while the normalized correlation prefers the fundamental (0.9961 against 0.9903).
Pass 2's refractory then collapses from `0.75 * P` to `0.75 * P/2`, which stops separating the two bursts, and the counter returns 16 for 8 true reps.
There is a second effect worth recording: pass 2 spacing is `round(0.75 * P)`, so whenever the estimate lands near `minLag` (35 samples for the air squat) the spacing is 26, below pass 1's own 35, and pass 2 becomes a guaranteed no-op.
The biased estimator drives the estimate into exactly the range where the second pass cannot fire.

**Risk**: this is the riskiest of the counter changes, because the current code exists to fix a measured 50% undercount.
The margins are thin (0.006 on the air squat, ~0 on a clean sinusoid).
It must land with tests in both directions: a clean single-peak-per-rep pull-up that must not double its period, and a double-burst squat that must not halve it.

**Do not** raise `.airSquat.minPeriod` above 0.7 s instead.
It cannot help at period 2.0 s / separation 1.0 s, and it caps a fresh athlete's cadence for nothing.

**How to tell it worked**: extend `testDoublePeakSquatsAreCountedOncePerRep` (RepDetectionTests.swift:123) to sweep `burstSeparation` 0.4-1.4 s at periods 1.4-2.6 s, and burst width 0.06-0.18 s.
Today width 0.18 s at separation 1.2 s returns exactly 16 for 8 reps.

### 7. (b) Narrow the band-pass upper corner from 11 Hz to 5 Hz

**File**: `Packages/SenseKit/Sources/SenseKit/Sensing/Bandpass.swift:124-127`, plus a rewrite of the doc comment at :102-107.

**Why it works**: the corner sets the frequency selectivity of the only absolute gate in the pipeline.
Closed-form on the shipped RBJ coefficients at 50 Hz, verified twice independently: junk-to-rep power ratio (integrating |H|² over 1.7-25 Hz against 0.25-1.7 Hz) is 6.542 at the 11 Hz corner, 2.549 at 5 Hz, 1.846 at 4 Hz.
Passband gain at 1.7 Hz, the fastest tempo the profiles allow, falls only from 0.9998 to 0.9883 at a 5 Hz corner.
Streaming a sustained out-of-band disturbance on an otherwise still wrist through the full engine: at the shipped corner, 8 Hz / 0.05 G gives 29 pull-up and 45-49 push-up phantom emissions in 40 s; at a 4 Hz corner the same inputs give 1 and 2.

**Risk**: this is the only recommendation that touches the signal a real rep produces.
Sharpness lives in the harmonics the corner removes, and rounding a peak can move the local maximum and lower it relative to neighbours, which matters at pass 3b.
No synthetic movement lost a rep at any corner from 11 Hz down to 2.0 Hz, including a sharp 0.25 s-impulse-per-rep model, but the synthetics are smoother than a real kipping pull-up.

**The trigger is unproven.**
Nobody has verified that a wrist during Cindy carries sustained 6-12 Hz energy at 0.05 G.
This is a real lever with an unmeasured premise.
Hold it until a device trace exists, and prefer 5 Hz over 4 Hz when it lands.

### 8. (b) Correct the profile comment, and raise the push-up floor to 0.025 G

**File**: `Packages/SenseKit/Sources/SenseKit/Sensing/Movement+RepCounting.swift:18-23` and :38.

The comment claims the floors sit "an order of magnitude above resting accelerometer noise (~0.005 G RMS)".
That is wrong twice.
On its own terms 0.030/0.005 is 6x and 0.020/0.005 is 4x.
More importantly, the floor is compared against the band-passed, PCA-projected *peak* (RepPeakCounter.swift:76 and :126), not per-axis raw RMS, and PCA selects the direction of greatest variation.
Measured through the real `Bandpass.repCounting` + `PrincipalAxis.reduce` chain on 60 s of per-axis Gaussian noise at 0.005 G RMS: projected |max| 0.0116-0.0137 G, p95 peak height 0.0074 G.
Real margins are pull-up 2.6x, air squat 2.2x, push-up 1.7x.
Rewrite the comment with those figures and name the statistic the floor is actually compared against.

Raising `.pushUp.activityFloor` from 0.020 to 0.025 is cheap insurance against a twitchy still wrist: at 0.012 G/axis resting noise it takes accepted peaks from 10 to 0 over 60 s.
It buys nothing against the actual over-count (9 accepted peaks at 0.020, 0.025 and 0.030 alike on 0.10 G non-repetitive motion), and no fatigued push-up trace exists to bound the recall cost.
Ship it only with the comment rewrite, and revisit once real traces exist.

### 9. (a) Documentation: the batched tier never achieves the 200 ms recount cadence

**File**: `RepDetectionEngine.swift:45-48`.

`ingest` is called once per batch, and lines 123-126 test `latest - lastRecountAt < recountInterval` where `latest` is the newest sample of the batch just appended.
With 1 s batches the test is evaluated once per batch and never suppresses a recount.
Amend the comment to say the effective cadence is `max(recountInterval, batchSpan)` and confirmation latency is bounded by `batchSpan + minPeriod`, which is up to 1.8 s for a pull-up.
Verified batch-size invariant: 24 s of 2 s-period pull-ups fed at batch sizes 1/10/25/50/100 emitted 12 every time, at most 1 rep per call.
No counts are lost, only delayed.
Do not add a per-call emission cap; a legitimate 1 s batch can honestly carry more than one rep.

## 3. The one structural change worth considering

**Require an asserted rep to open a movement block, exactly as one is already required to close it.**

The audits converged on a missing activity gate, and three candidate designs were tested.
A periodicity-confidence gate cannot reject walking (measured: walking 0.777, air squat 0.593 on the same metric), which is the dominant confounder in Cindy and which RecoFit names explicitly as unseparable by heuristic.
RecoFit's own 6-second accumulator hysteresis is the published answer and would work, but it needs a vote source, it costs 6 s of latency at the start of every set, and its decrement rate has to be tuned against fatigued traces that do not exist.
The asserted-rep gate needs no vote, no threshold, no new state in `Sensing/`, and no CPU.
It is also symmetric with the rule the product already commits to: `detectedRepAllowance` says the detector may never advance the sequence, and this says it may never start one.

It is a product decision, not only an engineering one, and it should go in front of the user before it is implemented.
The cost is two taps per movement instead of one, so six per round instead of three, and an athlete who forgets to tap gets nothing counted for that movement.

**Signature.**
Nothing changes in `SenseKit/Sensing`.
The gate lives in the one funnel where a rep becomes a rep.

```swift
// SenseWatch/Views/RepLogging.swift
@discardableResult
static func logDetected(_ count: Int, into tracker: RoundRepTracker) -> Int
```

```swift
// Packages/SenseKit/Sources/SenseKit/Tracking/RoundRepTracker.swift
/// True once the athlete has asserted at least one repetition of the movement
/// now in progress. Derived from `events`, never cached: a cached flag would be
/// a second source of truth that `undoLastRep` and the bulk undo must keep in
/// sync, which is the class of bug the derived-state design exists to prevent.
public var hasAssertedRepInCurrentMovement: Bool
```

**Pseudocode.**
`hasAssertedRepInCurrentMovement` scans backwards from the end of `events` over the current movement's slice, which starts at `events.count - repsInCurrentMovement`, and returns true if any event in that slice has `source != .detected`.
The scan is bounded by 15 events, against a 3-step sequence tapped a few hundred times over 20 minutes, so it costs nothing.
`RepLogging.logDetected` returns 0 without logging and without a haptic while the flag is false, so the walk to the bar, the drop off the bar, the kneel, and the straddled boundary batch all produce nothing.
The athlete's first real rep of the block is a tap, the flag flips, and the detector carries the rest of the set as it does today.
Pair it with fix 2 from section 2: the opening tap does not clear the engine's buffer, so without the warm-up floor the pre-block motion still sitting in the buffer can fire on the first post-tap recount.
Alternatively have the opening tap itself call `repSensor.setMovement`, so the buffer is dropped at the moment the block opens.

**What it does not fix.**
Phantom reps *inside* a set, when the athlete shakes out their forearms between reps and the detector keeps counting.
That is what the periodicity gate in fix 5 is for, and the two are complementary.

**The fallback, if the extra tap is rejected.**
Implement RecoFit's accumulator instead: a 6-second hysteresis on a crude per-tick vote ("pass 1 accepted at least one peak this tick"), with `emittedThrough` set to `openTime - accumulatorThreshold` on the gate's rising edge rather than left at `-.infinity`.
Six seconds of hysteresis alone kills every sub-6-second bar-to-floor transition, which is what dominates a Cindy round.
Do not source the vote from periodicity confidence, for the reason above.

## 4. How to measure it

The constants are currently hypotheses, and the file says so (`Movement+RepCounting.swift:11`).
Three seams turn tuning into a number.

**Seam 1: `ingest` must return times, not a count.**
`RepDetectionEngine.swift:140` computes `confirmed` as the peak timestamps that crossed the watermark and line 145 throws them away with `return confirmed.count`.
Return `[TimeInterval]`.
A precision/recall matcher needs nearest-in-time assignment, and per-rep timing error is the only metric that catches a change which still counts N but reports every rep a second late.
Measured today on a clean 10-rep 0.5 Hz signal: accepted peaks at 0.42, 2.38, 4.38, 6.40, 8.36, 10.42, 12.36, 14.40, 16.40, 18.36 s against true peaks at 0.50, 2.50 … 18.50, an 0.08-0.14 s phase lead from the band-pass that nothing asserts.

**Seam 2: a clock bridge.**
`RepEvent.date` is a wall-clock `Date`; `MotionSample.timestamp` is Core Motion's monotonic clock, which `MotionSample.swift:11-14` warns is "never a wall-clock date".
Capture one paired `(Date, CMLogItem.timestamp)` reading at segment start and store the offset.
Without it, labels cannot be aligned to samples and the harness produces unusable files.
Record an asserted rep's `Date` as a *tap* time, not a peak label, and let the scorer apply an explicit documented reaction offset.

**Seam 3: an evaluation type.**
`RepDetectionTests.swift:92-107` defines `counted(...) -> Int` and every assertion compares that Int to an expected Int.
A count cannot separate a phantom from a miss, which is the exact axis this design weights.
Add `LabelledTrace` (samples plus asserted-rep times plus movement plus segment boundaries) and `DetectionScore` (precision, recall, mean absolute timing error, and the matching `tolerance` stored inside the score so it is self-describing).
Define precision as 1.0 when nothing was detected and nothing was labelled, because the rest-period fixtures are exactly that case.
`MotionSample` is `public struct MotionSample: Sendable, Equatable` with no `Codable`; add the synthesised conformance (it is four Doubles) or encode the trace as four parallel `[Double]` arrays, which is also several times smaller as JSON.
Document the greedy nearest-pair matching as a deliberate choice, since it is order-dependent at exact ties.

**Adversarial tests to add.**
All of these fail today.
Label each as pinned to a synthetic generator until a device trace exists.

| Test | Input | Assert | Emits today |
|---|---|---|---|
| `testWalkingArmSwingIsNotCounted` | 30 s, 0.8-2.0 Hz, 0.25-0.40 G, no reps | `== 0` | 15-41 per movement |
| `testFidgetAfterRepsIsNotCounted` | 5 pull-ups then 60 s of two-tone 0.37/0.61 Hz wander at 0.03-0.12 G | `<= 6` | 17-21 |
| `testSingleImpactIsNotCounted` | one Gaussian impact in 40 s of quiet, 1-4 G | `== 0` | 1-4 |
| `testSegmentStartDoesNotEmitFromPrimingTransient` | 40 s still wrist, segment opened mid-motion | `<= 1` | 3-7 |
| `testMovementBoundaryDoesNotCreditOutgoingMotion` | 10 s pull-ups, `beginSegment(.pushUp)`, 4 s more pull-up-shaped motion | `== 0` push-ups | 2 |
| `testWristReorientationIsNotCountedAsARep` | 12 s reps then a contiguous step from (0,0,1) to (0.6,0,0.8) held constant | no extra rep | +1 |
| `testDoublePeakSquatsSweepSeparationAndWidth` | the shipped `doublePeakSignal`, separation 0.4-1.4 s x width 0.06-0.18 s | `== 8` everywhere | 16 at (1.2 s, 0.18 s) |

Parameterise `emittedReps` (RepDetectionTests.swift:391-406) over a `restMotion` amplitude; its rest is currently `motion = 0` plus 0.006 G noise, which is why the shipped tests pass.
Parameterise `feed` (`batchSize: Int = 25`, line 267) over [1, 25, 50]; no test today exercises the 1 s batch the batched tier ships, and the totals are batch-size invariant, so this locks in a property that currently holds.

**Tighten the tolerances.**
Every counting assertion is `XCTAssertEqual(Double(count), N, accuracy: 1)`, which passes at N+1.
Measured against the shipped generators, the pipeline returns the exact truth on all of them: 10 pull-ups → 10, 6 slow 0.25 G pull-ups → 6, 8 double-peak squats → 8, 12 gravity-rotation push-ups → 12, 20 s still → 0, and 10 → 10 at every amplitude from 0.50 down to 0.05 G.
The slack buys nothing.
Pin lines 113, 120, 128, 138 and 355 to exact equality, and pin the engine-level upper bounds too: 5 reps + 80 s rest emits exactly 5 (line 426 allows 6), 10 + 48 s emits exactly 10 (line 432 allows 11), 15 + 60 s emits exactly 15 (line 438 allows 16), 12 reps emits exactly 12 (lines 291-292 allow 8...12).
`testMidSetPauseIsNotCountedButLaterRepsAre` (line 444) already hides a phantom: ground truth 6, engine emits 7, sitting exactly on its `<= 7` bound.
The extra rep is the step discontinuity where the synthetic motion snaps to zero.
Rename it so that reads as a known defect rather than a pass.

**The parameter sweep.**
`RepCountingProfile` has a public memberwise init and both `RepPeakCounter.peakIndices` and `.count` take a `profile:` argument, so a segment-level sweep needs no source edits; the suite already does this at RepDetectionTests.swift:353.
Cost split measured in an optimised build: over 2000 thirty-second windows, filter+PCA 0.069 s against `RepPeakCounter` 0.904 s, so counting is 93% of a pass at ~0.49 ms, consistent with the 0.39 ms release figure documented at `RepDetectionEngine.swift:38`.
Caching the projection buys 7-9%, not 10x, because `estimatedPeriodSamples` is O(peaks × maxLag²) with maxLag up to 200 samples.
A 4420-point grid over a 500-segment corpus is ~11 minutes single-threaded per movement.

Use the segment sweep to **shortlist** only, then re-score the top 20-50 triples per movement by full engine replay and pick the winner on the engine's precision.
A segment-level count does not bound the engine's false positives, and this was measured both ways: a 120 s set of 60 fading reps scores 51 whole-segment against 60 sliding (truth 60), and a 0.12 G fidget trace scores 20 whole-segment against 21 sliding.
Pass 3b's floor is computed over whatever peak population the window holds, and a 30 s window's population is not the segment's.
Report the segment-versus-engine delta per movement; a large delta is itself a signal.

**CI.** `.github/workflows/build.yml:50` runs `xcodebuild test -scheme SenseKitTests` on one iOS simulator, which handles anything Foundation-only and deterministic.
Put the fixture regressions there and the sweep on `workflow_dispatch`.
Fixtures need `resources:` on the SenseKit test target in `Package.swift` **and** a matching XcodeGen entry, because `project.yml:74-75` declares `sources: - path: Packages/SenseKit/Tests/SenseKitTests` wholesale and will sweep a `Fixtures` folder into compile sources; the failure surfaces as a confusing compile error, not a missing-file error.

**Trace capture.** `MotionRepSensor.consume` (line 229-236) keeps only the returned Int and lets `samples` go out of scope.
Add a `#if DEBUG` recorder behind a launch argument, following the precedent already in this repo at `ContentView.swift:204-213` and `RootTabView.swift:43-55` ("DEBUG-only and opt-in by launch argument, so it cannot reach a release build or affect a normal run").
Buffer in memory and write once at session end; writing 50 samples per second to disk in a background workout app is exactly the work that gets an app suspended.
Committing a named athlete's accelerometer traces to a public repo is that athlete's decision, not a default.

**Do not adopt Soro et al.'s figures as the accuracy gate** in the form `docs/research/automatic-rep-detection.md:331-333` currently states them.
Those numbers come from CNNs fed six channels from a wrist watch *and* an ankle watch, and the doc's own caveats section already says so.
Keep them as a labelled recall ceiling and add RecoFit's automatic-segmenter row (MAE 0.52, 93% within ±1) as the realistic classical reference, noting that RecoFit measured under "at least 30 seconds between sets", which a continuous 20-minute AMRAP never provides.

## 5. What was considered and ruled out

- **Pass 0's excursion gate is buffer-global** — true but inert; pass 3a (line 126) already re-applies the same floor per peak, and a local-window replacement is a provable no-op because a window centred on a peak contains that peak.
- **Pass 2 gives noise a shorter refractory than signal** — did not reproduce; on real projected signals the median winning lag for the pull-up bracket was 97 samples, not the claimed 59, and in a mixed buffer the fidget peaks mostly estimated *longer* periods than the real reps.
- **`greedilyThinned`'s symmetric max lets noise cluster** — the failing example is unreachable, because pass 2 only sees pass 1's survivors, which are already `minPeriodSamples` apart; the proposed asymmetric test changed nothing across five signals and is strictly more permissive.
- **`Decimator.factor` floors and the rate is never reconciled with `analysisRateHz = 50`** — real robustness gap, no over-count: every documented watch rate (800, 200, 100 Hz) divides exactly, and the standard tier passes a hardcoded 50 so the decimator is a pass-through by construction. The narrow band that does break is roughly [85, 100) Hz, which no shipping device is known to report. Close it cheaply if you touch that code: compare `sourceRateHz / Double(factor)` against `analysisRateHz` in `RepDetectionProcessor.process`, and skip a batch reporting rate 0 rather than falling back to 50 (`MotionRepSensor.swift:173`).
- **`activityFloor` is compared to a 1500-sample maximum rather than an RMS** — the statistical point is fair and folded into fix 8, but the headline "1% margin" was the worst of 20 seeds; the typical margin is 1.46x for the push-up, and pass 3a neutralises the mechanism anyway.
- **The box-FIR decimator gives only 11.7 dB of alias rejection** — the arithmetic is exact and the fix is a provable no-op: two non-overlapping box averages cascade into one box average of the product, so `box4@800 × box4@200 = box16@800` exactly. A palm strike is broadband, so it already passes the band-pass at unity gain through the direct path.
- **`-.infinity` puts no bound on a single `ingest`** — the measured "burst" is correct: 30 s of 2 s-period reps contains 15 real reps and emitting 15 is right. `reset()` clears the buffer, so the seed means "count everything in this fresh buffer". The real defect at a reset is *which* motion is in the buffer, which is fix 2.
- **A forward gap in the stream makes the band-pass ring** — the extra rep depends entirely on a wrist reorientation, not on the temporal hole; the same input delivered contiguously produces the same extra rep, and the same hole without a reorientation produces none. A forward-gap reset would add a recall cost and no precision.
- **The engine believes a sample rate it never measures** — no over-count on either live path, and the proposed fix (measuring rate from buffer timestamps) reports a low rate on any delivery gap, which inflates the refractory and undercounts.
- **Switch to `CMDeviceMotion` for `userAcceleration` and `rotationRate`** — the API is confirmed present (`deviceMotionUpdates()` at `WatchOS26.5.sdk` swiftinterface line 83), but the dominant phantom sources all carry genuine linear acceleration, so `userAcceleration` retains them. It is the largest change proposed, adds a fourth acquisition tier and gyroscope power draw, and would require re-deriving the push-up floor from scratch with "push-ups stop counting entirely" as the failure mode.
- **Replace pass 0 with a training-free periodicity gate (RecoFit's autocorrelation features, uLift, ExerSense DTW)** — the citations are real (uLift was not retrieved and its author attribution is uncertain), but the metric inverts the ranking you want: walking scores 0.777 and an air squat 0.593. Any threshold that admits the squat admits the walk.
- **Use asserted reps as per-set amplitude exemplars** — no over-count traced. Its stated harm is what pass 3a's ordering already prevents (RepPeakCounter.swift:110-127), and the proposed `max(activityFloor, 0.5 × confirmedAmplitude)` floor only helps if walking projects below half a real rep, which at 0.179 G projected is doubtful.
- **RecoFit dropped the gyroscope only for counting, not for segmentation** — true, and correctly scoped in the paper, but a grep for "gyro" across all `.swift` files returns nothing, so the codebase never over-generalised the quote. It is contingent on a segmenter that does not exist.
- **Gate detected reps on `activityState.isResting`** — self-defeating as it stands. `RestDetection.state` runs off `RoundRepTracker.lastRepAt`, which is `events.last?.date` over *all* events including detected ones (RoundRepTracker.swift:143, :127), so a phantom every ~1.1 s keeps `.working` permanently latched exactly when the gate is needed. If a rest-based mute is ever wanted, add a separate `lastAssertedRepAt` and leave the displayed rest clock on the existing value.
- **`RepDetectionEngine`'s profile is not injectable, so no grid search is possible** — false; `RepCountingProfile` has a public memberwise init and `RepPeakCounter` takes a profile directly. Only whole-engine replay needs a new seam, and only for the confirmation pass in section 4.
- **Apple ships a first-party rep counter** — it does not. Verified locally: `grep -rn "watchos(26" WatchOS26.5.sdk/.../CoreMotion.framework/Headers/` returns no matches, and no header in that directory is exercise- or repetition-related. Record the grep commands in `docs/research/automatic-rep-detection.md` so the next revision re-runs them instead of re-researching from blogs.

## 6. Sources

Verified by retrieval or by reading the shipped SDK on this machine.
Every measurement quoted above from a synthetic signal is marked as such at the point of use; none of it is device data, because no device trace exists yet.

- Morris, D., Saponas, T.S., Guillory, A., Kelner, I. "RecoFit: Using a Wearable Sensor to Find, Recognize, and Count Repetitive Exercises." CHI 2014, pp. 3225-3234. DOI 10.1145/2556288.2557116. https://www.microsoft.com/en-us/research/wp-content/uploads/2016/11/Morris_Workout_CHI_2014.pdf
  Quotes verified verbatim in the primary PDF: the 6-second accumulator and its rationale; "the amplitude of acceleration during exercise is generally consistent with that during non-exercise"; "walking is extremely periodic … it's almost impossible to heuristically describe systematic differences between walking and exercise"; the five autocorrelation features and the 5-second / 200 ms windowing; "Each of these signals is repeated for the gyroscope"; "Empirically, we did not find the gyroscope helpful for counting" (in the Counting section only); Figure 2b's squat "double peak"; 97% within ±1 with true boundaries against 93% with the automatic segmenter, MAE 0.26 against 0.52; "participants were asked to take at least 30 seconds between sets".
- Soro, A., Brunner, G., Tanner, S., Wattenhofer, R. "Recognition and Repetition Counting for Complex Physical Exercises with Deep Learning." Sensors 19(3):714, 2019. DOI 10.3390/s19030714. https://pmc.ncbi.nlm.nih.gov/articles/PMC6387025/
  Table 7 per-movement figures verified, and that the counting models used both a wrist and an ankle watch.
- Boersma, P. "Accurate short-term analysis of the fundamental frequency and the harmonics-to-noise ratio of a sampled sound." Proceedings of the Institute of Phonetic Sciences, University of Amsterdam, 17 (1993), pp. 97-110. https://www.fon.hum.uva.nl/paul/papers/Proceedings_1993.pdf
  RecoFit's own reference [3]. Step 3.10 (divide by the window's autocorrelation) and the explicit, signed `OctaveCost` lag preference verified.
- Marcotte, R.T., Bachman, S.L., Zhai, Y., Clay, I., Lyden, K. "Analytical Validation of Wrist-Worn Accelerometer-Based Step-Count Methods during Structured and Free-Living Activities." Digital Biomarkers 9(1):10-22, 2024. DOI 10.1159/000542850. https://pmc.ncbi.nlm.nih.gov/articles/PMC11771982/
  "Including a locomotion classifier had the largest positive influence on performance" verified.
- Ishii, S., Yokokubo, A., Luimula, M., Lopez, G. "ExerSense: Physical Exercise Recognition and Counting Algorithm from Wearables Robust to Positioning." Sensors 21(1):91, 2020. DOI 10.3390/s21010091. https://pmc.ncbi.nlm.nih.gov/articles/PMC7795271/
  Single-template DTW and wrist segmentation recall 0.916 verified; wrist push-up F1 of 0.745 is its worst movement.
- Lim, Y., Lee, S. "Intelligent Repetition Counting for Unseen Exercises: A Few-Shot Learning Approach with Sensor Signals." arXiv:2410.00407v2, 9 Oct 2024. https://arxiv.org/pdf/2410.00407
  Five-repetition registration verified; Table 4 gives pull-up 35.3% and squat 16.5% within ±1, far worse than Soro et al.
- Apple. watchOS SDK headers, read locally at `/Applications/Xcode.app/Contents/Developer/Platforms/WatchOS.platform/Developer/SDKs/WatchOS26.5.sdk`.
  `grep -rn "watchos(26" .../CoreMotion.framework/Headers/` returns no matches, so Core Motion gained no API in watchOS 26.
  `CMBatchedSensorManager.h:53` is `@property(readonly, nonatomic) NSInteger accelerometerDataFrequency;` with no documented value.
  `.../CoreMotion.swiftmodule/arm64_32-apple-watchos.swiftinterface:83` declares `public func deviceMotionUpdates() -> CoreMotion.CMBatchedSensorManager.DeviceMotionUpdates`.
- Apple. "Track daily activity with Apple Watch." https://support.apple.com/guide/watch/track-daily-activity-apple-watch-apd3bf6d85a6/watchos
  No mention of strength-training repetitions. Blog claims that Apple Watch counts reps natively are unsupported and were not used.

Inference markers, restated so they are not read as fact.
The walking arm-swing model (0.08-0.40 G at 0.8-2.0 Hz) is synthetic and unvalidated against a real wrist trace, so the *magnitude* of cause 1 is an inference even though the mechanism is traced through compiled source.
The claim that a fatigued air squat separates its two bursts by 1.2 s at 0.18 s burst width is unverified.
The claim that a wrist during Cindy carries sustained 6-12 Hz energy at 0.05 G, which is the whole premise of fix 7, is unverified.
The Swift actor-ordering argument in cause 3 (no FIFO guarantee between separately submitted jobs on the same actor) is inference from documented reentrancy semantics, not something measured on device.
---

## Appendix: the completeness review, verbatim

The critic re-read the source independently and spot-checked every line number.
Its corrections are already folded into "Read this first" above; this is the full text.

## 1. Claims that are wrong or unsupported

**Fix 1 (ranked #1) rests on an unrepresentative measurement, and its stated mechanism is wrong.**

The report's evidence is `Bandpass.repCounting(50).filtering` on "1500 constant samples with only sample 0 offset". I reproduced it exactly (0.1046 / 0.2091 / 0.3451 / 0.5229 for offsets 0.10 / 0.20 / 0.33 / 0.50), so the number is real — but that input is degenerate: a lone outlier sample followed by a flat line is the one signal where `series.first` is maximally wrong and `mean` is maximally right. On a realistic rolling buffer (0.5 Hz, 0.3 G sinusoid on 1 G, error measured against the same filter run from a settled 40 s prefix, phase swept in 8 steps) the mean-primed filter is barely better and is sometimes worse:

```
phase 0.79  err(prime=first)=0.2786  err(prime=mean)=0.2247
phase 1.57  err(prime=first)=0.2772  err(prime=mean)=0.2062
phase 2.36  err(prime=first)=0.1172  err(prime=mean)=0.1262   <- mean is WORSE
phase 5.50  err(prime=first)=0.1172  err(prime=mean)=0.1262   <- mean is WORSE
```

The report's justification — "the mean of a rolling accelerometer buffer is close to the true DC level … so the settling step is small" — does not hold. The residual transient is still ~0.21 G, roughly 7-10x every `activityFloor` (0.020-0.030). Priming from the mean fixes the *DC belief* but introduces a real step of `first - mean` at sample 0, which on a moving buffer is up to the full rep amplitude. The direction of the fix is defensible; the claimed magnitude and the #1 ranking are not, and the claim "no recall cost" was measured only on synthetics the fix was chosen against.

**Fix 2's latency claim is arithmetically wrong.** The report says the warm-up floor "subsumes the span guard below … so emission latency does not change". It does not. With `emittedThrough = first + 2·minPeriod` and `cutoff = latest - minPeriod` (`RepDetectionEngine.swift:139-140`), the first emissible peak needs `latest ≥ first + 3·minPeriod`. That is 2.4 s for a pull-up against today's 1.6 s. At a 0.8 s cadence roughly **two** opening reps are lost per movement block, not "one rep per block" as stated — six per round, not three.

Everything else I spot-checked holds. Verified independently: the walking over-count (40 s / 0.9 Hz / 0.08 G → **36** reps on all three profiles, flat from 0.06 to 0.60 G; 30 s / 1.4 Hz / 0.30 G → **15 / 41 / 41**, matching the report exactly); the two amplitude gates at `RepPeakCounter.swift:76-77` and `:126`; `emittedThrough = -.infinity` at `:93`; `ActiveWorkoutView.swift:141` and `:165-167`; `MotionRepSensor.swift:165-173` (whole-batch map, single `await consume`) vs `:202-211` (one sample per callback); `undoTrailingDetectedReps` at `RoundRepTracker.swift:70-78`; every test line number (113, 120, 128, 138, 355, 426, 432, 438, 444, and `feed` defaulting to `batchSize: 25` at line 266, not 267).

## 2. Citations

I could not do live retrieval in this session, so I cannot certify any external DOI. Two internal-evidence notes:

- The SDK claims are checkable and the report states the exact grep, which is the right form. I did not re-run it.
- The report itself flags uLift as "not retrieved and its author attribution is uncertain". That is the correct disclosure. No citation in section 6 looks fabricated in shape (real journals, plausible volumes/DOIs, Boersma 1993 is genuinely RecoFit's reference [3]).

The claim I would most want re-verified before anyone acts on it is Soro et al. Table 7 "the counting models used both a wrist and an ankle watch", because fix 8 and the accuracy gate in `docs/research/automatic-rep-detection.md:331-333` both hang on it.

## 3. What no lens covered

**(a) The Digital Crown is an ungated, unauditable, unremovable rep source, and the report never mentions it once.**

`ActiveWorkoutView.swift:110-126` keeps the crown focused for the entire workout, re-asserting focus on every state change. `handleCrown` (`:474-487`) turns any positive delta into `RepLogging.logAsserted(delta, source: .crown, into: tracker)`. Asserted reps bypass `detectedRepAllowance` entirely (`RepLogging.swift:18-20`: "Never gated"), so a crown rep **can close a movement and a round**, renders as a solid "athlete asserted" pip, and is invisible to both `undoTrailingDetectedReps` and `detectedRepFraction`.

During Cindy the crown spends the whole workout pressed against a bar, a forearm, or the floor — pull-up grip and push-up hand plant both put the crown face in contact with something. (Inference, not measured: I have no device trace of accidental crown rotation. But `sensitivity: .low` is a mitigation, not a lock.) An athlete who sees their score jump has no way to tell a crown rep from a tap rep from a detected rep, and "the auto detect seems too sensitive" is exactly what they would say either way.

Worse, this defeats a documented invariant. `MotionRepSensor.swift:118-119` says pause exists "so a walk to the water fountain cannot log reps", and `togglePause` duly calls `repSensor.pause()` (`:498`) — but leaves the crown focused and `handleCrown` live. Reps can still be logged while the clock is paused, by the one input path nobody audited.

**(b) Correcting phantoms manufactures more phantoms — a positive feedback loop.**

`undoLastRep` → `recompute()` → `currentStepIndex` changes → `.onChange(of: tracker.currentStepIndex)` at `:165-167` → `repSensor.setMovement` → `beginSegment` → `reset()`. So an athlete undoing back across a movement boundary **resets the engine to `emittedThrough = -.infinity` with maximum allowance**, mid-motion, while their hand is on the watch. That is the report's own Cause 2, triggered by the correction rather than by a boundary tap. Nothing in section 2 or 3 addresses it, and it explains why the feature reads as unfixable rather than merely inaccurate.

**(c) `RepPipRow` misreports provenance, and its own doc comment says that is fatal.**

`ActiveWorkoutView.swift:285` passes `detected: min(tracker.trailingDetectedRepCount, tracker.repsInCurrentMovement)`, and `RepPipRow.swift:68` computes `manualCount = completed - detected`, rendering manual pips *first*. So detected reps that are not trailing render as solid asserted pips. Concretely: tap, detect ×3, tap → `completed = 5`, `trailingDetectedRepCount = 0`, five solid pips. Three of the watch's guesses have just been laundered into the athlete's own reps. `RepPipRow.swift:12-13` states the requirement it violates: "Provenance has to persist for the life of the movement or it is not auditable at all." This makes phantoms *less* visible, so it cuts against the report's "what the athlete sees" narrative — but it also means the athlete cannot audit anything, and it compounds the bulk-undo defect the report did find (fix 4).

**(d) Session cold start is unguarded and fix 2 does not reach it.**

`ContentView.swift:116-134` starts the HK session and then, in the same main-actor turn, starts sensing and the clock. There is no countdown. The athlete presses Start on the watch, then walks to the pull-up bar — five to ten seconds of walking, at `detectedRepAllowance = 4`, before their hands touch the bar. Fix 2's blackout is `2·minPeriod` = 1.6 s. It does not cover this, and it is the very first thing the athlete experiences every session.

Related, cheap, and unmentioned: `CMBatchedSensorManager` needs an *active* HK session, but `beginCollection` is asynchronous (`WorkoutSessionManager.swift:72-86` sets `isActive` in its callback) while `repSensor.start` runs immediately. If the stream throws on that race, `handleBatchedFailure` demotes to `CMMotionManager` for the whole session, silently and permanently. Not an over-count, but it means the tier you are tuning against may not be the tier that ships.

**(e) `RepPeakCounter` bounds nothing per unit time, and `logDetectedReps` silently drops the excess.**

`RoundRepTracker.swift:125` clamps to the allowance and drops the remainder. So when the detector is running away, the tracker eats most of the evidence. `detectedRepFraction` therefore *understates* how badly the detector is behaving, and there is no counter anywhere of how many detected reps were refused. That is the one instrument that would have answered this question already, and it does not exist.

## 4. Do this first

**Log `RepEvent.source` counts per session and surface them, before touching any signal-processing code.**

Every number in this report is synthetic — the report says so itself, four times. Nobody has established that the excess reps are `.detected` at all. `RepSource` already distinguishes `.manual`, `.crown`, and `.detected`; `RoundRepTracker.events` already holds every one; `SessionSummaryView` already shows `detectedRepFraction`. Adding a per-source breakdown plus a "detected reps refused by the allowance" counter is an afternoon, needs no clock bridge, no fixtures, no `Codable` conformance, and no device trace.

It is first because it is the only cheap experiment that can *falsify* the report's thesis. If one real attempt comes back with a large `.crown` count, then sections 1 through 3 of this report — every band-pass corner, every periodicity gate, the whole structural asserted-rep proposal — are aimed at the wrong subsystem, and the fix is a two-line change to `handleCrown`. If it comes back mostly `.detected`, the report's ranking stands and the seam work in section 4 is the right next move. Doing the tuning infrastructure first spends weeks before that question is even asked.

**Files:** `/Users/kyseah/Documents/GitHub/cindy-app/.claude/worktrees/humming-swinging-pizza/SenseWatch/Views/ActiveWorkoutView.swift`, `/Users/kyseah/Documents/GitHub/cindy-app/.claude/worktrees/humming-swinging-pizza/SenseWatch/Views/RepPipRow.swift`, `/Users/kyseah/Documents/GitHub/cindy-app/.claude/worktrees/humming-swinging-pizza/SenseWatch/Views/RepLogging.swift`, `/Users/kyseah/Documents/GitHub/cindy-app/.claude/worktrees/humming-swinging-pizza/Packages/SenseKit/Sources/SenseKit/Sensing/Bandpass.swift`. Verification harness: `/private/tmp/claude-501/-Users-kyseah-Documents-GitHub-cindy-app/8e761d8c-9c93-4a62-909f-06d050f988f2/scratchpad/main.swift` (compiles the unmodified `Sensing/` + `Models/Movement.swift` sources).