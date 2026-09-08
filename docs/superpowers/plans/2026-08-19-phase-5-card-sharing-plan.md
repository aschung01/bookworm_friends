# Phase 5: sharing the Library Card — Implementation Plan

> **Status: all 7 tasks built** (2026-08-21). Task 7's migration is **applied to the linked database** and
> verified. Three of the four destination slots are built — Stories, Photos, More — and the messenger is
> deliberately absent. What is outstanding needs hardware: **nothing in Task 6 has been run on a device**, and
> two of its three slots cross a platform channel that `flutter test` cannot execute.
>
> Written against the decisions taken in review on 2026-08-19 and the drawings in
> `docs/mockups/library-card-share/index.html` (version `main`; `tile-share` is parked). Each task records
> what the build settled that the plan had not — and where the drawings turned out to be wrong, they were
> corrected in place and say so.
>
> **Revised on 2026-08-20, and the revision is larger than the plan it edits.** This started as twelve
> tasks in three sub-phases, on the premise that the share should carry a link back into the app. It
> should not: the share is the **image and nothing else**, which is what Flighty's own passport does. Its
> destinations hand over a file, and the only thing pointing home is printed _on the card_ — Flighty's
> strip reads `ISSUED28JUN26SFO<<<…FLIGHTY.COM`, and that is a wordmark in the pixels rather than a link
> in a message. Five tasks went with the link; see "Cut, and why". What is left is one client-only
> sub-phase and one additive migration.

> **For agentic workers:** implement task-by-task, in order. Steps use checkbox (`- [ ]`) syntax for
> tracking. Read `.agents/skills/flutter-tester/SKILL.md` before writing any test — this project has
> established Given-When-Then and layer-isolation conventions. Read
> `.agents/skills/supabase/SKILL.md` before writing any migration or storage policy.

> **There is no installed base.** The app was pulled from the store years ago, so no client is in the
> wild and no reader opens it today. Read the 153 profiles as a **dormant migrated corpus**, not as
> users: they constrain the schema and the backfill, and none of them will see a card until they
> reinstall. The flip side is that this phase is not an enhancement to an existing growth loop — but with
> no link and no attribution, it is not a measurable loop either. It is a better object, shared by hand.

**Drawings:** `docs/mockups/library-card-share/index.html` — every screen, flow and element named below
exists there. Verify the page with `node docs/mockups/library-card-share/verify.js` after any change.
**Design:** `docs/superpowers/specs/2026-08-14-library-shell-design.md` — "Library Card", "Bar", "Still open"
**Phase 3:** `docs/superpowers/plans/2026-08-16-phase-3-library-card-plan.md` — read its audit first. This
phase repeats the method and inherits every constraint it recorded.

**Goal:** make the exported Library Card an artifact worth sending. Concretely: the covers become the
card's signature visual, the export is a library checkout card rather than a chart, a `View and share`
screen sits between the tap and the platform, and the card carries its own name in print — no link, no
hosted copy, nothing to serve.

---

## The audit, done first, because it reorders the phase

Every figure below is measured against the migrated corpus or read out of the code, not estimated.

| Measure                                                         | Value                                                                                                         |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Display names printable in a Latin strip (`[A-Za-z0-9_]{3,20}`) | **9 of 153**                                                                                                  |
| Usernames containing a space                                    | **99 of 153**                                                                                                 |
| Usernames containing non-ASCII                                  | **142 of 153**                                                                                                |
| Usernames that are machine-made (`독서하는 <8 hex>`)            | **72 of 153**                                                                                                 |
| `username` schema                                               | `varchar(20) UNIQUE` — already an identity                                                                    |
| Profiles with `is_private = true`                               | **18 of 152 (11.8%)**                                                                                         |
| Finished books carrying a `finish_date`                         | **293 of 293** — the Candlelight reveal is safe                                                               |
| Median finished books per reader                                | **2**                                                                                                         |
| `share_plus`                                                    | 10.1.4 — `text:` exists, `ShareResult` is discarded                                                           |
| `logEvent` calls in `lib/`                                      | **0** — `firebase_analytics` is a dependency and has never been wired                                         |
| Navigation mechanism                                            | named routes only (`AppRoutes`), no `MaterialPageRoute` anywhere                                              |
| Clients in the wild / store listing                             | listing is **live** (`id1643321634`, v1.0.6, 2022-09-24) but two years stale; 2 ratings. See correction below |
| Hosts the app owns                                              | **`libstack.app`** — bought 2026-08-20, on Vercel nameservers, nothing served yet                             |

> **Correction, 2026-08-30.** The row above read "**none** — pulled years ago" until
> Apple's lookup API was actually queried. The listing is live and installable:
> `trackId` 1643321634, `com.unicorn.bookwormFriends`, v1.0.6, last updated 2022-09-24,
> 2 ratings, KR storefront. **The literal claim was wrong; every decision taken on it
> stands.** What the row was being used for was "no installed base worth protecting,"
> and 2 ratings on a binary that predates the Supabase migration is exactly that. Where
> it now matters is elsewhere: the invite landing page's `Get the app` would send a
> stranger to a 2022 build that cannot redeem an invite — see
> `docs/superpowers/specs/2026-08-30-invite-landing-design.md`.

### What the audit forces on the review decisions

**1. "Measure the share" is a first-time integration.** `firebase_analytics` is in `pubspec.yaml` and
`FirebaseAnalytics` appears nowhere in `lib/`. There is no logging layer to add an event to.

**Two other amendments died with the link, on 2026-08-20.** Both were right while a URL was in the design,
and both are recorded because their reasoning will look load-bearing to anyone reading the drawings:

- _Search must match `handle` OR `username`._ Only needed because `poke_user()` was switching to `handle`
  and `username` was losing its uniqueness. Neither happens now; search and poke are untouched.
- _The `cards` bucket has to be public, inverting the avatars precedent._ Only needed because Kakao's SDK
  takes an image **URL** rather than a file. With no link there is no upload, so `is_private` gains no hole
  and the phase's highest-risk task does not exist.

### What the audit does not change

`finish_date` coverage is total, so the Candlelight stamps are real data for every reader. `page_count`
exists since the chassis work but is only 35%-covered, which is why the four extra stats it would feed
live in the parked `tile-share` version and not here.

---

## What this phase changes, stated carefully

|                       | Today (Phase 3)                      | After Phase 5                                                        |
| --------------------- | ------------------------------------ | -------------------------------------------------------------------- |
| Tap share             | spinner → platform sheet             | `View and share` screen, then a destination                          |
| The exported card     | hero + up to 2 tiles, theme-coloured | covers, card stock pinned in both themes, issue block, printed strip |
| Delight               | none                                 | Candlelight, carried by the export                                   |
| Export sizes          | one, 360×450                         | 4:5, plus 9:16 only if the Stories API needs it                      |
| Payload               | PNG + `subject`                      | **PNG, and nothing else** — the return path is printed on it         |
| Identity on the image | `@username`, omitted when null       | `Holder` in the reader's own script; the handle in the strip         |
| Destinations          | whatever the OS offers               | Stories · messenger · Photos · More, messenger by locale             |
| Measurement           | none                                 | `share_opened` / `share_completed`, by surface, format and outcome   |
| New queries           | —                                    | none                                                                 |

