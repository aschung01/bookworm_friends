# A streak on the home screen, and the evening state it needs first

Give the reader an iOS home-screen widget carrying the run, the book they are in, and
whether tonight is still open — and, because a widget must not say something no in-app
surface says, build the evening state in the app first.

Two phases, separately shippable:

1. **The late state**, in the app. Pure Dart, no native work, no new dependency.
2. **The widget.** A WidgetKit target, an App Group, a snapshot contract, SwiftUI.

Bundling them would put "does the page read right at 21:30" behind provisioning-profile
work, so they ship in that order.

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

The design is **one `Timer` to the next boundary** — 21:00, then midnight — which
invalidates the provider and reschedules. Deliberately not a periodic ticker: at most two
wakes a day, and a per-second rebuild of a surface that changes twice is the kind of cost
that shows up as battery in a review.

A timer alone is insufficient, because a suspended app's timer does not fire on schedule.
So the phase also recomputes on `AppLifecycleState.resumed`. There is **no app-level
lifecycle observer today** — `lib/ui/pages/scan_book_page.dart` has the only
`WidgetsBindingObserver` in the codebase — so phase 1 adds one. It is the same hook phase
2 needs for writing the snapshot on pause, which is why it is built as a proper observer
rather than inlined into a page.

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
  }
}
```

**The extension derives `recorded / open / late` itself, from `lastReadDay` and the
entry's own date. The app never writes a state flag.** This is the single rule the
correctness of the whole feature rests on: an entry generated at 22:00 must still be right
at 00:05 when the day has turned. Had the app written `"phase": "late"`, the widget would
insist it is late at 9am the following morning.

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

Real jackets are a documented follow-up with a clean route: `cover_sample.dart` already
decodes covers in order to sample `cover_color`, so a re-encoded thumbnail can be written
from there rather than scavenged from a cache. **This is the weakest point of v1** — a hex
rectangle is a thinner version of "the book you are 41% through" than a jacket is.

**Colours** live in an extension asset catalog mirroring `kCandleFlame` and the neutrals,
guarded by a Dart test that reads the catalog JSON and asserts the hexes still equal the
Dart constants. The same habit as the existing `expect(kReadingDayRolloverHour, 0)`.

### Empty states

No snapshot, or signed out, draws an **invitation** — never a blank, never a bare zero.
This inverts the Library Card's omit-rather-than-zero-fill rule for the reason
`ReadingStreakChip` already inverted it: a widget the reader deliberately placed must
never look broken. A missing reading book against a live streak degrades to the
streak-only layout, the way `LibraryCardStats.hasPace` omits its tile.

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

## Decomposition

| step   | scope                                                             |
| ------ | ----------------------------------------------------------------- |
| **1**  | The late state: constant, phase, timer, observer, page copy       |
| **2a** | Entitlement proof, target, MethodChannel, snapshot, `systemSmall` |
| **2b** | `systemMedium`, the week row, the two `Link`s                     |
| **2c** | Real jackets, lock-screen accessory — only if wanted              |

Step 1 ships alone and is worth shipping alone.

## Testing

**Phase 1.** `readingDayPhase` at 20:59 / 21:00 / 23:59 / 00:00, in the style
`reading_date_test.dart` already uses for the rollover. The timer firing at a boundary and
rescheduling, and a resume recomputing after a suspended stretch. The page showing
`streakTodayLate` past the hour and `streakTodayOpen` before it.

`test/reading_streak_chip_test.dart` is expected to pass **untouched** — if a chip test
needs changing, phase 1 has strayed into the surface it agreed to leave alone.

**Phase 2.** Dart: the snapshot as a golden JSON, the writer firing on each trigger,
sign-out clearing it. Swift: the three-case derivation and its boundaries — which means
the project's **first Swift test target**. That is a real cost, and it is the one place
that earns it: a silently wrong streak would live in exactly that function, and no Dart
test can reach it.

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
