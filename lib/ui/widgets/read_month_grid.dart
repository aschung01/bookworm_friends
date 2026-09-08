import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';

/// One month's read books: a name, a count, and the covers.
class ReadMonth {
  /// First day of the month, or `null` for the group of books that are finished
  /// but carry no finish date.
  final DateTime? month;
  final List<Book> books;

  const ReadMonth({required this.month, required this.books});
}

/// The read view's **expanded** state: covers grouped by the month they were
/// finished in, newest first.
///
/// This is the body the sheet shows at its **medium and expanded** positions — the
/// pile is the collapsed one — and the two are never on screen together, which is
/// what lets the covers here be Heroes: `LibrarySheet` swaps one body for the other
/// rather than stacking them, so a tag in this grid cannot meet the same tag in the
/// pile. See [_flyableIsbns] for the one thing that still has to be checked.
///
/// Lazy on purpose. The sheet hands this a bounded height, so a `ListView` builds
/// only the rows that fit rather than every cover a heavy reader owns — which
/// matters because each [BookWidget] loads an image through its own
/// `ImageStream`. A `Column` inside a `SingleChildScrollView` would build all of
/// them.
///
/// A `ConsumerWidget` only so that a decoded cover can report its colour back to
/// `books.cover_color`. Nothing here watches a provider.
class ReadMonthGrid extends ConsumerWidget {
  final List<ReadMonth> months;

  /// Extra room at the bottom, so the last row clears whatever floats over the
  /// sheet.
  final double bottomPadding;

  /// Which year is being shown, or `0` for all time — the same convention as
  /// `libraryCardStats` and [ReadFilter], so nothing here can disagree about what
  /// a year means.
  ///
  /// Two things read it. Month headers spell out their year only under all time,
  /// where a name alone would leave months from different years
  /// indistinguishable; once a year is selected it is already stated once, above
  /// the grid. And the empty state needs to say which year is empty rather than
  /// claiming the reader has never finished a book.
  final int filterYear;

  const ReadMonthGrid({
    super.key,
    required this.months,
    this.bottomPadding = 0,
    this.filterYear = 0,
  });

  /// Four across, at the 2:3 the drawings use.
  static const int _columns = 4;
  static const double _coverAspect = 2 / 3;
  static const double _gap = 10;

  /// The ISBNs entitled to fly to the details page: those belonging to **exactly
  /// one** book in the grid, and not the empty string.
  ///
  /// The details header is a Hero tagged `book_<isbn>`, so a cover here can fly to
  /// it by taking the same tag — but unlike the pile, which turns one book out at a
  /// time and tags only that one, this grid renders every read book at once. Two
  /// books under one tag on a route is a Flutter assertion, not a design problem,
  /// and there are two ordinary ways to get there: a book finished twice (a reread,
  /// or simply two rows for one title), and a book with **no ISBN at all**, which
  /// tags as `book_` — 15 of the migrated rows have none, so a grid of them is a
  /// grid of identical tags.
  ///
  /// Both copies lose the flight rather than the first one keeping it. Tagging the
  /// first occurrence would still animate, but from whichever cell happened to be
  /// built first — so tapping the second copy would send a cover across the screen
  /// from a cell the finger never touched, which is worse than not moving. A book
  /// with no source hero simply arrives on the details page, which is what every
  /// book in this grid did before.
  ///
  /// Computed over `months` rather than per row: uniqueness is a fact about the
  /// whole route, and the grid is built lazily, so a per-row answer would depend on
  /// how far the reader had scrolled.
  ///
  /// What it deliberately does **not** check is the shelves behind the sheet, which
  /// tag their covers the same way. It does not have to for the ordinary case —
  /// `withoutFinishedBooks` keeps every book in this grid off them, so the two sets
  /// are disjoint by status — and it could not check the pathological one: an ISBN
  /// held by both a finished row and a shelved row is the same collision two
  /// *shelved* copies would already be, and the shelves have always assumed an ISBN
  /// names one book in a library.
  Set<String> _flyableIsbns() {
    final once = <String>{};
    final more = <String>{};
    for (final month in months) {
      for (final book in month.books) {
        if (book.isbn.isEmpty) continue;
        if (!once.add(book.isbn)) more.add(book.isbn);
      }
    }
    return once.difference(more);
  }

