# Status and Progress as One Sheet — Implementation Plan

**Spec:** `docs/superpowers/specs/2026-09-28-status-progress-merge-design.md`

**Drawings:** `docs/mockups/status-progress-merge/index.html` (22 screens, 9 elements, 4
flows, 3 versions; `verify.js`)

**Citations:** `python3 docs/superpowers/plans/cite_check.py --show` — every `file.dart:line`
below is checked to exist. It does **not** check that the line means what the prose claims,
so read the `--show` output when a task looks wrong.

**Goal:** Replace the three-segment status sheet and the separate percent wheel with one
sheet whose hero is a glassy drag-only track; derive the status word from the position; and
give a book the reader abandoned its own status so it can be recorded without lying.

**Order of work, and why.** Three phases, and the split is by risk rather than by screen:

- **Phase 1 (Tasks 1–8) is the sheet.** No schema change, no new status value, nothing new
  written to the database. It ships alone and is useful alone: one door instead of two, one
  control instead of two, and the vocabulary fixed. Set aside is not offered yet, so a
  reader who abandons a book is no better off than today — which is the honest cost of
  shipping this half first.
- **Phase 2 (Tasks 9–13) is set aside.** This is the half with a new `status` value in it
  and therefore the half that can be wrong about _other_ screens' counts. It must not start
  until Phase 1 is in a reader's hands.
- **Phase 3 (Task 14) is editing the total page count.** Independent of both, and the only
  task that writes a column nothing currently writes after insert. Last because it is the
  most likely to want its own review.

**What is already in place, so do not build it.** Three things the spec needed and found:

- `showSelectPercentBottomSheet` **does not write.** It takes `onConfirmed` and
  `onProgressSelected` and hands the value out (`select_percent_bottom_sheet.dart:94`).
- `recordReadingPosition` (`library_provider.dart:752`) is the narrow two-column writer that
  derives nothing. `reading_streak_page.dart:313` already uses exactly the
  capture-then-write shape Phase 1 needs.
- `book_status_bottom_sheet.dart:186` already holds the wheel's answer in `setState` and
  lets Save write it. **Save-commits is the behaviour that survives** once the band's
  immediate writer is deleted, not a mechanism to add.

**One open question, and it does not block.** The spec's remaining question is whether
offering the position at Finished inverts `ss-finished` wrongly. That is a judgement on the
drawing; build it as drawn and raise it at review.

---

## Build log — 2026-09-28

All three phases were built in one pass, in the worktree `.worktrees/status-progress` on
`feat/status-progress-merge`. **`flutter test`: 2013 pass, 0 fail** (baseline before the work
was 1903). `flutter analyze` is clean of errors and warnings in `lib/` and `test/`.

### Corrections to this plan and to the spec, made while building

- **Task 1's "use a horizontal drag gesture only" was wrong, and produced the exact defect
  the design exists to prevent.** `GestureArenaManager.close` resolves an arena by default
  when it holds one member, in a microtask after pointer-down, so a lone
  `HorizontalDragGestureRecognizer` **wins before the finger moves**: a plain tap fired
  `onHorizontalDragStart` and rewrote the position, and a *vertical* pan moved the thumb too.
  The inert tap is a **slop gate** measured in the widget (`kTouchSlop` of horizontal travel
  before anything is reported), not a choice of recognizer. A no-op `TapGestureRecognizer` as
  a second arena member was rejected in a comment: it fixes the tap and not the vertical pan.
- **"Save commits the drag" needed no new plumbing, and the spec said it would.** The spec
  claimed `showSelectPercentBottomSheet` writes and that making it return was the trap. It
  does not write — it hands the value out and its callers decide. Two of three callers already
  held the answer for Save; the third was the band's second door, which this work deletes.
- **A drag to the origin could not be expressed at all**, and this is the one place the design
  hit a documented invariant head-on. `updateBookStatus`'s `progress` uses `null` to mean *do
  not write*, so "erase the position" had no spelling. Resolved with an explicit
  `clearProgress` flag on both the provider and `BookStatusEdit`, rather than by overloading
  the sentinel — the asymmetry is the point and is now documented in both places.
- **Deleting `BandProgressRow` took the band's numerals with it**, which no task said to do.
  The spec and the drawing both have the card carrying "status, dates *and* position"; the
  band went silent about the position for a round, and a test was written asserting that
  silence before it was caught. `ReadingPeriodRow` now takes `progress` / `pageCount`.
- **And then four values did not fit in the card, which is the one defect a reader reported
  from the finished build.** "This looks too messy", against `[Reading] 2026.09.13 ~ | 71% ·
  p.307 / 432 | 15 days` wrapped onto two lines. Two separate faults, and the count was the
  lesser one: two of the four values were redundant with the other two (start date ↔ elapsed
  days, percent ↔ page), and three things on the line were green (the badge and both
  `brandText` values). The card now has **two slots** — *where or when*, then *how long* —
  with exactly one of them the answer. The start date is gone from the card; the finish date
  survives, because nothing else on the card implies it. Recorded in the spec's *One sheet,
  one door*, in `reading_period_row.dart`, and pinned by `reading_period_row_test.dart`'s
  `the two slots` group.
