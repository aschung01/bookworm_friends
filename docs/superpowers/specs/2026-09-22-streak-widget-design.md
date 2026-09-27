# A streak on the home screen, and the evening state it needs first

Give the reader an iOS home-screen widget carrying the run, the book they are in, and
whether tonight is still open — and, because a widget must not say something no in-app
surface says, build the evening state in the app first.

Two phases, separately shippable:

1. **The late state**, in the app. Pure Dart, no native work, no new dependency.
2. **The widget.** A WidgetKit target, an App Group, a snapshot contract, SwiftUI.

Bundling them would put "does the page read right at 21:30" behind provisioning-profile
work, so they ship in that order.

**Amended 2026-09-26, after the mockup round, and every amendment below is a reversal rather
than an addition.** Phase 1 shipped as specced, and a widget target drawing `systemSmall` and
`systemMedium` exists on this branch — the version this file first described, jacket and all,
with the deep links and the week row still outstanding. `docs/mockups/streak-widget/` then put the tile through a character, a colour ladder and
four copy voices, and three rules written here — that the late state must not read as a scold,
that it must not be a second warm hue, and that it states the deadline rather than the threat —
turned out to have been written for a tile with nothing on it. Each is corrected in place, with
the reasoning that lost kept rather than deleted, and the design that replaces them is recorded
in **The ladder, as chosen** at the end of phase 2. The mockup sheet asked for exactly this:
_"either the spec is amended in writing or this version is a rejected experiment — what it must
not become is a selector someone picks without noticing."_

## The problem this closes

The streak mechanic is built — `reading_days`, `currentStreakProvider`,
`ReadingStreakChip`, `ReadingStreakPage`, the month calendar, the celebration — and it
has **no reach outside the app**. `flutter_local_notifications` is in `pubspec.yaml` and
schedules nothing; it only renders foreground FCM pushes. So the feature can encourage
only a reader who has already opened the app, which is the reader who least needs
encouraging.

A home-screen widget is the one surface that can raise its hand without permission
prompts, without a server, and without the reader launching anything.

## The state the app is missing, and why the widget cannot supply it alone

`docs/superpowers/specs/2026-09-12-reading-streaks-design.md` specced four states — green
recorded, grey open, **amber late**, blue freeze. Two shipped. Freezes are deferred; the
evening warning (`sc-risk`) was never built. The deadline is carried entirely by copy:

| state    | copy                                             |
| -------- | ------------------------------------------------ |
| open     | "A page is enough. Today counts until midnight." |
| recorded | "Today is recorded."                             |

A widget-only escalation was considered and **rejected**: the home screen and the library
bar would then disagree about how worried to be on the same evening, and the widget is the
one surface that cannot be hotfixed, because readers see a cached timeline. So the app
gains the state and the widget inherits it.

## Phase 1 — the late state

### The hour is a named constant, beside the rollover

```dart
const int kReadingDayWarningHour = 21; // lib/models/reading_date.dart
```

21:00, giving a three-hour window against the midnight rollover. 20:00 was the
alternative and gives four; 21:00 wins on evenings having settled by then.

Named for the reason `kReadingDayRolloverHour` is named, which that file already states:
the hour in the arithmetic and the hour in the copy must be one number. Phase 2 puts it in
the snapshot rather than letting Swift hold a fourth copy.

**The three-hour window is a consequence of the midnight rollover and is accepted.** At
the former 4am rollover a 21:00 warning gave seven hours. The warning is now more
genuinely urgent and correspondingly more able to read as a scold, which is why the copy
below names the deadline and does not count down.

**Half of that conclusion is withdrawn, 2026-09-26.** _No countdown_ survives and was never in
doubt: the mockup round cut its `countdown` voice on the voice's own evidence, because "19 hours
left" at dawn reads as reassurance rather than as pressure. _Must not read as a scold_ does not
survive. It was reasoning about a tile that drew a grey flame and a number, where a hard line is
the only pressure available and therefore the only thing that can go wrong; the widget the round
produced carries a character and a coloured ground, so the pressure is spread across three
channels and the words are the smallest of them. The instruction that settled it was explicit
that a copy rule wide enough to forbid a scold was costing more in ideation than it bought in
tone — the chosen ladder scolds twice on purpose, and this section is no longer what the widget's
copy is held to.

### A phase, not a second bool

`readTodayProvider` answers one question about the day; _late_ is a different question
about the same day, and threading two booleans through three surfaces is how they come to
disagree. So a pure function beside `readingDate`, with `now` a parameter and no clock
inside it — the rule `reading_date.dart` already argues for at length:

```dart
enum ReadingDayPhase { recorded, open, late }

ReadingDayPhase readingDayPhase(DateTime now, Set<DateTime> days);
```

### The clock is the real engineering problem

Every existing streak provider derives from a `Set` and needs no wall clock, so **nothing
in this app currently rebuilds because time passed.** A page that changes its line at
21:00 does.

The design is **one `Timer` to the next boundary** — 21:00, then midnight — rescheduled when
it fires. Deliberately not a periodic ticker: at most two wakes a day, and a per-second
rebuild of a surface that changes twice is the kind of cost that shows up as battery in a
review.

A timer alone is insufficient, because a suspended app's timer does not fire on schedule.
So the phase also recomputes on `AppLifecycleState.resumed`. There is **no app-level
lifecycle observer today** — `lib/ui/pages/scan_book_page.dart` has the only
`WidgetsBindingObserver` in the codebase — so phase 1 adds one. It is the same hook phase
2 needs for writing the snapshot on pause, which is why it is built as a proper observer
rather than inlined into a page.

**The timer lives in `MyApp`, not in the provider, and that is a correction made during
implementation.** The first cut put it inside `readingDayPhaseProvider`, which reads well:
the provider that depends on the clock owns the clock. It broke **seventeen existing streak
page tests at once**, none of them about time. `testWidgets` fails any test that ends with a
timer pending, and a `ProviderContainer` disposed through `addTearDown` is torn down _after_
that check runs — so `ref.onDispose(timer.cancel)` was correct and still too late.

The lesson is not about test plumbing. A provider that spawns a timer is a provider every
widget test has to know about, whether or not the test cares about the clock. So the split
is: **the provider answers what phase it is; the shell owns when to ask again.** That leaves
`readingDayPhaseProvider` a pure function of the map and the current moment, which is what
every other value in `reading_days_provider.dart` already is, and puts the one long-lived
timer in the one object that is already long-lived.

The practical test of the split: the page's suite needs no knowledge of timers, and the two
cases that pin a particular hour do it by overriding a plain derived provider with a value.

### Not amber, and the hex that decides it

The spec's amber was authored when the recorded state was **green**, so amber was plainly
a different fact. It no longer is. `ReadingStreakChip` and `ReadingStreakPage` were moved
onto `kCandleFlame` so that one generated silhouette would not be "rust in the library bar
and amber one tap later on the streak page":

```
kCandleFlame       #F2A93F   card_lighting.dart:30 — one value, both themes
AppColors.flame    #B54708 light / #FF922B dark    — superseded for the mark
```

**The recorded state is already amber.** A warning rendered in amber would be the same
hue as the thing it warns about, in both themes. A state whose entire job is to be noticed
cannot be one shade off the state it is warning you about. So whatever carries _late_, it
is not a second warm hue.