  /// Groups by finish date, newest month first.
  ///
  /// Undated books get their own trailing group rather than being dropped. The
  /// header shows a count, and silently omitting rows from a total the user can
  /// see is the kind of bug nobody reports — they just distrust the number.
  static List<ReadMonth> group(List<Book> books) {
    final byMonth = <DateTime, List<Book>>{};
    final undated = <Book>[];
    for (final book in books) {
      final finished = book.finishDate;
      if (finished == null) {
        undated.add(book);
        continue;
      }
      final key = DateTime(finished.year, finished.month);
      byMonth.putIfAbsent(key, () => []).add(book);
    }
    final keys = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final key in keys) ReadMonth(month: key, books: byMonth[key]!),
      if (undated.isNotEmpty) ReadMonth(month: null, books: undated),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (months.isEmpty) {
      // Centred in the sheet's *visible* height rather than in the box this body was
      // laid out at, so the line tracks the card through a drag instead of sitting at
      // the middle of the expanded state and jumping every time the sheet settles.
      // See [SheetBodyCenter].
      return SheetBodyCenter(
        child: Text(
          // **A filtered year that is empty is not the same claim as a library
          // that is empty.** "No books read yet" is a nudge for someone who has
          // never finished anything, and it was wrong in both halves once empty
          // years became selectable: "yet" is forward-looking at a year that is
          // already over, and the reader may well have read that year and simply
          // never added the book. All this view can honestly say is that it holds
          // no record for the year.
          filterYear == 0
              ? l10n.noFinishedBooks
              : l10n.noFinishedBooksInYear(filterYear),
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(
            color: context.colors.secondaryText,
          ),
        ),
      );
    }

    final flyable = _flyableIsbns();

    return ListView.builder(
      // Lets `LibrarySheet` decide whether a swipe scrolls this or opens the sheet:
      // without it the constructor bakes in `AlwaysScrollableScrollPhysics` and the
      // grid scrolls at every detent. See [LibrarySheet.body].
      primary: false,
      padding: EdgeInsets.only(bottom: bottomPadding),
      itemCount: months.length,
      itemBuilder: (context, index) {
        final group = months[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.month == null
                            ? l10n.readNoDate
                            : filterYear == 0
                            ? l10n.monthYearLabel(
                                group.month!.year,
                                '${group.month!.month}',
                              )
                            : l10n.monthLabel('${group.month!.month}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // [AppTextStyles.label], not `subtitle`, even though this
                        // is a section heading and `subtitle` is the token for
                        // one. `subtitle` is what [LibrarySheetTitle] uses, and
                        // that title is pinned in the header directly above this
                        // list — matching it would put the scrolling month
                        // dividers at the same size and weight as the sheet they
                        // scroll inside, which is a flat hierarchy rather than a
                        // legible one.
                        style: AppTextStyles.label,
                      ),
                    ),
                    Text(
                      '${group.books.length}',
                      // Same token as the month beside it; the distinction moved
                      // from weight (bold vs normal) to colour, because these two
                      // are a heading and its annotation rather than two levels of
                      // heading. `label` also carries tabular figures, which is
                      // what stops a column of `1`-heavy and `8`-heavy counts from
                      // sitting at different widths down the right edge.
                      style: AppTextStyles.label.copyWith(
                        color: context.colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              GridView.builder(
                // The outer list scrolls; each month's grid is laid out at its
                // natural height inside it.
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _columns,
                  childAspectRatio: _coverAspect,
                  crossAxisSpacing: _gap,
                  mainAxisSpacing: _gap,
                ),
                itemCount: group.books.length,
                itemBuilder: (context, i) {
                  final book = group.books[i];
                  return LayoutBuilder(
                    builder: (context, constraints) => BookWidget(
                      imageUrl: book.thumbnail,
                      isbn: book.isbn,
                      title: book.title,
                      height: constraints.maxHeight,
                      pageCount: book.pageCount,
                      // Uniform heights, each book's own thickness.
                      //
                      // The cells are already a uniform 2:3, so the shelf's
                      // height jitter has nothing to vary against here and only
                      // makes neighbouring covers look misaligned. Thickness is a
                      // separate question with the opposite answer: it is only
                      // visible edge-on, so it moves no cover, and a book held in
                      // the grid turns far enough to show its fore-edge. Under a
                      // plain `jitter: false` that fore-edge was the thinnest in
                      // the range for every book on the screen. This is the same
                      // thickness the shelves and the pile draw the book at — one
                      // resolution, so the three cannot disagree.
                      //
                      // Harmless for the flight below, which is the one thing that
                      // might have cared: `BookMetrics` derives width from height,
                      // so both ends of the flight share an aspect ratio whatever
                      // the jitter, and the shuttle builds the *destination's*
                      // subtree — so the fore-edge that lands is the details
                      // page's own either way.
                      jitterOverride: BookJitter.fromIsbn(
                        book.isbn,
                        pageCount: book.pageCount,
                      ).atNeutralHeight,
                      // Every book in this grid is the signed-in reader's own, so
                      // this is the densest backfill path in the app: one screen
                      // of the read view can fill in a dozen rows.
                      onCoverSampled: (color) => ref
                          .read(libraryActionsProvider)
                          .recordCoverColor(book, color),
                      // The tapped cover flies to the details page's header,
                      // rather than vanishing here while a different one appears
                      // there. Withheld from a book whose tag would be ambiguous;
                      // see [_flyableIsbns].
                      heroTag: flyable.contains(book.isbn)
                          ? 'book_${book.isbn}'
                          : null,
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.details,
                        arguments: book,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
