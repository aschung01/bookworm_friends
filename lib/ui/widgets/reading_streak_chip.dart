import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/providers/reading_days_provider.dart';

/// The mark that leads the chip: a flame.
///
/// **It replaced a stamp (`▣`), and the argument it replaced is worth recording.**
/// The design originally refused a flame on the grounds that the app already owns four
/// working metaphors for "a day was recorded" — the ink stamp on the due-date card, the
/// reading lamp, the wax seal, the library card itself — and a flame would be a fifth,
/// borrowed one competing with four that fit.
///
/// That argument is sound about *a day*, and wrong about *a run*. It answers "what
/// marks a day?" when the chip's job is "what kind of number is this?". `▣ 12` sat in
/// the library bar beside a shelf-count badge and an avatar and read as a third count;
/// nothing in it says the number is consecutive days. A flame says that instantly,
/// because the genre taught everyone to read it, and being a cliché is exactly what
/// makes it legible.
///
/// The split it does *not* cross: a flame names the run, never a day. When the month
/// calendar lands it draws recorded days as numerals in a connected ligature — the
/// stamp metaphor's actual territory — rather than thirty flames.
///
/// A `Icons.` glyph rather than an SVG in `assets/icons/`, because the app already uses
/// Material icons in 69 places, the chip needs it in two tints (so it must be
/// recolourable, which rules out anything with baked-in colour), and hand-authoring
/// vector art for this app has a documented history of costing ten rounds and being
/// rejected — see `docs/mockups/empty-states/PROMPTS.md`.
const IconData kReadingStreakIcon = Icons.local_fire_department_rounded;

/// The reader's run, in the library bar.
///
/// **A pointer, not a second home for the number.** The Library Card is where the
/// figure lives; this is the everyday glance on the screen the reader opens most, and
/// tapping it goes to the Card. A number displayed in two places is a number that will
/// eventually disagree with itself — the only thing that makes two safe here is that
/// both read the same derived value and neither stores one.
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
    // intact all day and only the day's own status changes at the 4am rollover; keying
    // the tint on the number made the chip green at 9am on an unstamped day, which is
    // the opposite of a nudge.
    //
    // Zero needs no state of its own and deliberately does not get one: a run of zero
    // cannot have today in it, so `read` is already false and the empty chip *is* the
    // cold chip. One rule, not two — and the number it shows is honest rather than
    // encouraging, which is the same reason the cold state still reads the full count.
    //
    // **`flame`, not `brandText`, is the hot colour.** It shipped tinted brand green, on
    // the reasoning that the chip is a brand surface like any other; a flame is not — a
    // green flame reads as a rendering defect rather than a streak, which is exactly
    // what it looked like on device. The whole capsule moves to `flame` together —
    // glyph, numeral, fill and border — so there is one hue standing for "today is
    // recorded" rather than a green ring around an orange flame.
    final tint = read ? colors.flame : colors.secondaryText;

    return Semantics(
      button: true,
      // The chip draws a glyph and a numeral, which a screen reader would otherwise
      // announce as a bare number beside the library's name. At zero it says what the
      // chip is *for* rather than reading out a nothing.
      label: l10n.readingStreakChip(streak),
      child: GestureDetector(
        onTap: () {
          // Straight to the Card, which is where the figure and its history live.
          //
          // **A stopgap, and known to be one.** The streak has no destination of its
          // own yet; the Card is the nearest surface that shows the figure. The design
          // record's own recommendation is a month calendar as its own destination that
          // this chip opens — see `docs/superpowers/specs/2026-09-12-reading-streaks-design.md`,
          // "The month grid has no home yet". Until that exists, this points at the
          // number rather than at nothing.
          ref.read(friendsSheetLevelProvider.notifier).state =
              FriendsSheetLevel.list;
          ref.read(selectedFriendProvider.notifier).state = null;
          ref.read(libraryTabProvider.notifier).state = LibraryTab.card;
        },
        behavior: HitTestBehavior.opaque,
        // **The chip is not grown to 44pt; the target is.** A 44pt ring drawn around
        // a 22pt chip is a failure this design has already rejected twice — it makes
        // the control look like it is floating inside a button. The padding here is
        // transparent, so the ink stays chip-sized and the touch area is not.
        //
        // Keyed so a test can measure this exact box rather than guessing at ancestor
        // order — it is what must stay a fixed size while the decoration inside it
        // toggles on and off.
        child: Padding(
          key: const ValueKey('reading-streak-chip-footprint'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            // **Colour goes to fully transparent when cold; the decoration itself never
            // goes away.** The first cut set this to `null` outright when today was not
            // yet recorded, and a test that measures the padded footprint across both
            // states caught what that actually did: `Container` folds a border's width
            // into its own effective padding *only when a border is present*, so
            // removing the decoration shrank the box by 2 × 1.5pt — the reader's tap
            // target moving by three points depending on whether they had read yet.
            // Keeping the border at a constant 1.5pt and only making both its colour and
            // the fill's fully transparent gets the same *look* — nothing paints — with
            // no such thing to get wrong, because the reserved space never changes.
            //
            // The pill itself is still the point: a persistent status readout is a
            // different kind of object from the density toggle, the shelves button and
            // the avatar beside it, and (`BookStatusBadge`'s own precedent) that
            // difference is drawn, never native-glassed — glass exposes one tint per
            // control with no separate fill/label knob, which cannot express this
            // chip's two-tone system, and the bar underneath is opaque, so there is
            // nothing for glass to refract anyway. Cold recedes to nothing painted at
            // all rather than a grey outline, so this is not a fourth chrome control
            // competing with three real buttons on every day the reader has not yet
            // read — which is most days — and hot is a full pill: `circular(20)` is not
            // a new number, it is `_SegmentChip`'s own radius, so the shape matches the
            // app's other pill rather than inventing a bespoke one. The chip's own
            // height is well under 40, so this clamps to a true stadium.
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: read
                  ? colors.flame.withValues(alpha: 0.12)
                  : Colors.transparent,
              border: Border.all(
                width: 1.5,
                color: read
                    ? colors.flame.withValues(alpha: 0.55)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  kReadingStreakIcon,
                  // **Derived from the token, not equal to it.** 1:1 with the numeral's
                  // 13pt read as too small to register as a flame at all — a filled
                  // glyph that size is mostly antialiasing. 1.5× is close to the ratio
                  // Duolingo's own badge uses between its flame and its digits, and it
                  // still tracks `AppTextStyles.label` if that token ever changes, so
                  // the two cannot drift apart the way a literal would let them.
                  //
                  // The row's default `crossAxisAlignment.center` keeps this centred
                  // against the numeral even though it is now the taller of the two, so
                  // the chip's height follows the icon rather than the text's line box
                  // — the outer `Padding` still owns the touch target either way.
                  size: AppTextStyles.label.fontSize! * 1.5,
                  color: tint,
                ),
                const SizedBox(width: 3),
                Text(
                  // The numeral is not localized past its digits: `NumberFormat` here
                  // would group a three-digit streak, and `1,000` in this pill
                  // reads as two values.
                  '$streak',
                  // The scale's badge-and-capsule token, unmodified except for colour.
                  // The drawing had this a point larger and a weight heavier; the scale
                  // is the authority on both, and a chip is exactly what `label` is for.
                  style: AppTextStyles.label.copyWith(
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
      ),
    );
  }
}
