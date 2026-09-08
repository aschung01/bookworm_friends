# Reaction controls on the book-details hero

**Date:** 2026-08-19
**Status:** Implemented — verified against the live database, see below
**Mockups:** `docs/mockups/praise-region/index.html` (7 versions; `stack-tint` shipped)

## Context

The defect was visible in a single screenshot: on a friend's finished book the
same emoji appeared **twice** — once on the green `칭찬하기` button's face, once as
an anonymous chip below it. Two controls, one fact.

It was not an edge case. **31 of the 35** reacted-to books in production hold
exactly **one** reaction, so the duplicated-single-emoji state _was_ the ordinary
rendering. Four books have two; none has more.

Pulling on it exposed that the button and the chips disagreed about what they
were for, and that neither was quite right.

**The chips could not say whose reaction they were.** A 28pt circle holds an
emoji and nothing else. That is precisely _why_ the button carried a copy of
yours on its face — the button was compensating for the record being anonymous,
and the compensation was the bug.

**The chips grew without limit.** The hero's right column is **217pt** (393 − 40
padding − 120 cover − 16 gap). A `Wrap` of N circles wrapped into rows that
pushed down toward the status badge. Fine at N=1, which is almost always, and
unbounded in principle.

**The chips were not a control, so reactions could be stranded.** Loose circles
read as decoration, so the only route to changing or withdrawing your reaction
was the button — and the button hides below status 2. A reaction on a book its
owner moved back to _Reading_ was visible and unreachable.

**The status badge was in two places for one thing.** Bottom-right corner of the
hero on a friend's book, top of the right column on your own, because the corner
belonged to a button the owner is never shown.

**And the badge was illegible for the largest status.** Measured against its own
composited fill on `surfaceVariant`:

| status     | colour          | text : own fill |
| ---------- | --------------- | --------------- |
| Read       | `primaryText`   | 10.78:1         |
| Reading    | `brandText`     | 4.14:1          |
| Interested | `secondaryText` | **1.66:1**      |

`secondaryText` (`#ADB5BD`) is **1.75:1 on surfaceVariant** and 2.07:1 on white
— unusable as text anywhere in the app. The _Interested_ badge was effectively
invisible, with a 1.23:1 border to match, on **133 of 472** books.

Two further facts from the data decided the vocabulary and the interaction cost:

- **39 reactions, 8 reactors, 0 in the last 90 days.** The feature is dormant.
  That is what makes two taps to withdraw acceptable.
- **Only ~8 of 39 reactions are praise** (👏🥳🎉🎊⭐🤩). Eight are affection. The
  rest are ☃️ 🌪️ 🐙 🦕 🦙 🧸 🪐 🛸 🤑 🤪. The picker offers ~3,500 emoji, so a
  button labelled _Praise_ describes maybe a fifth of what people do with it.

## Decision

**The record owns the reactions; the button only ever adds a first one.**

One capped, tinted capsule states what the book has collected and opens a sheet
that says who left what. The button collapses to a single job and disappears once
that job is done. Every duplication in the old design was two controls sharing
one fact — the fix is to give the fact one owner.

### The button hides once you hold a reaction

This is the load-bearing choice, and it is what removed the last blocker.

You may hold only **one** reaction. A button that still says `React` after you
have reacted is offering an action it cannot perform; what a tap does at that
point is _replace_ or _withdraw_, and both belong to the reaction you already
have. So it hides — no state label, and therefore **no new string in any
locale**.

The alternative considered was a `Reacted` state label on the button. Rejected:
it needs a new string in two locales, it leaves a control on screen whose tap
target does something other than what it says, and it re-creates the duplication
(button says you reacted, capsule says you reacted).

### The tint replaces the label

With the button gone, something has to say _one of these is yours_. The capsule
takes `brand` at 25% with a `brandText` border — deliberately the **same
treatment `PraiseEmojiPicker`'s `emojiRenderer` uses to mark your cell**, so the
record and the picker say the same thing the same way.

The numbers are better than they look. The two fills are only **1.37:1** apart in
luminance, but the border goes from **1.3:1 to 3.88:1**. The cue that survives a
dim screen is the border becoming visible, not the hue changing.

The tint means _you are in this set_, not _this emoji is yours_. With two
reactions the whole capsule tints rather than marking which one is yours: yours
is pinned first by `orderedReactions`, so per-emoji marking would repeat what the
order already says, at a size too small to read.

### Verb: `reaction` in English, `칭찬` in Korean — deliberately

The two locales **diverge on purpose**, and this is a decision rather than a
translation gap:

|                                      | English                   | Korean                     |
| ------------------------------------ | ------------------------- | -------------------------- |
| `praise` — the button                | `React`                   | `칭찬하기`                 |
| `reactionsTitle` — the sheet         | `Reactions`               | `칭찬`                     |
| `selectComplimentEmoji` — the picker | `Choose a reaction emoji` | `칭찬 이모지를 선택하세요` |

**English goes neutral** because the label has to match the affordance, and the
affordance is a 3,500-emoji picker that people mostly use for 🦕 and 🛸. Only ~8
of 39 reactions are praise; calling it _Praise_ described a fifth of the feature.

**Korean stays `칭찬`** — the affectionate framing is the one the Korean-speaking
users have had since the feature shipped, and it is the register the app is
written in. Nothing about the English argument transfers: the point of the English
change was that the label overpromised, and `칭찬` is not a promise anyone has
complained about.

The rule for anything added here later: **one vocabulary per locale, not one
vocabulary across locales.** All three strings above must agree within their own
column. That is what caught two defects late — English `selectComplimentEmoji` was
still `Choose a praise emoji`, so tapping `React` opened a sheet about praise, and
Korean `reactionsTitle` had been added as `반응`, which was the only `반응` in the
app.

## 1. The capsule

`lib/ui/widgets/reaction_capsule.dart`

At most `kVisibleReactions` (2) emoji, then `+N`, then a chevron, in one 30pt
tappable capsule.

- **Untinted:** `pageBackground` fill, `brand` at 30% hairline — the same material
  as the chips it replaces, so it reads as the same kind of object rather than as
  something new to learn.
- **Tinted:** `brand` at 25%, `brandText` border, when `ordered.first` is yours.
- **`+N` uses `primaryText`, not `secondaryText`** — the latter measures 2.0:1 on
  `pageBackground`.
- **`+1` is information; a bare `1` is not**, so the count only renders when
  something is actually hidden behind it.
- **`onTap` is required, not optional.** The capsule is now the only route to your
  own reaction; one that answered no taps would strand every reaction on the book.
- The chevron is load-bearing rather than decorative: on a book that is not
  finished, the capsule is the only interactive thing in the hero, so the
  affordance is stated rather than implied.

`kVisibleReactions = 2` because 2 is the complete form for every real book today
(max observed = 2) — `+N` is the escape hatch, not the normal case.

## 2. The sheet

`lib/ui/widgets/bottom_sheets/reactions_sheet.dart`

40pt `AvatarCircle`, name, emoji, per row. This is what capping the capsule buys:
detail moves somewhere it has room, and every reaction gets the one thing an emoji
alone cannot carry — whose it is.

It is also **the only route to your own reaction**. The alternative is to
recognise your own emoji among three and a half thousand in the picker and know
that tapping it takes it back: works, unfindable. Your row leads the list, is the
only tappable one, and shows `You` in `brandText` plus a trailing chevron.

The chevron carries that unaided. A line of help text under a single tappable row
captions a control the row's own disclosure already announces — see Amendments.

Other rows pass `onTap: null` rather than an empty callback: an `InkWell` with a
null `onTap` shows no press feedback, so the row does not pretend to be
interactive.

Tapping your row **pops this sheet, then** calls `onEditMine`, so the picker
replaces it rather than stacking on it. The caller puts it back if the picker is
dismissed without a choice — see Amendments.

Unreadable profiles are said rather than left blank (`reactorUnknown`) — a
nameless row beside an avatar placeholder reads as a bug. `profiles` select RLS
(_public OR self OR you-follow_) and `book_compliments` select RLS
(`is_book_visible(book_id) OR from_user_id = auth.uid()`) are **independent**, so
you can see a reaction without its author. **0 of 8 current reactors are private**,
but **15 of 136 profiles are** — the path is hypothetical today and reachable.

## 3. Reading the reactor

`lib/models/book_compliment.dart` gains `reactorName` / `reactorEmoji` /
`reactorAvatarPath` (nullable together) plus a `reactorIsKnown` getter, parsed
from `json['reactor']`.

`lib/providers/book_details_provider.dart` embeds:

```
reactor:profiles!book_compliments_from_user_id_fkey(username, emoji, avatar_path)
```

The disambiguating FK hint is required because the table has more than one path
to `profiles`.

## 4. Where the status badge lives

The badge moved out of the hero corner into `ReadingPeriodRow`, **replacing** its
old `Reading period` label. Status, dates and duration are one class of fact and
belong in one place, and the badge does more work than the label did — so this
**removed a string rather than adding one**, and gave both viewers one rule
instead of two. The corner now holds only `ShelfLabel`.