**Superseded 2026-09-26: the requirement is right and "not a second warm hue" was a proxy for
it.** The requirement is the middle sentence — _a state whose entire job is to be noticed cannot
be one shade off the state it is warning you about_ — and a hue prohibition is a guess at when
that happens rather than a measurement of it. The chosen ground ladder warms all the way into a
deep red by 23:00, which breaks the letter of the rule, and cannot be confused with recorded at
any hour, because recorded is a pale candle cream. Measured at the **worst pairing** — the
lightest stop of the open ground against the darkest stop of the recorded one, so nothing is
flattered by comparing midpoints:

| tier      | open ground, lightest stop | vs recorded's darkest (`kCandleGlow` #FFE8C4) |
| --------- | -------------------------- | --------------------------------------------- |
| dawn      | `#55688A`                  | 4.71:1                                        |
| morning   | `#525DA0`                  | 5.13:1                                        |
| afternoon | `#6A4FA0`                  | 5.43:1                                        |
| evening   | `#83438A`                  | 5.61:1                                        |
| late      | `#9C3459`                  | 5.77:1                                        |
| final     | `#A02128`                  | 6.41:1                                        |

So the rule is restated as the thing it was for: **late must not be confusable with recorded,
measured rather than asserted.** That is a better rule on two counts — it is checkable in a test,
and it survives the palette moving, where a hue prohibition has to be re-argued every time the
ground does. Note the direction of the ladder, too: it is not "recorded is the bright one".
Recorded is the only _quiet_ tile, which works at every hour instead of collapsing on whichever
hours the open ground happens to be pale.

**What has not changed: the flame is amber only when the night is in.** `kCandleFlame` is still
the one thing on the tile that means recorded — `RunAndFlame` in `StreakWidget.swift` draws two
tints and never three — and the ladder colours the _ground behind it_, which is a different
object. The `sc-risk` rule in `2026-09-12-reading-streaks-design.md` is amended there too, and
only for the widget.

### Which surfaces carry it, and the chip is not one of them

| surface              | late state                                                |
| -------------------- | --------------------------------------------------------- |
| `ReadingStreakChip`  | **unchanged — two states**                                |
| `ReadingStreakPage`  | `streakTodayLate`, plus the today-token's dashed ring     |
| the widget (phase 2) | the week row's dashed today cell, plus the same copy line |

**The chip is deliberately left alone, and that reverses this design's own first draft.**
The first version of this section gave the chip a dashed pill outline when late, reasoning
from the shipped `main` chip, which kept a 1.5pt border alive in both states with
transparent colours so the tap target could not shift. That chip no longer exists. This
branch deleted the box outright — _"There is no box, in either state… the instruction is
Duolingo's own bar, where the streak counter is a mark and a numeral on the bar's own
ground and the hue is the entire state."_

It was removed twice, for two separate reasons, and both of them rule a dash out:

1. The **cold** outline went first, because "a pill here is a fourth chrome control in a
   row of three real buttons" — the density toggle, the shelves button, the avatar. A
   dashed pill on the late state re-introduces exactly that, on the evenings the reader
   has not read, which is most evenings.
2. The **hot** pill went on instruction, leaving hue as the whole state. A box on the one
   state that is neither cold nor recorded is incoherent with that.

There is also a concrete regression in it. The chip's padding is now `16.5 × 14.5`,
collapsed from `8 + 7 + 1.5` and `11 + 2 + 1.5` so that removing the pill moved nothing
else in the bar. `Container` folds a border's width into its effective padding _only when a
border is present_, so a border returning in one state moves the reader's tap target by 3pt
depending on whether they have read yet — the precise bug that comment exists to record.

And the chip is the surface least able to take a third state anyway: `#F2A93F` against
`secondaryText` measures **2.75:1 in light and 1.5:1 in dark**, where hue is doing all of
the work and `Semantics` is the only other channel. Loading a third state onto it asks the
most of the readout that can bear the least.