**Out of scope, deliberately.** The library bar's own share button (`home_page.dart:_shareLibraryCard`)
is left exactly as it is: that entry point belongs to My Library and is being redesigned separately. One
consequence has to be said out loud because this phase does not fix it — that button reads
`cardFilterYearProvider` whatever tab it is pressed from, so it can export a year nothing on screen
names. Task 3 makes the year visible for shares started on the Card tab and no others.

Also out of scope: the `tile-share` fork, rating entry, and any change to `libraryCardStats`.

---

## Phasing within the phase

**5a — the preview and the artifact (Tasks 1–6).** Client-only: no migration, no host, no bucket, and one
platform channel (Stories) that degrades to an absent slot. Independently shippable, and it is now most of
the phase.

**5b — the strip's identity (Task 7).** `profiles.handle`, the generator, the backfill and an editor. One
additive migration over dormant rows, and the only reason it exists is that a machine-readable zone cannot
print a Korean name. Until it lands the strip omits its identity segment, which is a working state.

**There is no 5c.** Hosting, the landing page, the Kakao template and follow-after-install were cut with
the link — see "Cut, and why" below.

---

## Task 1: the covers on the card, and the precache that makes them exist

**Drawings:** `el-covers`, `el-art`, `card-open`, `sh-nocovers`

**Built.** `lib/ui/widgets/library_card/card_cover_row.dart`, `card_furniture.dart`, the precache seam in
`widget_png_renderer.dart`, two new slots on `StatTile`, and `booksInCardYear` in
`library_card_stats.dart`. 35 tests across three files; the whole suite is unchanged at 487 passing and
the 6 pre-existing failures in `library_read_books_test` / `shell_tab_bar_test`, which fail identically
with the cover row fed an empty list.

- [x] A `CardCoverRow` widget in `lib/ui/widgets/library_card/`, taking `List<Book>` and a target width.
      Sizes inversely to count — larger covers at n≤3 — because the median reader has two books and a
      two-cover row has to read as an object rather than a gap. The drawings' rule: ≤3 → full size,
      ≤6 → medium, else small.
- [x] It renders a real cover when `book.thumbnail` is non-empty and `GeneratedCover` otherwise. Reuse
      both; do not invent a placeholder. `GeneratedCover` sets its title at 13.5% of width — Phase 4
      shipped an illegible 3pt smudge that way, so **assert a minimum width** below which the row draws a
      bare colour block instead.
- [x] **`captureWidgetToPng` gains a precache step, and this is the task's real content.** Covers are
      `NetworkImage` (`book_widget.dart:225`) and `RepaintBoundary.toImage` paints only what is already
      decoded, so a capture without it exports a card with holes. Add a `precache` parameter taking the
      `ImageProvider`s the subtree will draw, `await Future.wait(...)` them before inserting the overlay,
      and document that a caller that draws network images and does not pass them gets a silent hole.
- [x] The hero tile in `LibraryCardBody` gains the card's furniture and the cover row, so the tile
      previews what share produces instead of being a chart.

**Seven things the build settled that the plan had not.**

1. **No new l10n keys, and the furniture is one line rather than two.** The plan said `MY LIBRARY CARD`
   over `도서관 카드 · LIBRARY · CARD` in both ARB files; `cardHero` in the drawings keeps the hero's
   existing localised label (`ALL-TIME LIBRARY CARD`) and adds only the bilingual line under it — three
   "library card"s stacked was the alternative. And that line is **fixed, not localised**, for the reason
   Task 2's Authority line is: it is furniture on a thing that travels. It lives in `card_furniture.dart`,
   which records the argument.
2. **`booksInCardYear` extracted from `libraryCardStats`.** The phase said not to touch that function;
   this is a behaviour-preserving extraction of the year filter it already applied, and it is what stops
   the covers disagreeing with the figure printed above them.
3. **The precache is a public seam with a budget, `precacheAll`.** Split out for the same reason
   `rasterizeBoundary` was — the hosting half cannot be pumped and rasterised in one test — and given a
   5-second `kPrecacheBudget`, because `Future.wait` on a thumbnail whose host went quiet hangs the share
   behind its spinner with nothing to cancel. That failure is worse than one missing cover.
4. **Errors are swallowed in the precache and handled where the cover is drawn.** One dead URL must not
   fail a reader's share, so `precacheAll` ignores errors and the row's `errorBuilder` falls back to the
   same thing an empty thumbnail gets. The precache stops a race; the builder stops a permanent hole.
5. **The minimum width is derived, not typed.** `kGeneratedCoverMinWidth = 7 / _kTitleSizeRatio` lives in
   `generated_cover.dart` beside the ratio it depends on, so the two cannot drift. At the small tier every
   cover is under it, which is why a twelve-book row draws colour blocks and no titles.
6. **The row's width is optional.** The hero cannot know its own inner width — the padding belongs to
   `StatTile` — so the row measures itself with a `LayoutBuilder` when no width is given, and the export
   pins 360 in Task 2.
7. **Twelve covers is a layout limit as well as a taste one, and it is guarded.** `unit = width /
max(106, contentUnits)` makes an overflow impossible rather than unlikely: twelve covers on the widest
   jitter come to 106.4 drawing units against a 106-unit card, and a clipped cover in an exported PNG has
   nothing on screen to explain it.

**Tests**

- [x] `test/card_cover_row_test.dart` — the tier inversion and the step at n=3→4; the 12-cover row inside
      the width it was given; the cap and that the newest cover is leftmost; the generated fallback, its
      absence below the minimum width, and the fallback for a URL that fails; `cardCoverProviders` naming
      one provider per drawn cover and none for a coverless book.
- [x] `test/widget_png_renderer_test.dart` — `precacheAll` returns without a frame on an empty list,
      completes for a decoded image, **waits and then gives up** on one that never decodes, and does not
      fail on a dead URL.
- [x] `test/library_card_body_test.dart` — extended: the hero carries the furniture line and a cover per
      book, a selected year draws only that year's covers, and an empty card has neither.

**Pitfall worth keeping:** `await createTestImage(...)` inside a `testWidgets` body never completes —
decoding is real async work off the fake clock — and it hangs the run with no output rather than failing.
It belongs in `setUp`, which is what `avatar_circle_test.dart` already says at the top of the file and
what cost ten minutes here.

---

## Task 2: the artifact, rebuilt as card stock

**Drawings:** `el-art`, `el-issue`, `el-mrz`, `el-art-thin`, `el-art-candle`

**Built.** `shareable_library_card.dart` rewritten from the drawing's own units, `card_furniture.dart`
extended, `memberSince` threaded from `home_page.dart` through `LibraryCardSheet` to the export, and
Task 1's precache seam given its caller. 38 tests across the artifact and contrast files.

- [x] `ShareableLibraryCard` is rebuilt to the drawn structure: cover well over a perforation, then
      `MY LIBRARY CARD`, the issue block, the stat row, the strip.
- [x] **Pinned to card stock in both themes.** Today it takes `colors.pageBackground`, so a dark-mode
      reader ships a different-looking product. The stock and the Candlelight palette are **new values,
      not theme tokens** — `app_theme.dart` has no cream and no flame, and the artifact is not a screen.
      Put them in the file that draws them, with a comment saying they are deliberately outside the
      theme.
