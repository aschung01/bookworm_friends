# Phase 4: Friends activity — Implementation Plan

> **Status: 4a complete. 4b complete bar one verification. 4c (the Activity feed) deferred, with
> numbers.** Written against the data audit below, which is the reason this plan **reorders the phase**
> rather than building what the design record describes.
>
> 4a shipped in one pass: 13 new tests, 384 green overall, `flutter analyze lib test` unchanged at its
> 11-issue baseline, and the row verified on an iPhone 17 Pro / iOS 26.4 simulator against all three
> states the drawing shows.
>
> **One bug, and the drawing caught it rather than the other way round.** The mini cover beside a
> friend's name was built as a real `GeneratedCover`, on the reasoning that a stand-in cover should look
> the same everywhere. `GeneratedCover` sets its title at 13.5% of the width, which on a 22pt swatch is
> **3pt** — the device screenshot showed "The Vegetarian" as an illegible smudge. The drawing had
> specified a bare colour block all along (`.cv` is `width:10px;height:15px;background:<colour>`, no
> text). So **`decided.html` needed no correction this time**; the build was wrong and the drawing was
> right, which is the reverse of Phases 1–3 and worth recording as such.
>
> The other thing worth carrying forward: the batched query was verified **against the live database**
> rather than only in tests. For the user who follows the most people (7), one request returned 9 rows
> covering their followees — replacing the **14** requests the drawn row would have cost through
> `userLibraryProvider` and `userFinishedBooksProvider`. That claim has no seam for a widget test, so it
> is checked where it is actually true.

> **For agentic workers:** Implement task-by-task, in order. Steps use checkbox (`- [ ]`) syntax for
> tracking. Read `.agents/skills/flutter-tester/SKILL.md` before writing any test — this project has
> established Given-When-Then and layer-isolation conventions.

**Design:** `docs/superpowers/specs/2026-08-14-library-shell-design.md` — "Friends", "Friend paging", "Phasing"
**Drawings:** `docs/mockups/library-shell/decided.html` — `fr-everyone`, `fr-activity`, and the `EVERYONE` /
`ACTIVITY` fixtures
**Phase 3:** `docs/superpowers/plans/2026-08-16-phase-3-library-card-plan.md` — read its audit section
first. This phase repeats the same lesson and the same method.

**Goal:** Give the Friends tab the row it was drawn with — what each friend is reading and how many books
they have read — from **one** query. Defer the Activity feed, and say why with numbers.

---

## The audit, done first, because it reorders the phase

The design record scopes this phase as _"Feed query for the Activity tab. Optional `poke_events` table if
pokes should appear in it."_ Measured against the live database, **the Activity feed cannot be built
usefully yet**, and the reason is not technical.

| Measure                                                      | Value                                |
| ------------------------------------------------------------ | ------------------------------------ |
| Feed events (start/finish) in the **last 90 days**, per user | **median 0, max 0** — for every user |
| Most recent book finished                                    | 2024-03-16 — **884 days ago**        |
| Most recent praise                                           | 2024-01-21 — **939 days ago**        |
| Praises ever, and by how many people                         | **39**, from **8** distinct givers   |
| Follows in the whole app                                     | **37**, across 136 profiles          |
| Users who follow anyone                                      | **24** (median 1 followee, max 7)    |
| Users who would see a **permanently empty** Activity tab     | **113 of 136**                       |
| Books added since the migration                              | **3**, by **1** user                 |
| Books finished since the migration                           | **0**                                |

The `ACTIVITY` fixture is drawn with relative times of "2h", "5h", "1d", "3d". The truthful figure is
884 days. A feed of "what just happened" would ship as an empty screen and stay empty.

**Why this is probably fine rather than alarming.** `pubspec.yaml` is at `1.1.0+1`; `origin/main` shipped
`1.0.6+7`. The rewrite is **unreleased**, so the 2022–2024 data is the old app's genuine history and the
silence since is the gap before launch. The three recent books look like developer testing. The
conclusion for this phase is the same either way: a feed cannot be designed, populated or verified
against data where nothing has happened.

### Three findings that outlive this decision