**A lit core was the alternative and is recorded, not taken.** `StreakFlameMark` accepts a
`coreColor`, so a grey flame with a warm core (`#FFD479`, already the artboard's pair)
would read as _catching, not yet lit_ — no box, no new token, no geometry change. It stays
available if the page alone proves too quiet. It was declined for now because at 19.5pt it
is a subtlety that can only be judged on device, and because the page and the widget
together already say the thing.

### What the page draws

**Correction, after the fact: the page draws none of this, and the widget is the only surface
that carries the late state.** It shipped as specced — an italic line under the hero choosing
between `streakTodayOpen` and `streakTodayLate` — and was withdrawn on instruction along with
the `", and today is open"` the hero's label carried, because between the flame's tint, the week
row's last cell and the presence of the record button the page already said whether tonight was
in three times over. Both strings survive in `app_en.arb` / `app_ko.arb` for the widget, which
has none of those three and so needs words. `readingDayPhaseProvider` is still what the page
watches, but it now reads `recorded` only. The rest of this section is the reasoning as it
stood.

`ReadingStreakPage`'s today-token already dashes, because it draws through
`read_week_row.dart` — `_kTodayEdgeWidth = 2`, "the dashed ring around an unrecorded today…
the ring is the only mark on that token, so it has to carry the affordance alone." The app
already says _today, not yet_ with a dash, so the late state inherits a vocabulary rather
than inventing one, and the widget inherits it in turn.

What the page needs is the phase and one string:

```
streakTodayLate: "Nearly midnight. A page is enough."
```

It names the deadline without counting one down, which is the line `sc-risk` drew —
"it states the deadline rather than the threat."

**That gloss is withdrawn with the rule, 2026-09-26, and the string is not.** "States the
deadline rather than the threat" was `sc-risk`'s line, and the chosen ladder's 21:00 line is
"Midnight approaches. So do I." — which states the deadline _and_ the threat in one sentence, on
purpose. `streakTodayOpen` / `streakTodayLate` stay exactly as written in both ARBs, because they
are the app's own voice and the app is not on the ladder. What changed is that **the widget no
longer prints them.** They were kept for the widget's sake after the page withdrew them; the
widget now draws a tier line instead, so those two are what it falls back to when a snapshot
predates the ladder — see the snapshot section below, where that fallback is the reason `v` does
not have to move.

**No dash painter is extracted.** An earlier draft moved it out of `read_week_row.dart` so
the chip could share it. With the chip untouched, the page's token is still the only Dart
caller and the widget's is Swift, so there is nothing to share and the refactor is dropped.

## Phase 2 — the widget

### The extension is read-only and never touches the network

No Supabase client, no auth session, no keys. `reading_days` is owner-only RLS and there
is no session in an extension to satisfy it; a timeline provider doing network I/O is also
the classic way a widget goes blank. It reads a snapshot the app wrote into a shared App
Group container.

**No Flutter engine in the extension**, either — pure SwiftUI. Widgets get roughly a 30MB
budget, and none of this needs Dart at render time.

### The snapshot

```json
{
  "v": 1,
  "writtenAt": "2026-09-22T21:04:00Z",
  "rolloverHour": 0,
  "warningHour": 21,
  "lastReadDay": "2026-09-22",
  "streak": 12,
  "longestStreak": 31,
  "book": {
    "id": "…",
    "title": "…",
    "author": "…",
    "coverColor": "#8A5A2B",
    "progress": 0.41
  },
  "copy": {
    "dayStreak": "day streak",
    "todayOpen": "A page is enough. Today counts until midnight.",
    "todayLate": "Nearly midnight. A page is enough.",
    "todayDone": "Today is recorded.",
    "nothingYet": "Record a night and it starts here."
  },
  "lines": {
    "dawn": "Keep it going!",
    "morning": "Your book's waiting!",
    "afternoon": "Anything yet?",
    "evening": "You said you'd read.",
    "late": "Midnight approaches. So do I.",
    "final": "This is how it ends?",
    "none": "Start a streak!"
  }
}
```

**`copy` is how the ladder is localized, and it is already the established rule here rather than
a new one.** Every string the widget prints is written by the app, translated, count-free and
passed through — the alternative is a second copy of translated strings in an extension that
cannot read `AppLocalizations`, kept in step by discipline, and translated copy kept in step by
discipline is copy that drifts. `lines` extends that to the seven ladder lines and costs the
extension nothing: Swift picks by tier, never formats, and never holds a sentence.

**`v` stays at 1, and that is this file's own rule being used rather than bent.** The version
bumps when a field _changes meaning_, not when one is added; the Swift decoder treats unknown
keys as absent, so an installed widget reading a snapshot with `lines` ignores it, and a new
widget reading a snapshot without `lines` falls back to `copy.todayOpen` / `.todayLate`. The
ladder is therefore shippable without a coordinated release, which is the property `v` exists to
protect.

**The extension derives `recorded / open / late` itself, from `lastReadDay` and the
entry's own date. The app never writes a state flag.** This is the single rule the
correctness of the whole feature rests on: an entry generated at 22:00 must still be right
at 00:05 when the day has turned. Had the app written `"phase": "late"`, the widget would
insist it is late at 9am the following morning.

**The tier is derived the same way, from the entry's hour, and for the same reason.** A written
tier would be a second baked-in phase with a shorter shelf life — six of them a day rather than
two. `lines` is a map, never a chosen sentence.

`rolloverHour` and `warningHour` ride along for the same reason rather than being
hardcoded in Swift — phase 1's constants stay the one source, and the drift
`kReadingDayRolloverHour` exists to prevent cannot reappear across a language boundary.

`streak` is the run **ending at `lastReadDay`**, which lets Swift mirror
`currentStreakProvider`'s rule in three cases:

| `lastReadDay` | state       | shows                                        |
| ------------- | ----------- | -------------------------------------------- |
| today         | recorded    | `streak`                                     |
| yesterday     | open / late | `streak` — a run ending yesterday is current |
| older         | broken      | 0, with `longestStreak` as the record        |

That third row is the argument for building this at all: **the widget is most correct
when the app is least used.** A reader four days lapsed is exactly who the nudge is for
and exactly who is not opening the app, and the widget still tells them the truth with no
network, no push and no background refresh.

The broken state follows `sc-broken`: the figure shown is the record, not a zero, and
there is no red and no guilt copy.

### Timeline

Three entries — `now`, today's `warningHour` if still ahead, next midnight — with a
`.after(nextMidnight)` policy. No refresh-budget pressure and no per-hour entries.

A countdown was rejected in the same breath: it needs an entry per hour, burns the refresh
budget iOS grants, visibly stalls when that budget is spent, and converts a deadline into
a threat.

**Corrected 2026-09-26: three entries becomes one entry per hour of the waking day, and the
reason the countdown was expensive was not the entry count.** Entries inside a single timeline
are free — the system renders them at their own dates without waking the extension — and the
budget iOS meters is **reloads**, i.e. calls to `getTimeline`. A minute-resolution countdown needs
continuous reloads and is expensive for that reason; a ground that interpolates per hour and a
line that steps at six tier boundaries is one timeline, generated at the same two moments as
before. The policy is unchanged. What the ladder does add is that a phone which never gets a
refresh window now has ~17 pre-rendered entries to walk through rather than 3, which makes the
offline case _better_ rather than worse.

**Midnight is also why this is cheap.** A 4am rollover would have meant the extension
carrying its own shifted-calendar arithmetic and disagreeing with every system date it
displayed. At midnight the boundary is `Calendar.startOfDay` and the OS agrees.

### Writing it

A `StreakWidgetSnapshot` service — one file, one job — writing on:

- `readingDaysProvider` settling with a value
- `setRead` succeeding, in either direction
- the reading book, or its progress, changing
- `AppLifecycleState.paused`, through phase 1's observer
- **sign-out, which clears it** — otherwise a shared device shows a stranger's streak

Then `WidgetCenter.shared.reloadAllTimelines()`.

**A small MethodChannel rather than the `home_widget` package.** Only two things need
native code: write a string to `UserDefaults(suiteName:)`, and reload timelines.
`home_widget`'s real value is launch-URL plumbing, and `app_links: ^7.2.1` is already a
dependency with `InviteLinkService` already consuming the incoming-link stream. Its
Android half would be dead weight in a `pubspec.yaml` whose comments show each dependency
argued for individually.

### Families and taps

- **systemSmall** — cover, flame, count. One `widgetUrl`, opening the book.
- **systemMedium** — cover, title and author, progress, count, and the week row in phase
  1's vocabulary. Two `Link`s: the cover opens the book, the flame and count open
  `ReadingStreakPage`.

Both deep-link over the existing `bookworm-friends` scheme into `AppRoutes`.

**The cover opens the book, and that is the whole point of the chosen shape.** A bare
number at 21:30 tells the reader what they are about to lose; a specific book they are 41%
through tells them what to do about it. It is `sc-risk`'s own rule — "it offers the act,
not the anxiety."

`systemLarge`, lock-screen accessories and StandBy are out of scope.

**Amended 2026-09-26: small loses the jacket, and losing it is what pays for everything else on
it.** The shipped small draws a 30×44 jacket, the flame, the run, the label and the title, and has
no room left for a line — so `open` and `late` are the same drawing, which is the one thing phase
1 existed to fix. The mockup's `streak-only` step made the trade and the rest of the round built
on it. Where the two families now stand — neither set of taps is wired yet:

| family           | draws                                                                              | taps                                                    |
| ---------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------- |
| **systemSmall**  | the ground, the cat, the flame and run washed over it, the tier's line. No jacket. | one `widgetUrl` → the book                              |
| **systemMedium** | four corners — run top-left, copy top-right, book along the floor, cat opposite    | two `Link`s → the book, and the flame/run → streak page |

So the division of labour is stated rather than implied: **small answers _where is my run_, medium
answers _what am I reading_.**

**Amended 2026-09-26: medium is four corners, not two columns — book bottom-left, copy
top-right.** The version that shipped first put the jacket in a column of its own at the far left
with the run, title, author, progress and line stacked beside it. It cost twice over. The line
inherited small's _52% of the column_ cap, but the column started a jacket and a 12pt gap in from
the left, so the copy came out **76pt** wide — narrower on the 338pt tile than on the 158pt one it
was supposed to have more room than. And a jacket at the left margin with everything else to its
right reads as a sidebar rather than as part of the tile.

Anchored to the corners the copy gets **133pt, 1.74×**, and the jacket, title, author and progress
sit along the floor as one object. The run row goes back to small's 28 and 40 from the two-column
version's 24 and 34, because there is no longer a jacket beside it to make room for.

**What it costs is the cat, and that is the one real trade.** At 70% of the tile its head reaches
the copy's own corner, and the copy is the only thing on the tile that cannot be sat behind — so it
comes down to **62%**, which puts its crown at 72.7pt against three lines of copy ending near
57pt. The character is therefore smaller on medium than on any other tile. The copy is
right-aligned because it hugs the right edge; flipping it to leading is one line. The recorded tile
leaves the top-right corner empty, because `recorded` has no line in any locale.

The two-column version is still drawn on `docs/mockups/streak-widget/final.html`, under the heading
that says it lost, because it is the arrangement the four-corner one is an argument against.

**Small's tap still opens the book, with nothing on the tile depicting one, and that is the cost
to record.** The argument above — a specific book at 41% tells the reader what to do about it —
was the _jacket's_ argument, and the jacket is gone from that family. The destination does not
change, because the act has not changed; what carries the invitation is now the line and the
character. If the round is wrong about that, the symptom will be small taps that land in a book
the reader did not expect, and the fix is the jacket returning as a corner detail rather than the
line going away.

`systemLarge`, lock-screen accessories and StandBy remain out of scope.

### Drawing, and not making a fourth flame

**The flame comes from the existing generator.** `rive/streak_flame/icon.py` already emits
`--svg` from the same geometry as `StreakFlameMark`'s painter and the Rive artboard; it
gains a Swift `Path` emitter. One silhouette across Dart, Rive and SwiftUI, with nothing
to keep in step by hand — which is the failure `StreakFlameMark`'s doc comment was written
to end, and re-introducing it in a third language would undo that work.

**The cover is drawn from `coverColor`, not the real jacket.** `books.cover_color` is
already stored and the app already draws covers and spines from it. Reaching into
`cached_network_image_ce`'s on-disk cache layout would couple the widget to package
internals that move on a version bump.

Real jackets **were** a documented follow-up with a clean route, and that route is now taken — see
_Real jackets, as built_ below. The paragraph above stands as the reasoning for v1's placeholder,
which is still what the tile falls back to.

**Amended 2026-09-27: the jacket needs a 1pt edge, and a device found it because the review page
was only ever shown a flattering cover.** `cover_color` is _sampled from the real jacket_, so for
the very many books whose cover is white paper it comes back near-white — `#FDFDFB` for
«월급쟁이 부자로 은퇴하라» on the device this was caught on — and a near-white rectangle on the recorded
tile's cream ground is invisible. It read as a cover that had **failed to load**, which is the worst
way for a placeholder to be wrong: the reader cannot tell a working one from a broken image. The
`ground.div` fallback for a null `cover_color` is fainter still, being a divider token.

This is the trap `AGENTS.md` records for `kStatTileCool` and `stampMark`, one level out — a colour
chosen for one role promises nothing about its lightness, and this one was sampled to _tint_ a
generated cover rather than to be the whole of one. The fix is a `strokeBorder` in the **ground's
own ink at 28%**, not a fixed dark hairline, which would vanish on the 23:00 tile. And the page now
draws every medium section twice, with `#8A5A2B` and with `#FDFDFB`: it could always have shown
this and simply had not been given the input, which is its own lesson about proof sheets that only
carry the happy case.

### Real jackets, as built (2026-09-27)

**The widget draws the actual cover now, and the colour stayed as the fallback.** That fallback is
the entire reason this shipped without a `v` bump or a coordinated release, so do not remove it:
it is what the tile draws on the first render after a book change, for a reader who was offline
when that happened, and for any cover URL that 404s.

| where                                      | what                                                                                            |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| `lib/services/streak_cover_thumbnail.dart` | fetch, decode at **120px wide**, re-encode PNG. Every failure returns null and none throws      |
| `lib/ui/widgets/streak_widget_sync.dart`   | fires it after the snapshot, deduplicated on the **cover URL** rather than on snapshot equality |
| `lib/models/streak_widget_snapshot.dart`   | `coverFileName(bookId)` → `cover-<id>.png`, carried in the payload as `book.coverFile`          |
| `ios/Runner/AppDelegate.swift`             | `writeCover`, name validation, prune-to-one, atomic write; `clear` deletes the directory        |
| `ios/StreakWidget/StreakSnapshot.swift`    | `StreakWidgetCovers.url(for:)`, resolving the same `covers/` path the app writes                |
| `ios/StreakWidget/StreakWidget.swift`      | `Jacket` loads it with `UIImage(contentsOfFile:)`, `.fill` and a crop                           |

Seven decisions worth not re-deriving:

- **It re-fetches rather than reading the app's own decode.** Threading bytes out of
  `cover_sample.dart` is free and permanently entangles the widget-sync path with the
  shelf-rendering path — two features with no reason to change together, where a change to how
  shelves decode could break the widget. One request per book change buys that separation.
- **The filename is named in Dart and only resolved in Swift.** Same rule as `rolloverHour`
  travelling in the payload: the extension holds no copy of a convention that lives in Dart.
- **Keyed on the book id, not one fixed `cover.png`.** A fixed name shows the _previous_ book's
  jacket under the next book's title for however long the fetch takes — a wrong picture that looks
  like a right one.
- **The snapshot is written first and the cover second, deliberately.** Reversing it would make a
  recorded night wait on a download. Two timeline reloads on a book change is affordable precisely
  because `write` is deduplicated per snapshot; the refresh budget is spent by per-rebuild reloads.
- **A file, not `UserDefaults`.** The PNG measures 46KB in practice; a property list is read whole
  by both processes on every snapshot read.
- **120px is sized for the extension, not for the source.** A WidgetKit extension is killed rather
  than degraded when it misses its memory budget, so a publisher's 2000px artwork is a crash and
  not a slow tile. Only the width is pinned — the height stays proportional, because jackets are
  not one ratio and the crop is the widget's decision, where the frame is known.
- **The name is validated natively even though Dart derives it from a Postgres UUID.** This is the
  one place in the app where a database value becomes a filesystem path, and a whitelist is used
  rather than a search for `..` and `/`, because the set of characters a filesystem treats
  specially is longer than it looks.

**`clear()` deletes the jacket too, and that raised the stakes rather than added a chore.** A hex
rectangle leaked the _fact_ of a book; a cover image leaks _which_ book, legibly, to anyone who
glances at a shared device's home screen — outside the `reading_days` RLS that protects it
everywhere else.

**The hairline is kept over the real cover as well.** The book this was built against is a Korean
paperback whose artwork sits in the middle of a white field, which is why `cover_color` sampled
`#FDFDFB` in the first place: a photographed white jacket is as invisible on cream as a white
rectangle is. The spine drops to 9% over a real cover, though — at the placeholder's 18% it reads
as a black stripe painted across the artwork rather than as a spine.

**Verified end to end on a simulator**: `covers/cover-373bec95-…-2bf0.png`, 46KB, **120 × 174**,
under exactly the name the snapshot's `coverFile` carries. What is _not_ yet verified is the tile
drawing it — see the note on this machine having no `Simulator.app`.

### The bookmark, as built (2026-09-27)

**The tile draws the library's own ribbon over the jacket**, slid in from the fore-edge by
`progress` — `BookmarkRibbon` and `ReadingBookmarkTrack` in `StreakWidget.swift`, ported from
`assets/icons/bookmarkIcon.svg` and `lib/ui/widgets/book/reading_bookmark.dart`. That makes one mark
reading one position at **three** sizes: the shelf at `scale: 1`, the Library Card, and now a 58pt
cover in a widget. The reasoning for the track — why the mark slides rather than lengthens, why it is
read and never dragged, why a null position pins rather than zeroes — lives in the Dart file and is
deliberately not repeated in Swift.

**Parametric rather than generated, which is the opposite call from the flame.** `StreakFlameGeometry`
is emitted by `icon.py` because an organic curve has no description shorter than its control points;
this silhouette is a rectangle with a notch and two rounded corners, so five named numbers say what
sixty coordinates would obscure. They are held in the **asset's own units** precisely so the guard
needs no arithmetic: `test/streak_widget_palette_test.dart` parses `static let unit*` back out of the
Swift and asserts they still match the SVG and the Dart constants — the same mechanism the palette
uses, and the drift it catches is the shelf's ribbon being retuned while the widget's stays put.

**The guard compares the two placements' output, not only their constants.** Flutter positions the
asset's 22-wide box and Swift draws only the 13.5-wide visible ribbon, so the two insets are measured
from different edges; an off-by-the-bleed would misplace the mark at every position while every
constant above still matched. The case walks `null`, 0, 0.25, 0.41 and 1 and compares the ribbon's
left edge.

**It draws for a book with no recorded position** — which the tile's own `ProgressBar` does not, and
the two are consistent rather than in conflict: a bar at zero is a claim about how far in the reader
is, where the ribbon at its pin is the absence of one. The track's own rule says the mark only ever
moves _in_ from where readers already know it.

Two placement details worth keeping: it is drawn **outside the jacket's clip** ("a bookmark a clip
swallows is not a bookmark") and **above the edge hairline**, since a bookmark sits on top of a book
rather than under its outline. And its **shadow is load-bearing** — a white ribbon on a white cover is
the pale-cover problem one object down, and SwiftUI's `.shadow` follows the shape's alpha so the notch
is respected without the hand-blurred copy the Flutter side needs.

**Colours** live in an extension asset catalog mirroring `kCandleFlame` and the neutrals,
guarded by a Dart test that reads the catalog JSON and asserts the hexes still equal the
Dart constants. The same habit as the existing `expect(kReadingDayRolloverHour, 0)`.

**Added 2026-09-26: the character, which is the one genuinely new asset class in the feature.**
Eight poses, named and stable, because a choice has to be nameable rather than describable:
`m01-flex`, `m03-reading`, `m05-puddle`, `m06-snooze`, `m07-drowsy`, `m12-panic`, `m13-blush`,
`m15-smug`. They ship as PNG cut-outs in the extension's own asset catalog, seated on the tile's
bottom edge and cropped — the reference's arrangement, where the mascot's feet are never drawn,
and a crop is free in both CSS and SwiftUI.

Four measured facts from the round, each of which cost a render to find:

- **The cat is bounded by height, never width.** Aspect ratios across the set run 0.74 to 1.31, so
  a width rule produces a different height per expression; a 76%-wide cat is 143px tall in a 158px
  tile and reaches the figure however far down it is pushed.
- **On a tile with a line, the cat is right-aligned and the line is capped at 52% of the width.**
  This is what makes `m05-puddle` usable at all: at 145px wide it overlapped the copy column by
  59.5px where every other cut-out stays under 10px, and Sheet B's gloss still says the puddle
  "appears nowhere but `done`". Side by side rather than stacked lifts that exclusion — verified by
  looking at `_chosen_puddle.png`, where the two-line copy sits clear of the cat's left edge — and
  the chosen ladder spends it on the afternoon.
- **The fur is a neutral grey, and the ground was rebuilt around that rather than the reverse.**
  The first ground ladder was a saturated purple-to-red arc at mid lightness, drawn so a _green_
  cat could sit opposite it; against a grey cat the four fur candidates scored 2.0–3.9:1, because
  saturated magenta and pink occupy the same value band a grey cat does. Being colourful was never
  the problem — being colourful at the cat's own lightness was. Every hour of the ladder is now
  dark, the same four furs score 5.9–8.3:1, and the character is the light thing in a lit room at
  every hour.
- **The flame and the run are washed back to 50% over a coloured ground, at full strength on the
  recorded one.** The character is meant to be the brightest thing on an unrecorded tile; on the
  recorded tile there is nothing competing and nothing left to ask for.

**The unlit core is knocked out to the tile, not drawn in grey.** Shipped, it is `secondaryText`
over the same grey at 55%, which has no internal contrast — so the notch and the low fat core that
make this _our_ flame disappear and it reads as a teardrop. Cutting the core through to the ground
behind is the app's own vocabulary: `docs/mockups/empty-states/PROMPTS.md` records that details
inside a shape are knocked out rather than drawn on top.

**The figure's face is not settled, and the mockup's is a trial.** The sheet sets it in Nunito
ExtraBold with tabular figures, which is most of what makes the reference's tiles read as friendly
rather than as a dashboard, and it is **not a face this app ships** — adding it means a font in the
extension's bundle and an OFL notice. Pretendard ExtraBold (what `AppTextStyles.displayStreak`
sets) and the shipped System SF rounded are the two alternatives, and the Type axis of the matrix
is where they are compared. Whichever wins, tabular figures are not optional: without them the
figure's width changes with the run and the tile twitches on the night it goes from 9 to 10.