`ReadingPeriodRow` is now rendered **unconditionally** with a required `status`
and a nullable `startDate`. It previously rendered only when dates existed, which
would have taken the badge off screen entirely on an _Interested_ book — 133 of 472.

With no dates there is **no card**: wrapping a lone chip in a full-width white
slab was drawn at real scale and looked worse than the corner it replaced. The
badge sits in the band bare, via `Align` — see Pitfalls.

## 5. Badge legibility

`lib/ui/widgets/book_status_badge.dart` rewritten from one-colour-derives-all to
an explicit per-status `(label, text, fill, border)` tuple.

Status 0 loses its fill and takes `primaryText`: **1.66:1 → 13.01:1** text,
1.23:1 → 3.41:1 border.

**Dropping the fill is the half that matters.** The old _Interested_ and _Read_
tints composite to `#E3E6EA` and `#D5D8DB` — two near-identical greys. The two
ends of the progression were only ever separated by a text colour nobody could
read. Darkening the text alone was tried and **rejected** for exactly that:
legible, but it made _Interested_ look like _Read_.

The three statuses now read as a **progression of weight** — empty outline, green
tint, dark tint — rather than as three hues.

With no fill, the border is what identifies the chip as a chip, so it is held to
WCAG 1.4.11's 3:1 bar: `primaryText` at **55%** measures 3.41:1, where the 35%
first drawn was 2.06:1. Exposed as `BookStatusBadge.unfilledBorderAlpha`.

**_Reading_ is left at 4.14:1**, just under AA, and that is a decision. `brandText`
genuinely is 4.74:1 on `surfaceVariant` — the figure `app_theme.dart` documents
and `color_contrast_test.dart` asserts — and it is this chip's own 10% tint
darkening the ground under it that drops it. Fixing it costs either the green text
or the green fill, and green-means-reading is load-bearing across the app. Pinned
by a test rather than left to drift.

## Dependencies

None added. `CNBottomSheet` and `AvatarCircle` already existed;
`compliment_block.dart` was **deleted**.

## Testing

467 passing, up from 434 (+33).

Rewrote `book_details_compliments_test.dart`, `book_details_status_badge_test.dart`,
`reading_period_row_test.dart`. New `reaction_capsule_test.dart`,
`reactions_sheet_test.dart`. `color_contrast_test.dart` gained a
`status badge contrast` group that measures every status against its own
composited fill. Harness gained `interestedBook()` and
`compliment(name:, reactorEmoji:, avatarPath:)`.

Three things widget tests cannot reach, and what was done instead:

- **The PostgREST embed** — verified with `curl` (below).
- **`showEmojiBottomSheet`** cannot be `pumpAndSettle`d through: it awaits
  `seedRecentEmojis()` (SharedPreferences) and pulls in the picker package. Tested
  the sheet's **callback contract** with a spy instead of following the navigation.
- **`useNativeGlass` / `CNBottomSheet` presentation** — device only.

## Verification against the live database

The embed syntax was the only real production risk. Confirmed with an anon
request:

```
GET /rest/v1/book_compliments
    ?select=*,reactor:profiles!book_compliments_from_user_id_fkey(username,emoji,avatar_path)
    &limit=1
```

**200**, with the nested object populated:
`"reactor":{"emoji":"🐶","username":"조이풀독서","avatar_path":null}`.

The FK target was already confirmed as
`book_compliments_from_user_id_fkey → public.profiles`. The fallback had the hint
been wrong was `profiles!from_user_id(...)`.

`flutter build ios --simulator --debug` succeeds, so the new native sheet path
compiles for the real target.

## Risks

- **Mixed vocabulary in the codebase.** See below. Temporary and known.
- **`reactorIsKnown` is exercised by tests but not by production data** — no
  current reactor is private.
- **The tinted/untinted distinction rests on the border**, not the fill. If the
  border is ever thinned or the radius grown, re-measure; the fills alone are
  1.37:1 apart and will not carry it.
- **A third reaction on one book has never been rendered in production.** `+N` is
  covered by tests only.

## Amendments after the first simulator run

Two things only showed up once the flow was driven by hand on a device.

### The picker's dismissal dropped you two levels

Tapping your row pops the reactions sheet and opens the picker in its place. That
was the right call for a _completed_ pick, and the wrong one for a cancel:
dismissing the picker left you on the bare book, two steps from where you started,
with nothing to show you had been anywhere. The sheet you were reading had
vanished because you backed out of the thing it opened.

**The reactions sheet is now a hub rather than one leg of a chain.**
`_onReactionsPressed` loops:

```
show reactions → row tapped? → show picker → chose? → write, done
     ↑                                        │ no
     └─────────────────────────────────────┘
```