1. **`books.created_at` is a migration stamp, not an event time.** 469 of 472 rows are stamped `2026-05`,
   the import date; only 3 are real. Any feed that treats `created_at` as "added a book" will claim 469
   books were added in May 2026. This needs handling in the query — excluded, or floored at the import
   date — and it is invisible until someone looks at the distribution.
2. **Two of the four drawn events need ratings, which do not exist.** The `★★★★☆` on the "finished" row
   and `rated Beloved ★★★★★` as an event of its own. `books.rating` is null in all 472 rows and
   `BookRating` is never instantiated — the same hole that cost the Library Card its Rating tile. Half
   the drawn feed is unbuildable for the same reason.
3. **Only praise carries a real timestamp.** `book_compliments.created_at` and `follows.created_at` are
   `timestamptz`; `books.start_date` and `finish_date` are `date`. So "finished 2h ago" is not
   expressible at all, and two same-day events cannot be ordered against each other. A feed mixing these
   sources has mixed granularity, which is a design problem and not a formatting one.

### The reordering

| Was                      | Now                                                                                               |
| ------------------------ | ------------------------------------------------------------------------------------------------- |
| Activity feed            | **4a — the Everyone row.** Works on existing data. It is the real regression against the drawing. |
| `poke_events` (optional) | **4b — do it before launch.** Cheap, and the only piece with a deadline.                          |
| —                        | **4c — the Activity feed. Deferred** until there is activity, i.e. after release.                 |

**Why `poke_events` stops being optional.** `poke_user()` writes no row, so every poke that happens
before that table exists is lost permanently. Recording is a small migration plus a line in the
function; the feed can consume it whenever. Launching without it throws away exactly the history the
feed will eventually want. This is insurance, not a feature.

**And the honest note about sequencing:** phases 1–3 have never been in front of a user. The next
milestone after 4a is more likely **releasing 1.1.0** than building 4c.

---

## Task 1 (4a): one query for the whole friends list

- [x] A `friendsReadingProvider` that returns, per friend id, their in-progress books and their finished
      count. **One round trip for the entire list**, not one per row — which is the whole point, and is
      why `friends_sheet.dart` shipped without this in Phase 1. Its doc comment states the problem
      exactly: `userLibraryProvider` and `userFinishedBooksProvider` are keyed by user id, so rendering
      the drawn row from them means a request per friend, fired the moment the tab opens.
- [x] Derived from `followingListProvider` rather than taking an argument. A list of ids is a poor family
      key (identity, not value, equality), and the provider always wants exactly the people the sheet is
      already showing.
- [x] Filter to `status in (reading, finished)` server-side. Fetching whole libraries to count two things
      would move the waste from round trips to payload.
- [x] RLS needs no special handling: `books` already has `Others can read visible books` gated on
      `is_profile_visible(user_id)`, so a batched `in` filter returns exactly what per-user reads would —
      fewer rows for a private profile, never someone else's.
- [x] Add `bookStatusReading = 1` beside the existing `bookStatusFinished = 2`. The literal `1` is
      currently spelled out in `book_info_bottom_sheet.dart` and inlined with a comment in tests.

**Done when** the provider returns one map for any number of friends, having made one request, and a unit
test pins the grouping.

**Built as planned.** `friendsReadingProvider` in `user_provider.dart`, with the grouping split into
`groupFriendReading` in `lib/models/friend_reading.dart` so it is a unit test rather than something only
an integration test could reach — the same split that made `libraryCardStats` cheap to trust.

**The "one request, not N" claim has no test seam** and is not faked with one. There is no Supabase
fake in this project; tests override providers instead, which would mean asserting against the very
thing under test. Verified against the live database instead, which is stronger: one request, 9 rows,
7 followees, versus the 14 requests the per-friend providers would have made.

What the live check also showed, and no fixture would have: **6 of those 7 followees have nothing in
progress and 0 finished books.** The sparse-data case is the common one here, exactly as it was for the
Library Card — which is why Task 2's "nothing in progress" state is a first-class state and not a
fallback.

---

## Task 2 (4a): the row as drawn

- [x] Subtitle is `Reading <title>`, with several titles joined by `·` — the `EVERYONE` fixture's
      `minho` row is `Reading Snow · Circe`, so multiple in-progress books is a drawn state, not an edge
      case.
