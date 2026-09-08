import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book/generated_cover.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_bookmark.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_shelf_plan.dart';

/// Resolves a book's stored thumbnail URL to something [Image] can draw.
typedef CoverImageResolver = ImageProvider Function(String url);

/// Swappable so widget tests can draw a cover without a network.
///
/// The same seam, for the same reason, as `avatarImageProvider`: Flutter's test
/// binding stubs HTTP to return 400, so a real [NetworkImage] never resolves under
/// `flutter test`. Tests assign a fake here and restore [networkCoverImage]
/// afterwards.
///
/// It is also the reason [cardCoverProviders] exists rather than callers building
/// their own providers: the list handed to a precache must be the same objects the
/// row draws, and one resolver is what guarantees that.
CoverImageResolver coverImageProvider = networkCoverImage;

/// The production resolver. Kept public so tests can restore it.
ImageProvider networkCoverImage(String url) => NetworkImage(url);

/// Width of the plate that carries the count of books the shelf is not showing.
const double kCardPlateUnits = 7.5;

/// The most covers the shelf will ever draw, and therefore the most a precache has to
/// resolve.
///
/// **Derived, and no longer a design limit.** It used to be twelve, chosen because
/// twelve small covers filled the row — and it silently truncated the reader's library
/// at twelve with nothing on the card to say so. The shelf now says how many books it
/// is not showing, so the only thing a maximum is still needed for is bounding the
/// precache: a reader with 293 finished books must not fetch 293 images to export one
/// card. The shelf's own capacity is the bound, asked for rather than chosen.
final int kCardCoverMax = cardShelfCapacity();

/// Cover count above which the flame stamps a mark instead of a month, from
/// [CardPalette.stampsMonths].
///
/// The books a row of [books] will draw, in the order it draws them.
///
/// Most recently finished first, so the leftmost cover — the one a reader's eye lands
/// on, the one that survives a crop, and the one painted nearest the front when the
/// covers lean — is the book they just put down.
///
/// Undated books sort last rather than being dropped: `finish_date` is present on all
/// finished books in the migrated corpus, so this is a guard against a future write
/// path rather than a case that exists today, and dropping a book the hero has already
/// counted would make the row disagree with the figure above it.
List<Book> cardCoverBooks(List<Book> books) {
  final ordered = [...books]
    ..sort((a, b) {
      final af = a.finishDate;
      final bf = b.finishDate;
      if (af == null || bf == null) {
        if (af != null) return -1;
        if (bf != null) return 1;
        return a.isbn.compareTo(b.isbn);
      }
      final byDate = bf.compareTo(af);
      // Stable tiebreak, and it is load-bearing rather than tidiness: 57% of finished
      // books were logged same-day, so ties are the common case and an unstable order
      // would reshuffle the shelf on every rebuild.
      return byDate != 0 ? byDate : a.isbn.compareTo(b.isbn);
    });
  return ordered.length <= kCardCoverMax
      ? ordered
      : ordered.sublist(0, kCardCoverMax);
}

/// Every image provider a shelf over [books] is going to draw.
///
/// **Hand this to `captureWidgetToPng`'s `precache`.** `RepaintBoundary.toImage` paints
/// only what is already decoded, so an export taken before these resolve leaves the
/// phone with holes where the covers should be — invisible on screen, invisible to a
/// widget test that asserts geometry, and visible only by opening the file.
///
/// One kind of book is absent: one with no thumbnail draws a [GeneratedCover], which needs
/// no decode. Books past what the shelf draws are absent too — the plan is asked how many
/// faces it will actually paint, so a reader with 293 finished books fetches what fits.
List<ImageProvider> cardCoverProviders(
  List<Book> books, {
  int readingCount = 0,
  int maxBoards = 2,
}) {
  final ordered = cardCoverBooks(books);
  final plan = cardShelfPlan(
    reading: readingCount,
    // The whole shelf's count, not the truncated list's -- see [CardCoverRow.build].
    read: books.length,
    maxBoards: maxBoards,
    plateUnits: kCardPlateUnits,
  );
  final faces = plan.items.where((i) => !i.reading).length;
  return [
    for (final book in ordered.take(faces))
      if (book.thumbnail.isNotEmpty) coverImageProvider(book.thumbnail),
  ];
}