- **A finished book was the state that still wrapped after the first fix**, which is the
  detail worth keeping: the one book whose reading period is *complete* is the one that
  cannot print it, because a closed range is twice as wide as an open one. It shows its
  finish date and drops the start.
- **Then the page pair was withdrawn from the card as well**, on instruction: *"no need to
  show total page count or current page index from the tappable row."* `71% · p.307 / 432`
  was about 120pt of the card's 333 spent restating the percent more precisely than a glance
  wants, and it is why a finished book's closed range would not fit beside it. `pageCount`
  left `ReadingPeriodRow` entirely — the widget can no longer draw a page — and
  `book_details_tab_view.dart` stopped passing `book.pageCount`. The numerals live on in the
  sheet's `ReadingStateLine`, where each is a tappable span onto the wheel, so this moved the
  precision to where it is asked for rather than deleting it. Three consequences worth
  expecting: the preview's six states collapsed to five, because "Reading with a count" and
  "Reading without one" stopped differing; `band_doors_test.dart`'s page assertion inverted
  to `findsNothing`; and the card's cases now search bare digit runs (`307`, `432`) rather
  than `p.307`, so bringing the numbers back under a different separator still fails.
- **`Stop reading this` is confirmed, and `Start reading again` exists**, both on
  instruction. The resume link reverses a decision this plan, the spec, the mockup caption
  and three comments in the sheet all stated — that a set-aside book resumes by moving the
  thumb, so a link would be a second affordance for a gesture already present. The premise
  was wrong: the thumb resumes only by *changing the position*, so a reader who stopped at
  46% and wants to carry on from 46% had no move at all. The confirmation is a sub-sheet that
  hands an answer back, like the date and percent sheets, **not** a second commit path —
  `Save` is still the only writer, and dismissing still discards. `Start reading again` is
  deliberately *not* confirmed: the band is confirmed because it is wide and easy to hit, and
  an accidental resume costs nothing.
- **The sheet has one height, 335, and the case that used to defend the opposite is the
  reason.** `and it grows rather than snapping when Save arrives` asserted the sheet grew
  mid-drag and sampled the animation halfway to prove it was eased — and its own comment gave
  the argument against itself: *"both happen on the same gesture, so without the animation the
  sheet would jump twice under the reader's thumb."* A bottom sheet is bottom-anchored, so
  growing moves its top edge and the track with it, because both date rows sit below the
  track; easing does not stop the control sliding out from under the finger dragging it. The
  case is now inverted and asserts `ReadingTrack`'s **rectangle** is unchanged.
- **Which caught a second one the height alone could not.** With the frame in, the sheet
  stopped resizing and the track still moved 11pt: the title `Row` was sized to its tallest
  child, so Save arriving grew it from the title's ~21 to the button's 32 and pushed
  everything below down. `_kTitleRowHeight` pins it. An assertion about the sheet's height
  passes on that bug; only one about the track's rectangle fails.
- **The cost is a 165pt void on Not started**, which is pinned rather than tolerated — the
  sheet is framed to a set-aside book and the state with the least in it is the one a reader
  meets first. Accepted because the alternative is a 115pt jump on the first drag of every new
  book. Available and not taken: drawing the start-date row at the origin would fill 60 of it
  and close a real gap, since a start date currently cannot be set without first inventing a
  position.
- **Save and Reset moved to the foot, and the read-out's page pair to the right edge**, both on
  instruction. The first is what made `Reset` possible at all — a 92pt slot beside a title holds
  one button, a full-width row holds a pair — and it let the title row's pinned height go, since
  anything arriving below the track cannot push the track. `Reset` restores the sheet's
  *arguments*, the same set `dirty` compares against, so a reset sheet is clean by construction
  and the row cannot survive its own press.
- **The right edge needed `spaceBetween` over two nested groups, not over the flat list.** Flat it
  spreads all four parts and floats the percent into the middle; and a `Row` with a `Spacer` — the
  obvious spelling — throws away the wrap degradation `ReadingStateLine` exists for, since a Row's
  children have no run to drop to. The case that pins it needs a **500pt** box rather than the
  sheet's 327, because `reading_state_line_test.dart` draws in the test font where `Reading` sets
  to 151pt and the two groups do not fit; at 327 it would measure the wrap instead of the
  alignment.
- **And the sheet went 335 → 384, past both sheets it replaced (342, 368).** The commit row costs
  60 and the frame follows the tallest state, so every state pays it. The case that asserted
  `lessThan` both now asserts `greaterThan` both — the claim is false and is recorded as false
  rather than deleted. The void on Not started went 165 → **214**, over half that sheet; the jump
  the frame prevents went 115 → 165 in the same move, so both sides of the trade got worse at
  once. Three ways out are written into the spec and none is taken.