- [x] `Nothing in progress` when there are none, and **no cover** in that case — the fixture's `sora` row
      has an explicit `null` where the others have a colour.
- [x] Trailing figure is the finished count in `brandText`, bold. **The drawing has no chevron**; the
      count sits where the chevron sits today. Follow the drawing — the row is still an `InkWell` and the
      visit is the affordance.
- [x] The cover is the first in-progress book's, drawn small. Reuse the book widgets rather than a bare
      `ColoredBox`, so a coverless book falls back the same way it does everywhere else.
- [x] Every new string through l10n, including `Nothing in progress` and the `Reading …` prefix. Korean
      does not take an English word order here, so the prefix cannot be interpolated as
      `'Reading ' + titles`.
- [x] Loading: the row keeps its name and avatar and simply has no subtitle or count yet. It must not
      change height when the query lands, or the whole list will jump.

**Done when** all four drawn states render from fixtures, and the row's height is the same with and
without data.

**Built, with the mini cover corrected on the device** — see the status block. Three of the four drawn
states are in the preview fixture and on screen: one book, two books joined with `·`, and nothing in
progress with no swatch. The fourth — a friend **absent from the map**, meaning still loading or
invisible to us — cannot be shown by a fixture that resolves instantly, so it lives in
`test/friend_reading_test.dart` only.

The chevron is gone, replaced by the count, per the drawing. Height stability is achieved by rendering
the subtitle **always**, empty while loading: an empty `Text` still occupies one line at its size, so
the list cannot jump when one batched query fills every row at once.

### Reported from the device: the row answered a tap with nothing at all

The checklist above says "the row is still an `InkWell` and the visit is the affordance". Half of that
was wrong, and only a finger could tell. **`InkWell` rendered nothing here**: `LibrarySheet` paints its
background with a `DecoratedBox` rather than a `Material`, so the splash landed on the `Scaffold`'s
material _behind_ the sheet and was never once visible. A test asserting an `InkWell` was present would
have passed for as long as the widget existed.

Replaced with an explicit `AnimatedContainer` highlight, tinted `surfaceVariant` over 110ms:

- **Driven by raw pointer events, not `onTapDown`.** `AvatarCircle` carries its own gesture detector and
  wins the arena for taps that land on it, so a tap-driven press state would leave the row looking dead
  when you press the most obviously pressable thing in it. `Listener` sees the pointer either way. Same
  reasoning as `_Capsule` in `read_filter.dart`.
- **`surfaceVariant`, deliberately not `sheetBackground`.** The drawing spends `sheetBg` on `.erow.hit`,
  the friend whose library you are currently visiting, so a press tinted to match would read as though
  the tap had already taken effect.
- Gated on `onTap == null`, so the sheet mid-edit stays inert rather than lighting up and doing nothing.
- `_highlightInset` 13 + `_contentInset` 12 = the 25pt gutter the content sat at before, so the
  highlight cannot shift the text sideways.

**Then reported again, and the endpoint tests could not see it:** the row "flashes dark gray for a
quarter sec upon tap then shows a lighter gray". The highlight faded from `Colors.transparent`, which is
transparent **black** (`0x00000000`), and `Color.lerp` walks the RGB channels alongside the alpha — so
every intermediate frame was a semi-opaque _dark_ grey on its way to a light one. Measured at the
mid-frame: RGB `0.48`, exactly halfway to black. Fixed by fading `tint ↔ tint.withValues(alpha: 0)`,
which holds the hue fixed and moves only alpha.

Two lessons, both about tests rather than about the row:

1. **Asserting the endpoints of an animation asserts nothing about the animation.** The press tests
   checked that the tint was present under a finger and absent after, and passed throughout the bug.
   What pins it is a frame _in between_, asserting the RGB is constant across it.
2. **Read the painted `DecoratedBox`, not the `AnimatedContainer`.** The latter carries the _target_
   decoration, which is correct the instant state changes and interpolates nothing — a test reading it
   can never catch a bad fade. And reaching the painted value needs **two** pumps: the frame built right
   after a state change is where the animation _starts_, still painting the old value, so a lone
   `pump(Duration(milliseconds: 200))` reads the colour from before the press no matter how long the
   duration is. That is what `_settlePress` in the test file exists for.