- [x] The issue block prints **Holder / Authority / Date of issue / Member since** — four rows, the same
      count Flighty prints, and every one answerable. Holder is the **display name**, in the reader's own
      script; the handle belongs to the strip. Member since is `profiles.created_at`, already selected by
      every profile read. **Place of issue is not invented** — Flighty has a home airport and this app has
      no home library — and neither is a card number, which Flighty does not print either.
- [x] **Authority prints `책벌레 친구들 · LIBSTACK`, fixed, in both locales.** Not an l10n key. The artifact
      leaves the device and lands in front of people whose locale we do not know, so a card that names the
      product differently depending on who exported it is two products. This is the same argument that
      pinned the stock in both themes, and it is the card's own established grammar — the hero already
      reads `MY LIBRARY CARD` over `도서관 카드 · LIBRARY · CARD`, and a real Korean passport prints
      대한밑국 / REPUBLIC OF KOREA on the data page regardless of who is reading it. The strip stays
      Latin-only for the same reason a Korean passport's machine-readable zone is.
- [x] **The strip has a fit rule, and `libstack.app` sets the numbers.** The drawn strip is 44 monospace
      columns; line two spends 16 on `ISSUED…`, leaving 28 for `host/@handle`. `LIBSTACK.APP/@` is 14, so
      a handle up to 14 characters fits on that line — which covers every generated one
      (`paper_fox_412` is 13) and not a 20-character custom one. So: when `14 + len(handle) > 28`, the
      return path takes **its own full-width line** rather than shrinking the type, because 14 + 20 = 34
      still fits inside 44. Assert both branches; this is the one piece of the artifact whose job is to be
      read by a stranger.
- [x] The stat row is variable-length and every entry has a floor, in the spirit of `kTopAuthorFloor`:
      days and pace need a real span, authors needs ≥3 distinct, shelves needs ≥2. **When nothing clears
      its floor the row is absent rather than empty** — that is the median reader's card, and it must
      still read as a card.
- [x] The strip is sanitised and padded in that order, never the reverse. The drawings hit the HTML
      version of this; in Dart the hazard is slicing by code unit, which is how a line ends up half a
      glyph long, so only `[A-Z0-9_]` reaches the grid and the cut happens after.

**Nine things the build settled that the plan had not.**

1. **The well ended at 46%, after going the wrong way first.** At the drawings' 44% the record wanted
   242pt in a 221pt box — measured, as a `RenderFlex overflowed by 21 pixels` — so the well dropped to 41%.
   Then the link was cut, the invented card number went with it and the strip became always two lines,
   which gave back more than the well had taken: 46%, closer to Flighty's own roughly half. An overflow
   test asserts the spring still has >5pt of slack at the fullest card, because the metrics under the test
   font are not a device's and zero slack would pass in CI and clip on a phone.
2. **The label ink is 70%, not the drawn 55%, and that was a real WCAG failure.** Ink at 55% composited on
   the stock measures **3.3:1**; at 62% it is barely better. These are 10pt labels on an image people scan
   at thumbnail size in a chat list. 70% measures 5.0:1 — the same weight `statTileMutedText` landed on,
   for the same reason. `cardLabelInk()` and `cardStripInk()` exist as functions for the same reason
   `stat_tile.dart`'s do: `withValues` is not a constant expression, and the contrast test needs
   something to import.
3. **The artifact no longer reuses `LibraryCardBody`.** It was a hero tile in a box; it is a checkout card
   now. The export and the sheet share `CardCoverRow` and the furniture strings, and nothing else — so
   `StatTile` no longer appears on the exported card at all, which is what most of the old test file was
   asserting.
4. **Every text style carries an explicit `height`.** For a fixed-size artifact this is correctness, not
   tidiness: without it the line box comes from font metrics, and the card's total height would then
   depend on which font the device resolved.
5. **`LS`, not the drawings' `BF` and `BW`.** The seal and the card-number prefix were drawn before the
   rename; every string file in the app says Libstack now.
6. **There is no card number, and the first version was wrong to invent one.** It derived `LS·4F2C·1204`
   from the holder. Flighty prints no card number either, and a derived one is the same class of fiction as
   the place of issue this deliberately leaves out. Cutting it is also what freed the row `Holder` now
   uses.
7. **`Date of issue` is injectable.** `issuedOn` defaults to now, which is what the row means, and tests
   pass a fixed date rather than asserting against the day the suite runs. The format is forced to `en`,
   so a Korean-locale export prints `AUG` like every other card rather than `8월`.
8. **Authors and shelves are counted in the artifact, not added to `LibraryCardStats`.** The phase leaves
   that function alone, and these two figures exist only on the export — the sheet has no tile for either.
   `cardDistinctAuthors` and `cardDistinctShelves` are pure and tested directly.
9. **The strip is a pure function returning two lines, and the return path is right-aligned.** Flighty
   hangs `FLIGHTY.COM` off the end of its second line, so this does the same with `@LIBSTACK.APP` — which
   also deleted the fit rule an earlier version needed, since without a per-reader path the return path is
   a fixed 13 columns and always fits. It is tested as text rather than pixels: under the test font every
   glyph is one em wide, so a geometry assertion about a 44-column monospace line would be measuring the
   test font.
10. **Two identities, two jobs.** `Holder` prints the _display name_, in the reader's own script, where the
    app's type can set it; the strip prints the _handle_, because a machine-readable zone is Latin-only.
    `cardStripToken` rejects anything that is not already a handle rather than transliterating it — a
    sanitised `독서하는 08269f2d` would print `08269F2D`, which reads as a fault.

**Tests**

- [x] `test/shareable_library_card_test.dart` — rewritten around what the card now draws. Keeps the
      fallback-`DefaultTextStyle` assertion Phase 3 added, and adds its other half: the _only_ monospace
      text on the card is the strip, since monospace everywhere else is what falling back to the error
      style looks like. Plus the stock is identical under `ThemeData.light` and `.dark`; furniture and the
      issue date are unchanged under a Korean locale; the issue block omits Holder, Card no. and Member
      since rather than filling them in; the median reader has no stat row and a full reader has four
      cells; both strip branches; non-ASCII never reaches the grid; and the fullest possible card fits
      with headroom.
- [x] `test/library_card_contrast_test.dart` — extended to the stock palette: ink, labels and the strip on
      cream, the strip held to a higher ratio than the labels because it is the return path, `brandFill`
      on the stock at both themes, and the well readable as a panel against the stock.

---

## Task 3: the `View and share` screen

**Drawings:** `sh-open`, `sh-render`, `card-year`

**Built** (2026-08-21). `lib/ui/pages/share_card_page.dart`, `AppRoutes.shareCard`, five new l10n keys in
both ARBs, and the Card sheet's share button repointed at the route. 10 tests in
`test/share_card_page_test.dart` plus 4 in the contrast file; 551 passing repo-wide.

- [x] A new named route in `AppRoutes` — `shareCard` — because that is how every page in this app is
      reached and there is no `MaterialPageRoute` anywhere in `lib/`. It takes the stats, the year and
      the reader.
- [x] Full-screen presentation: no bar, no well, no tab bar. That is the shell's own rule for a focused
      dismissible context and the stated reason a visit hides the tab bar.
