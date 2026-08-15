# Free emoji praise

**Date:** 2026-08-14
**Status:** Approved design

## Context

"Praise" (칭찬하기) is the app's only persisted social action: one emoji, from one
person, on one finished book. As of `eef61d0` it is unique per person per book,
readable by anyone who can see the book, and a tap on the palette is a toggle —
the same emoji withdraws, a different one replaces.

That commit also picked a fight with the live data. Applying the migration showed
that **28 of the 39 praises in production are emoji outside the fixed 16** —
🦄 🐲 🧸 🛸 ☃️ ✌🏻 — dated 2022 to 2024 and carried over from the archived project.
Their shape gives away where they came from: ✌🏻 carries a skin-tone modifier and
☃️ a variation selector, which is system-keyboard output, not a curated grid.

So the fixed palette was never what people used. 72% of real praise went outside
it the moment users had a free keyboard. The palette is being replaced with a
real picker.

One argument in the mockups' design record does not survive this change, and
should not be quietly retained: the closed set was justified as "so praise can be
aggregated (👏 3) rather than listed". Nothing aggregates today — chips render
1:1 — and the only aggregation on the roadmap is the proposed shelf hint, which
needs a _count_, not a shared glyph. What the palette actually bought was speed:
praise was one tap on a two-row grid. Preserving that speed is the constraint
this design has to respect.

## Decision

Use [`awesome_emoji_picker`](https://pub.dev/packages/awesome_emoji_picker)
`^1.0.5` — search, persisted recents, categories, skin tones, light/dark, and
translatable category labels. `flutter pub add --dry-run` resolves it cleanly
against this project's pinned `path_provider_foundation` and
`shared_preferences_foundation` overrides; its dependencies (`collection`,
`flutter_svg`, `path_provider`, `shared_preferences`) are all already in the
tree, so it adds no new native plugin.

## 1. Schema — prerequisite

`compliment` is `varchar(6)`, sized for one emoji when ❤️ (2 code points) was the
worst case. A free set does not fit: of the 3,544 emoji in the (dormant) `emojis`
package, **290 exceed 6 code points** and would be rejected outright — families
at 7–8, couples with skin tones at 10 (🧑🏿‍❤️‍💋‍🧑🏾). Postgres `varchar` counts
characters, so this is a hard rejection, not truncation.

`profiles.emoji` is `varchar(6)` too and is fed by _this same sheet_, so both
columns widen together.

| Column                        | From         | To                                              |
| ----------------------------- | ------------ | ----------------------------------------------- |
| `book_compliments.compliment` | `varchar(6)` | `text` + `CHECK (char_length BETWEEN 1 AND 16)` |
| `profiles.emoji`              | `varchar(6)` | `text` + `CHECK (char_length <= 16)` (nullable) |

16 code points clears the widest emoji that exists with headroom while still
refusing prose. The `CHECK` is the point: "free" must not quietly become a text
field. A tighter constraint pinning the column to a known emoji list is now
permanently off the table — it would reject the 28 legacy rows.

New migration created with `supabase migration new`, applied with
`supabase db query --linked`, then recorded with `supabase migration repair`.

## 2. The sheet becomes the picker

`showEmojiBottomSheet` keeps its signature and its `CNBottomSheet` host, and
swaps `PraisePalette`'s 16 tiles for `EmojiPicker`. `PraisePalette` and its
`praiseEmojis` list are deleted as a widget; the 16 characters survive only as
seed data (§3).

Category names, the search hint and the skin-tone label are passed our own
strings, because untranslated English categories in a Korean app read as
unfinished. New ARB keys in `app_en.arb` / `app_ko.arb` for the nine categories
plus `searchHintText`, `searchResultsText`, `skinToneLabel`.

## 3. The 16 become the seed, not the menu

`EmojiRepository` persists 24 recents through `SharedPreferences`. Recents are
more honest than an editorial guess — they are what _you_ actually use — but a
first-time user would meet a 3,544-emoji grid with an empty Recents row.

So the current palette seeds recents when the store is empty, and praise gets its
own `prefsKey` separate from the profile-emoji picker: what you praise with and
what you use as your avatar are different vocabularies, and letting one pollute
the other's recents would make both worse.

## 4. Toggle legibility moves to a header strip

This is what the change costs. `EmojiPicker` exposes only `onEmojiSelected` — it
has no selected state — so the highlighted cell shipped in `eef61d0` cannot
survive. It was already weak: a highlight in a 3,544-cell scrolling grid is
unfindable.

The sheet gets a strip above the picker instead: your current praise shown as a
chip, with a text button beside it that withdraws it and closes the sheet. The
strip is absent entirely when you hold no praise, so it never advertises a
withdrawal you cannot make. That states the toggle rather than implying it, and
it works for legacy off-palette praise, which no grid position could represent.

`praiseTapFor` and `togglePraise` are unchanged. Picking the emoji you already
hold still withdraws it, so the strip is an affordance, not a second code path.
The Praise pill on the details page continues to wear your own emoji.

## 5. Attribution

The package is MIT **with an attribution requirement** — visible credit to
Sébastien Gruhier (development) and Inès Gruhier (design). pub.dev reports the
licence as "unknown", so this is easy to miss.

The app has no licences screen at all today. Settings gains an Acknowledgements
row opening Flutter's `showLicensePage`, which aggregates every bundled package's
licence — hygiene we owe generally, not just here — plus an explicit credit line
naming both authors.

## 6. Cleanup

`emojis: ^0.9.9` is removed. It is imported nowhere, it is the dormant engine of
the old free picker, and the new package supersedes it.

## Testing

- `praiseTapFor` / `praiseBy` unit tests stand unchanged: the decision logic is
  untouched, which is the point of having extracted it.
- The `PraisePalette` highlight tests are replaced by tests on the header strip —
  that your praise is shown, and that withdrawing is offered only when you hold
  one.
- A widget test that the sheet presents the picker and is reachable, following
  `book_info_bottom_sheet_test.dart`'s open-via-button pattern.
- The picker touches `SharedPreferences`, so tests need
  `SharedPreferences.setMockInitialValues({})`. Seeding is a pure function over
  "current recents" so it can be tested without the plugin.
- Existing `book_details_compliments_test.dart` and the status-badge suite must
  stay green; neither depends on the palette.

## Risks

**Adoption.** 334 downloads, 11 likes, one maintainer, last published 14 months
ago, and the author states roughly 25% of the code was LLM-written. That is a
supply-chain bet on the app's peak interaction. The exit is that the licence
permits vendoring: if it goes stale, copy it in. Worth revisiting if the picker
ever blocks a Flutter upgrade.

**Sheet height.** `CNBottomSheet` is the native iOS 26 sheet; a tall child may
need an explicit detent, which could change the sheet's shape. Verify before
building the layout — it is the one unknown that could move this design.

## Consequences

- All 28 legacy off-palette praises become first-class rather than
  unrepresentable.
- The mockups' praise palette element and the `praise-book` flow must be redrawn:
  a search field, category bar and recents row rather than a 16-tile grid.
- Praise vocabulary is now unbounded, so any future "most-used praise" or
  emoji-grouped feed row has a long tail to handle. Counts stay safe.
