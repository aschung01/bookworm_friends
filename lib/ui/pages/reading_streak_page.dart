import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/reading_date.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/models/streak.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/reading_days_provider.dart';
import 'package:bookworm_friends/ui/widgets/book/book_chassis.dart';
import 'package:bookworm_friends/ui/widgets/book/generated_cover.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/pick_reading_book_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_percent_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/reading_streak_chip.dart';
import 'package:bookworm_friends/ui/widgets/streak/read_calendar_month.dart';
import 'package:bookworm_friends/ui/widgets/streak/read_week_row.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_celebration.dart';

/// The ✕, keyed so a test taps a target rather than a glyph.
const Key kStreakPageCloseKey = Key('streak-page-close');

/// The hero figure, keyed because the month below it draws numerals too.
///
/// A test looking for the run by its text found two widgets on a day whose number happens
/// to match the streak — which is most days.
const Key kStreakFigureKey = Key('streak-figure');

/// The one control, keyed for the same reason.
const Key kStreakRecordButtonKey = Key('streak-record-button');

/// The undo, which is a different control from the button it replaces.
///
/// **Not the primary button read back, and that is a correction.** The first cut put "Undo
/// today" in the green CTA slot once the night was in — which advertises an undo as the page's
/// primary action and invites the tap. What the drawing has, and what ships, is a
/// *confirmation* that today is recorded with the undo as a quiet secondary inside it: the
/// reader is told the act landed, and taking it back is available without being urged.
const Key kStreakUndoKey = Key('streak-undo');

/// The run, the week, the month, the record, and one button.
///
/// **The streak's destination, and the reason the chip is no longer a stopgap.** The figure
/// used to have no home of its own: the chip pointed at the Library Card, which is the
/// nearest surface that shows a streak and the wrong one — the Card is *year-scoped* and
/// says so in its own label, so a month grid cannot sit inside it. This page is
/// year-agnostic, holds the month at the Card's own geometry, and the Card's streak tile
/// becomes a second pointer here rather than a rival figure. One home, two pointers.
///
/// **Not one figure this page draws needs a query that does not exist.**
/// `currentStreakProvider`, `longestStreakProvider`, `readTodayProvider` and
/// `readingDaysProvider`'s 400-day window are all shipping, and the month is
/// [ReadCalendarMonth] — the same renderer any other surface must use, so two grids cannot
/// drift.
///
/// **A full-screen cover rather than a sheet**, for the reason `app_routes.dart` already
/// argues at length: a `CupertinoSheetRoute` is `UIModalPresentationPageSheet`, which
/// scales the presenting page down behind it, and this page is the one thing on screen
/// rather than a panel belonging to a shrunken app. Hence a ✕ and no grab handle — the two
/// sheets it raises *do* carry handles, and that difference is deliberate.
///
/// **The hero figure is derived from the grid under it**, by `currentReadingRun`'s own
/// rule: a run ending *yesterday* still counts, because today being unstamped means the day
/// is open rather than broken. That is why the figure can read 11 beside a month whose last
/// stamp is the 12th, and why the *label* rather than the number carries the day's status.
class ReadingStreakPage extends ConsumerStatefulWidget {
  const ReadingStreakPage({super.key});

  @override
  ConsumerState<ReadingStreakPage> createState() => _ReadingStreakPageState();
}

class _ReadingStreakPageState extends ConsumerState<ReadingStreakPage> {
  /// Whether the celebration is over the page.
  ///
  /// Local rather than a route, so the page underneath keeps its state and the reader lands
  /// back on the same scroll position with today now stamped. A pushed route would rebuild
  /// this page on the way back for no reason.
  bool _celebrating = false;

  /// The run the celebration should show.
  ///
  /// **Captured at the moment of the write rather than read live.** The celebration is the
  /// receipt for one act; reading the provider inside it would let the figure change
  /// underneath the reader if anything else touched the set while it was up.
  int _celebratedStreak = 0;

  /// Guards the pair against a second tap while a sheet is already up.
  bool _recording = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    final days = ref.watch(readingDaysProvider).valueOrNull;
    final streak = ref.watch(currentStreakProvider);
    final longest = ref.watch(longestStreakProvider);
    final read = ref.watch(readTodayProvider);
    final today = readingDate(DateTime.now());

