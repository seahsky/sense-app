# Context

Glossary for the S.E.N.S.E. iOS and watchOS apps.

## SENSE

The product.
Displayed as `SENSE` on device, written `S.E.N.S.E.` in prose.
A backronym for Sets, Effort, Notes, Streaks, Elapsed.

Two of those letters do not yet correspond to anything the app does.
There is no Streaks feature, and Effort is not a named concept in the code.
The name is a name, not a specification.
See [[sets-vs-rounds]] for the letter that actively conflicts with the domain.

## Cindy

The workout, not the product.
A CrossFit benchmark WOD: a 20-minute AMRAP of 5 pull-ups, 10 push-ups, and 15 air squats.

This distinction is load-bearing.
The app is called SENSE; the thing it tracks is called Cindy.
Types that model the workout keep the name (`CindySession`, `CindyVariant`), because renaming them would throw away the precise word for what they are.
Types and targets that model the *shell* do not (`SenseApp`, `SenseWatch`, `SenseKit`, `SenseUI`).

## Round

One full pass of the movement sequence: 5 pull-ups, then 10 push-ups, then 15 air squats.

## Rep

One repetition of one movement.
Every rep carries its origin, either asserted by the athlete or detected from wrist motion.
See [[asserted-rep]] and [[detected-rep]].

## Asserted rep

A rep the athlete logged by hand, through the "+1 REP" button or the Digital Crown.
Ground truth.
Only an asserted rep can close a movement and advance the sequence.

## Detected rep

A rep the automatic counter inferred from wrist motion.
Never allowed to close a movement.
Always auditable and always reversible, because published counting accuracy for these three movements runs 80 to 88 percent of sets within one rep.

## Score

Rounds plus partial reps, written `17+8`.
The canonical way a Cindy attempt is recorded.

## Variant

A scaled version of Cindy: Rx, weighted vest, or a scaled movement substitution.
Changes the movement sequence or the load, never the 20-minute cap.

## Sets vs rounds

The app has no concept of a **set**.
It counts rounds and reps.
The `S` in S.E.N.S.E. stands for Sets, which is the one letter of the backronym that contradicts the domain vocabulary.
If the acronym is ever made literal, this is the letter to reconsider first.