- [x] Chrome: dismiss left, `Your {scope} Library Card` / `View and share` centre, framing toggle right,
      artifact centred, Candlelight under it, destinations along the bottom.
- [x] **The subtitle names the scope**, and that is load-bearing rather than decorative: once the
      presentation covers the year capsules it is the only thing on screen that can say which year is
      about to leave the phone.
- [x] The assembling state is the screen, not a spinner over the sheet: the card builds in place while
      covers precache and the destinations stay inert until the PNG is real.

**Tests**

- [x] `test/share_card_page_test.dart` — the route builds from the sheet's share button; the subtitle
      states the selected year; destinations are disabled while assembling and enabled after; dismissal
      pops without touching the sheet's detent.

**Six things the build settled that the plan had not.**

1. **The two share buttons now do different things, and that is the change with the most reach.** The Card
   sheet's pushes the preview; the library bar's still exports straight to the platform sheet, because that
   entry point belongs to My Library and is out of scope. Both still end at the same `shareLibraryCard`, so
   the _image_ cannot differ between them — only the path to it. The consequence the plan already flagged
   survives unchanged: the bar's button can still export a year nothing on screen names.
2. **The sheet's button drops its `origin`.** The rect exists to anchor the iPad popover to whatever was
   tapped, and by the time the OS sheet opens that is a destination on the pushed screen, not the header
   button. `LibraryCardShareButton` still computes it, because the bar's site still needs it.
3. **`ShareCardArgs` is typed, and it deliberately carries no `LibraryCardStats`.** `/details` and
   `/user_library` both read a `Map<String, dynamic>` and cast field by field, which is how `userId` ends
   up silently defaulting to `''`. More than that: the sheet has a `LibraryCardStats` in hand and passing it
   would be free, but it is derived from `books` and `year` and a second copy is free to disagree with the
   covers drawn beside it. The page derives its own. Same rule as `booksInCardYear`.
4. **The preview had to pin `TextScaler.noScaling` too, and that was not obvious.** `captureWidgetToPng`
   already removes the reader's text scale because the card is a fixed size and clips at 200%. The preview
   is the one screen whose entire job is to show what is about to be sent — so a preview that clips where
   the export does not is worse than no preview. `FittedBox` over a card built at `kShareableCardSize` is
   what makes the two the same object rather than two layouts of the same content.
5. **An indefinite `CircularProgressIndicator` makes `pumpAndSettle` advance the fake clock past the
   precache budget — and that made the assembling assertions pass vacuously.** A frame is always scheduled
   while the spinner is on screen, so `pumpAndSettle` kept pumping until something else stopped it, which
   was `kPrecacheBudget`'s five-second timeout firing. Every test then saw a _ready_ page. The harness
   pumps exactly twice instead. The related trap: `Future.timeout` cancels its timer only when the guarded
   future completes, so any test that leaves the precache pending fails the framework's
   "a Timer is still pending" invariant — which is why the two assembling tests finish by landing the
   covers.
6. **The framing toggle and the Candlelight pill are absent, not disabled.** Both belong to Tasks 4 and 5,
   and the phase's own rule is an absent slot rather than a fake one. The chrome reserves the right-hand
   edge (`_Chrome._edge`) so the title stays centred on the screen when Task 4 fills it. The destination
   row ships **one** slot for the same reason: `More` is the platform sheet, which `share_plus` already
   does; Stories and the messenger need channels that cannot be verified without a device.

**One thing left visibly incomplete, on purpose:** the `_DestinationRow` in `share_card_page.dart` is
private and single-slot. Task 6 extracts it to its own file with the four drawn slots, which is where
`test/destination_row_test.dart` lands.

---

## Task 4: framing, and whether a second pinned size is needed

**Drawings:** `sh-fill`, `sh-float`, `el-art-story`, the `share-frame` flow

**Built** (2026-08-21). `lib/ui/widgets/library_card/card_framing.dart`, the toggle in the chrome, and
`framing:` threaded through `shareLibraryCard`. 8 tests in `test/card_framing_test.dart` plus 4 on the
page. **The answer to the question in the title is no** — there is one pinned size, and the drawings were
corrected to match.

- [x] Two positions, one control: **Fill** bleeds the card to the edge, **Float** insets it on a ground
      taken from the stock. The toggle changes the ground only, never the card.
- [x] **The destination picks the canvas, the toggle picks the ground.** Float at 4:5 is the default;
      Float at 9:16 is what Stories needs, because a 4:5 card cannot fill a 9:16 frame and the ground is
      what makes up the difference. Fill is 4:5 only — bleeding a card to the edge of 9:16 would mean
      stretching or cropping it.
- [x] **Check whether the 9:16 export needs to exist at all before building it.** It does not — see below.
- [x] ~~If it is needed: a second pinned constant beside `kShareableCardSize`~~. Not needed. `framedCardSize`
      is `kShareableCardSize`, and it is a getter rather than a second constant precisely so that a future
      reader looking for the Story size finds the argument instead.

**Tests**

- [x] Whatever constants exist are asserted, and any 9:16 export is asserted to contain the unchanged 4:5
      card rather than a re-laid-out one. (The second half became the _Float_ assertion: the card inside
      the ground is still laid out at `kShareableCardSize` and only scaled.)

**Four things the build settled that the plan had not.**

1. **Float insets the card within a fixed canvas; it does not pad outward from one.** The drawings did the
   latter, which makes the Float image 0.8215 rather than 0.8 — a _different shape_ from Fill for the same
   card. A reader toggling would be handed two differently-proportioned files, and
   `shareable_library_card_test.dart`'s assertion against a size fixed in **both** dimensions would have had
   to become two assertions. Insetting is visually identical at any display scale, because what the eye
   reads is the ratio of card to ground rather than the pixel count. `.artg.float` in the drawings was
   corrected and says so in place.
2. **No 9:16 constant, for two independent reasons.** Framing does not change the canvas (above), and
   Instagram paints the Story ground itself: the hand-off is `stickerImage` plus
   `backgroundTopColor`/`backgroundBottomColor`, which is exactly why Flighty's passport lands centred and
   movable. A 9:16 PNG of ours would fight that. The only destination that could want one is Photos → post
   by hand, which is not a reason to put a second shape of the product into circulation.
3. **The float ground has square corners, and the reason is the file rather than the drawing.** A radius on
   the outermost element of an exported PNG is a _transparent_ corner, and the targets this lands in treat
   alpha differently — a messenger that flattens onto black gets four dark notches. The drawn 4-unit radius
   is the preview sitting on the screen's own ground, which is a different object. A consequence worth
   naming: **Float is the only framing whose exported edge is fully opaque.** Fill inherits the card's own
   3-unit radius, so Fill's corners have been transparent since Task 2 and still are.
4. **The toggle stayed one button rather than becoming two named segments.** Two segments read better and
   need about 72pt; the chrome has 44 and the title is already two lines at accessibility sizes. What a
   single button costs is a screen reader's understanding of the state, so that is carried explicitly: the
   tooltip names the _control_ and the current position is the `Semantics` value, rather than a tooltip that
   describes the tap while the glyph describes the state.