    // **Watched, not read, and that distinction was a bug.** The month colours each night by
    // its book's jacket, which means resolving a `book_id` against the library — and the
    // library arrives asynchronously. Read once during the first build it is still loading,
    // so every patch drew in neutral ink and nothing ever rebuilt the page to correct it. An
    // index rather than a list because the grid asks per day, and a linear scan per cell is
    // a scan per cell.
    final booksById = {
      for (final shelf
          in ref.watch(libraryProvider).valueOrNull ?? const <Shelf>[])
        for (final book in shelf.books) book.id: book,
    };

    return Scaffold(
      backgroundColor: colors.pageBackground,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _TopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Hero(streak: streak, read: read),
                        const SizedBox(height: 18),
                        // **A week beside a month, which is not the duplication it looks
                        // like.** The month is the record; the week is the run in progress,
                        // and seven cells is the span a reader counts without reading —
                        // which is what makes a gap on Thursday legible as a gap rather than
                        // as a pale square among thirty. Same renderer as the celebration's,
                        // so the week behind that screen and the week inside it cannot
                        // disagree.
                        ReadWeekRow(
                          days: _weekEndingToday(days ?? const {}, today),
                          endingOn: today,
                          palette: ReadWeekPalette.page(context),
                        ),
                        const SizedBox(height: 18),
                        _RecordRow(longest: longest),
                        const SizedBox(height: 16),
                        _MonthCard(
                          days: days ?? const {},
                          today: today,
                          booksById: booksById,
                        ),
                        // **The slack is left empty on purpose.** On a six-row month the
                        // content ends a long way above the button, and this is where a
                        // freeze chip or a share row would go if either ships. Inventing
                        // something to occupy it now would be furniture bought for a room
                        // nobody has moved into.
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: read
                      ? _DoneFooter(onUndo: _undoToday)
                      : SizedBox(
                          width: double.infinity,
                          child: ElevatedActionButton(
                            key: kStreakRecordButtonKey,
                            height: 50,
                            buttonText: l10n.streakRecordToday,
                            // The flame leads the label here the way it leads the chip, so
                            // the control and the figure it moves are visibly the same
                            // feature.
                            leading: const Icon(
                              kReadingStreakIcon,
                              size: 18,
                              color: Colors.white,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            onPressed: _recordToday,
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (_celebrating)
            Positioned.fill(
              child: StreakCelebration(
                streak: _celebratedStreak,
                week: _weekEndingToday(days ?? const {}, today),
                today: today,
                onDone: () => setState(() => _celebrating = false),
              ),
            ),
        ],
      ),
    );
  }

  /// The seven days ending today, oldest first.
  List<bool> _weekEndingToday(Map<DateTime, String?> days, DateTime today) => [
    for (var back = 6; back >= 0; back--)
      days.containsKey(DateTime(today.year, today.month, today.day - back)),
  ];

  /// Every book the reader owns, flattened out of the shelves.
  ///
  /// Read at the moment the picker opens rather than watched, because this is an *action*
  /// path: it wants whatever the library holds when the reader taps, and a rebuild of the
  /// page is not what should follow from it. The rendered month takes its own watched copy.
  ///
  /// Finished books are deliberately not fetched. They live in their own query
  /// (`finishedBooksProvider`) and pulling it in would make opening this page cost a second
  /// round trip for the sake of naming a book the reader is no longer reading. The
  /// consequence is stated where it shows: a month whose book has since been finished
  /// colours that day in neutral ink rather than guessing.
  List<Book> get _books => [
    for (final shelf
        in ref.read(libraryProvider).valueOrNull ?? const <Shelf>[])
      ...shelf.books,
  ];