Device-verified twice: settled, and again against a build with the duration temporarily raised to 3s so
a mid-fade frame could be photographed. The mid-fade frame is a _fainter_ light grey, not a darker one.

Still unbuilt, and flagged rather than scope-crept: the drawn `.erow.hit` row-level tint for the friend
being visited. `isSelected` currently only rings the avatar.

### Then the swatch was reversed again: the real book, in miniature

Requested directly — the book in the row should look 3D like the ones on the shelves, and be the exact
same book rather than a lookalike. So `_MiniCover` is gone and the row draws the shelf's own
[`BookWidget`] at 34pt: same cover, same chassis, same page block and back board, same ISBN-hashed
height and page-count thickness.

That overturns the swatch decision recorded above, which is worth being explicit about rather than
quietly overwriting. The swatch reasoning was **right about the type and wrong about the book**: 3pt of
title really is a smudge, but the fix chosen threw away the whole chassis to solve a font-size problem.
The type is still tiny at 34pt and that is now an accepted cost, not a bug. Two of the other objections
turned out not to apply:

- **Jitter.** The read grid's bug was a _row_ of books at hashed heights reading as misalignment. There
  is one book per row here and the row's height is set by the 40pt avatar, so a book between 32 and 36pt
  cannot move it — the height-stability test still passes untouched. Keeping the jitter is what makes the
  thickness reflect the real page count, which is most of what makes it the same book.
- **The press and turn.** `pressEffect` is off, because the finger is on the row and not on the book.

**The turn is driven by the row's press, and getting there needed the device.** The request was for the
turn to play "upon tapping the friend row", and that is what was built first: a tap-triggered flourish,
turn out and fall back, unit-tested and green. On the device it did nothing visible at all. Tapping a row
calls `onSelectFriend`, which also flips `libraryModeProvider`, so the shell **replaces the entire
Friends sheet** with the library and the friend rail — the row unmounts within a frame or two and takes
its animation with it. The screenshot aimed at the middle of the turn came back showing a different
screen.

So the turn follows `_pressed` instead: it starts on pointer-down and unwinds on release, which is the
only window in which the row still exists. One deliberate difference from the shelves: **no
`kBookHoldDelay`.** There the 140ms delay exists so an ordinary tap produces no rotation, because the
book stays put and the turn means "keep holding, something is about to happen". Here holding longer
changes nothing and release navigates away, so a delay would mean an ordinary tap showed no motion at
all. The angle, durations and curve are the shelf's exactly — `kBookTurnDuration` and
`kBookReleaseDuration` were made public for it.

Driving the turn from outside needed two additive changes to `BookWidget`, which is worth knowing about
because that file is shared: a `turnDrive` parameter that replaces the internal hold rather than adding
to it, and a fix for a latent crash it exposed. Both animation controllers were `late final` field
initialisers, and `dispose` reads them — so a book that never read one during its life would _construct_
it while unmounting, and creating a ticker reads `TickerMode.of(context)` from a defunct element. Dormant
while `build` always touched both, and reachable the moment a book was driven from outside and stopped
touching `_turn`. Both are now built in `initState`.

Device-verified at 34pt, which was the real open question — whether a turn is legible at that size.
It is: held, the cover skews and the page-block band appears down the right-hand edge; the resting book
in the row below stays flat. Checked twice, once against a build with the turn slowed to 3s to confirm
the mid-turn frames, and once at the real 260ms.

---

## Task 3 (4a): tests and verification

- [x] Unit test for the grouping: several friends, one with two in-progress books, one with none, one
      with no books at all, and a friend id absent from the response entirely.
- [x] Widget test for the four drawn states, asserting **absence** as well as presence — no cover and no
      count where there is no data, per Phase 3's lesson that a hollow figure is worse than none.
- [x] A test that the row's height does not change between loading and loaded.
- [x] Assert one request, not N. This is the entire justification for the task, so it is worth an
      explicit test rather than an assumption.
- [x] Re-measure clearance if the row's height changes — the Friends sheet shares the band with the
      library like every other tab.
- [x] **Run it on a simulator.** The Friends tab is at approximately `--x 0.41 --y 0.918`.
- [x] Update `decided.html` only where the build proves a drawing wrong, and say so in the note.

---

## Task 4 (4b): `poke_events`, as insurance