### Empty states

No snapshot, or signed out, draws an **invitation** — never a blank, never a bare zero.
This inverts the Library Card's omit-rather-than-zero-fill rule for the reason
`ReadingStreakChip` already inverted it: a widget the reader deliberately placed must
never look broken. A missing reading book against a live streak degrades to the
streak-only layout, the way `LibraryCardStats.hasPace` omits its tile.

**The ladder must never reach this state, and that is the sharpest rule the round produced.** The
escalation is a function of _an unrecorded day inside a live run_, not of the absence of a run. Of
137 profiles in production exactly one has a reading day, so a deep red tile here would be
shouting at people for not having started — which is the one first impression nothing recovers
from. `none` draws the dawn ground at every hour, a sleeping cat and "Start a streak!", and
`broken` follows `sc-broken`: the figure is the record, not a zero, and there is no red and no
guilt copy.

(The chosen-ladder sheet renders `D-none` on the 21:00 rose. That is the sheet laying eight cards
out in a row, not a decision about the state; the rule above is the decision.)

### Release-process risk, which is the real cost

Adding an App Group entitlement to **Runner** changes its capabilities, so its
provisioning profile must be reissued. `release_ios.sh` passes the ASC key with
`-allowProvisioningUpdates`, so cloud managed signing should mint both it and the new
target's profile without a local distribution certificate — but per `AGENTS.md` this is
the fragile part of the pipeline, and this keychain has no usable Apple Distribution
identity to fall back on.