/// The month a book was finished, as the flame stamps it.
///
/// `MAR`, and always in English — furniture on an object that travels, exactly like the
/// date of issue. Month only rather than a full date: this is printed inside a cover
/// and the year is already on the card twice.
///
/// Null when the book cannot say, which is always true of a book the reader still has
/// open. An unstamped cover in a stamped row is better than a stamp reading a date
/// nobody recorded — and on the card it is one of the two things that mark an open book
/// out as uncounted, the other being its bookmark.
String? cardStampMonth(Book book) {
  final finish = book.finishDate;
  if (finish == null) return null;
  return DateFormat('MMM', 'en').format(finish).toUpperCase();
}

/// The shelf: this card's answer to the passport's world map.
///
/// Flighty's passport is carried by a world map with the holder's routes drawn on it —
/// unique to them, legible at a glance, impossible for a competitor to fake. Stat tiles
/// are none of those things, and books are all three.
///
/// **Every measurement comes from [cardShelfPlan], which is a pure function.** This
/// widget converts units to points and paints; it decides nothing. The defect it
/// replaces was a geometry decision buried in a widget — boxes at 0.36 aspect for
/// 0.67-aspect covers, with `BoxFit.cover` throwing 20.7pt of artwork off each one —
/// and no widget test could see it, because the widget was doing exactly what it meant
/// to do. See `docs/mockups/card-cover-crop/index.html`.
class CardCoverRow extends StatelessWidget {
  /// The books the reader has finished, already filtered to the selected window by the
  /// caller — see `booksInCardYear`, because a cover the hero has not counted would
  /// make the two disagree.
  final List<Book> books;

  /// The books the reader has open right now.
  ///
  /// **These are the exception to the rule above, and deliberately so.** They stand at the
  /// front of the shelf, and the hero does *not* count them: it counts books read, and that number has to keep meaning exactly what
  /// it says. What stops the two from looking like a mistake is that an open book is
  /// visibly a different class of thing — it wears a bookmark and carries no month
  /// stamp. That is the whole of the answer, so neither can be dropped for looks.
  final List<Book> reading;

  /// Points per drawing unit. Derived from the width the shelf is given when null,
  /// which is what the artifact wants: the well hands the row its inner box, and that
  /// box is [kCardShelfUnits] units wide by construction.
  final double? unit;

  /// A ceiling on the shelf's height, in points, for a caller with less room than the
  /// well — the in-app hero tile. The whole drawing scales to fit; **nothing is
  /// squeezed**, so the covers keep their aspect and their proportion to each other and
  /// simply arrive smaller.
  final double? maxHeight;

  /// One board for a preview, two for the artifact.
  final int maxBoards;

  /// Whether the shelf draws the board its books stand on. The artifact wants them;
  /// the hero tile puts the row inside a stat tile that has furniture of its own.
  final bool showBoards;

  /// `center` on the artifact, `start` in the hero tile, per the drawings.
  final MainAxisAlignment alignment;

  /// How the shelf is lit. Under [CardLighting.candlelight] the covers deepen rather
  /// than wash out, take a warm rim, and — at [kCardStampMax] covers or fewer — carry
  /// the month each book was finished.
  final CardLighting lighting;

  const CardCoverRow({
    super.key,
    required this.books,
    this.reading = const [],
    this.unit,
    this.maxHeight,
    this.maxBoards = 2,
    this.showBoards = true,
    this.alignment = MainAxisAlignment.center,
    this.lighting = CardLighting.daylight,
  });