**Also settled:** the default is **Float**, which is what `sh-open` draws — but `shareLibraryCard` defaults
to **Fill**, because the library bar's direct share is out of scope and must keep exporting what it exported
before this task.

---

## Task 5: Candlelight

**Drawings:** `sh-candle`, `el-art-candle`, `el-stamps`, `el-candle`

**Built** (2026-08-21). `lib/ui/widgets/library_card/card_lighting.dart` (the palette),
`shareable_library_card.dart` rewritten to read it, gilt and stamps drawn, and the pill on the page.
12 tests in `test/card_lighting_test.dart`, 4 more contrast groups, 5 more on the page.

- [x] One toggle, and exactly one. Flighty has one; two is a settings panel.
- [x] It is a **flame, not a blacklight**, and the difference is the feature.
- [x] Covers keep their colour rather than washing out; warm light deepens what is there.
- [x] **The gilt and the seal are Task 2's leftovers, and they land here.** Both are now drawn: the gilt as
      a `CustomPainter` at ±62° in two weights, at 7%/4.5% ink in daylight and 32%/20% flame under the
      candle; the seal from 10% opacity to 1.
- [x] **The export carries it.** `lighting:` is threaded through `shareLibraryCard`, and the test that holds
      it rasterises both states and asserts the bytes differ.
- [x] Stamps print the month only at ≤6 covers; past that they degrade to a warm mark.
- [x] **The falloff must not eat the strip.** Solved structurally rather than with a workaround — see below.

**Tests**

- [x] Stamps at n=6 carry dates and at n=12 do not; the strip clears AA in both lighting states; the
      exported bytes differ between the two states (the toggle reaches the file).

**Five things the build settled that the plan had not.**

1. **The falloff moved into the stock, and that is the whole answer to the strip problem.** The drawings
   painted it as an overlay ending in `rgba(0,0,0,.13)` — over the card, therefore over the strip — and
   protected the strip with a `z-index`. That is a workaround for a misplaced effect. Putting the falloff in
   the stock's own gradient (`kCandleStockTop` → `kCandleStockBottom`) puts it **behind** the type: the card
   still darkens toward the bottom edge, and nothing printed on it is dimmed by the light. The bloom painted
   over the card now carries **no dark stop at all**, which is asserted, and the drawings were corrected in
   place.
2. **A `CardPalette` value type, rather than `if (lit)` at forty call sites.** The card had one palette
   hard-coded into the widgets that drew it. Branching in place would have doubled every colour expression in
   the file, and the failure mode of that is one element left in daylight in an image that has already left
   the phone. Daylight is now two identical stock stops and an empty bloom list — one code path paints both
   states, so there is nowhere for a colour to be left behind.
3. **Covers are lit by multiplying, not by overlaying.** `BlendMode.modulate` with the light's own colour is
   literally `cover × light`, which is what a warm point source does to a surface: it darkens and warms while
   keeping the cover's hue. A translucent brown laid on top would flatten them; the CSS's
   `saturate/brightness/sepia` filter chain has no Flutter equivalent worth reconstructing.
4. **The stamp needed `BoxFit.scaleDown`, and it was not optional.** At the six-cover tier a cover is 37pt
   wide in the export, and `MAR` in a bordered plate rotated 11° is close to that before it is rotated.
   Scaling down is what makes a stamp that cannot fit shrink instead of overflowing, and an overflow here is a
   clipped half-glyph in an image that has already left the phone.
5. **`DateFormat` throws until a localisation delegate has run.** `cardStampMonth` forces `en`, like every
   other piece of card furniture — and `intl` raises `LocaleDataException` in a bare test `MaterialApp` with
   no delegates. Harmless in the app, which always has them; it cost a confusing "found 0 widgets with text
   MAR" first.

**Also settled:** the chrome stops being themed when the card is lit. The screen and the card are one scene,
and cool grey chrome around a card in a dim room reads as two images stacked — so `shareChromeGround` and
`shareChromeInk` return pinned values under candlelight, asserted at _both_ themes precisely so that a theme
leaking back in would fail.

---

## Task 6: destinations, the payload, and measurement

**Drawings:** `el-dest`, `sh-more`, `sh-kr`, `sh-private`

**Built, in part** (2026-08-21). `lib/services/analytics.dart` (new),
`lib/ui/widgets/library_card/share_destination_row.dart` (extracted from the page), branded filename,
`ShareResult` captured. 12 tests in `test/destination_row_test.dart`. **Three of the four drawn slots are
not built, and are absent rather than disabled** — see the block below for what each one needs.

- [x] Four slots, ordered by what each is for. **Three built**: Stories, Photos, More.
- [ ] The messenger is **Messages**, replaced by **KakaoTalk** when the device language is Korean.
      **Not built, and the only slot that stays absent.** Android could target KakaoTalk with an explicit
      `ACTION_SEND` to `com.kakao.talk`; iOS cannot target an app from the share sheet at all, so it would
      work on one platform and silently fall back to the same sheet as `More` on the other. iOS would need
      `kakao_flutter_sdk_share`, whose `uploadImage` puts the PNG on **Kakao's** server for up to 100 days —
      which does mean the hosted-URL requirement that cut the public `cards` bucket can be met without a
      bucket of ours, but it is a third-party upload and therefore a decision rather than an implementation.
      Image-attached SMS is covered by no package; iOS needs `MFMessageComposeViewController`.
- [x] **Stories.** Built on `social_story_share` 0.2.2, behind the `shareCardToStory` seam. **Conditional on
      Instagram being installed**, probed once while the covers precache so the slot is either there when the
      reader looks or never — it does not appear under their thumb. `FacebookAppID` and
      `LSApplicationQueriesSchemes: instagram-stories` in `Info.plist`; `com.instagram.android` in the
      Android `<queries>`, declared ours rather than relying on the plugin's manifest merge, because the probe
      runs in our process. **App ID `1623819535975796`**, in source: an App ID is public by design and carries
      no authority — the App _Secret_ is the one that would not belong there, and nothing here needs it.
- [x] **Photos.** Built on `gal` 2.3.3, behind the `saveCardToGallery` seam.
      `NSPhotoLibraryAddUsageDescription` (add-only, a narrower grant than the read permission the profile
      photo picker already has) and `WRITE_EXTERNAL_STORAGE` capped at API 29 — uncapped it is unnecessary from
      API 30 and a Play review question. No `requestLegacyExternalStorage`, which is only needed to save into a
      named album.
- [x] **The payload is the PNG and nothing else: no `text:`, no URL.** `subject` stays for the targets that
      use one.
- [x] Wire `firebase_analytics` **for the first time** and log `share_opened` and `share_completed` with
      surface, format, lighting and outcome. `Share.shareXFiles`'s `ShareResult` is no longer discarded.
- [x] Give the temp file a branded name — `libstack-library-card-2026.png`.

**Tests**

- [x] `test/destination_row_test.dart` — 19 tests. The row is inert while assembling and _present_ rather than
      absent while inert; Stories leads it when installed and is gone when not; the messenger is absent rather
      than faked; each hand-off records the right destination and outcome, including a refused photo
      permission and an Instagram that vanished between the probe and the tap. The Korean/Kakao substitution
      is **not** tested, because the slot it is about is not drawn.