- **`ConstrainedBox(minHeight:)`, never `SizedBox`.** A fixed height trades a moving control
  for a clipped one at large accessibility text sizes. The `AnimatedSize` is kept for exactly
  that residual case and for nothing else.
- **A third-party threshold moved with the height, and its case had already warned about
  it.** `BottomSheet` dismisses on a drag past half its own height, so `the sheet takes a
  decisive vertical pan` broke when 160pt fell from 0.58 of the sheet to 0.48. The comment
  above it already recorded the same failure from the font loading. The drag is measured off
  the sheet now rather than written as a literal.
- **The render harness for that card lied in its first frame, in the way `AGENTS.md` already
  warns about one level down.** `test/reading_period_row_render_preview.dart` had no
  `Material` ancestor, so every inherited `Text` fell back to `MaterialApp`'s
  `_errorTextStyle` — red with a yellow double underline — while the spans that set a colour
  explicitly survived. The result looks like a selectively broken widget rather than a broken
  harness, and it cost a round of reading the wrong thing. A missing `Material` and a missing
  icon font are the two things to check before believing a preview.
- **`BookStatusBadge` would have said "Other"**, as Task 9 predicted. Its `switch` is now
  lifted into `BookStatusBadge.presentation`, which the sheet's read-out borrows, so the chip
  and the running text cannot drift about either the word or the colour.
- **`U+2248` is not in the app's fonts.** `progressApproxPage` shipped `≈ p.{page}` and the
  faces are subset to Latin-1 plus Hangul, so the glyph came from a platform fallback in
  another typeface. Pre-existing, and the merged read-out made it prominent. Changed to an
  ASCII tilde, which is what the drawings used anyway.
- **`ReadingStateLine` inherited an underline from `MaterialApp`'s fallback `TextStyle`**,
  on a widget whose whole contract is which parts are underlined. `decoration` is now stated
  rather than omitted. Every existing assertion read `Text.style`, which is why nothing caught
  it.
- **The sheet's heights were estimates and are now measured** at a real 375×667 with the app's
  fonts loaded: Reading clean **275** (estimated 270), dirty 286 (292), Finished 276 (282),
  Not started **170** (estimated 246 — at the origin the read-out collapses to one word and
  both date rows are absent). Both replaced sheets were 342 and 368.
- **`cite_check.py` was broken for every doc in the repo**, reporting 51 citations across four
  pre-existing docs as `ambiguous`, because `.worktrees/` holds full copies and was not in its
  `SKIP` set. Fixed.
- **The "reading-day set still in flight" case did not exist.** `AGENTS.md` says
  `band_doors_test.dart` caught that regression; the case was never committed. Written now.

### Second review round — the control was rebuilt

A reader looked at the shipped sheet and asked whether it was using the glass slider the
Cupertino package provides, said the bookmark made an ugly thumb, asked for the action to be
centred, and asked for a real sheet title instead of the book's name. Three of the four were
straightforward; the first was the important one.

- **`ReadingTrack` went from ~650 lines of `CustomPaint` to ~150 wrapping `CNSlider`.** The
  package was already a dependency and already shipped a native `UISlider`; the hand-drawn
  groove got the *fallback's* look on every platform, including iOS 26, which is the only one
  with the real material. The bookmark thumb went with it, and the glide, the slop gate and
  the groove painter went with that.
- **The inert tap now comes from the platform**, because `CupertinoSlider` and `UISlider` are
  relative. The slop gate was a correct fix to a real discovery — a lone drag recognizer wins
  its arena by default at pointer-down — and the platform sliders had already solved the same
  problem by adding deltas instead of seeking.
- **`CupertinoSlider` is used explicitly rather than letting `CNSlider` fall back**, because
  its fallback is a *Material* `Slider`, which taps-to-seek. That would have reintroduced the
  rejected `band-scrubber` behaviour on Android and in every widget test. A case now asserts
  the widget is a `CupertinoSlider` and not a `Slider`, with that reason in its comment.
- **Three defects in the rewrite, all found by review rather than by the suite**, and all
  fixed: the root `Column` lost `mainAxisSize.min` (600pt in a bounded box, measured); the end
  labels lost `Flexible` + `maxLines: 2` + ellipsis and overflowed by 119pt at 2× text, undoing
  a documented decision; and `report` needed a no-change guard, because `CupertinoSlider` fires
  `onChanged` for sub-step movement and the sheet treats every report as a percent answer — so
  a 1pt slip dropped the reader's page provenance and raised Save with nothing changed.
- **Two test files were passing vacuously**, both for the same reason: they dragged from the
  middle of the track, and `_RenderCupertinoSlider.hitTestSelf` accepts a pointer only within
  ~22pt of the thumb, so the gesture reached no recognizer. In `book_details_streak_test.dart`
  that meant the transition-not-state assertion — the one that file exists for — **was not
  live**: with no write happening, it would have passed against a `lib/` that celebrated on
  state. Confirmed by mutating `lib/` and watching it fail only after the repair.
- **The heading is a sheet title now.** `readingProgressTitle`, replacing the book's own name.
  `changeReadingStatus` was already unread and stays annotated.