  @override
  Widget build(BuildContext context) {
    final ordered = cardCoverBooks(books);
    if (ordered.isEmpty && reading.isEmpty) return const SizedBox.shrink();

    final plan = cardShelfPlan(
      reading: reading.length,
      // **The reader's whole count, not the truncated list's.** `cardCoverBooks` keeps
      // at most [kCardCoverMax] books to bound the precache, and planning against that
      // number instead of the real one would make the plate say `+1` to a reader with
      // 293 finished books -- the shelf would understate exactly the thing it exists to
      // state. Drawing is still done out of `ordered`, which is safe because
      // [kCardCoverMax] is the shelf's own capacity.
      read: books.length,
      maxBoards: maxBoards,
      plateUnits: kCardPlateUnits,
    );
    if (plan.boards.isEmpty) return const SizedBox.shrink();
    assert(
      plan.items.where((i) => !i.reading).length <= ordered.length,
      'the shelf asked for ${plan.items.where((i) => !i.reading).length} read books '
      'but cardCoverBooks kept ${ordered.length}: kCardCoverMax is meant to be the '
      'shelf own capacity, so raising the capacity has to raise it too',
    );

    final given = unit;
    if (given != null) return _shelves(plan, ordered, given);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : kCardShelfUnits;
        // Two ceilings, and the smaller wins. Scaling the whole drawing is not
        // squeezing: every proportion survives and the shelf simply arrives smaller,
        // which is what a preview of an artifact should do.
        var u = width / kCardShelfUnits;
        final ceiling = maxHeight;
        if (ceiling != null) {
          u = math.min(u, ceiling / plan.heightUnits(withBoards: showBoards));
        }
        return _shelves(plan, ordered, u);
      },
    );
  }

  Widget _shelves(CardShelfPlan plan, List<Book> ordered, double u) {
    final palette = cardPalette(lighting);
    // **One left edge for the whole shelf, and it is the shelf that [alignment] moves.**
    // Letting each board centre on its own contents makes a partly-filled second row
    // read as a centred stub floating under the first, rather than as books standing at
    // the left-hand end of a shelf. It also gives both boards the same length, which is
    // what a board is: furniture, not an underline for the row that happens to be on it.
    var widest = 0.0;
    for (var b = 0; b < plan.boards.length; b++) {
      final last = b == plan.boards.length - 1;
      widest = math.max(
        widest,
        plan.boardWidthUnits(
          b,
          plateUnits: last && plan.remainder > 0 ? kCardPlateUnits : 0,
        ),
      );
    }

    return Row(
      mainAxisAlignment: alignment,
      children: [
        SizedBox(
          width: widest * u,
          // **The shelf states its own height, and that is a guard rather than a
          // formality.** The plan knows it exactly, so saying it costs nothing — and
          // without it every child is offered unbounded height, which is how a single
          // thrown exception became `BOTTOM OVERFLOWED BY 99901 PIXELS` on a real card:
          // Flutter's `ErrorWidget` takes its default enormous size when nothing has
          // constrained it. A failure inside a bounded box is a red rectangle where one
          // shelf was; a failure inside an unbounded one takes the whole screen.
          height: plan.heightUnits(withBoards: showBoards) * u,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var b = 0; b < plan.boards.length; b++) ...[
                if (b > 0) SizedBox(height: kCardShelfGapUnits * u),
                _Board(
                  plan: plan,
                  board: b,
                  ordered: ordered,
                  reading: reading,
                  unit: u,
                  palette: palette,
                  showBoard: showBoards,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One board: the books standing on it, and the board itself.
class _Board extends StatelessWidget {
  final CardShelfPlan plan;
  final int board;
  final List<Book> ordered;
  final List<Book> reading;
  final double unit;
  final CardPalette palette;
  final bool showBoard;

  const _Board({
    required this.plan,
    required this.board,
    required this.ordered,
    required this.reading,
    required this.unit,
    required this.palette,
    required this.showBoard,
  });

  @override
  Widget build(BuildContext context) {
    final items = plan.boards[board];
    final last = board == plan.boards.length - 1;
    final plate = last && plan.remainder > 0;
    final booksUnits = plan.boardWidthUnits(board);
    final heightUnits = plan.boardHeightUnits(board);

    // Painted back to front, so the leftmost book is the one on top and the one shown
    // whole. `depth` carries that ordering out of the plan rather than relying on the
    // list order, because the two are the reverse of each other.
    final painted = [...items]..sort((a, b) => a.depth.compareTo(b.depth));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: heightUnits * unit,
          child: Stack(
            // A leaning cover's shadow falls outside its own box, and a bookmark
            // hangs over the head of one. Clipping either would put a hard edge
            // across the shelf.
            clipBehavior: Clip.none,
            children: [
              for (final item in painted) _placed(item),
              if (plate)
                Positioned(
                  // Beside the books rather than at the shelf's far right, so the count
                  // sits with what it is counting. Always inside the board: its width
                  // was reserved out of the same 98 units by [cardShelfPlan].
                  left: (booksUnits + kCardGapUnits) * unit,
                  bottom: 0,
                  width: kCardPlateUnits * unit,
                  height: heightUnits * unit * 0.42,
                  child: _Plate(
                    count: plan.remainder,
                    unit: unit,
                    palette: palette,
                  ),
                ),
            ],
          ),
        ),
        if (showBoard) ...[
          SizedBox(height: kCardBoardGapUnits * unit),
          // Full width whatever the books came to, because a board is furniture: it is
          // the shelf, not an underline for the row that happens to be on it.
          SizedBox(
            height: kCardBoardUnits * unit,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.shelf,
                // **Square ends, and no radius at all.** `BorderRadius.circular(1 *
                // unit)` on a bar 1.6 units tall is a pill, which is exactly the
                // underline the comment above says a board must not be. The library's
                // plank sets no radius either, and the two are meant to read as one
                // object.
                boxShadow: [
                  // The cast shadow, which is what makes the books look like they are
                  // standing *on* the board. It reaches [kCardShelfFloorUnits] below the
                  // box, which is precisely the air `_Well` now leaves under the bottom
                  // board — without that gap the well's `ClipRect` would swallow this on
                  // the bottom board alone.
                  if (palette.boardShadow != null)
                    BoxShadow(
                      color: palette.boardShadow!,
                      offset: Offset(0, kCardBoardShadowUnits * unit),
                      blurRadius: kCardBoardShadowUnits * unit,
                    ),
                  if (palette.isLit)
                    BoxShadow(color: kCandleFlame, blurRadius: 2 * unit),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The book an item stands for.
  ///
  /// No arithmetic, deliberately. This used to be
  /// `ordered[item.index - reading.length]`, which is correct only while every open book
  /// fits on a board — past that it reads `ordered[-1]` and throws a `RangeError` in
  /// place of the shelf, which is exactly what a reader with six books on the go got.
  /// [CardShelfItem.index] now indexes the list it belongs to and nothing has to be
  /// undone here.
  Book _bookAt(CardShelfItem item) =>
      item.reading ? reading[item.index] : ordered[item.index];

  /// One book, at the size it is actually drawn.
  Widget _placed(CardShelfItem item) {
    final book = _bookAt(item);
    final size = _sizeUnits(item, book);
    return Positioned(
      // Keyed by book so a test can assert which book is where. The newest-first order
      // is a claim about position, not only about membership — and when the covers lean
      // it is also a claim about which one is painted whole.
      key: ValueKey('cover-${book.isbn}'),
      left: item.offsetUnits * unit,
      // Bottoms aligned, because they are standing on a shelf. It is also what makes
      // the jitter below legible: the variation shows along the top edge, where a row
      // of real books varies, instead of floating each book at its own height.
      bottom: 0,
      width: size.width * unit,
      height: size.height * unit,
      child: _book(item, book, size.width * unit),
    );
  }

  /// The plan's size for a book, with the jitter that keeps a row of them from reading
  /// as a bar chart.
  ///
  /// **Applied here and not in [cardShelfPlan] because it is keyed on the ISBN**, which
  /// is the only way a cover keeps its size when the reader finishes another book and
  /// everything shifts along. What varies depends on what is being drawn, and each case
  /// is a constraint rather than a preference:
  ///
  ///  - **A cover the shelf grew varies in both, by one scale** ([kCardShelfJitter]), so
  ///    its aspect cannot move. Two independent perturbations moving the box aspect
  ///    between 0.30 and 0.49 is the defect this file replaces.
  ///  - **A cover at [kCardFaceUnits] does not vary at all.** There is nowhere for it to
  ///    go: that width sits 0.2 units above [kCardMinFaceUnits], so any shrink puts the
  ///    cover under the width at which it stops carrying its own title. It is also the
  ///    width the covers lean on a constant step at, and a leaning book that is not its
  ///    neighbour's size breaks the rhythm the step exists to create.
  ///  - **An open book does not vary.** It stands at the front of the shelf and is the
  ///    first thing read; it is not texture.
  Size _sizeUnits(CardShelfItem item, Book book) {
    if (item.reading || item.widthUnits <= kCardFaceUnits) {
      return Size(item.widthUnits, item.heightUnits);
    }
    final scale = cardShelfScaleFor(book.isbn);
    assert(
      item.widthUnits * scale >= kCardMinFaceUnits,
      'the jitter took a grown cover below the width at which it draws its own '
      'title: ${item.widthUnits * scale} < $kCardMinFaceUnits',
    );
    return Size(item.widthUnits * scale, item.heightUnits * scale);
  }

  Widget _book(CardShelfItem item, Book book, double width) {
    return _Cover(
      book: book,
      width: width,
      unit: unit,
      palette: palette,
      stamped: palette.stampsMonths(plan.drawn),
      marked: palette.marksCovers(plan.drawn),
      bookmarked: item.reading,
    );
  }
}

/// The count of books the shelf is not showing.
///
/// **Printed rather than absorbed.** Two earlier designs made room for a large library
/// by thinning the books until they stopped being books; this one states the shortfall.
/// Drawn in the stamp's own visual language rather than as a new element, and its width
/// is reserved out of the board by [cardShelfPlan] — a plate that overhangs is clipped
/// by the well's `ClipRect` and invisible until somebody opens the exported file.
class _Plate extends StatelessWidget {
  final int count;
  final double unit;
  final CardPalette palette;

  const _Plate({
    required this.count,
    required this.unit,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.isLit
            ? Colors.black.withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(1 * unit),
        border: Border.all(
          color: palette.isLit ? kCandleFlame : palette.statRule,
          width: math.max(0.5, 0.3 * unit),
        ),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 0.6 * unit),
            child: Text(
              '+$count',
              maxLines: 1,
              style: TextStyle(
                fontSize: 3 * unit,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: palette.isLit ? kCandleGlow : palette.labelInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One cover, with the furniture that makes a rectangle read as a book.
class _Cover extends StatelessWidget {
  final Book book;

  /// The cover's own rendered width, which [GeneratedCover] scales its type from.
  final double width;

  /// One drawing unit in points, so the corner radii and the binding band stay
  /// proportional at every size.
  final double unit;

  final CardPalette palette;

  /// Whether the flame prints this cover's finish month on it.
  final bool stamped;

  /// Whether the flame leaves a warm mark instead, because there are too many covers
  /// for a legible date.
  final bool marked;

  /// Whether this is a book the reader still has open.
  final bool bookmarked;

  const _Cover({
    required this.book,
    required this.width,
    required this.unit,
    required this.palette,
    this.stamped = false,
    this.marked = false,
    this.bookmarked = false,
  });

  @override
  Widget build(BuildContext context) {
    // Tight at the spine, rounder at the fore-edge. Symmetric corners read as a card;
    // these read as a bound object, and it costs nothing.
    final radius = BorderRadius.only(
      topLeft: Radius.circular(0.5 * unit),
      bottomLeft: Radius.circular(0.5 * unit),
      topRight: Radius.circular(1.1 * unit),
      bottomRight: Radius.circular(1.1 * unit),
    );

    final bloom = palette.coverBloom;
    final month = stamped ? cardStampMonth(book) : null;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              if (bloom == null)
                BoxShadow(
                  offset: Offset(0.5 * unit, 0.5 * unit),
                  blurRadius: 1.5 * unit,
                  color: Colors.black.withValues(alpha: 0.28),
                )
              else
                // Centred rather than offset: a drop shadow says "lit from up and
                // left" and this is a rim the flame leaves all round the fore-edge.
                BoxShadow(color: bloom, blurRadius: 2.5 * unit),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _lit(_face()),
                // The binding band. What the eye reads as "this is a book seen slightly
                // from the side" — and the reason [GeneratedCover] insets its title from
                // the left by roughly the same amount.
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 1.2 * unit,
                    child: ColoredBox(
                      color: Colors.black.withValues(
                        alpha: palette.bindingAlpha,
                      ),
                    ),
                  ),
                ),
                if (month != null)
                  Center(
                    key: ValueKey('cover-stamp-${book.isbn}'),
                    child: _stamp(month),
                  ),
                if (marked)
                  Center(
                    key: ValueKey('cover-mark-${book.isbn}'),
                    child: _mark(),
                  ),
              ],
            ),
          ),
        ),
        // Outside the ClipRRect, because a bookmark a clip swallows is not a bookmark.
        //
        // **The library's own ribbon, at the card's scale** — not a mark of the card's
        // own. See [ReadingBookmark]: the card is trying to look like the shelf the
        // reader already knows, and it used to draw a red rectangle where the shelf draws
        // a white notched ribbon. The scale and the inset are the only things computed
        // here, and both are ratios, so the two cannot drift in shape or colour.
        if (bookmarked)
          Positioned(
            key: ValueKey('cover-bookmark-${book.isbn}'),
            top: 0,
            right: kReadingBookmarkInset * _bookmarkScale,
            child: ReadingBookmark(scale: _bookmarkScale),
          ),
      ],
    );
  }

  /// The ribbon's size, as the ratio of this cover to the shelf's book.
  ///
  /// Taken off the height rather than the width because that is the dimension
  /// [kReadingBookmarkBook] is: the card's cover and the shelf's share the app's aspect,
  /// so either would do, and the height is the one that needs no conversion.
  double get _bookmarkScale =>
      width / kDefaultCoverAspect / kReadingBookmarkBook;

  /// Puts the light on the cover.
  ///
  /// `BlendMode.modulate` is a multiply, so this is `cover × light` — literally what a
  /// warm point source does to a surface. It darkens and warms while leaving the cover's
  /// own hue, which is the requirement: covers deepen rather than wash out.
  Widget _lit(Widget child) {
    final light = palette.coverLight;
    if (light == null) return child;
    return ColorFiltered(
      colorFilter: ColorFilter.mode(light, BlendMode.modulate),
      child: child,
    );
  }

  /// The date stamp: warm ink on a shadowed impression, raked across the cover.
  ///
  /// **`BoxFit.scaleDown`, and it is load-bearing.** `MAR` in a bordered plate is close
  /// to a cover's width before it is rotated. Scaling down is what makes a stamp that
  /// cannot fit shrink instead of overflowing — and an overflow here is a clipped
  /// half-glyph in an image that has already left the phone.
  Widget _stamp(String month) => Transform.rotate(
    angle: -11 * math.pi / 180,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 1.1 * unit,
          vertical: 0.2 * unit,
        ),
        decoration: BoxDecoration(
          // The impression the die left, which is what the ink sits in.
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(1 * unit),
          border: Border.all(color: kCandleFlame, width: 0.5 * unit),
        ),
        child: Text(
          month,
          maxLines: 1,
          style: TextStyle(
            fontSize: 2.8 * unit,
            fontWeight: FontWeight.w800,
            height: 1.15,
            color: kCandleGlow,
            shadows: palette.bloom,
          ),
        ),
      ),
    ),
  );

  /// What the reveal degrades to past [kCardStampMax].
  ///
  /// A warm point rather than a smaller date. Past that count a stamp per cover would be
  /// a row of smudges, and a smudge that is *trying* to be information is worse than
  /// texture that is not. It is still a reveal: something appears that daylight does not
  /// show.
  Widget _mark() => Container(
    width: 1.6 * unit,
    height: 1.6 * unit,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: kCandleGlow,
      boxShadow: [BoxShadow(color: kCandleFlame, blurRadius: 2 * unit)],
    ),
  );

  Widget _face() {
    if (book.thumbnail.isNotEmpty) {
      return Image(
        image: coverImageProvider(book.thumbnail),
        // The box is the cover's own aspect now, so this scales and does not crop.
        // It stays `cover` rather than becoming `contain` because a real jacket runs
        // 0.60 to 0.75 and the last few percent should be trimmed, not letterboxed.
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  /// What a book with no usable cover draws.
  ///
  /// [GeneratedCover] where its title is legible, and the colour block alone where it is
  /// not: the title is 13.5% of the width, so below [kGeneratedCoverMinWidth] it is
  /// under 7pt and reads as a smudge. Phase 4 shipped exactly that.
  ///
  /// On the artifact this now always draws the title, because [kCardFaceUnits] is
  /// derived from this very floor. It still matters for the in-app preview, which scales
  /// the whole shelf down to fit a stat tile.
  Widget _fallback() => width >= kGeneratedCoverMinWidth
      ? GeneratedCover(isbn: book.isbn, title: book.title, width: width)
      : _block();

  Widget _block() => ColoredBox(color: generatedCoverColor(book.isbn));
}