- [ ] Verified on device. **Not done — and this is now the largest untested surface in the phase.** Two of the
      three slots cross a platform channel, and `flutter test` can exercise neither the channel nor the render
      behind it (see the seams below). Everything asserted about Stories and Photos is asserted about the
      _request_, not the result.

**Four things the build settled that the plan had not.**

1. **The analytics seam is an interface with a swappable global, not `FirebaseAnalytics.instance` at the call
   site.** The latter makes every widget test that touches a logged interaction depend on Firebase being
   initialised, and there is no Firebase under `flutter test`. Same shape as `coverImageProvider` and
   `avatarImageProvider`, which the project already uses for exactly this reason. The production sink
   **swallows its own errors**: a share that works and is not counted is a worse dashboard, a share that fails
   because it could not be counted is a worse product.
2. **`share_opened` fires when a destination is pressed, not when the screen opens.** Opening `View and share`
   is not an intent to send anything — the entire point of the screen is that a reader can look and change
   their mind — so counting it as the top of the funnel would make the screen look like it _reduces_ shares
   by construction.
3. **A `surface` parameter, which the plan listed but did not justify.** The two entry points are now
   genuinely different experiences, one showing the reader the image first and one not, and this parameter is
   the only thing that can answer whether that matters. Without it the phase's central bet is unfalsifiable.
4. **The filename is year-scoped, not one fixed string.** The plan's `libstack-library-card-2026.png` implies
   the year is in it; a single fixed name would then be wrong for all-time, and two shares in flight would
   overwrite each other while both were still in a chat's upload queue. `cardShareFileName(0)` drops the year
   rather than printing a `0`.

**Three more things the build settled, all of them about testability.**

5. **The render needed a seam of its own (`exportCardFile`), and the symptom was a hang rather than a
   failure.** `captureWidgetToPng` waits on two real frames and then `toImage`, and PNG encoding only runs
   inside `runAsync` — from which a test cannot pump. A widget test that taps a destination and lets the real
   exporter run does not fail, it _hangs_. Faking it also sharpened the assertions: a test now reads the
   `CardExportRequest` and checks that Stories asked for **Fill**, rather than inferring it from pixels.
6. **`EasyLoading` breaks `pumpAndSettle` twice over, in two different ways.** Its spinner is indefinite, so a
   frame is always scheduled and `pumpAndSettle` runs to its own ten-minute timeout; and `showSuccess` /
   `showError` leave a **2-second** dismissal timer, which the framework treats as a failure if the test ends
   first. So hand-off tests pump a fixed number of short frames _and then past two seconds_ — the first
   version of the helper did only the former and passed the three silent paths while failing the three that
   report to the reader.
7. **A test caught a real bug: a throwing probe stranded the screen on the assembling state.** `Future.wait`
   rejects as soon as either side does, so the `setState` that ends assembly never ran. The two callees
   happened to swallow their own errors, which made the promise "this always finishes" true by luck rather
   than by construction. It is now enforced in `_assemble`, where it is made.

**A correction about how the first pass reached "blocked", because it is the more useful lesson.** Three slots
were called blocked from memory, without searching the ecosystem, and two of those calls were wrong. What
made them _sound_ right is that each had a real technical obstacle attached — `share_plus` genuinely cannot
target a named app, Stories genuinely needs a channel — so the conclusion arrived with evidence for the wrong
claim. **The rule that would have caught it: a dependency claim about a moving ecosystem is not a memory
question.** Corrected on 2026-08-21 after searching, prompted by a screenshot of Flighty's own Stories share.

**Where the messenger actually stands, which is the one that survives scrutiny.** Android can target
KakaoTalk with an explicit `ACTION_SEND` to `com.kakao.talk`. iOS cannot target an app from the share sheet
at all — no public API — so it needs `kakao_flutter_sdk_share`. And that turns up something that revisits a
cut decision: `ShareClient.uploadImage(imagePath:)` uploads the **local file to Kakao's own server** (5MB cap,
retained 100 days) and returns the URL for the template. The "hosted image URL" requirement that removed the
public `cards` bucket, the domain and the `is_private` hole from this phase can therefore be met by **Kakao
hosting it rather than us** — nothing of ours is uploaded and no bucket returns. The cost that does return is
narrower and needs a decision: the PNG leaves the device to a third party for up to 100 days. Kakao's own docs
also note that for plain files without a message template, the OS share sheet is the supported route.

Image-attached **SMS** is the one thing no package covers: they all offer SMS with prefilled _text_. iOS would
need `MFMessageComposeViewController`.

**What a device session still has to do**, now that the slots exist. **The Stories path was run on a real
device on 2026-08-22 and works**, which closes item 3 outright and most of item 1:

1. **Stories.** **Confirmed on iOS**: the probe answers true with Instagram installed — the slot appears —
   the hand-off reaches the composer, and the **App ID `1623819535975796` is accepted** rather than producing
   "The app you shared from doesn't currently support sharing to Stories". That last one was the single
   assumption behind putting the ID in source, and it held. **Two things a working send does not
   distinguish, so they stay open**: whether the card lands as a _sticker_ centred on the ground Instagram
   paints rather than full-bleed, and whether a _lit_ card arrives on the dark ground rather than the
   daylight green. The second needs the Candlelight pill pressed _before_ sharing, which a first attempt
   would not have done. Android untested.
2. **Photos**, including a _refused_ permission, which is a normal answer and must read as one.
3. ~~**`social_story_share` at all.**~~ **Closed** (2026-08-22). It ran. It was 0.2.2 from an unverified
   uploader with 2 likes and the only dependency in this app that had never executed once — the largest
   single risk in the phase, and it is now spent. The seam in `card_destinations.dart` stays, because it is
   also what the tests stub, but the fallback plan behind it is no longer on the table.
4. **Open an actual exported file** in both lighting states, both framings, on a phone in Korean and in
   English. That is the check that catches what `Member sin…` and `Pace, per bo…` cost, and no widget test
   can perform it. **Still the largest untested surface in the phase**, and now the only one of these four
   that has had no device contact at all.

---

## Task 7: `profiles.handle`, the Latin identity the strip needs

**Why this exists, restated — the original reason was wrong.** The first version of this plan justified a
handle by URL-safety: `username` cannot be a URL. Nothing in this phase is a URL any more. The real and
narrower reason is the strip: a machine-readable zone is **Latin-only**.

**And the numbers are now measured rather than remembered.** Queried against the live database on
2026-08-21, over **136** profiles (the plan said 153, from an older snapshot):

|                                        | count           |
| -------------------------------------- | --------------- |
| profiles                               | 136             |
| `username` containing non-ASCII        | **126** (92.6%) |
| `username` containing a space          | 90              |
| `username` already `^[a-z0-9_]{3,20}$` | **2**           |

Two. So without this column the strip has no identity segment for 134 of 136 readers, and `cardStripToken`
rejects rather than converts — sanitising `독서하는 08269f2d` would print `08269F2D`, which reads as a
rendering fault.

**What this does not do.** `username` is not demoted, keeps its unique index, and stays the key for
`poke_user()` and user search.