**So step one of phase 2 is a throwaway archive proving the entitlement signs**, before
any Swift is written. The extension gets no pods and must not be added to the Podfile's
`Runner` target.

## The ladder, as chosen

Added 2026-09-26. The review sheet is `docs/mockups/streak-widget/index.html`; the submitted pick
is `_submissions/latest.json` and `_chosen.html` renders it in the order a day runs through it.

The design is **the reference's construction with our objects**: one ground per time of day,
deepening and warming toward the deadline; the cat seated on the bottom edge and cropped; the
flame and the run washed back over it; and one line whose _voice_ changes with the hour.

| tier         | from  | ground at its anchor  | pose        | voice     | line                          |
| ------------ | ----- | --------------------- | ----------- | --------- | ----------------------------- |
| dawn         | 00:00 | `#55688A` → `#3A4760` | m01-flex    | duoLike   | Keep it going!                |
| morning      | 10:00 | `#525DA0` → `#363E6E` | m03-reading | duoLike   | Your book's waiting!          |
| afternoon    | 14:00 | `#6A4FA0` → `#46356E` | m05-puddle  | desperate | Anything yet?                 |
| evening      | 18:00 | `#83438A` → `#572C5C` | m06-snooze  | guilt     | You said you'd read.          |
| late         | 21:00 | `#9C3459` → `#68203A` | m07-drowsy  | unhinged  | Midnight approaches. So do I. |
| final        | 23:00 | `#A02128` → `#5E0F14` | m12-panic   | guilt     | This is how it ends?          |
| **none**     | —     | dawn's, at every hour | m06-snooze  | duoLike   | Start a streak!               |
| **recorded** | —     | `#FFFDF8` → `#FFE8C4` | m13-blush   | —         | none                          |

