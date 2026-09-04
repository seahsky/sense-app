# 1. SENSE is the product, Cindy is the workout

Date: 2026-09-04

## Status

Accepted

## Context

The app was called Cindy, after the CrossFit benchmark workout it tracks.
It has been renamed to S.E.N.S.E. (Sets, Effort, Notes, Streaks, Elapsed).

That rename is ambiguous in an unhelpful way, because "Cindy" named two different things at once.
It named the product, and it named the domain concept the product is about.
A blanket find-and-replace would have renamed both.

The domain types are precise.
`CindySession` is a record of one attempt at Cindy.
`CindyVariant` is a scaled version of Cindy.
Neither is "a SENSE session" or "a SENSE variant", because SENSE is an app and Cindy is a workout.
Renaming them to `WorkoutSession` and `WorkoutVariant` would have been *less* precise, not more, since the app models exactly one workout and the type names are what say so.

## Decision

Rename the shell, keep the domain.

Renamed:

- Product name and display name, to `SENSE`
- Bundle identifiers, to `com.senseapp.ios` and `com.senseapp.ios.watchkitapp`
- Xcode project, targets, and source folders, to `Sense.xcodeproj`, `SenseApp`, `SenseWatch`
- The shared package, to `SenseKit`, plus a new `SenseUI` package for the design system
- App entry points, to `SenseApp` and `SenseWatchApp`

Not renamed:

- `CindySession`, `CindyVariant`, and every reference to the workout in prose and comments
- Health usage strings that describe what is saved, which is still "a Cindy AMRAP attempt"

## Consequences

A reader who opens `SenseKit` and finds `CindySession` will wonder whether the rename was left half-finished.
It was not, and this record is why.
`CONTEXT.md` carries the same distinction in the glossary.

Changing the bundle identifier gives the app a new container.
Any workout history saved under `com.senseapp.ios` is unreachable after this change.
That was accepted deliberately: there are no shipped users, and the old identifier was worth leaving behind while it was still free to do so.

`WKCompanionAppBundleIdentifier` in the watch target's `Info.plist` hardcodes the phone app's bundle ID.
It is not derived from build settings, so it has to move with the rename or the watch app stops pairing.

## Alternatives considered

**Rename the domain types too.**
Rejected.
It would have cost the vocabulary that makes the code readable, in exchange for a consistency that only looks like a virtue from a distance.

**Keep the bundle identifier.**
Reasonable, and it would have preserved on-device data.
Rejected because the app has no users to protect and a `com.senseapp` prefix under a product called SENSE is a small permanent confusion.
