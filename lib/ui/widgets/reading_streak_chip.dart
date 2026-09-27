import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/reading_days_provider.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_flame_mark.dart';

// **The mark that leads the chip is a flame, and it is `StreakFlameMark` rather than a font
// glyph.** Two arguments are recorded here because they are the chip's rather than the mark's,
// and because both were reversed.
//
// **Why a flame at all — it replaced a stamp (`▣`).** The design originally refused a flame on
// the grounds that the app already owns four working metaphors for "a day was recorded": the
// ink stamp on the due-date card, the reading lamp, the wax seal, the library card itself. A
// flame would be a fifth, borrowed one competing with four that fit. That argument is sound
// about *a day* and wrong about *a run*. It answers "what marks a day?" when the chip's job is
// "what kind of number is this?" — `▣ 12` sat beside a shelf-count badge and an avatar and
// read as a third count, with nothing in it saying the number is consecutive days. A flame
// says that instantly because the genre taught everyone to read it, and being a cliché is
// exactly what makes it legible. The split it does *not* cross: a flame names the run, never a
// day. `ReadCalendarMonth` draws recorded days as stamped numerals — the stamp metaphor's
// actual territory — rather than thirty flames.
//
// **Why not a font glyph any more.** This was `kReadingStreakIcon`, Phosphor Fill's `fire` at
// U+E242, constructed as a bare `IconData` because `import
// 'package:phosphor_flutter/phosphor_flutter.dart'` does not compile on this SDK — the package
// declares `class PhosphorIconData extends IconData` and `IconData` is final. Before that it
// was `Icons.local_fire_department_rounded`, whose hollow base closes into a blob at 19pt.
// Both were about *availability*, and the argument for a font — "the chip needs it in two
// tints, so it must be recolourable, and hand-authoring vector art for this app has a
// documented history of costing ten rounds" — was answered by the Rive flame existing: the
// silhouette is already authored, in text, in `rive/streak_flame/smooth.py`, so the icon is
// generated from it rather than drawn. What the glyph was actually costing was that the chip
// and the celebration showed two unrelated flames for one feature. See `StreakFlameMark`.
//
// `phosphor_flutter` was in `pubspec.yaml` for this one codepoint and nothing else, so it went
// with it.
//
// **Still not the same flame as the share card's**, deliberately. That one
// (`share_card_page.dart`) is a candlelight *toggle* — it names a lighting mode, not a run — so
// it is not this mark and must not become it. If the two are ever unified it should be because
// the card's lighting design says so, not because they happen to both be flames.

/// The reader's run, in the library bar.
///
/// **A pointer, not a second home for the number.** The streak page is where the figure
/// lives; this is the everyday glance on the screen the reader opens most, and tapping it
/// opens that page. A number displayed in two places is a number that will eventually
/// disagree with itself — the only thing that makes two safe here is that both read the
/// same derived value and neither stores one.
///
/// **It draws at zero, and that reversed the original rule.** The chip used to return
/// `SizedBox.shrink()` for an empty run, following the Library Card's
/// omit-rather-than-zero-fill rule, on the reasoning that `▣ 0` "is not a smaller
/// version of a streak, it is an announcement that the reader has nothing". The premise
/// was right and the conclusion inverted: of 137 profiles in production, **exactly one
/// has any reading day at all**. Omitting at zero therefore hid the chip from 136 of
/// 137 accounts, which is not a tasteful default but the feature failing to exist. A
/// reader cannot start a run they have never been shown, and the first day is the only
/// day the nudge has anything to do.
///
/// **It costs no vertical space**, which is the whole reason it won the placement. The
/// alternative drawn beside it was a line above the reading shelf: warmer, able to say
/// more in words, and 29pt of permanent rent at the top of the one screen whose last
/// redesign was specifically about lifting the reading books higher.
///
/// **A `ConsumerWidget` rather than a prop on the bar**, deliberately. Nothing about
/// the streak relates to anything else the bar carries, so threading a count and a
/// boolean through the bar's constructor would put two fields on a widget that has no
/// use for them and would make the bar rebuild for a reason it cannot explain.
class ReadingStreakChip extends ConsumerWidget {
  const ReadingStreakChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **Absence still means one thing, and it is no longer "zero".**
    //
    // `currentStreakProvider` answers 0 while the fetch is in flight, because
    // `valueOrNull` is null and 0 is the only int it can offer. That was harmless while
    // the chip omitted itself at zero — it simply appeared once the days arrived. Now
    // that zero draws, an ungated chip reads a cold `0` on every cold open and then
    // flips to the real run, so a reader with twelve days watches the app appear to
    // lose them. Not knowing is not the same fact as zero, which is the distinction
    // this codebase makes everywhere else (`Book.progress` null against 0.0, the band's
    // prompt against `0%`).
    //
    // `hasValue` rather than `!isLoading`, so a background refresh over a cached set
    // does not blink the chip out; and an error keeps it hidden rather than claiming a
    // zero nobody has established.
    if (!ref.watch(readingDaysProvider).hasValue) {
      return const SizedBox.shrink();
    }