**`dawn` starts at the rollover and not at 05:00, and the 05:00 the mockup labels it with is
nominal.** `StreakTier.forHour` has no 05:00 test at all: every hour below the first real boundary
falls through to dawn, which the sheet's own `tierAt` does too. That is deliberate rather than
leftover — a reader awake at 03:00 is either very late or very early, and neither of them wants the
23:00 voice, so the gentlest line in the set is the safe end to clamp to. `final.html` prints the
spans a tier really owns for this reason.

**The hours are two ladders on purpose.** The copy and the pose step at the tier boundaries in the
`from` column; the ground _interpolates_ between anchors at 07:00, 11:00, 14:00, 18:00, 21:00 and
23:00 — the hexes above, clamped to the first anchor before 07:00 — so it travels continuously
while the sentence holds. A ground that stepped with the copy would announce six times a day that
something changed; a sentence that changed with the ground would be re-readable seventeen times and
worn out by the third.

**Six lines from four voices, mixed, and the mixture is the decision rather than a failure to
make one.** `duoLike` → `duoLike` → `desperate` → `guilt` → `unhinged` → `guilt`. A single set
read front to back is a register, and a register is exactly what wears out: the round's own
complaint about the compliant voice was that at 23:00 on an unrecorded day it is still only
cheerful. Picking per hour buys an arc no one set contains — cheerful while there is time, first
person once there is not, relational at the hours a reader has actually broken a promise to
themselves. The instruction was explicit that a copy rule narrow enough to forbid that mixture
was not worth the tone it protected.

**`final` is `G-final-2`, not the `G-final` that was submitted, and this is the one line changed
after the fact.** The submitted pick was "Don't leave it like this." Read against the 21:00 tile
the two hours contradict each other: at 21:00 the cat is calm and half-lidded and the line is a
threat — the cat holds the power, and the threat lands _because_ it is unbothered — and at 23:00,
the last hour before the run dies, the cat is panicking with its paws up and asking for a favour.
The face escalates while the words retreat, so the two channels disagree at the one hour they most
need to agree. "This is how it ends?" keeps the guilt voice and the relational pressure and makes
it a verdict rather than a request, which the panic pose can carry.

Two alternatives are recorded rather than dropped, because neither is wrong:

- **Let `unhinged` close the day** (`U-final-1` "You. Book. Now."). Monotonic escalation, which is
  the reference's own choice, and the cat stays in charge through midnight.
- **Keep the submitted plea.** A cat that menaces at 21:00 and is sincerely upset at 23:00 is a
  _character_; one that escalates monotonically is a pressure machine. The reference can be a jerk
  because its mascot has ten years of earned affection, and ours has none — so the softer ending
  may simply be the more likeable one, and likeable buys retention too.

**Recorded has no line, in any voice, deliberately.** The reference's own recorded tiles carry a
figure and nothing else: the lit flame already says the thing, and a sentence under it would be the
tile explaining its own drawing — the same defect that withdrew the page's italic line.

### The Korean is written, not translated

| tier      | English                       | Korean                          |
| --------- | ----------------------------- | ------------------------------- |
| dawn      | Keep it going!                | 오늘도 독서!                    |
| morning   | Your book's waiting!          | 책이 기다려요!                  |
| afternoon | Anything yet?                 | 아직인가요..?                   |
| evening   | You said you'd read.          | 읽기로 했잖아요.                |
| late      | Midnight approaches. So do I. | 곧 자정인데, 책은 언제 펴려나.. |
| final     | This is how it ends?          | 이렇게 끝내요?                  |
| none      | Start a streak!               | 책 읽기 좋은 날이에요!          |

**Korean is the binding constraint on length, not English.** The copy column is 52% of a 158pt
tile: about 15 Latin characters a line, but only about **7 full-width syllables**. That is why the
line box allows **three** lines rather than the sheet's two — `곧 자정인데, 책은 언제 펴려나..` is 14
syllables and would otherwise be truncated in the one locale nobody reviews by eye.

Four of the seven are not translations of the line above them, and the differences are the
interesting part:

- **`evening` uses `-잖아요`**, which means _as you and I both know_. That is guilt's mechanism
  stated in grammar rather than in words, and English has no ending that does it.
- **`late` is a soliloquy, not an address** — the cat wondering aloud when the book will be opened.
  The English threatens the reader directly; the Korean is creepier for not bothering to. A third
  register the sheet never offered, and it arrived from the reader rather than from the ladder.
- **`final` picks 끝내요 over 끝나요**, i.e. _you_ are ending it rather than _it_ ends. The English is
  ambiguous on purpose and Korean cannot be, so the verdict points at somebody.
- **`none` drops the instruction entirely** — "it's a good day for reading" where the English says
  "start a streak". Consistent with that state's own rule: nothing has been failed there, so
  nothing should be asked.

The app speaks 해요제 everywhere else and every line here stays inside it, including the menace.
That is a decision rather than an accident: 반말 would make the cat a peer and 21:00 genuinely
hostile, where politeness plus a threat is the register the reference's own Korean owl uses.

**The one cost that is not a trade-off: the ground hues are invented and off-palette.** The app's
surface is cream and these are jewel tones; nothing in `card_lighting.dart` contains them. The
round built and measured two alternatives that stay inside the codebase — `dusk` (darker, more
restrained) and `ember` (warming into the candle darks instead of into red) — and both pass their
contrast checks, so swapping is one edit to the anchors if the jewel tones prove to be somebody
else's app.

## Decomposition

| step   | scope                                                                    |
| ------ | ------------------------------------------------------------------------ |
| **1**  | The late state: constant, phase, timer, observer, page copy              |
| **2a** | Entitlement proof, target, MethodChannel, snapshot, `systemSmall`        |
| **2b** | `systemMedium`, the week row, the two `Link`s                            |
| **2c** | Real jackets, lock-screen accessory — only if wanted                     |
| **2d** | The ladder: `lines`, the ground ramp, the cut-outs, the knocked-out core |

Step 1 ships alone and is worth shipping alone. **2d is mostly a change to code that already
exists**: step 1 and the whole of 2a are implemented on this branch, so the ladder is a snapshot
field, an asset catalog, and a rewrite of two SwiftUI view builders. The deep links and the week
row in 2b are still outstanding, and the week row is now the one item the ladder may make
redundant — it was small's alternative to a status line, and small now has both a line and a
character.

### 2d, as built