- **"Stop reading this" is centred and full width.** Left-aligned it sat under the start-date
  row's inset and read as a third field rather than an action.

`flutter test`: **2008 pass, 0 fail, 0 skipped** — including one case that had been skipped
because the label row overflowed, which the `Flexible` restoration made live again.

### Deferred, with the reason

- **`changeReadingStatus` is now unread in `lib/`** and is kept with an `@` note saying why,
  rather than deleted: it is the only phrase in either ARB for what that sheet used to be.
- **The Korean copy wants a native reader.** Eleven strings were written rather than
  translated, per house rule, but not by a native speaker: `읽기 전`, `완독`, `중단`,
  `읽기 중단`, `전어듄 쓰수 입력`, `현재 쪽`, `전어듄 쓰수`, `완독한 책`,
  `완독한 책이 없어요`, `완독한 책만 보기`, `읽은 책 모두 보기`.
- **`ReadingStateLine` draws no `Add total pages` offer on a not-started book**, because the
  whole percent-and-page region is gated on there being a position. Consistent with the
  drawing's not-started state; worth revisiting, since that offer is the largest thing the
  sheet adds and a book with no count and no position cannot reach it from here.
- **The read-set popover occludes the year rail entirely**, plus the first month header and
  the top of the first cover row — measured at 390×800, slightly less than the drawing. Left
  as drawn; dropping the card below the rail is available and leaves it hanging off nothing.
- **The set-aside filter mode lives in the sheet's own `State`**, so it resets on a trip
  through the Friends list level. One line to promote to a provider if that matters.
- **`main_shell_preview.dart` overrides the finished providers but not the set-aside ones**,
  so the device preview's inclusive mode shows an empty extra set.
- **The track's drag is absolute** (the thumb jumps under the finger once slop is crossed)
  rather than relative. Relative avoids the jump but makes the far end unreachable in one
  gesture, which matters because the −/+ steppers were deliberately removed. Recorded in the
  class doc.

## Phase 1 — the sheet

### Task 1: `ReadingTrack` — the glassy, drag-only control

**Files:**

- Create: `lib/ui/widgets/book/reading_track.dart`
- Create: `test/reading_track_test.dart`

- [x] **Step 1: A horizontal track with the bookmark as its thumb.** Reuse the geometry in
      `lib/ui/widgets/book/reading_bookmark.dart` rather than drawing a second ribbon — one
      mark reads one position at four sizes now (shelf, Library Card, home-screen widget,
      this). Ends labelled _Not started_ and _Finished_, not `0%` and `100%`: the words are
      what let the status be read off the control.
- [x] **Step 2: The tap is inert. Only a drag moves the thumb.** This is the design's whole
      defence and it is load-bearing —
      `docs/mockups/streaks/index.html`'s `band-scrubber` is the same control and was
      rejected because _"a stray touch could silently rewrite your position"_. Use a
      horizontal drag recognizer only; do **not** add `onTapDown`/`onTapUp` "for
      convenience". A test asserts a tap at 80% leaves the value alone.
- [x] **Step 3: The origin writes `null`, not `0`.** Dragging to the leftmost position
      yields "not started", which is what makes Reading → Not started reachable. `0%` is
      deliberately unreachable from this control and stays reachable from the percent
      sheet's own `0` stop. Model the callback as `ValueChanged<double?>` so the state is
      in the type and not in a sentinel.
- [x] **Step 4: Glass through the app's existing path, and check which one.**
      `native_glass.dart` gates iOS 26; `shelf_picker_popover.dart:340` shows the
      `LiquidGlassContainer` / `BackdropFilter` pair and `shell_tab_bar.dart:417` shows the
      hand-rolled blur. Take the existing division of labour — _Flutter draws every pixel of
      content, the platform supplies the material behind it_ — and do not introduce a third
      glass idiom.
- [x] **Step 5: Real `Slider` semantics, and this is not optional.** A drag-only scalar is
      unusable under VoiceOver. Wrap in `Semantics` with `slider: true` and implement
      `onIncrease`/`onDecrease`; the accessible path is allowed to do what the touch path
      refuses, because an explicit assistive gesture is not a stray touch.
- [x] **Step 6: Reduced motion.** Follow `StreakFlame`'s precedent and let the thumb move
      without any spring or overshoot when `MediaQuery.disableAnimations` is set.

### Task 2: `ReadingStateLine` — the one-line read-out with three doors

**Files:**

- Create: `lib/ui/widgets/book/reading_state_line.dart`
- Create: `test/reading_state_line_test.dart`

- [x] **Step 1: One line, four parts** — status word, percent, and the page inside the
      total, as `Reading · 46% · p.213 of 462`. It is one line on purpose: a second line
      would re-separate the two facts this design merged.
- [x] **Step 2: Only the two page numerals are underlined.** The percent is equally
      tappable and carries no underline: it is the largest thing on the line and obviously
      the value, and marking all three made three competing affordances out of one read-out.