    final streak = ref.watch(currentStreakProvider);
    final read = ref.watch(readTodayProvider);
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);

    // **Keyed on whether *today* is recorded, never on the count.** The count is
    // intact all day and only the day's own status changes at the midnight rollover;
    // keying the tint on the number made the chip green at 9am on an unstamped day,
    // which is the opposite of a nudge.
    //
    // Zero needs no state of its own and deliberately does not get one: a run of zero
    // cannot have today in it, so `read` is already false and the empty chip *is* the
    // cold chip. One rule, not two — and the number it shows is honest rather than
    // encouraging, which is the same reason the cold state still reads the full count.
    //
    // **Warm, not `brandText`, is the hot colour.** It shipped tinted brand green, on
    // the reasoning that the chip is a brand surface like any other; a flame is not — a
    // green flame reads as a rendering defect rather than a streak, which is exactly
    // what it looked like on device. Mark and numeral move together, so there is one hue
    // standing for "today is recorded" rather than a green ring around an orange flame.
    // (This used to say "the whole capsule — mark, numeral, fill and border". There is no
    // fill and no border any more; see the box note further down. The rule survives the
    // pill's removal because it was never about the pill — it is that the chip carries one
    // hue, whatever it draws with it.)
    //
    // **And the warm hue is [kCandleFlame] #F2A93F, not `colors.flame` #B54708 — which
    // reverses this file's own second decision, on instruction.** `flame` was authored
    // for this chip and for nothing else: a burnt orange, darkened from a true fire
    // colour exactly the way `brandText` is darkened from `brand`, so that the 13pt
    // numeral beside the mark clears AA on every light surface the bar can sit on. The
    // instruction is that the streak reads in **one** orange, and the one it reads in is
    // the flame's own — the Rive artboard's amber, which `_Hero`, `ReadWeekPalette.page`
    // and `StreakCelebration` all moved to before this chip did. Leaving the chip behind
    // meant the *same generated silhouette* ([StreakFlameMark]) was rust in the library
    // bar and amber one tap later on the streak page: the "one object looked like two"
    // defect those three swaps were made to fix, still shipping on the screen the reader
    // sees first and the only one of the four they see every day.
    //
    // **What it costs, measured, and it is light mode only.** #F2A93F is 2.00:1 on
    // `surface`, 1.89:1 on `pageBackground`, 1.80:1 on `sheetBackground` and 1.68:1 on
    // `surfaceVariant` — where #B54708 measured 5.43/5.15/4.90/4.58:1 and cleared AA on
    // all four. Dark mode is not a trade at all but an improvement: the amber is 8.35:1
    // on the dark surface against the token's own 7.46:1, because `flame` is already a
    // bright #FF922B there.
    //
    // **That cost is now unhedged, and this comment used to say otherwise.** It read "so
    // the capsule's fill and border keep carrying the state — the pill's *shape* is what
    // says 'recorded' at a glance", which was true and is not: the pill is gone, so a
    // 2.00:1 numeral and a 2.00:1 mark are the whole readout. The amber is the first thing
    // to revisit if anyone asks why this chip is hard to read, and the answer can no longer
    // be "the shape is doing it". `read_week_row.dart` records the same trade for
    // `labelToday`, at 1.76:1.
    final tint = read ? kCandleFlame : colors.secondaryText;

    return Semantics(
      button: true,
      // The chip draws a glyph and a numeral, which a screen reader would otherwise
      // announce as a bare number beside the library's name. At zero it says what the
      // chip is *for* rather than reading out a nothing.
      label: l10n.readingStreakChip(streak),
      child: GestureDetector(
        onTap: () {
          // **The destination the figure now has, and this replaced a stopgap.** This used
          // to switch the library's tab to the Library Card, because the streak had no
          // surface of its own and the Card was the nearest thing that showed the number.
          // The Card was always the wrong home for it: it is *year-scoped* and says so in
          // its own label, so the month grid could not sit inside it. The streak page is
          // year-agnostic, holds the month, and is what this chip's own comment was asking
          // for — see `docs/superpowers/specs/2026-09-12-reading-streaks-design.md`.
          //
          // Pushed on the root navigator's own table rather than switching shell state, so
          // the library is still exactly as the reader left it underneath.
          Navigator.pushNamed(context, AppRoutes.readingStreak);
        },
        behavior: HitTestBehavior.opaque,
        // **The chip is not grown to 44pt; the target is.** A 44pt ring drawn around
        // a 22pt chip is a failure this design has already rejected twice — it makes
        // the control look like it is floating inside a button. The padding here is
        // transparent, so the ink stays chip-sized and the touch area is not.
        //
        // **The inset is 16.5 × 14.5 because it used to be 8 + 7 + 1.5 and 11 + 2 + 1.5**,
        // and the arithmetic is preserved rather than rounded so that removing the pill
        // moved nothing else: the bar's row of controls lays out to the same pixel it did
        // before, and the touch target is the same 48.5pt tall. Three numbers collapsed
        // into one because two of them belonged to the pill — an inner inset holding the
        // ink off its edge, and a border width — and there is no pill.
        //
        // That border width is the term worth keeping a note on, because it is why these
        // are not simply 8 and 11. `Container` folds a border's width into its own
        // effective padding *only when a border is present*, which is why the decoration
        // used to be kept alive in the cold state with transparent colours rather than set
        // to `null`: nulling it took 2 × 1.5pt out of the layout and moved the reader's tap
        // target by three points depending on whether they had read yet. There is nothing
        // left to keep in sync now that neither state has a decoration — but those 3pt were
        // real, and dropping them silently would have quietly shrunk the target.
        //
        // Keyed so a test can measure this exact box rather than guessing at ancestor
        // order.
        child: Padding(
          key: const ValueKey('reading-streak-chip-footprint'),
          padding: const EdgeInsets.symmetric(horizontal: 16.5, vertical: 14.5),
          // **There is no box, in either state, and that reverses this file's own "hot is
          // a full pill".** The chip used to draw a `circular(20)` stadium filled
          // [kCandleFlame] at 12% behind a 1.5pt border of the same hue at 55%, once today
          // was recorded; cold was the identical decoration with both colours transparent.
          // The instruction is Duolingo's own bar, where the streak counter is a mark and a
          // numeral on the bar's own ground and the *hue* is the entire state.
          //
          // The reasoning it overrides is worth keeping, because it was not decoration for
          // its own sake. The amber numeral measures 2.00:1 on `surface`, so the fill and
          // the border were deliberately carrying the state that the ink could not — the
          // pill's *shape* is what said "recorded" at a glance, and this file's contrast
          // note said so in as many words. What that argument missed is the complaint that
          // had already deleted the *cold* outline one revision earlier: a pill here is a
          // fourth chrome control in a row of three real buttons (the density toggle, the
          // shelves button, the avatar). Removing it when cold fixed that for the days the
          // reader had not read — most days — and left it running on the good ones, which
          // is the wrong way round. A status readout is not a control, and the way to stop
          // it looking like one is to stop drawing it like one.
          //
          // **So the state now rests entirely on two hues, and the delta is small.**
          // #F2A93F against `secondaryText` #626A72 is 2.75:1 in light mode and **1.5:1**
          // in dark, where the amber and the grey are near enough the same lightness that
          // hue is doing all of the work. That is the same bet Duolingo makes and it is a
          // real one: it holds for a reader who can see the difference between orange and
          // grey and fails quietly for one who cannot. `Semantics` below carries the run in
          // words either way, which is what keeps this from being the only channel.
          //
          // It is also why the mark is not shrunk to match the numeral (see below): with no
          // pill, the flame is the largest coloured thing in the chip and therefore the
          // thing actually delivering the state.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreakFlameMark(
                // **Derived from the token, not equal to it.** 1:1 with the numeral's
                // 13pt read as too small to register as a flame at all — a filled
                // glyph that size is mostly antialiasing. 1.5× is close to the ratio
                // Duolingo's own badge uses between its flame and its digits, and it
                // still tracks `AppTextStyles.streakChip` if that token ever changes,
                // so the two cannot drift apart the way a literal would let them.
                //
                // **The number survived the move off the font glyph** because the mark
                // boxes itself square, exactly as `Icon` did: it is still 19.5 wide and
                // 19.5 tall, with the flame's own 1:1.23 centred inside. The row's default
                // `crossAxisAlignment.center` therefore still centres it against the
                // numeral even though it is the taller of the two, and the chip's height
                // still follows the mark rather than the text's line box — the outer
                // `Padding` owns the touch target either way.
                size: AppTextStyles.streakChip.fontSize! * 1.5,
                color: tint,
              ),
              const SizedBox(width: 3),
              Text(
                // The numeral is not localized past its digits: `NumberFormat` here
                // would group a three-digit streak, and `1,000` in this pill
                // reads as two values.
                '$streak',
                // **Nunito Bold, not the badge-and-capsule token, on instruction.**
                // [AppTextStyles.streakChip] carries [label]'s exact size and metrics —
                // this is still a badge numeral, not a display figure — with
                // [AppFonts.streak] in place of [AppFonts.sans], so the chip's digits
                // are drawn in the same face as the streak page's hero figure and the
                // celebration's, rather than the app's general-purpose sans.
                style: AppTextStyles.streakChip.copyWith(
                  // **Grey before today, flame after — and grey rather than red or
                  // empty.** It still reads the full count, because the streak is
                  // intact until the day actually ends. A chip that panics at 9am is
                  // a chip readers learn to resent, and the rule the whole design
                  // shares is that the record does not scold.
                  color: tint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