| where                                                  | what                                                                                                                                  |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/l10n/app_en.arb`, `app_ko.arb`                    | seven `streakWidgetLine*` keys, with the register notes on each                                                                       |
| `lib/models/streak_widget_snapshot.dart`               | `StreakWidgetLines`, `lines` in the payload, `v` unmoved                                                                              |
| `lib/ui/widgets/streak_widget_sync.dart`               | the ladder localized and passed through                                                                                               |
| `ios/StreakWidget/StreakSnapshot.swift`                | `StreakTier`, the 5/10/14/18/21/23 boundaries, `line(at:)` and its fallback                                                           |
| `ios/StreakWidget/StreakWidget.swift`                  | `StreakGroundRamp`, the `groundVars` port, the cat, the sticker figure, hourly entries, small without a jacket, medium's four corners |
| `ios/StreakWidget/Assets.xcassets`                     | eight imagesets at 1x/2x/3x, resampled **by height** — the puddle is wider than tall, so a long-edge resize would have drawn it short |
| `ios/StreakWidget/Nunito-ExtraBold.ttf` + `Info.plist` | the figure's face, 2.7KB, with `UIAppFonts`                                                                                           |
| `test/streak_widget_snapshot_test.dart`                | the wire keys, the `final`-not-`last` key, no `recorded` line, the ladder in equality                                                 |
| `test/streak_widget_palette_test.dart`                 | the contrast rule, and that no-run states stay pinned to dawn                                                                         |
| `docs/mockups/streak-widget/final.html`                | every state, both locales, at real tile sizes — generated by `scripts/render_final_widget.py`                                         |

**The review page reads the shipped sources and nothing else**, which is what separates it from the
three sheets beside it: the copy comes out of the ARBs, the ramp and the poses out of the Swift, the
tier hours out of `StreakSnapshot.swift`, the cut-outs are the extension's own asset catalog at 3x,
and the flame is printed by `icon.py --svg`. So a tile that is wrong there is wrong in the app, and
a decision that drifts out of the code drifts off the page with it. `--check` asserts the ground
recipe round-trips, every pose has a 3x asset, and no Korean line overflows the three-line box.

**Rendering it immediately caught three things, which is the argument for having it.** The page drew
a `0` on the no-run tile where the Swift deliberately draws no figure at all; it labelled dawn
"from 05:00" when the code clamps everything below 10:00 to it; and it broke `읽기로 했잖아요.` between
syllables, because CSS breaks CJK anywhere and CoreText does not — a defect in the page that would
have been read as a defect in the app. `word-break: keep-all` fixes the third.

**The ground recipe was ported numerically rather than by eye**: the Swift reproduces all six of
`_chosen.html`'s tiles' `--tile`/`--ink`/`--dim`/`--div`, the three mesh blob colours and the 158°
stops exactly. Three approximations are forced by SwiftUI and are recorded in the file —
`RadialGradient` is circular so each CSS ellipse is a squashed circle, a base fill sits under the
mesh because SwiftUI paints nothing outside a gradient's frame, and the `feTurbulence` grain layer
is dropped. The `dim` floor loop never fires on this ramp (every hour clears 3.46:1), which matches
the sheet's "no band declared" note; it is kept because `dusk` and `ember` would need it.

**`letter-spacing: -0.5px` on the figure is dropped**, because `.tracking()` is iOS 16 and this
target's floor is 15. And the sticker numeral is twelve offset copies of the glyph behind a white
fill, because SwiftUI cannot stroke `Text` and a WidgetKit extension cannot host a
`UIViewRepresentable`.

### Two defects the page could not see, so measure the device

The tile rendered on a simulator and looked, in the reader's words, different from what the spec
describes — the composition pushed in and the cat seemingly uncropped. Neither was visible as an
error: `flutter build` passed, `swiftc -typecheck` passed, `--check` passed, and the review page
drew the design correctly. Both were found by measuring a screenshot with
`scripts/measure_widget_shot.py`, which walks the tile's own edges out from a seed pixel and reports
the content inset, the cut-out's box and whether it reaches the bottom edge.

**What the measurement actually said**, on a 164.0 × 164.3pt small tile:

| measured                | device          | the page | verdict                                        |
| ----------------------- | --------------- | -------- | ---------------------------------------------- |
| amber, from the left    | 16.7pt          | 16.5pt   | agrees — the 14pt inset is intact              |
| amber, from the top     | 23.0pt          | 15.5pt   | **7.5pt low**                                  |
| cut-out box             | 95.3 × 101.0pt  | —        | 70% of the tile, cropped 8% — exactly as drawn |
| grey at the bottom edge | 30pt wide, flat | —        | cropped; the gap is 0.3pt                      |

So **the cat was never the defect** — it is drawn and cropped precisely as specified, and the
impression that it was not came from the run row above it having drifted down into it. Two things to
keep from that:

**The numeral's line box, which is the whole 7.5pt.** Nunito ExtraBold's own metrics are ascent
1011 and descent −353 on a 1000 em, so its natural line box is **1.364 em** — 54.6pt at a 40pt font
— and SwiftUI lays `Text` out in all of it, putting the digit's cap 12.2pt below the box's top. The
page sets `line-height: 1`, which applies −7.3pt of half-leading and lifts the same glyph to 4.9pt.
Both predictions land within half a point of what was measured. The fix is
`.frame(height: figureSize)` on the figure, which is exactly what `line-height: 1` means; the
symptom it removes is a 9pt dead band across the top of the tile with the run row pressed toward the
cat. **This is a CoreText-versus-CSS difference, not a layout mistake**, which is why no amount of
reading either side would have found it — only measuring both did.

**`contentMarginsDisabled()` was missing, and is now called.** From iOS 17 the system adds ~16pt of
content margins around the view, which would stack on `StreakWidgetView`'s own `.padding(14)` and
leave a content box near 98pt wide inside a 164pt tile. **Not isolated on device**: the run that
measured 14.0pt already had the call, and SpringBoard may have been showing a snapshot cached from
before the install, so what is proven is that the shipped behaviour is right rather than that the
margins were ever being applied. The call needs no `#available` guard — it is declared
`@available(iOS 15.0, *)` and `@_alwaysEmitIntoClient`, with Apple's own body doing the 17 check —
and it could not have one, because the two branches of an `if #available` would have different
opaque types.

**The page now guards the layout the way it already guarded the palette.** `QUAD_NUMBERS` in
`render_final_widget.py` lists every literal the four-corner medium is built from, plus these two
calls, and `--check` reads them back out of the Swift. Rendering the page also turned up that its
CSS percentages and the Swift's resolve against **different origins** — an absolutely positioned
box's `max-width: 43%` is 43% of the whole 338pt tile, where `geometry.size.width * 0.43` is 43% of
the 310pt content box, so the page was drawing a copy column 9% wider than the app's. Both caps are
pinned in points now for that reason: only an absolute value can be read as agreeing.

**What is still unverified.** The four-corner medium has not been seen on a device — this machine's
Xcode ships no `Simulator.app`, so the widget cannot be re-added to a home screen after a reboot
clears it, and `simctl` alone cannot place one. The page is faithful to the numbers, but what it
still cannot settle is `lineLimit(3)`, `minimumScaleFactor(0.85)` and the sticker ring at this
size. To close it: add the medium widget by hand, screenshot with `xcrun simctl io booted
screenshot`, and run `measure_widget_shot.py --seed` on it. A SwiftUI render harness would remove
the hand step permanently and is the obvious follow-up.

## Testing