  /// The mandatory pair: which book, then how far in.
  ///
  /// **Four taps, and they are spent rather than saved.** An earlier draft of this chased
  /// one. What changed is not the count but what the taps *are*: all four are the act
  /// itself rather than navigation through a book's form, and a second, shorter door exists
  /// for the reader who is holding the book.
  ///
  /// **Either sheet dismissed abandons the whole write.** A day stamped with no position
  /// after the reader walked away from the wheel would be a silent half-write, and the
  /// pair is either mandatory or it is not.
  Future<void> _recordToday() async {
    if (_recording) return;
    _recording = true;
    try {
      final books = _books;
      final book = await showPickReadingBookSheet(context, books: books);
      if (book == null || !mounted) return;

      // Set inside the sheet's own callbacks, read after the await. `confirmed` is not the
      // same fact as `answer`: a reader who agrees with the pre-filled value confirms the
      // step and writes no position, and `_touched` inside the sheet is what stops Confirm
      // from rewriting the column with the value it was already showing.
      var confirmed = false;
      ProgressAnswer? answer;
      await showSelectPercentBottomSheet(
        context,
        // Opens at the book's last known position, which is what keeps the cost honest: on
        // a night where the reader has not moved much, Confirm is one tap on a wheel
        // already showing roughly the right number.
        initialProgress: book.progress,
        initialPage: book.progressPage,
        pageCount: book.pageCount,
        onConfirmed: () => confirmed = true,
        onProgressSelected: (value) => answer = value,
      );
      if (!confirmed || !mounted) return;

      final today = readingDate(DateTime.now());
      // The day first, because `setRead` updates its set before the request goes out — so
      // the page's own figure and button answer instantly — and the position second,
      // through the narrow write that touches two columns and derives nothing.
      await ref
          .read(readingDaysProvider.notifier)
          .setRead(today, read: true, bookId: book.id);
      final value = answer;
      if (value != null) {
        await ref
            .read(libraryActionsProvider)
            .recordReadingPosition(
              book.id,
              progress: value.progress,
              progressPage: value.page,
            );
      }
      if (!mounted) return;

      // Read after the write rather than incremented: the figure is derived from the set,
      // and there is no counter here to get out of step with it.
      final days = ref.read(readingDaysProvider).valueOrNull ?? const {};
      setState(() {
        _celebratedStreak = currentReadingRun(days.keys, today);
        _celebrating = true;
      });
    } finally {
      _recording = false;
    }
  }

  Future<void> _undoToday() async {
    await ref
        .read(readingDaysProvider.notifier)
        .setRead(readingDate(DateTime.now()), read: false);
  }
}

/// The footer once the night is in: a confirmation, with the undo inside it.
///
/// **The undo lives where the act was made**, which is the rule this replaces a hidden
/// control with: `setRead(read: false)` is a real delete rather than a flag, so it has to be
/// reachable — and the place a reader looks for it is the place they just tapped. What it is
/// *not* is the primary slot: a green CTA reading "Undo today" advertises taking the night
/// back as the thing to do next.
class _DoneFooter extends StatelessWidget {
  const _DoneFooter({required this.onUndo});

  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        children: [
          Icon(Icons.check, size: 18, color: colors.brandText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.streakTodayDone,
              style: AppTextStyles.body.copyWith(color: colors.primaryText),
            ),
          ),
          TextActionButton(
            key: kStreakUndoKey,
            buttonText: l10n.streakUndoToday,
            textColor: colors.secondaryText,
            onPressed: onUndo,
          ),
        ],
      ),
    );
  }
}

/// ✕ and the page's name.
///
/// `xmark` rather than a chevron, and for the reason the scanner and the share card use it:
/// this is a presentation over the shell, so the gesture that ends it is dismissal rather
/// than going up a level. No grab handle, because a full-screen cover is not
/// drag-dismissible on iOS and an affordance for a gesture that does not exist is worse
/// than none.
class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          SizedBox(
            width: kIconButtonDiameter,
            child: AdaptiveIconButton(
              key: kStreakPageCloseKey,
              symbol: 'xmark',
              icon: Icons.close,
              diameter: kIconButtonDiameter,
              symbolSize: kIconButtonSymbolSize,
              iconSize: kIconButtonIconSize,
              iconColor: colors.primaryText,
              semanticLabel: l10n.close,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Expanded(
            child: Text(
              l10n.streakTitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.subtitle,
            ),
          ),
          // Balances the ✕ so the title is centred on the page rather than on what is left
          // of it.
          const SizedBox(width: kIconButtonDiameter),
        ],
      ),
    );
  }
}

/// The flame and the figure.
///
/// **The flame names the run, never a day.** That split is the whole reason a flame is
/// allowed here at all: the app owns four metaphors for *a day was recorded* — the ink
/// stamp, the lamp, the seal, the card — and a fifth borrowed one would compete with them.
/// What none of them says is *consecutive*, which a flame says instantly because the genre
/// taught everyone to read it. So the flame leads the number and the month below draws
/// stamps, not thirty flames.
class _Hero extends StatelessWidget {
  const _Hero({required this.streak, required this.read});

