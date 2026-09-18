import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/library_card_stats.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_cover_row.dart';
import 'package:bookworm_friends/ui/widgets/library_card/stat_tile.dart';

/// The Library Card's contents: a hero tile and whatever tiles have something true
/// to say.
///
/// **Built for a thin card, which is the common case.** The drawings show a reader
/// with 12 books, 4,180 pages and a favourite novelist. The real distribution is
/// harsher: the median reader here has finished **two** books, 57% of finished books
/// were logged same-day so they contribute no reading span, and 40 of the 53 readers
/// with author data have a "top author" who wrote exactly one of their books. So at
/// the median this renders a hero and one tile, and at n=1 it may render a hero
/// alone.
///
/// That is the design, not a degradation. Every tile is omitted rather than
/// zero-filled, and the row below the hero gives its tiles `Expanded` slots so a
/// lone tile takes the full width instead of sitting in a half-width box beside a
/// hole.
///
/// **The one figure that is zero-filled is the hero's, and only because it is a
/// count.** A year the reader finished nothing in still renders a card, reading 0 —
/// see [build]. The omit-rather-than-zero-fill rule is about *derived* figures, whose
/// zero would be a claim the sample cannot support; a count of nothing is just true.
///
/// **The hero now previews the artifact rather than charting it,** which is why this
/// takes [books] at all. It carries a row of the reader's covers, so what the sheet
/// shows and what share produces are recognisably the same object; before this, a
/// reader tapped share on a green rectangle and got something they had never seen.
///
/// **The covers are the whole of that resemblance now — the hero prints none of the
/// card's lettering.** It used to carry the artifact's stamp line under its label, on
/// the reasoning that the printed furniture is what makes a preview a preview. It was
/// saying the card's name twice: the label already reads `ALL-TIME LIBRARY CARD` in
/// `en` and `전기간 도서관 카드` in `ko`, and the line beneath it added
/// `LIBRARY · CARD` and `도서관 카드` to those. The artifact keeps the line because
/// *its* title is English in both locales, so a Korean reader learns something from it
/// — see `cardStampLine`. Here there is nothing left for it to add.
///
/// Still deliberately holds **no** read-books list — read books belong entirely to
/// the Library tab. Covers are not that list: they are unordered, unlabelled, capped
/// at [kCardCoverMax] and not tappable. The rule was "no second home for the same
/// rows", and a row of spines is not a home.
class LibraryCardBody extends StatelessWidget {
  final LibraryCardStats stats;

  /// Every finished book, unfiltered — the same list the sheet derives [stats] from.
  /// Filtered here by [year] through `booksInCardYear`, the same rule
  /// [libraryCardStats] counts by, so the covers and the hero figure cannot disagree.
  final List<Book> books;

  /// The selected year, `0` for all time. Drives the hero's label — which would
  /// otherwise say "all-time" over a single year's figures — and which of the
  /// reader's covers the hero previews.
  final int year;

  /// The books the reader has open right now.
  ///
  /// Drawn at the front of the hero's shelf wearing a bookmark, and **not year-filtered**:
  /// an open book has no finish date, so there is no year to filter it into. [stats] does
  /// not count them either — the hero figure is a count of books *read*.
  final List<Book> reading;

  /// The run of consecutive reading days that is still alive, and the record.
  ///
  /// **Not part of [stats], and that is deliberate rather than an oversight.**
  /// `LibraryCardStats` is derived from `books`; a run is derived from `reading_days`,
  /// which is a different table read through a different provider. Folding it in would
  /// give that class a second source and make every one of its pure-function tests need
  /// a set of days it has no opinion about.
  ///
  /// **Not year-filtered either**, unlike everything else on the card. A run is a fact
  /// about now; "your longest streak in 2024" is a different feature. That is a real
  /// inconsistency on a year-scoped surface, and it is the same tension that leaves the
  /// month grid without a home — see the note on the tile below.
  final int streak;

  /// The longest run on record, which a missed night does not erase.
  final int longestStreak;