**Phase 1.** `readingDayPhase` at 20:59 / 21:00 / 23:59 / 00:00, in the style
`reading_date_test.dart` already uses for the rollover. `nextReadingPhaseBoundary` at the
warning hour exactly, across a month end and a year end, and **swept across every minute of a
day asserting the boundary is strictly later** — a non-positive gap is a timer that fires at
once and reschedules itself forever, which presents as heat rather than as a wrong answer.
The page showing `streakTodayLate` past the hour, `streakTodayOpen` before it, no line at all
once recorded, and the figure and flame unchanged by the warning. (Superseded by the correction
in _What the page draws_: the page draws no line at all, and
`reading_streak_page_test.dart` pins that it reads identically either side of the warning hour.
The strings are exercised through the snapshot instead.)

`test/reading_streak_chip_test.dart` is expected to pass **untouched** — if a chip test
needs changing, phase 1 has strayed into the surface it agreed to leave alone.

**Phase 2.** Dart: the snapshot as a golden JSON, the writer firing on each trigger,
sign-out clearing it. Swift: the three-case derivation and its boundaries — which means
the project's **first Swift test target**. That is a real cost, and it is the one place
that earns it: a silently wrong streak would live in exactly that function, and no Dart
test can reach it.

**The ladder (2d).** Dart: `lines` carries all seven keys in both ARBs, and a case asserting the
snapshot still decodes with `lines` absent — the fallback is the whole reason `v` did not move, so
it is the one path a future reader will assume is covered. Swift: the tier boundaries at 04:59 /
05:00 / 22:59 / 23:00, the tier of an entry generated before a boundary and rendered after it, and
`none` returning the dawn ground at 23:00 rather than the final one — that last case is the rule
the design most wants protected and the one a refactor is most likely to lose.

**And the contrast rule is a test, not a paragraph.** The amended rule — late must not be
confusable with recorded — is checkable: assert the lightest stop of every open ground against the
darkest stop of the recorded one clears 4.5:1. That is what makes it better than the hue
prohibition it replaces, so leaving it in prose would throw away the improvement.

## Open questions

1. **Should the chip carry `late` after all?** Left two-state for now. The recorded option
   is `StreakFlameMark`'s `coreColor` — a lit core in a grey flame — and the trigger to
   revisit is the page proving too quiet to change behaviour.
2. **Does the widget ever show a friend?** Out of scope here, and `reading_days` RLS is
   owner-only, so there are no rows to read. Noted because it will be asked.
3. **Android.** The snapshot format is platform-neutral and the MethodChannel is not. A
   Glance widget would reuse the Dart half wholesale; nothing here forecloses it.
4. **Does `longestStreak` earn its place in the payload?** It is only read on the broken
   path. Kept because that path is the one with nothing else to say.
5. **Which face sets the figure? — answered: Nunito, and it is already the app's.**
   `AppTextStyles.streak` is `'Nunito'` and `assets/fonts/Nunito-ExtraBold.ttf` ships today,
   subset by `build_fonts.py` **to digits and a minus sign**, because the one thing it sets is
   `int.toString()` of a streak count. So the sheet's "trial" face is the app's face, the widget
   matches the page rather than inventing a third figure, and the digits-only cut is exactly what
   a widget needs — **2.7KB**. The same file is now a member of the **extension's** target with
   `UIAppFonts` in its `Info.plist`, because an extension inherits none of the host app's fonts and
   Flutter's copy is inside `App.framework`'s asset bundle where nothing native can reach it. It
   must never be asked for a letter here: there are none in the file. **And the name Swift asks for
   is `Nunito-ExtraBold`, not `Nunito`** — the subset carries the family name _Nunito ExtraBold_, so
   `UIFont(name: "Nunito")` returns nil and the figure falls through to SF Rounded with nothing
   failing. `pubspec.yaml`'s `family: Nunito` is no guide, because Dart resolves against that
   declaration rather than against anything inside the file. `streak_widget_palette_test.dart` now
   parses the TTF's `name` table and asserts the Swift asks for what is actually in there. If the
   copy line ever goes
   serif the way the sheet draws it, `GowunBatang-Bold` has to travel the same way — 1.39MB, cut to
   KS X 1001's 2,350 syllables, which covers our own Korean by construction.
6. **The recorded figure is a stroked sticker numeral** — white fill inside a 6pt flame-coloured
   stroke, with `paint-order` putting the stroke behind. On the cream ground that puts all of the
   contrast on the outline (amber on cream is 1.96:1) and none on the fill. It is the same trade the
   streak page already accepted for amber on cream, and it is the one thing in the ladder that can
   only be judged on device. The fallback is the plain `#212529` figure the open tiles use, at
   15.2:1.
7. **The cat art is final, and the record of how it was made is in the other checkout.** The eight
   cut-outs were generated by prompting **xAI's Imagine API** (`grok-imagine-image-2.0`, the `edits`
   route, three variants each, 2026-09-24), seeded by `docs/mockups/mascot/REFERENCE.png`. The full
   prompt for every image ever generated is `docs/mockups/mascot/art/manifest.json` — 498 entries,
   each with model, route, reference, resolution, cost and timestamp; the generator is
   `scripts/gen_mascot_art.py`, where the eight widget poses are the `WIDGET` dict and the shared
   identity-preserving wrapper is `core_edit()`; the rules are `docs/mockups/mascot/CHARACTER.md`
   under "Prompt-craft rules that are load-bearing".

   **All of that lives in the main checkout and not in this worktree**, so a reader here will look
   for it and not find it — which is the whole reason it is written down at this length. There is no
   `PROMPTS.md` for the mascot; that file belongs to the empty-state illustrations, which used a
   different pipeline.

   Three constraints from those comments, because they are the expensive ones to rediscover: **the
   pose clause goes first**, since an edit prompt is an imperative and burying the pose at the end
   of 2,165 words returned the seed's own pose; **`keep_eyes=False` wherever the pose changes the
   eyes**, because claiming the eyes are unchanged while describing new ones is a contradiction and
   contradictions are what four earlier rounds failed on; and **negations are ignored**, so every
   clause is positive and the mouth is named explicitly in all of them (an unnamed mouth came back
   rose-pink, a sixth colour outside the five-colour palette). `--reference` is not optional in
   practice — without it the script falls back to the `generations` route and returns a different
   cat.

8. **Korean is the tighter constraint on the copy, not English.** The line box is 52% of a 158pt
   tile over two lines — about 15 Latin characters a line, but only about **7 full-width Hangul
   syllables**, so a Korean line has roughly 14 characters to work in where the English has 30. The
   ladder's register mixing also lands differently: Korean carries the cat's relationship to the
   reader in its speech level, so "unhinged" in 해요제 (polite) is a different joke from the same
   sentence in 반말, and the app speaks 해요제 everywhere else.
9. **Does the mascot come back into the app?** The widget would be the only surface with a
   character on it, and a character that exists solely on the home screen is a stranger inside the
   app. Out of scope here, and the first place it would land is the celebration.

## Out of scope

- **Interactive widgets — tapping to record a day.** An `AppIntent` stamp would bypass the
  book picker and the progress capture, and the extension has no Supabase session, so it
  would need a write queue in the App Group and conflict handling against a table with a
  `(user_id, day)` primary key. The widget offers the act by opening the book.
- **Scheduled local notifications.** A second nudge channel with its own permission
  prompt, and not needed to prove this one.
- **Freezes.** Still deferred. The snapshot's `v` field is how a `freeze` day arrives
  later without breaking installed widgets.
- **`systemLarge`, Live Activities, StandBy, lock-screen accessories.**