  final int streak;
  final bool read;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    // The chip's own rule, at the page's size: keyed on whether *today* is recorded, never
    // on the count. Warm once the night is in, grey while the day is still open.
    final tint = read ? colors.flame : colors.secondaryText;

    return Column(
      children: [
        Icon(kReadingStreakIcon, size: 44, color: tint),
        const SizedBox(height: 4),
        Text(
          '$streak',
          key: kStreakFigureKey,
          style: AppTextStyles.display.copyWith(color: colors.primaryText),
        ),
        // **Two lines, and the split is the point.** The bold line names what the figure
        // *is*, and it is the line that carries the day's status — which is what lets the
        // number stay honest all day. A run is intact until the day actually ends, so the
        // figure never drops at 9am; what changes at 9am is that the label says the day is
        // still open. The line under it is the encouragement, and it is the only place on the
        // page that asks for anything.
        Text(
          streak == 0 && !read
              ? l10n.streakNothingYet
              : read
              ? l10n.streakDays(streak)
              : l10n.streakDaysOpen(streak),
          textAlign: TextAlign.center,
          style: AppTextStyles.subtitle.copyWith(color: colors.secondaryText),
        ),
        const SizedBox(height: 2),
        Text(
          read ? l10n.streakTodayDone : l10n.streakTodayOpen,
          textAlign: TextAlign.center,
          style: AppTextStyles.label.copyWith(
            color: colors.secondaryText,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

/// The record a missed night does not erase.
class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.longest});

  final int longest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l10n.streakLongest, style: AppTextStyles.body),
          Text(
            l10n.streakDayCount(longest),
            style: AppTextStyles.body.copyWith(color: colors.secondaryText),
          ),
        ],
      ),
    );
  }
}