**Built** (2026-08-21). `supabase/migrations/20260821100303_add_profile_handle.sql`,
`supabase/tests/handle_test.sql`, `lib/models/handle.dart`, `Profile.handle`,
`UpdateProfileNotifier.updateHandle`, an editor in `settings_page.dart`, eight new l10n keys, and `handle:`
wired through both share paths. 12 tests in `test/profile_handle_test.dart`.

- [x] Migration adding the column with a format check matching exactly what `cardStripToken` accepts.
      **`citext` was dropped** — see below.
- [x] **A generated handle for all 136 migrated readers, and no prompt.**
- [x] **The generator produces something pronounceable** — 24 adjectives × 24 nouns × 3 digits, word lists in
      the migration. Verified against the real corpus: 136 rows, 136 distinct handles, 0 nulls, all 136
      name-shaped, lengths 13–17.
- [x] New signups get one at creation, through `handle_new_user`.
- [x] `Profile` gains `handle`. No query changes — every profile read is a bare `select()`.
- [x] An editor in `settings_page.dart` beside the display name, with a taken/invalid state.
- [x] Wire it through: `home_page.dart` and `LibraryCardSheet` pass `handle:` to `shareLibraryCard`.

**Tests**

- [x] `supabase/tests/handle_test.sql` — six assertion groups, and it was **proved to fail**: run without the
      migration it raises on the missing column, and with a deliberately broken assertion it raises on
      `olive_quill_924`. Both halves ran against the linked database inside a rolled-back transaction.
- [x] One test that the SQL check and `cardStripToken` agree. It reads the migration **off disk** and asserts
      the pattern string, rather than trusting a comment to stay true.

**Five things the build settled that the plan had not.**

1. **`citext` is unnecessary, and the plan's reason for it was self-defeating.** It was there so `@PaperFox`
   and `@paperfox` could not both exist — but the format check forbids `@PaperFox` from existing _at all_, so
   citext would guard against a value the column cannot hold. `text` plus a lowercase-only check gives one
   canonical representation, which is a stronger invariant than two that compare equal, and it costs no
   extension.
2. **The backfill has to loop.** `UPDATE profiles SET handle = generate_handle()` evaluates the function per
   row but the function cannot see the handles the _same statement_ is assigning, so two rows in one statement
   can collide. A row-at-a-time `DO` block makes each call see the previous one's result.
3. **`generate_handle()` is SECURITY DEFINER _and_ has EXECUTE revoked from `anon` and `authenticated`.** The
   collision check has to see every row and RLS would hide private strangers' handles from an invoker-rights
   version — but Postgres grants EXECUTE to PUBLIC on every new function, so a definer function is exposed as
   an RPC by default. That is the trap the Supabase security checklist names, it is easy to forget, impossible
   to notice, and now asserted by `has_function_privilege` in the SQL test. `search_path` is pinned empty in
   both functions; `handle_new_user` had it unset since 2026-05, which this fixes in passing.
4. **A third copy of the rule turned up, and it is looser on purpose.** `cardStripToken` accepts
   `[A-Za-z0-9_]` because it uppercases for the strip, while the column accepts only lowercase. That is safe
   _exactly as long as case is the only thing it is loose about_, which is now its own assertion — anything the
   strip will print must be a handle the column could store once lower-cased.
5. **The editor drops rather than transliterates, and needs a `HandleProblem` enum to say why.** A field with
   four ways to be wrong cannot report "invalid", and a Korean name run through a converter comes out as a
   remnant that reads as a fault — an empty field at least says "choose something". Length is _reported_, never
   enforced in the field: a text field that silently stops accepting characters is indistinguishable from a
   broken keyboard.

**Applied** (2026-08-21, `supabase db push --linked`). `supabase migration list --linked` shows
`20260821100303` on both sides, and the state was checked rather than assumed:

| check                                                     | result                                         |
| --------------------------------------------------------- | ---------------------------------------------- |
| `supabase/tests/handle_test.sql`                          | silent — all six groups pass                   |
| rows / distinct handles / nulls / bad format              | 136 / 136 / 0 / 0                              |
| name-shaped (`^[a-z]+_[a-z]+_[0-9]{3}$`)                  | 136 of 136, lengths 13–17                      |
| `profiles_handle_format`                                  | `CHECK ((handle ~ '^[a-z0-9_]{3,20}$'::text))` |
| `profiles_handle_key`                                     | unique btree on `(handle)`                     |
| `handle` NOT NULL                                         | true                                           |
| `generate_handle()` reachable by `anon` / `authenticated` | false / false                                  |
| `on_auth_user_created` still attached                     | yes                                            |

**The signup path was proved end to end rather than inferred from the trigger definition.** A real
`auth.users` insert inside a rolled-back transaction produced a profile carrying `rusty_usher_008` and a null
`username` — which is the correct pair: a new reader has a handle before they have chosen a display name, so
`needsOnboarding` still routes them to pick one and no share is ever gated on setting a handle. The probe left
nothing behind (0 rows matching it afterwards, 136 profiles, 0 nulls).

---

## Cut, and why — what used to be Tasks 8 to 12

**Cut on 2026-08-20, when the share turned out to be image-only.** Recorded rather than deleted, because
each was argued for at length and the arguments were sound _given a link_.

- **Task 8, switching what looks a reader up.** `poke_user()` resolving `handle` and search matching either
  column existed because `username` was going to lose its uniqueness. It does not. Nothing changes.
- **Task 9, the public `cards` bucket and its privacy guard.** This was the phase's highest-risk task: a
  public bucket inverting the profile-photos decision, an INSERT policy refusing private uploaders, and a
  trigger deleting objects on flip to private. All of it existed because **Kakao's share SDK takes a hosted
  image URL**. With no link, Kakao is a local file hand-off like the other three destinations, nothing is
  uploaded, and `is_private` has no new hole to guard.
- **Task 10, the landing page.** No link to land. `libstack.app` stops being load-bearing here; the
  Instagram account is the live destination and the strip prints `@LIBSTACK.APP`, which is both.
- **Task 11, the KakaoTalk slot** as a _template_ share. It survives only as an ordinary OS destination,
  which is Task 6.
- **Task 12, follow after install.** Nothing to deep-link, so the `app_links`/PKCE hazard `main.dart`
  records stays untouched — which is the best outcome available for it.

**The cost, stated plainly.** There is now **no attribution and no measurable loop**: a card that lands in
a group chat and produces an install is invisible to us. Task 6's analytics can say a share happened and
where it went, and nothing after that. That is the accepted price of an artifact that does not nag, and it
means the phase's success criterion is the card itself rather than a funnel.

---

## Risks

**The precache is the bug most likely to ship.** A cover that failed to decode paints nothing and the
export leaves the phone with a hole in it. Invisible on screen, invisible to a widget test that asserts
strings and geometry, and only visible by opening the file — exactly like the yellow underline Phase 3
caught. Task 1 pins it, with a budget so a stalled thumbnail cannot hang the share instead; Task 6's device
verification is the backstop.

**The fixed height is now the tightest thing on the card.** Task 2 measured the record's worst case at 21pt
over its box before the well gave ground, and the test that holds it measures the _test font_. Anything
Task 4 or Task 5 adds to the body has to be checked against the fullest card, not the median one.

**Stories is the only platform-channel work left, and it is conditional.** The pasteboard plus
`instagram-stories://share` has no precedent in this repo, and the slot must be absent when Instagram is
missing rather than present and dead — which is exactly what Flighty's own row does. It degrades to an
absent slot, so it blocks no release.