**Choosing deliberately does not loop.** A pick is the task completing, and
completing closes the flow where cancelling returns you to where you were — the
ordinary modal contract. It also sidesteps the one case a loop would get wrong:
withdraw your only reaction and there is no record left for the sheet to show, so
a loop would have to special-case re-showing an empty sheet.

Because only the cancel path loops, `compliments` is never stale between passes:
the path that repeats is by definition the one that changed nothing. No refetch,
no `await ...future`, no provider read inside the loop.

The write moved out of `onEmojiPressed` and below the `await`, so it is sequenced
after the picker is off screen rather than racing the pop.

Two mechanical notes, both of which cost a debugging pass:

- `chosen` is captured by `onEmojiPressed`, so Dart **disables promotion** on it.
  `chosen!` after the null check is load-bearing, not defensive.
- `while (mounted)` does **not** satisfy `use_build_context_synchronously` for
  `context` uses inside the loop body. It needs a dedicated `if (!mounted) return;`
  as the first statement of each pass.

### The hint text is gone

`reactionsHint` — _"Tap your row to change or remove it."_ — was removed from both
locales.

The original argument for it was that it made withdrawal legible for the first
time. On screen that did not hold up: it is a full line of prose captioning a
single row that already carries `You` and a right chevron, which is the same
disclosure every other drill-in row in the app uses without explanation. It read
as an apology for the control rather than a description of it.

Removing it takes the sheet's string count from four to three and deletes the only
line here that had to be translated to say anything at all.

**The cost, recorded honestly:** nothing in the app now uses the word _remove_.
Withdrawal is discoverable by drilling into your own row and tapping the marked
cell, and the marked cell is the entire instruction. That was true of `main` too,
and was listed there as a defect — the difference is that the route is now two
obvious taps from the record instead of hidden behind a 3,500-cell grid. If
withdrawal turns out to be undiscoverable, the fix belongs **in the picker** (an
explicit affordance on the marked cell), not as prose on the sheet.

## Deliberately not done

- **No DB rename.** `book_compliments`, the `compliment` column and the now
  misleadingly-named `compliment_uniqueness` constraint are untouched. 136
  profiles exist, so other people's clients are in the field. If wanted: a
  separate migration behind a compatibility view.
- **No Dart identifier rename.** `ComplimentBlock` is gone, but
  `bookComplimentsProvider`, `BookCompliment`, `togglePraise`, `praiseBy`,
  `praiseTapFor`, `showEmojiBottomSheet` and `selectComplimentEmoji` all still say
  _praise_/_compliment_. A 40-file rename would have buried the behaviour change.
- **Korean is not "unresolved".** `칭찬` is the settled answer for that locale, not
  a pending translation — see the Verb section.

## Consequences

The hero has one reaction control where it had two, and the record — not the
button — owns the reactions. That is what makes the non-finished states work:
`Reading` and `Interested` books now keep a reachable route to a reaction they
previously displayed and stranded.

`Interested` becomes legible for the first time on 133 books. That change is
independent of the reaction work and is worth committing separately.

The design alternatives are browsable rather than lost:
`docs/mockups/praise-region/index.html` holds seven versions, with `owned`,
`named` and `gift` labelled **(rejected)**. Two ideas were measured and killed
_in the drawing_ — a 16pt emoji badge notched onto a 26pt avatar (the emoji lands
at 9px, illegible), and darkening only the _Interested_ text. Regenerate and
re-verify with:

```
cd docs/mockups/praise-region && python3 _build/build.py && sh _build/verify.sh
```

## Pitfalls hit

- **`ReadingPeriodRow`'s bare badge stretched edge-to-edge** under tight
  constraints — `BookStatusBadge` is a `Container` with no intrinsic width. The
  band passes _loose_ constraints, so nothing would have caught it on device
  either. Fixed with `Align`; a test pins it.
- **`flutter_test`'s font draws every glyph as a square of the font size**, so
  "Interested" measures 144pt in tests vs ~87pt on device. Never assert absolute
  pt widths; compare against the offered width.
- **`statusBadge` as a Read/Reading ternary** silently drew a _Reading_ badge for
  status 0.
- In the mockups: **`stack-status` drew the badge twice** because `frame()`'s
  corner did not check the badge axis, and **`patch()` dropped changed flow
  prose**, so `stack-tint` inherited a note claiming nothing uses the word
  _remove_ — on the very screen whose sheet says it. Caught by reading the
  rendered output, not by reasoning about the patch.
- **`OPEN` callouts only render in the flows view**; a key under a screen id is
  dead config.