- [x] A migration adding `poke_events (id, from_user_id, to_user_id, created_at)` with RLS matching the
      existing poke rules, and a line in `poke_user()` that records the poke it already sends.
- [x] **No UI.** Nothing reads this table yet, and that is the point — it exists so that history begins
      accumulating before launch rather than after the feed is built.
- [ ] A test that poking writes exactly one row, since nothing else will notice if it stops.
      **Not done, and it cannot be from here.** The insert is guarded on `auth.uid()`, which is null for
      both the service role and the anon key, so no REST call can exercise the positive path — and the
      app signs in with Apple/Google, so the simulator has no session either. What _was_ verified appears
      below. The gap: **nobody has yet confirmed that a real poke writes a row.** Do it on the first
      signed-in build: poke someone, then `select * from poke_events`.

**Applied to the live database** (`supabase db push`, one migration, history in sync beforehand), and the
security model verified rather than assumed:

| Attempt                                       | Result                                      |
| --------------------------------------------- | ------------------------------------------- |
| `poke_user('__no_such_user__')`               | HTTP 204, **no row** — still a silent no-op |
| service role INSERT (what `poke_user` does)   | 201 — the only writer                       |
| unauthenticated INSERT                        | **401, RLS violation** — cannot be forged   |
| unauthenticated DELETE / UPDATE of a real row | 204, and **the row survived**               |
| unauthenticated SELECT                        | `[]` — no leak                              |

The DELETE result is the one worth explaining, because it looks like a hole and is not: with RLS on and
no DELETE policy, the statement matches zero rows and PostgREST reports 204 for a delete that affected
nothing. Proving that required **seeding a real row first** — the initial check ran against an empty
table and was therefore meaningless. The seeded row was removed afterwards.

**Three decisions inside the function, all recorded in the migration:**

- The insert sits **outside** the `fcm_token` check. A poke with no deliverable notification still
  happened, and the sender was told it worked; recording only deliverable ones would make history depend
  on whether the recipient had push enabled at the time.
- It is **guarded** on `poker_id IS NOT NULL AND target_id IS NOT NULL AND target_id != poker_id` rather
  than left to the CHECK constraint. A failed CHECK raises, which would turn today's silent no-ops —
  unknown username, unauthenticated caller, self-poke — into an error the app reports as "poke failed".
  Recording history must not change what the button does.
- **No uniqueness constraint**, unlike `book_compliments`. Praise is a state and is one-per-person-per-
  book; a poke is an event, and poking twice is two pokes. That leaves the table open to spam, which is a
  rate-limiting problem rather than a schema one.

**What this does not fix:** `poke_user()` still never checks that the poker follows the target, so anyone
can poke anyone by username — and now that poke gets recorded. Left alone deliberately: tightening it is
a behaviour change and belongs with the praise policy gaps in the design record's "Still open", not
smuggled into a migration about recording. The recording arguably helps, since an abusive poke now leaves
a trace.

---

## Risks

- **The batched query is the one thing here that could regress the Friends tab**, which currently works.
  It replaces nothing — the row gains a subtitle and a count — so the failure mode is a slow or failing
  query leaving the row as it is today. That is a soft failure by construction, and Task 2's loading
  requirement is what keeps it soft.
- **`is_profile_visible` is applied per row, not per request.** A friend who goes private drops out of the
  result rather than erroring, so the row must render a friend with **no entry in the map at all** — not
  merely a friend with zero books. Task 3 tests that case explicitly.
- **Read counts here and on the Library Card must agree.** Both are "books with `status = 2`", and if they
  ever diverge a user will see two different numbers for the same friend. Worth deriving from the same
  constant, which is why Task 1 adds `bookStatusReading` beside `bookStatusFinished` instead of a literal.

## Open questions to settle during, not before

- **Does the count mean books read, or books read that you can see?** A private-ish profile shows fewer
  rows to a visitor than to itself, so the same friend can honestly have two different counts. The Card
  has the same ambiguity and nobody has hit it yet.
- **Whether the row should show what they are reading at all when it is stale.** A book started in 2023
  and never finished still has `status = 1`, so `Reading …` may be reporting an abandoned book as current.
  There are 118 such rows in the corpus. Decide from the rendered list.