**Generated handles are the public identity on almost every card.** Every new signup gets one and most never
open the editor, so the generator's output is what strangers read in the strip. `paper_fox_412` reads like a
choice; `reader_4f2c1204` does not.

**No attribution, by construction.** See above. The risk is not technical: it is that in three months
somebody asks whether sharing works and there is no number to answer with.

---

## Open questions

**Settled in review on 2026-08-19, and revised on 2026-08-20**, recorded here so the plan is readable
without the drawings:

- **The share is the image and nothing else.** No `text:`, no URL, no hosted copy, no landing page — which
  is what Flighty does. The return path is _printed_ on the card instead, right-aligned on the strip's
  second line, because a caption does not survive a screenshot and pixels do. This reversed the plan's
  original goal and cut five tasks.
- **`@LIBSTACK.APP`, printed once.** Flighty prints `@FLIGHTY` and `FLIGHTY.COM`, two strings for two
  places; ours would be the same string twice. The handle form wins the legible slot, because with no
  landing page the domain reaches nothing while the Instagram account is live.
- **The export carries Candlelight.** Cost accepted: a lit card is slightly harder for a stranger to read
  as a library card. Rejected: screen-only, and destination-aware.
- **No card number, and no place of issue.** Flighty prints neither. A derived number is the same class of
  fiction as an invented home library.
- **`handle` exists for the strip, not for a URL**, generated and backfilled rather than prompted,
  pronounceable rather than hex — with `username` keeping its uniqueness, its lookup jobs, and its place on
  the card as `Holder`.
- **The `poke_user` window is a non-issue** twice over: there are no clients in the wild, and the RPC no
  longer changes at all.
- **`main` ships; `tile-share` is parked** — six tiles need 92% of the screen, which is the whole library
  gone on a shell whose first axiom is that the library is always the background.

**Still open:**

- **Which promise leads.** `책벌레 친구들` promises friends; `Libstack` promises a collection. Answered as
  "the stack" for the brand; the artifact follows it, and nothing in the remaining tasks blocks on it.
- ~~**Whether the 9:16 export needs to exist.**~~ **Answered: no.** Task 4 settled it in the build — one
  pinned size, `framedCardSize == kShareableCardSize`, and framing changes the ground rather than the canvas.
  The real API has now been exercised on a device and did not ask for a second size, which is the confirmation
  Task 4 could only assume.

---

## Revisions after the phase was built (2026-08-22)

Three changes from looking at the screen on a real device rather than at a drawing. Each overturns something
a task above records as settled, so they are recorded here rather than edited into those tasks silently.

**The chrome's two controls are native Liquid Glass** (`Task 3`). They were plain `IconButton`s; they are now
`AdaptiveIconButton`, the widget the scanner, Add Book and Manage Shelves already use. This screen was simply
the one place that had not adopted the house control. `AdaptiveIconButton` grew an optional `iconColor` to
make it possible: this chrome inverts its ground under Candlelight, and a glyph left to the Material default
there is near-black ink on a near-black ground. It is carried on `CNSymbol(color:)` rather than
`CNButton.tint`, because `tint` stains the glass disc instead of the mark on it.

The SF Symbol names were checked against the **iOS 26.5 simulator runtime's own `symbol_order.plist`**, not
recalled: `xmark`, `inset.filled.rectangle.portrait` for Float, `rectangle.portrait.fill` for Fill.
`rectangle.inset.filled` — the name memory reaches for first — is **absent** from that catalog, and a symbol
name that does not exist is discarded silently, leaving an empty glass circle. Under `flutter test` the target
platform reports Android, so the glass rendering never runs and no test can ever see this; the strings are
therefore pinned by assertion so a rename has to go back to the catalog.

**The screen is a full-screen cover, not a page sheet** (`Task 3`, which recorded it as a route in the
`AppRoutes.routes` table). It was first rebuilt on `CupertinoSheetRoute`, which rises from the bottom and
looked like the more native answer. It is the wrong native answer: a `CupertinoSheetRoute` is
`UIModalPresentationPageSheet`, and on iOS 18+ that presentation scales the page behind it down into the
stacked-card effect — so the card read as a panel belonging to a shrunken app. Flighty's Passport share, which
this screen is modelled on, is `.fullScreen` with `.coverVertical`: it covers everything and leaves the app
underneath perfectly still. `shareCard` therefore leaves the `routes` table for `AppRoutes.onGenerateRoute`,
which returns `CupertinoPageRoute(fullscreenDialog: true)`.

`fullscreenDialog` is what buys the _stillness_, not just the direction: both
`CupertinoRouteTransitionMixin.canTransitionFrom` and `MaterialRouteTransitionMixin.canTransitionTo` test the
incoming route for it and refuse to animate the outgoing one. Two independent gates, which is what neutralises
`CupertinoPageRoute` reporting a non-null `delegatedTransition` even for a fullscreen dialog — an
inconsistency with `_PageBasedCupertinoPageRoute`, which does gate it. `CupertinoPageRoute` rather than
`MaterialPageRoute(fullscreenDialog: true)` because the Material route takes its transition from the ambient
`PageTransitionsTheme`, and `ZoomPageTransitionsBuilder` — the Android default, and this app sets no theme of
its own — never consults `fullscreenDialog` at all.

The drag handle the sheet version drew went with it. A full-screen cover is not drag-dismissible on iOS, so
keeping the affordance would advertise a gesture that no longer exists; the ✕ is the only way out, as in
Flighty.

**The destination tiles were flush** (`Task 6`). Three fixed 56pt squares in a `Row` with no spacing, so the
only thing between two of them was the pair of rounded corners where they met and the row read as one
segmented control. Now `Row(spacing: kShareDestinationGap)`, the gap set equal to the tile's corner radius so
the negative space reads at the scale of the curve that forms it.

Worth knowing for any future assertion about this row: `Row.spacing` separates _slots_, and a slot is as wide
as the wider of its tile and its label. Under `flutter test` the label always wins — the font is Ahem, where
every glyph is one em, so `Stories` measures about 80pt against a 56pt tile. A first version of the test
measured the _tile_ gap and read 36.4 instead of 16. The gap between slots is asserted exactly; the gap
between tiles is asserted as a floor, which is also the honest design claim: a label wider than its tile
pushes neighbours further apart, never closer. Clamping the label would buy even gaps at the price of an
ellipsis on `Stories`, and silent ellipsis is the failure this phase has already been bitten by.

**How these were verified.** A throwaway harness at `tool/verify_share_card.dart`, built with
`flutter build ios --simulator -t …`, installed with `simctl install`, and screenshotted with `simctl io`. Two
tricks made it work where reasoning could not: `timeDilation = 10` to slow the 0.33s cover transition enough
for `simctl` to catch it mid-flight, and a hard grid with a border flush to the screen edge and solid corner
markers on the page underneath — flat colour would have hidden a scale-down, the border and corners cannot.
`instagramInstalledProbe` was stubbed true so the row could be judged with all three slots on a simulator that
has no Instagram. The harness was deleted afterwards; it is worth rebuilding rather than keeping, since it is
twenty lines and always specific to the question being asked.
