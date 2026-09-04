# 2. Zilla Slab SemiBold as the display face, with its tabular figures

Date: 2026-09-04

## Status

Accepted

## Context

The design reference sets titles and the primary button in a heavy slab serif and
leaves body text in a plain sans. The app needed a display face that could carry a
countdown clock, a rounds-plus-reps score, screen titles and action labels, on a
dark ground, on a 162 x 197 pt watch screen, and be embeddable in an App Store
binary.

Eighteen candidate faces were measured directly from their font binaries rather
than judged by eye. Two findings decided it.

**Most display faces cannot set a clock.** Their digits have different advance
widths, so a centred countdown physically shifts every second. Measured at 40 pt,
the jitter across `18:00` / `11:11` / `88:88` / `09:59` ran from 10 pt (Bowlby One)
to 49 pt (Rammetto One). Only faces that ship a `tnum` OpenType feature, or draw
their digits to one width already, avoid this.

**`.monospacedDigit()` fails silently.** Apple documents it as leaving the font
unchanged when the face has no tabular figures. There is no error and no warning.
Of the first ten faces measured, only Bevan and Bitter contained `tnum`, and only
those two went to zero jitter; the other eight were returned completely unchanged.

The first shortlist was Bagel Fat One, which is the face in the design reference,
and Bevan, which ships purpose-drawn tabular figures. Bagel Fat One has no `tnum`,
though its Latin subset is only 39 KB (the 1.55 MB full font is almost entirely
Korean) and its digits can be given uniform advances by patching the font, which
its licence permits. Bevan's tabular `1` covers 0.781 of its slot against Bagel Fat
One's 0.689, so Bevan's `11:11` is measurably tighter.

Both were rejected on a later requirement: a slimmer face than either.

## Decision

**Zilla Slab SemiBold**, subset to Latin, 41 KB, shipped in the `SenseUI` package.

It keeps the slab genus of the reference at a much lighter weight, it ships a real
`tnum` feature whose ten tabular digits are all exactly 600 units wide, and its
squared serifs sit well with the web motif's straight tension lines.

The face is used **only** for the clock, score, titles and action labels. Every
display face in this class loses its counters below about 13 pt on a dark ground:
at 9 pt the `o`, `e`, `a` and `8` fill in and the word becomes a shape. The watch UI
has 9 pt and 11 pt labels, so those stay on the system font.
`SenseFont.minimumDisplaySize` asserts the floor.

## Consequences

The clock must go through `SenseFont.clock(size:)`, never `SenseFont.display(size:)`.
That function is the one place `.monospacedDigit()` is applied, so a future font
swap to a face without `tnum` fails in one reviewable place rather than silently
reintroducing a jittering clock.

The font ships in a Swift package resource bundle, which the `UIAppFonts`
Info.plist key cannot see, because that key searches only the app bundle. It is
registered at launch with `CTFontManagerRegisterFontsForURL(_:.process:_:)` instead.
`Font.custom` resolves the PostScript name, `ZillaSlab-SemiBold`, not the file name.

Zilla Slab is under the SIL Open Font License 1.1, which permits embedding in a
commercial app and asks in clause 2 that the copyright notice and licence travel
with it. The Settings tab's Acknowledgements screen carries both.

Two subsetting traps are pinned in `Tools/`, because both are silent:

- `--layout-features="+tnum"` **drops** `tnum`. That syntax replaces the default
  feature set with a literal string rather than adding to it. The correct spelling
  is `--layout-features+=tnum`.
- Instancing a variable font leaves the original PostScript name in place, so a
  static instance cut at weight 600 still calls itself `Bitter-Thin`. Zilla Slab
  SemiBold ships as a static file and is not affected, but any future move to a
  variable face is.

## Alternatives considered

**Bagel Fat One, patched for tabular figures.** The exact face in the reference,
39 KB, and its licence carries no Reserved Font Name so a modified copy is
unrestricted. Rejected when a slimmer face was chosen; it is also the only
candidate that stays mushy even at 13 pt.

**Bevan.** Ships unmodified with purpose-drawn tabular figures and needs no font
surgery at all. Rejected as too heavy and too squarely Western for the intended
look.

**The system font throughout.** Free, perfectly legible, and supports
`.monospacedDigit()`. Rejected because it gives up the design entirely.