/// This month, its nights, and which books they were.
///
/// **The \u201clongest this month\u201d stat the Library Card's month carries is dropped here**, and
/// swapped for the book count. The hero above is already the run; without the swap the page
/// printed the same number three times, which is exactly the defect the design record exists
/// to catch. The Card keeps the stat, because nothing above it says the number.
class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.days,
    required this.today,
    required this.booksById,
  });

  final Map<DateTime, String?> days;
  final DateTime today;
  final Map<String, Book> booksById;

  /// The colour a recorded day is drawn in, or null when the book cannot be found.
  ///
  /// `cover_color` when the column has been filled in, and the ISBN-derived tone otherwise
  /// — the same fallback every cover in the app uses, so a day and its book agree on colour
  /// even before a cover has been decoded. Null for a night whose book is gone, which the
  /// grid draws in neutral ink rather than dropping.
  Color? _colourOf(String? bookId) {
    final book = bookId == null ? null : booksById[bookId];
    if (book == null) return null;
    return book.coverColor ?? generatedCoverColor(book.isbn);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final materialL10n = MaterialLocalizations.of(context);
    final month = DateTime(today.year, today.month);

    final inMonth = {
      for (final entry in days.entries)
        if (entry.key.year == month.year && entry.key.month == month.month)
          entry.key: entry.value,
    };

    final marks = {
      for (final entry in inMonth.entries) entry.key: _colourOf(entry.value),
    };

    // One entry per book, with how many of this month's nights it accounts for. Insertion
    // order is the map's, which is the query's own `day` order — so the legend reads newest
    // book first, matching the grid the reader is looking at.
    final nights = <String, int>{};
    for (final bookId in inMonth.values) {
      if (bookId == null) continue;
      nights[bookId] = (nights[bookId] ?? 0) + 1;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // **Sans at 17, not the record's 15pt serif, and the scale is why.** `.cnav b` is
          // Georgia 15 — a quiet serif header. The scale's serif tokens start at `spine` 12
          // and jump to `titleVisit` 20: 12 would put the card's heading *below* its own 13pt
          // stat figures, and 20 inside a 14pt-padded card next to them is a shout. So this
          // takes `subtitle`, which is the page's own section voice (`_TopBar` uses it), and
          // loses the serif. Worth revisiting if the scale ever grows a small serif head.
          //
          // **The ‹ › pagers the record draws are deliberately absent.** They imply
          // `readingDaysProvider` can be asked for an arbitrary month, and it cannot — it
          // holds one window. Drawing the control before the query exists would be an
          // affordance for something that does nothing, which is the mistake the grab handle
          // on this page's cover would have been.
          Text(
            materialL10n.formatMonthYear(month),
            style: AppTextStyles.subtitle,
          ),
          const SizedBox(height: 10),
          // **Two facts off the same stamps, and the one that is missing is the run.** The
          // Library Card's month carries "longest this month" here; the hero above *is* the
          // run, so keeping it made the page print one number three times — exactly the
          // defect the design record exists to catch. The book count is a different fact.
          Row(
            children: [
              Expanded(
                child: _MonthStat(
                  figure: l10n.streakMonthDaysRead(inMonth.length),
                  caption: l10n.streakMonthDaysReadCaption,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MonthStat(
                  figure: l10n.streakBooksThisMonth(nights.length),
                  caption: l10n.streakMonthBooksCaption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ReadCalendarMonth(month: month, marks: marks, today: today),
          if (nights.isNotEmpty) ...[
            const SizedBox(height: 10),
            // The legend is what makes the colours mean anything: without it the month is a
            // handsome tally that cannot say one word about what was read, which is the
            // state the whole `book_id` decision exists to get out of.
            //
            // **Spines, not swatches — and spines that read as spines.** A swatch in the
            // patch's own 22%/50% grammar was the obvious first choice, and it was wrong
            // twice over: at 12pt a fifth-strength wash is barely a colour, and the app's
            // entire vocabulary for *a book* is a cover seen edge-on.
            //
            // **The reader's follow-up was whether these should be covers**, and four
            // alternatives were drawn for it (groups (g) and (g+)). Three used an 18x27
            // thumbnail and all three lost: at that size a jacket is a coloured chip, so
            // the title beside it still did the recognising, while the row cost 27pt
            // instead of 15 and put this card's first network image on a surface that is
            // otherwise vectors and text. What won was widening the spine until its
            // binding and fore edge are visible — see [_LegendSpine]. The row wraps
            // rather than stacking, so five books is two lines and not five rows of
            // mostly empty space.
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final entry in nights.entries)
                  _LegendSpine(
                    colour: _colourOf(entry.key) ?? colors.secondaryText,
                    title: booksById[entry.key]?.title ?? '',
                    nights: entry.value,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One of the month's two stat tiles: a figure over what it counts.
///
/// The record's `.cstats s` — a bordered box on a faintly tinted ground, both stats the same
/// width, so neither reads as the more important one.
class _MonthStat extends StatelessWidget {
  const _MonthStat({required this.figure, required this.caption});

  final String figure;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceVariant.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // `label` for the figure, because it is the token that carries tabular figures —
          // which is what keeps two tiles' numbers from sitting at different widths.
          Text(figure, style: AppTextStyles.label),
          // `caption` is *the* uppercase letterspaced stat label, and this is a stat label:
          // its own doc says to pass natural case and uppercase at the call site, which is a
          // no-op on Korean and the reason the casing is not baked into the l10n string.
          Text(
            caption.toUpperCase(),
            style: AppTextStyles.caption.copyWith(color: colors.secondaryText),
          ),
        ],
      ),
    );
  }
}

/// The legend's mark: one book's jacket colour, drawn as a spine.
///
/// **Public and separate from its row**, for the reason [ReadCalendarStampDie] is: it is the
/// object a future Library Card legend would want, and a Card that drew its own spine is
/// exactly the drift that would follow. Being nameable is also what lets a golden review
/// the anatomy without reaching into a private class.
///
/// **The anatomy is the point, and it is what a widened rectangle does not have.** This
/// shipped as a 5x15 rounded rectangle in the book's colour — a correct colour key and not
/// much else. Four alternatives were drawn (`docs/mockups/streaks/index.html`, groups (g)
/// and (g+)), three of them replacing it with an 18x27 cover, and the finding was that **at
/// that size a jacket is a coloured chip**: the photo cover renders as a plain dark
/// rectangle and a typeset one carries type too small to read, so the title beside it was
/// still doing all the recognition work. The covers paid a cover's costs — a 27pt row
/// instead of 15, three rows instead of two on a five-book month, and the card's first
/// network image on a surface that is otherwise all vectors and text — and collected a
/// swatch's benefit.
///
/// What won was widening this until **the two details that make a spine legible as a book**
/// have room: the binding strip at its hinge and a sliver of page block at its fore edge.
/// It reads as a book standing on a shelf where the 5pt version read as a rounded tick, and
/// it keeps the key perfect, because one flat hue beside a ring of the same hue is
/// unambiguous in a way mixed artwork is not.
///
/// **What it costs is width, not height.** At 17pt tall the card does not grow, but each
/// entry is 4pt wider, so a three-book month wraps to two rows where the 5pt version fit
/// one. That is cheap beside a cover's row and it is not free; the tuning knob if it ever
/// matters is [width], and the drawings note 7pt as the value worth trying first.
class ReadLegendSpine extends StatelessWidget {
  const ReadLegendSpine({super.key, required this.colour});

  /// The book's `cover_color`, at full strength — the grid's ring is the same hue, which
  /// is what makes the key work.
  final Color colour;

  /// The spine's width. 9pt is what the drawing settled on: at 5 the binding strip and
  /// fore edge have no room to be seen, which is the whole reason the widening happened.
  static const double width = 9;

  /// And its height. Unchanged from the 5x15 original at 17, so the legend's line box and
  /// the card's height do not move — the change is horizontal only.
  static const double height = 17;

  /// The binding strip's share of [width], as the drawing's own 22%. Proportional rather
  /// than absolute so tuning [width] cannot leave a hinge the wrong size for the spine it
  /// is on.
  static const double bindingShare = 0.22;

  @override
  Widget build(BuildContext context) {
    // The app's own page-block tone rather than a typed cream, and that matters in dark
    // mode: `BookChassisColors` deliberately does not use `surfaceVariant` there, because
    // a page block in the surface's own colour makes the fore edge disappear. Reusing it
    // means this 1.5pt sliver is the same paper every cover in the app shows.
    final paper = BookChassisColors.of(context).pageBase;
    return Container(
      width: width,
      height: height,
      // Clipped so the binding and the fore edge stop at the spine's own corners. The
      // shadow is the decoration's, painted outside the clip, so it survives — unlike the
      // design record's first cut of the stamped legend, where a mark hung over a clipping
      // box vanished entirely and every check still passed.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colour,
        // Rounded on the fore edge and square at the hinge, which is the silhouette a book
        // seen edge-on actually has.
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(1),
          right: Radius.circular(2),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x42000000),
            offset: Offset(0.5, 0.5),
            blurRadius: 1.5,
          ),
        ],
      ),
      child: Stack(
        children: [
          // The binding, at the hinge: a shadow in the gutter where the boards fold, which
          // is what tells the eye which end of the spine is the spine.
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: bindingShare,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0x4D000000), Color(0x0D000000)],
                  ),
                ),
              ),
            ),
          ),
          // The fore edge: the leaves, held off the head and tail by a point so the boards
          // read as standing slightly proud of the pages — which is what they do, and what
          // stops the sliver reading as a gap in the colour.
          Positioned(
            top: 1,
            bottom: 1,
            right: 0,
            width: 1.5,
            child: ColoredBox(color: paper.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }
}

/// One book in the month's legend: its spine, its title, and how many nights it holds.
class _LegendSpine extends StatelessWidget {
  const _LegendSpine({
    required this.colour,
    required this.title,
    required this.nights,
  });

  final Color colour;
  final String title;
  final int nights;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReadLegendSpine(
          key: ValueKey('streak-legend-spine-$title'),
          colour: colour,
        ),
        const SizedBox(width: 6),
        // Constrained, because a long title in a `Wrap` child with no bound is a child
        // wider than the `Wrap` and an overflow rather than a new line.
        //
        // `spine` is the token — 12pt serif, the style the app sets a book's own spine in,
        // beside a drawing of one. The record's 10.5px sans would need a size the scale does
        // not have, and this is closer to the voice anyway.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.spine.copyWith(color: colors.secondaryText),
          ),
        ),
        const SizedBox(width: 4),
        // Natural case, where the stat tiles' captions are uppercased: `caption`'s convention
        // is for the *label* that names a figure, and this is the figure. Shouting the value
        // beside a quietly-set title inverts which of the two is the fact.
        Text(
          AppLocalizations.of(context).streakNightsThisMonth(nights),
          style: AppTextStyles.caption.copyWith(
            color: colors.secondaryText.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
