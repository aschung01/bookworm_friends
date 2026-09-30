import 'dart:math' as math;

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

/// Length of the dog-ear's legs, as a fraction of the cover's width.
///
/// From the drawing, which folds 20pt off a 74pt cover. Proportional rather than flat,
/// the same rule every other mark on a book here follows: a fold that is a quarter of
/// one cover has to be a quarter of every cover, or the grid's uniform cells would be
/// the one place in the app where a book's marks do not scale with it.
const double kReadDogEarRatio = 20 / 74;

/// Width of the shadow the folded corner casts on the page it came off, as a fraction
/// of [kReadDogEarRatio]'s leg.
///
/// The drawing spends 6% of a 225° gradient on it against the 50% the flap takes, which
/// over a square of side *l* is `0.06 * l * sqrt(2)` — 8.5% of the leg.
const double _kDogEarShadowRatio = 0.085;

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

  /// Whether the sheet above this grid is in its finished-only mode.
  ///
  /// Read for one thing: which of the two all-time empty states to draw. The read
  /// sheet's title is the read-out of a completion filter — `Books finished` against
  /// `Books read` — and the empty line has to follow it, or the sheet says "No books
  /// read yet" under a `Books finished` title. See `ReadSetFilter`.
  ///
  /// The year-specific line needs no mode: "No books recorded for 2025" is true of
  /// either set, and it is already the narrower claim — see the note on it below.
  ///
  /// **Defaults to false, which is the wording this grid had before the filter
  /// existed.** A default matching the sheet's own default would silently re-word every
  /// other caller, and the callers that do not have a completion filter — the render
  /// previews, a grid pumped on its own — are exactly the ones with no answer to give.
  final bool finishedOnly;

  const ReadMonthGrid({
    super.key,
    required this.months,
    this.bottomPadding = 0,
    this.filterYear = 0,
    this.finishedOnly = false,
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

  /// [cover] with its head-and-fore-edge corner folded down, for a book that was set
  /// aside.
  ///
  /// **Keyed on the book's own status, not on a set handed down from the sheet.** The
  /// sheet merges two queries to build this grid, so a passed-in set of ids would be a
  /// second answer free to disagree with the first; `status == bookStatusSetAside` is
  /// the fact itself.
  ///
  /// **Deliberately not the bookmark ribbon.** That mark means *actively reading* on
  /// the shelf, on the Library Card and on the home-screen widget, so reusing it for a
  /// book nobody is reading any more would say the opposite of what it says everywhere
  /// else. The fold is also what stops `Books read 29` being read as 29 completions,
  /// which is the whole reason a mark is needed at all.
  ///
  /// **Drawn by the grid rather than by the book, which is the one compromise here.**
  /// `BookWidget.bookmarked` records why the ribbon moved *into* the book: hung by each
  /// caller as a sibling of the cover it sat outside the [Hero], so an opened book
  /// arrived on the details page without it, and it floated flat over a cover turned
  /// under a finger. Both apply to this fold: it does not fly, and it does not turn. It
  /// is drawn here because the fold is a statement this *view* makes — the grid is the
  /// one surface that shows finished and set-aside books side by side, and the details
  /// page says the same thing in words with a status badge. If it is ever judged worse
  /// than the ribbon's own history says it should be, the fix is a flag on [BookWidget]
  /// beside `bookmarked`, not more geometry in here.
  ///
  /// What being outside the [Hero] actually costs, measured rather than feared: a source
  /// hero is replaced by an *invisible* placeholder for the length of a flight, so for
  /// ~300ms the fold is drawn over an empty cell. It is nearly invisible when it happens,
  /// because the flap's colour is the ground the empty cell shows — all that is left is
  /// the shadow's ~2pt diagonal hairline. That is the second thing [ReadDogEar]'s choice
  /// of fill buys, after working in both themes.
  Widget _dogEared(Book book, Widget cover) {
    if (book.status != bookStatusSetAside) return cover;
    return Stack(
      // Passthrough, not the default `loose`: the cell hands this a tight box and the
      // book sizes itself from the constraints it is given, so a loose stack would let
      // the cover shrink to its own metrics and the fold would no longer be on its
      // corner.
      fit: StackFit.passthrough,
      children: [
        cover,
        const Positioned.fill(child: ReadDogEar()),
      ],
    );
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
              ? (finishedOnly ? l10n.noBooksFinished : l10n.noFinishedBooks)
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
                    builder: (context, constraints) => _dogEared(
                      book,
                      BookWidget(
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

/// The fold, drawn over a cover's head-and-fore-edge corner.
///
/// Sized by its parent — it paints into whatever box it is given, which in the grid is
/// the cover's own cell. Public so a test can find it by type and a preview can draw it
/// beside a finished cover; it carries no state and no parameters, because both of its
/// colours are decisions rather than inputs. See [ReadMonthGrid._dogEared] for why the
/// grid draws this rather than the book drawing it.
class ReadDogEar extends StatelessWidget {
  const ReadDogEar({super.key});

  @override
  Widget build(BuildContext context) {
    // A `CustomPainter` answers a hit test `true` by default, so without this the fold
    // would swallow the taps aimed at the corner of the cover it covers — and the
    // cover's whole job here is to open the book.
    return IgnorePointer(
      child: CustomPaint(
        painter: _DogEarPainter(
          // The sheet's own ground, so the corner reads as *removed* rather than as a
          // pale sticker laid on the jacket — which is also what makes it work in both
          // themes without a second colour: the fold is whatever is behind the grid.
          fold: context.colors.sheetBackground,
          // A cast shadow, so black in both themes: the flap is above the cover whatever
          // colour the page behind it is. It does the most work of the two on a cover
          // that happens to match the sheet, where the flap itself is invisible and this
          // line is the fold.
          shadow: Colors.black.withValues(alpha: 0.28),
        ),
      ),
    );
  }
}

/// The fold itself: a triangle of the ground showing through the cover's corner, and
/// the shadow the flap casts on the page it was folded off.
///
/// Painted rather than composed out of boxes because a diagonal is the whole shape, and
/// because the clip has to be the cover's own rounded rect: a right-angled paper corner
/// poking past the cover's arc is the one detail that would give away that this is drawn
/// over the book rather than out of it.
class _DogEarPainter extends CustomPainter {
  const _DogEarPainter({required this.fold, required this.shadow});

  final Color fold;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final leg = size.width * kReadDogEarRatio;
    // Through [BookMetrics] rather than a literal, so the fold's clip and the cover's
    // own corner come from one definition. At the widths this grid draws — ~77pt on a
    // 390 phone — the ratio is under the clamp's floor, so this is 2.0 everywhere
    // today; it is derived anyway because a `BookMetrics` change is exactly the kind
    // that would otherwise leave a bright sliver of jacket outside the fold.
    final radius = BookMetrics.from(
      baseHeight: size.height,
      coverAspect: size.width / size.height,
      jitter: BookJitter.neutral,
    ).rightRadius;

    // Where the fold hinges: across the head, and down the fore-edge.
    final atHead = Offset(size.width - leg, 0);
    final atForeEdge = Offset(size.width, leg);

    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndCorners(
        Offset.zero & size,
        topRight: Radius.circular(radius),
      ),
    );

    canvas.drawPath(
      Path()
        ..moveTo(atHead.dx, atHead.dy)
        ..lineTo(size.width, 0)
        ..lineTo(atForeEdge.dx, atForeEdge.dy)
        ..close(),
      Paint()..color = fold,
    );

    // On the *cover's* side of the hinge, not centred on it: the flap is above the page
    // and its shadow falls inward. Offset along the hinge's inward normal, which for a
    // 45° fold is `(-1, -1) / sqrt2`.
    final shadowWidth = math.max(leg * _kDogEarShadowRatio, 0.75);
    final inward = const Offset(-1, -1) * (shadowWidth / 2 / math.sqrt2);
    canvas.drawLine(
      atHead + inward,
      atForeEdge + inward,
      Paint()
        ..color = shadow
        ..strokeWidth = shadowWidth,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_DogEarPainter old) =>
      old.fold != fold || old.shadow != shadow;
}