- [x] **Step 3: Three callbacks, not one.** `onPercentTap`, `onPageTap`, `onTotalTap` — the
      total's is what Phase 3 fills in; until then pass null and draw the total unmarked.
- [x] **Step 4: The no-count case is the majority.** ~65% of books have no `page_count`, so
      the page pair is replaced by a single underlined _Add total pages_ affordance (inert
      until Phase 3). Do not draw `p.213 of —`.
- [x] **Step 5: Derived vs. given pages read differently.** A page computed from the
      fraction is prefixed `~`; one the reader typed is not. `progress_page` is what
      distinguishes them, which is why it is stored at all.
- [x] **Step 6: Measure it in Korean.** `Set aside 46% p.213 of 462` is the longest English
      case and Korean is longer; the line must degrade by wrapping the page pair rather
      than by ellipsising the status word. Test at 2× text scale.

### Task 3: Rebuild `showBookStatusBottomSheet` around the track

**Files:**

- Modify: `lib/ui/widgets/bottom_sheets/book_status_bottom_sheet.dart`
- Modify: `lib/ui/views/book_details_tab_view.dart`
- Modify: `test/book_status_bottom_sheet_test.dart`

- [x] **Step 1: Delete `BookStatusSelector` from this sheet** (`book_status_bottom_sheet.dart:115`).
      It stays in the add-book sheet, where nothing has happened yet and there is no
      position to derive from. The status word is now drawn by `ReadingStateLine`.
- [x] **Step 2: Replace `ProgressFieldRow` with `ReadingTrack`** and drop the `status == 1`
      guard around it (`book_status_bottom_sheet.dart:178`). The track is present in every
      state — that is what makes it the control rather than a field.
- [x] **Step 3: Delete `ReadTodayFieldRow` from this sheet** (`book_status_bottom_sheet.dart:209`)
      and `readToday` from the `BookStatusEdit` record. Moving a position already stamps the
      day. **`_onEditStatusPressed` must still stamp it** — `book_details_tab_view.dart:1288`
      currently passes `edit.readToday`; it becomes `read: true`, conditional on the position
      having moved, and `wasRead` at `book_details_tab_view.dart:1224` still feeds
      `_celebrateIfTonightIsNew`.
- [x] **Step 4: Derive the status from the position, and keep the date defaulting.** `null` →
      Not started, `0 ≤ p < 1` → Reading, `p == 1` → Finished. The start/finish date rows keep
      their `status >= 1` and `status == 2` guards (`book_status_bottom_sheet.dart:134` and
      `:154`) — they are reading the derived status now, so nothing about them changes.
- [x] **Step 5: Save appears only when dirty**, inside the `AnimatedSize` the sheet already
      has (`book_status_bottom_sheet.dart:104`). Clean 270pt, dirty 292pt. Its arrival _is_
      the dirty indicator, so there is no other "unsaved" affordance to add.
- [x] **Step 6: The book title is always left-aligned in the title row**, present or absent
      Save, so the row does not re-centre when the button appears.
- [x] **Step 7: Save is the only writer.** The drag does not persist on release; the wheel
      opened from the percent numeral still returns rather than writes, exactly as
      `book_status_bottom_sheet.dart:186` already does. **Assert it**: a drag then a dismiss
      must leave `progress`, `progress_page` and `reading_days` untouched. This is what makes
      "dismissing discards" true rather than claimed, and it is the answer to the objection
      that killed `band-scrubber`.
- [x] **Step 8: Route the position write through `recordReadingPosition`, not
      `updateBookStatus`,** when only the position changed. `updateBookStatus`
      (`library_provider.dart:895`) recomputes `reading_shelf_index`, so a nudge would bump
      the book to the head of the Reading shelf ~30 times a book. A test asserts
      `reading_shelf_index` is untouched by a position-only save.

### Task 4: Gate the re-head on an actual status change

**Files:**

- Modify: `lib/providers/library_provider.dart`
- Modify: `test/library_provider_test.dart`

- [x] **Step 1: In `updateBookStatus` (`library_provider.dart:895`), compute
      `reading_shelf_index` only when the status actually changes.** Today it is recomputed
      on every call, which is safe only because the sheet's Save was rare. The merged sheet
      is not rare.
- [x] **Step 2: Test both directions** — a status change still re-heads, a status-identical
      call does not. The second is the regression this task exists to prevent.

### Task 5: The band becomes one card, and `BandProgressRow` goes

**Files:**

- Modify: `lib/ui/views/book_details_tab_view.dart`
- Modify: `lib/ui/widgets/reading_period_row.dart`
- Delete: `lib/ui/widgets/band_progress_row.dart`
- Modify: `test/band_doors_test.dart`

- [x] **Step 1: Delete `BandProgressRow` from the band** (`book_details_tab_view.dart:647`)
      and the `showsProgressRow` / `bandRowSpills` machinery with it
      (`book_details_tab_view.dart:247`, `:581`). The period card at
      `book_details_tab_view.dart:629` now carries status, dates **and** position, and opens
      the one sheet.