  /// How the reader has chosen to see the books they have finished.
  const LibraryCardBody({
    super.key,
    required this.stats,
    this.books = const [],
    this.year = 0,
    this.reading = const [],
    this.streak = 0,
    this.longestStreak = 0,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // **The message is for a reader with nothing, not for a filter that found
    // nothing** — which is why the test is [books] rather than [stats].
    //
    // The rail offers every year back to the earliest finish, gaps included, so
    // selecting a year you finished nothing in is an ordinary thing to do, and more
    // ordinary still now that a swipe across the card does it. Answering that with a
    // line of grey copy got two things wrong. It told a reader with a full library
    // that their reading stats would live here one day, which is false. And it
    // *removed the card* — the one object this tab exists to show, and the thing a
    // swipe is flicking through — so paging across an empty year made the card blink
    // out of existence and back.
    //
    // So an empty year renders the card, reading 0. The furniture is the answer: the
    // hero is already labelled with the year, and `0 / books` under it is a count
    // rather than an inference — it is simply true, in the way a zero-filled *pace*
    // or a one-book "most-read author" would not be. That distinction is what the
    // omit-rather-than-zero-fill rule on this class is actually about, and the tiles
    // below still obey it: at 0 books neither has a sample, so the hero stands alone.
    //
    // It is also what the share button already does at this exact moment — it stays
    // put and goes inert rather than vanishing, because moving the furniture is worse
    // than showing a control that cannot be used. Seeing the empty card beside the
    // dimmed button is the whole explanation of why it is dimmed.
    if (books.isEmpty) {
      return _Empty(message: l10n.libraryCardEmpty);
    }

    final numbers = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    );

    // The books the hero is about, by the one rule [stats] counted by — hoisted
    // because the cover row and the *presence* of the cover row are now two
    // questions, and asking `booksInCardYear` twice is how they would come to
    // disagree.
    final shown = booksInCardYear(books, year);

    // "books · 86 days reading", and just "books" when nothing has a real span.
    // The unit is separate from the figure because the figure is the hero's whole
    // point and lives at 46pt, while its unit belongs with the small print.
    final parts = <String>[l10n.libraryCardBooksUnit(stats.booksRead)];
    if (stats.daysReading > 0) {
      parts.add(l10n.libraryCardDaysReading(stats.daysReading));
    }

    final tiles = <Widget>[
      // **A peer of Pace, never the hero.** `booksRead` stays the 46pt figure —
      // settled by looking at the shipped widget rather than by arguing about it. A
      // streak is a fact about this fortnight; the card's subject is a library.
      //
      // **Omitted, never zero-filled**, per this class's own rule: a run of 0 is not a
      // small streak, it is the absence of one, and every account in this database is
      // on day one. A `0d` tile would be the *normal* first-run state.
      //
      // **The month grid does not go here**, and that is a decision rather than a
      // gap. This card is year-scoped and its label reads "All-time library card", so
      // a month pager inside it would put two conflicting time scales on one surface.
      // The grid needs a destination of its own, which is an open question and not a
      // task.
      if (streak > 0)
        StatTile(
          label: l10n.libraryCardStreak,
          figure: l10n.libraryCardStreakValue(streak),
          // Carries the record as well as the run. With freezes deferred a single
          // missed night severs a run outright, so this is the only figure on the card
          // that survives the night that reset everything else — without it a reader
          // who missed one Thursday sees a fortnight of reading reduced to `1d`.
          sub: l10n.libraryCardStreakSub(longestStreak),
        ),
      if (stats.hasPace)
        StatTile(
          label: l10n.libraryCardPace,
          // Rounded to whole days. A pace of "6.5d per book" implies a precision
          // the input does not have — these are calendar dates, and over half of
          // them are the day the book was logged rather than the day it was
          // finished.
          figure: l10n.libraryCardPaceValue(stats.pace!.round()),
          sub: l10n.libraryCardPaceSub(stats.paceSampleSize),
        ),
      if (stats.hasTopAuthor)
        StatTile(
          label: l10n.libraryCardTopAuthor,
          figure: stats.topAuthor!,
          figureIsText: true,
          sub: l10n.libraryCardAuthorBooks(stats.topAuthorCount),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        StatTile(
          variant: StatTileVariant.hero,
          label: year == 0
              ? l10n.libraryCardHeroAllTime
              : l10n.libraryCardHeroYear(year),
          figure: numbers.format(stats.booksRead),
          sub: parts.join(' · '),
          // `start` rather than centred, per the drawings: inside the hero the row
          // sits under the sub-line and reads as part of the same left-aligned
          // block. On the artifact it is centred, because there it *is* the block.
          //
          // Withheld rather than handed an empty list, which an empty year would
          // otherwise do. [CardCoverRow] shrinks to nothing on its own, but
          // [StatTile] pays for a non-null footer with 12pt above it — so an empty
          // year would end in a strip of blank card under the figure, which reads as
          // a row that failed to load rather than as a row that is not there.
          footer: shown.isEmpty && reading.isEmpty
              ? null
              : CardCoverRow(
                  books: shown,
                  reading: reading,
                  alignment: MainAxisAlignment.start,
                  // **One board, and no board drawn under it.** In here the shelf is
                  // a footer inside a tile that has furniture of its own; on the
                  // artifact it *is* the object, and gets both boards and the boards
                  // painted. Two boards in a stat tile would also mean two rows of
                  // covers under a figure, which reads as a chart again.
                  maxBoards: 1,
                  showBoards: false,
                  // No taller than the figure it stands under. Without a ceiling the
                  // shelf takes its height from the width it is given, which in a
                  // tile 300pt wide is a 78pt row of covers under a 46pt figure — the
                  // footer becoming the hero. Nothing is squeezed to meet it: the
                  // whole drawing scales, so the covers keep their aspect and their
                  // proportion to each other and simply arrive smaller.
                  maxHeight: AppTextStyles.display.fontSize,
                ),
        ),
        if (tiles.isNotEmpty) ...[
          const SizedBox(height: 10),
          // **At most two per row, which is new and is forced by there now being a
          // third tile.** One tile fills the width and two split it — both unchanged.
          // Three used to be unreachable, and letting them share one row would give
          // each about 97pt of a 310pt card: "Most-read author" wraps to three lines in
          // that and the name under it wraps again, so the widest tile in the set would
          // be the one squeezed hardest. A second row costs 10pt and keeps every tile
          // at a width its contents were drawn for.
          for (var start = 0; start < tiles.length; start += 2) ...[
            if (start > 0) const SizedBox(height: 10),
            // `IntrinsicHeight`, and it is not decoration. The row wants
            // `CrossAxisAlignment.stretch` so two tiles are the same height whatever
            // their contents — an author's name wraps to two lines and a pace never
            // does — but a `Row` inside a min-height `Column` is offered unbounded
            // height, and `stretch` against unbounded height is
            // "BoxConstraints forces an infinite height". Measuring the tallest child
            // first is what makes stretch legal here.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (
                    var i = start;
                    i < start + 2 && i < tiles.length;
                    i++
                  ) ...[
                    if (i > start) const SizedBox(width: 10),
                    // Expanded, so one tile fills the width and two split it. The
                    // alternative — a fixed half-width tile — leaves a hole beside
                    // itself for the majority of readers, who have only one.
                    Expanded(child: tiles[i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// What a reader with **nothing finished at all** sees, in place of the card.
///
/// The narrow case, deliberately. A year that happens to be empty still gets a card
/// reading 0 — [LibraryCardBody.build] says why at length. This is the state where
/// there is no card to draw and nothing to be scoped to: an onboarding moment rather
/// than a data one, which is why it is a promise rather than a figure.
///
/// Kept close to what Phase 1 shipped, and not rare: every new user starts here, and
/// 213 of the 624 migrated books are still on a want-to-read shelf.
class _Empty extends StatelessWidget {
  final String message;

  const _Empty({required this.message});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(
            color: context.colors.secondaryText,
          ),
        ),
      ),
    );
  }
}