- [x] **Step 2: Delete `_onEditProgressPressed` (`book_details_tab_view.dart:1328`).** This
      is the second door and the only immediate position writer; removing it is what makes
      Save-commits true everywhere.
- [x] **Step 3: Move `kBandProgressRowSpill` before deleting its file.**
      `reading_period_row.dart:41` defines `kStatusVerbSpill = kBandProgressRowSpill`, so the
      deletion breaks that file unless the constant moves into it. Its sibling
      `kBandProgressRowResidualPadding` (16 − 14 = 2) exists only for the deleted row and
      goes; the band's bottom padding returns to a plain 16.
- [x] **Step 4: `spillsIntoBandPadding` simplifies to `true`.** The band passed
      `!showsProgressRow` because the two rows contended for one padding
      (`reading_period_row.dart:191`). With one row there is no contention, and the comment
      explaining the contention should go rather than be left describing an absent widget.
- [x] **Step 5: On a friend's book the chevron and the tap target drop and the read-out
      stays** — the existing rule that _"a door nobody can open must not draw a handle."_
- [x] **Step 6: Rewrite `band_doors_test.dart`'s expectations.** It asserts
      `find.byType(BandProgressRow)`. Keep every claim about
      _what the band says_, drop the claims about which widget says it, and keep the case
      that a stalled `readingDaysProvider` still lets the sheet open — that one caught a
      real regression and is not about this change.

### Task 6: The vocabulary sweep

**Files:**

- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_ko.arb`

- [x] **Step 1: Four string values, no key renames.** `statusInterested` "Interested" →
      "Not started" and `statusFinished` "Read" → "Finished", in both ARBs. Both keys
      already exist with the right names, so no call site moves.
- [x] **Step 2: The Korean is written, not translated**, per the widget copy's precedent.
      `관심` → not-started and `읽음` → finished are the two to get right.
- [x] **Step 3: Check every surface that draws these**, not just the sheet:
      `BookStatusBadge` (`book_status_badge.dart:57`), the add-book sheet's selector, and
      `_OwnedBookRow` in `add_book_bottom_sheet.dart:1026`. The rename lands in all of them,
      which is the point — but look at the add-book selector's width at 2× text, since
      "Not started" is longer than "Interested" in a three-segment native control.

### Task 7: Sub-sheet doors for the percent and the page

**Files:**

- Modify: `lib/ui/widgets/bottom_sheets/select_percent_bottom_sheet.dart`
- Modify: `lib/ui/widgets/bottom_sheets/book_status_bottom_sheet.dart`

- [x] **Step 1: `46%` opens the wheel unchanged.** No new sheet, no new parameters — this is
      `showSelectPercentBottomSheet` exactly as it ships, and keeping it that way is what
      lets the track be coarse.
- [x] **Step 2: `213` opens the same sheet straight into Page mode**, so a reader who thinks
      in pages converts nothing. Add an `initialMode` parameter rather than inferring it
      from `initialPage`, which already means "resume where they left off"
      (`select_percent_bottom_sheet.dart:104`).
- [x] **Step 3: Both return to the parent sheet and mark it dirty.** Neither writes. The
      `_touched` gate must survive: agreeing with a pre-filled wheel must not rewrite the
      column, and its own record notes the regression — _"merely opening the sheet and
      agreeing with it moves the bookmark back a page."_

### Task 8: Phase 1 tests

**Files:**

- Modify: `test/book_status_bottom_sheet_test.dart`
- Modify: `test/band_doors_test.dart`
- Create: `test/reading_track_test.dart`, `test/reading_state_line_test.dart`

- [x] **Step 1: Set a real surface size.** `flutter_test`'s default 800×600 is shorter than
      any phone the app supports; the sheet must be asserted at **375×667**. Moving the
      streak ladder failed 31 cases with an overflow for exactly this reason.
- [x] **Step 2: The track is inert on tap, moves on drag, and reports `null` at the origin.**
- [x] **Step 3: Nothing writes before Save** — drag then dismiss, and sub-sheet Confirm then
      dismiss, both leave all three stores untouched.
- [x] **Step 4: Save absent when clean, present after a drag, present after a sub-sheet
      Confirm.**
- [x] **Step 5: The status word is derived** — four cases, one per position, with no status
      control touched.
- [x] **Step 6: A position-only save leaves `reading_shelf_index` alone.**
- [x] **Step 7: Run the render previews and look at them.** Two defects in the streak work
      were invisible to a green suite and visible in a render; this sheet's glass and its
      one-line read-out are the same kind of risk.

---

## Phase 2 — set aside

### Task 9: `bookStatusSetAside`, and the badge that would say "Other"

**Files:**

- Modify: `lib/providers/library_provider.dart`
- Modify: `lib/ui/widgets/book_status_badge.dart`
- Create: `supabase/migrations/<ts>_book_status_set_aside.sql`
- Modify: `test/book_status_badge_test.dart`

- [x] **Step 1: `const int bookStatusSetAside = 3;`** beside `bookStatusReading`
      (`library_provider.dart:27`) and `bookStatusFinished` (`library_provider.dart:30`).
      There is no `bookStatusInterested` today, so this is the third of four names.
- [x] **Step 2: A comment-only migration.** `books.status` is a `smallint` with no CHECK, so
      value 3 needs no DDL; the migration documents the vocabulary and nothing else. **Apply
      it with the Supabase MCP `apply_migration`, never `supabase db push`** — this checkout
      has pending migrations from parallel work. Then reconcile
      `supabase_migrations.schema_migrations.version` with the local filename's timestamp.
- [x] **Step 3: Give `BookStatusBadge` a fourth arm** (`book_status_badge.dart:76`). Without
      it a set-aside book wears a chip reading **"Other"** — the same silent-wrong-label trap
      as the segmented control's `clamp`, and it fails soft, so nothing catches it.
- [x] **Step 4: Two constraints on the new arm's colours.** It must not be green, because
      _green-means-reading is load-bearing across the app_ and the class doc says a test pins
      it; and it must not be status 0's treatment (transparent fill, `primaryText` outline at
      `unfilledBorderAlpha`), which is also what the fallback draws today — or _Not started_
      and _Set aside_ are one chip.
- [x] **Step 5: Five call sites, and one is outside this design.** Four are in
      `reading_period_row.dart` (`:190`, `:234`, `:274`, `:295`), which this work rebuilds;
      the fifth is `add_book_bottom_sheet.dart:1026`, which it does not touch.

### Task 10: The predicates that must admit or exclude 3

**Files:**

- Modify: `lib/providers/library_provider.dart`
- Modify: `test/library_provider_test.dart`

- [x] **Step 1: `status >= 1` (has a start date) and `status == 2` (has a finish date) must
      admit 3.** `finish_date` on a status-3 row is **the day it was closed**, which is what
      keeps `ReadMonthGrid.group` and `readFilterYears` working untouched — both read
      `finishDate` and neither cares why the book ended.
- [x] **Step 2: `withoutFinishedBooks` (`library_provider.dart:47`) and `shelvedBookCount`
      (`library_provider.dart:151`) must exclude 3**, or the cover double-lists on its plank
      _and_ in the read sheet. Both are pure functions with existing tests.
- [x] **Step 3: Assert the blast radius is zero, because that is what the status value was
      chosen for.** `finishedBooksProvider` is `.eq('status', bookStatusFinished)`
      (`library_provider.dart:539`), and `home_page.dart` hands that one list to
      `FinishedBooksSheet`, `ReadPile` **and** `LibraryCardSheet`. A status-3 book must leave
      the Library Card hero, `libraryCardStats` and `groupFriendReading` **unchanged**. This
      is the test that earns its keep.

### Task 11: "Stop reading this"

**Files:**

- Modify: `lib/ui/widgets/bottom_sheets/book_status_bottom_sheet.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ko.arb`

- [x] **Step 1: One text action, in `secondaryText` grey**, not `flame`. Giving up on a book
      is ordinary, not destructive, and the grey is what keeps it from being the loudest
      thing on the sheet.
- [x] **Step 2: Drawn in the Reading state only.** Nothing has started at Not started; a
      finished book cannot be given up on; and a set-aside book **resumes by moving the
      thumb**, so a resume link would be a second affordance for a gesture the sheet has.
- [x] **Step 3: It writes `status = 3` and `finish_date = today`, and leaves the position
      exactly where it is** — the read-out keeps saying 46%. That is the whole point of the
      status existing.
- [x] **Step 4: No "Put back on the shelf" and no "Start reading".** The thumb performs both:
      a drag off the origin starts, a drag to the origin writes `null` and un-starts.
- [x] **Step 5: New ARB key in both files**, Korean written rather than translated.

### Task 12: The read sheet's title is the filter

**Files:**

- Modify: `lib/ui/widgets/finished_books_sheet.dart`
- Modify: `lib/ui/widgets/library_sheet.dart`
- Modify: `lib/providers/library_provider.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ko.arb`
- Modify: `test/finished_books_sheet_test.dart`, `test/library_clearance_test.dart`

- [x] **Step 1: The title carries a chevron and is the read-out.** `Books finished` / 23 by
      default, `Books read` / 29 inclusive. `LibrarySheetTitle`
      (`library_sheet.dart:1914`) gains a trailing chevron and an `onTap`; title, count and
      chevron are **one** tap target.
- [x] **Step 2: Use `showShelfPickerPopover`'s pattern (`shelf_picker_popover.dart:97`), not
      `CNPopupMenuButton`.** The native button looks like an exact fit — `read_filter.dart:178`
      already uses it with `checked:` items — but its `buttonLabel` is **platform-rendered**,
      and that file records the label arriving at "the system's 17pt in the theme's tint,
      wrapped onto two lines inside a platform view Flutter had sized for 13pt". The title is
      the sheet's largest text and its count is brand-coloured, so it cannot become a platform
      button label.
- [x] **Step 3: Two checkable rows** — _Show finished only_ (default) and _Show all read_.
- [x] **Step 4: The year rail stays directly under the title row.** `expandedHeader` is
      `Column[title, ReadFilter(expanded: true)]` (`finished_books_sheet.dart:308`) and that
      is structure. Drawn to scale the popover **occludes the rail**, which is recorded rather
      than designed away — if it is judged worse than the occlusion, drop the card below the
      rail instead of moving the rail.
- [x] **Step 5: The filter applies in both sheet states; only the chevron is expanded-only.**
      A filter honoured in one state and not the other makes the count jump on collapse.
      Collapsed, the header row already has the year popover competing for it
      (`finished_books_sheet.dart:281`).
- [x] **Step 6: A set-aside provider, merged inside the sheet**, so nothing else in the app
      changes. `userFinishedBooksProvider` (`library_provider.dart:535`) needs the same
      sibling, because **a friend's library shows the filter too** — which means a friend can
      see what you gave up on. Default is finished-only, so it is per-view.
- [x] **Step 7: New ARB keys for both titles and both rows, and `noFinishedBooks` /
      `noFinishedBooksInYear` must follow the mode**, or the empty state reads "No books read
      yet" under a `Books finished` title.
- [x] **Step 8: The title row must not overflow at 2× text with a two-digit count.** That row
      is what `library_clearance_test.dart` exists for and the chevron adds to it.
- [x] **Step 9: The month counts must sum to the header count in both modes** — the reason the
      count has to track the visible list rather than the achievement.

### Task 13: The dog-ear

**Files:**

- Modify: `lib/ui/widgets/read_month_grid.dart`
- Modify: `test/read_month_grid_test.dart`

- [x] **Step 1: A corner fold on a set-aside cover in the read grid.** It is what stops
      "Books read 29" being read as 29 completions.
- [x] **Step 2: Deliberately not the bookmark ribbon**, which means _actively reading_ on the
      shelf, the Library Card and the home-screen widget. Reusing it would say the opposite.

---

## Phase 3 — editing the total page count

### Task 14: The total-pages sheet, and the first write to `page_count` after insert

**Files:**

- Create: `lib/ui/widgets/bottom_sheets/select_total_pages_bottom_sheet.dart`
- Modify: `lib/providers/library_provider.dart`
- Modify: `lib/ui/widgets/book/reading_state_line.dart`
- Create: `test/select_total_pages_bottom_sheet_test.dart`

- [x] **Step 1: Keypad first, wheel second.** A total is typed off the back of the book, not
      scrolled to — the wheel's own record calls reaching an arbitrary page in a 912-page book
      "tens of flicks either way". **No Percent/Page segment**, because a total has one unit.
- [x] **Step 2: A floor and a ceiling.** A book cannot have 0 pages, mirroring
      `kProgressPageFloor`'s reasoning; a plausibility ceiling stops a typo becoming a
      permanent fact.
- [x] **Step 3: It must not move `progress`.** The fraction is the position, so changing the
      total re-derives the **page** and leaves the position byte-identical. Assert exactly
      that.
- [x] **Step 4: `page_count` is written once by `addBook` and never again today**, so this is
      a genuinely new writer and wants its own narrow method rather than a parameter bolted
      onto `updateBookStatus`.
- [x] **Step 5: This is the largest single win here.** ~65% of the corpus has no count —
      Kakao supplies none — which is why the wheel hides Page mode and stores a fraction.
      Filling the total in lights up Page mode, the derived page, and the home-screen
      widget's page read-out for a book that never had them. Test that path end to end.

---

## Testing beyond the per-task tests

- [x] **`flutter test` is fully green today (1851 cases) and there is no expected-failure
      list**, so any red is a real regression. Do not add to a list; fix or explain.
- [x] **`flutter analyze` must stay clean of errors _and_ warnings in `lib/` and `test/`.**
      Filter the vendored SPM noise first:
      `flutter analyze 2>&1 | grep -E "^\s*(error|warning) •" | grep -vE "•\s*build/"`.
- [x] **Re-run the design record's own checks** — `node docs/mockups/status-progress-merge/verify.js`
      and `python3 docs/superpowers/plans/cite_check.py` — after any task that moves a line
      number this plan cites. The citations are checked for existence, not meaning.
- [x] **Look at the screens.** Both of the streak work's worst defects were invisible to a
      green suite: a progress bar with no track, and a label half off the page. Render the
      sheet at 375×667 and 393×852, in both themes, in English and Korean.
- [x] **Update `AGENTS.md` when Phase 2 lands.** The sheet's count and the Library Card's now
      agree in the default state, so the note is one sentence about the inclusive state rather
      than the standing 29-vs-23 disagreement an earlier draft promised.
- [x] **A reading day still cannot be un-recorded, by decision.** Do not quietly un-gate
      `streakUndoVisible` while working in here; `AGENTS.md` gives the reason it is
      `kDebugMode`-only, and this design does not overturn it.
