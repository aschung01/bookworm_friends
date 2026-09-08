/// The library card's shelf, solved before anything is drawn.
///
/// **This file contains no widgets on purpose.** Every number the shelf depends on
/// lives here and is derived from a named constant somewhere else, so the geometry
/// can be asserted arithmetically instead of by pumping a card and measuring
/// rectangles. The defect this replaces was invisible to exactly that kind of test:
/// `_tierFor` handed out boxes at 0.36 and 0.50 aspect where a cover is 0.67, and
/// `BoxFit.cover` centre-cropped the difference away — 20.7pt of artwork per cover at
/// twelve books, half off each side. A widget test asserting "the cover is 17pt wide"
/// passed the whole time, because 17pt was what the code intended.
///
/// Drawn and argued at `docs/mockups/card-cover-crop/index.html`, whose `verify.js`
/// holds the same assertions as `test/card_shelf_plan_test.dart`. **The two must move
/// together**; a drawing that disagrees with the code is worse than no drawing.
///
/// ## The one rule
///
/// **Nothing is ever squeezed.** Three fixed sizes, and past capacity the shelf says
/// how many books it is not showing rather than making anything smaller. Two earlier
/// designs absorbed a large library by thinning — one shrank the overlap step until
/// covers were 9.4pt slivers, the other thinned spines until they stopped carrying
/// titles — and both were rejected. Every size below has a floor, and
/// `test/card_shelf_plan_test.dart` asserts the floors hold at every count from one
/// book to five hundred.
library;

import 'dart:math' as math;

import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book/generated_cover.dart';

/// The artifact's width in drawing units.
///
/// `shareable_library_card.dart` lays the card out as `106 * u` and every measurement
/// in it is in the same units, so this is the one number that converts the drawing
/// into points.
const double kCardUnits = 106;

/// The well's padding, from `_Well`.
const double kCardWellPadUnits = 4;

/// **The width a board actually has, which is not [kCardUnits].**
///
/// The well insets its contents by [kCardWellPadUnits] on both sides, so a shelf gets
/// 98 units and not 106. Getting this wrong is not a rounding error: at six units of
/// slack the side-by-side setting fits an extra cover per board, which quietly turns a
/// capacity of 10 into 12 and every capacity assertion into a lie. It did, until
/// `card_shelf_plan_test.dart` caught the row hanging 12 units off the card.
const double kCardShelfUnits = kCardUnits - 2 * kCardWellPadUnits; // 98

/// Fraction of the card's height the cover well takes.
///
/// Lives here rather than in `shareable_library_card.dart` because the shelf's height
/// budget is computed from it and this file is the lower layer. The card reads it back.
const double kCardWellFraction = 0.46;

/// The well's own height, in units, on a 4:5 card.
///
/// `450 * 0.46` points over `360 / 106` points per unit. Written as the ratio rather
/// than as 60.95 so a change to either dimension carries through.
const double kCardWellUnits =
    (kCardUnits * 450 / 360) * kCardWellFraction; // 60.95

/// A shelf board, and the air between the books and the board under them.
const double kCardBoardUnits = 1.6;
const double kCardBoardGapUnits = 1.4;

/// Air between one shelf and the next, when there are two.
const double kCardShelfGapUnits = 1.5;

/// Gap between two books standing side by side.
const double kCardGapUnits = 1.6;

/// The embossed seal, from `_Seal`.
///
/// Lives here rather than in `shareable_library_card.dart` because the shelf reserves room
/// for it and this is the lower layer; the card reads it back. It is the disc's diameter,
/// and it is the *unrotated* box: `_Seal` rotates with a `Transform`, which paints askew
/// without changing what it occupies.
const double kCardSealUnits = 15;

/// Room the top board holds clear at its right-hand end, so the seal is never covered.
///
/// **The seal is what Candlelight exists to reveal**, and the shelf was standing in front of
/// it. `sealOpacity` is 0.1 in daylight and 1.0 under a candle, so a card that hides it has
/// nothing to show when the reader lights it — and it was hidden badly: the 18th overlapping
/// book left 38% of the disc visible and a full row of spines left 15%. The corner is held
/// instead, at every count.
///
/// The seal's own width plus one [kCardGapUnits], because a book that stops flush against a
/// disc reads as a collision rather than as a shelf that ends there.
///
/// **What it costs is stated rather than absorbed:** three books overlapping and four as
/// spines, off capacities of 34 and 40. It costs nothing at all below eleven books, because
/// a shelf that fits on one board stands at the bottom of the well where the seal is not —
/// see [cardShelfPlan], which solves the bare shelf first for exactly that reason.
const double kCardSealReserveUnits = kCardSealUnits + kCardGapUnits; // 16.6

/// Air left above the top board.
///
/// **Bounded, and tightly.** Push this past about 1.6 units and the cover width it
/// leaves drops below [kCardMinFaceUnits], at which point a two-board card is not
/// legal by its own rule — see [kCardThreeBoardFaceUnits] for what that means for a
/// third board.
const double kCardSlackUnits = 1.5;

/// A board's cast shadow: how far it drops, and how far it blurs.
///
/// **A quarter of the board each, because that is the library's own ratio.**
/// `ShelfWidget` draws an 8pt plank under `offset (0, 2)` with `blurRadius: 2`, so the
/// shadow drops a quarter of the plank and blurs another quarter. Ported as a ratio and
/// not as 2pt: the card's board and the library's plank are one object drawn at two
/// sizes, and that is the whole reason a reader recognises the second as the first.
const double kCardBoardShadowUnits = kCardBoardUnits / 4; // 0.4u -> 1.4pt

/// Air left under the bottom board, and it is exactly the shadow's reach.
///
/// **Free, which is worth stating because it looks as though it could not be.** A
/// two-board shelf is 53.95 units tall inside a 56.95-unit well, so `2 *
/// [kCardSlackUnits]` was already sitting above the top board unspent; spending some of
/// it below the bottom one moves the shelf up without touching
/// [kCardTwoBoardCoverUnits]. No capacity moved when this arrived, and
/// `card_shelf_plan_test.dart` pins both halves of that.
///
/// Without it the bottom board's box ends exactly on the well's floor, the well's own
/// `ClipRect` eats its shadow, and the card ships one shadowed board above one
/// unshadowed one — which reads as a bug rather than as furniture. What the gap does
/// cost is the seal: the shelf is bottom-aligned, so the top board's clearance from the
/// well's top falls from 7.0 units to 6.2.
///
/// Sized for the cast shadow alone. Under a candle the board also carries a
/// `kCandleFlame` halo reaching 2 units, so that glow's outer edge is still clipped on
/// the bottom board; matching it would spend another 1.2 units of the seal's clearance
/// on the faintest part of a blur.
const double kCardShelfFloorUnits = 2 * kCardBoardShadowUnits; // 0.8u -> 2.7pt

/// What one shelf costs in height: its board, and the air above the board.
const double _shelfCostUnits = kCardBoardUnits + kCardBoardGapUnits;

/// The tallest a cover may be with one board, and with two.
///
/// The one-board figure is the height `_tierFor`'s first tier already drew, restated
/// rather than carried over. That tier was 30 units of *the row's own scale*, and the
/// row scaled itself against the well's inner box instead of the card — which made its
/// unit 7.5% smaller than this file's. Handing the row a unit removes that
/// discrepancy, so the number has to be converted or a two-book card would silently
/// grow by 7.5% the day the deviation was fixed.
const double kCardOneBoardCoverUnits =
    30 * kCardShelfUnits / kCardUnits; // 27.74

const double kCardTwoBoardCoverUnits =
    (kCardWellUnits -
            kCardWellPadUnits -
            2 * _shelfCostUnits -
            kCardShelfGapUnits) /
        2 -
    kCardSlackUnits; // 23.22

/// A whole cover's width, once the shelf has stopped growing them.
///
/// The widest a two-board card can carry, so a reader who finishes their eleventh book
/// does not watch the other ten shrink: past that point the *step* absorbs the count
/// and this does not move.
const double kCardFaceUnits =
    kCardTwoBoardCoverUnits * kDefaultCoverAspect; // 15.48

/// The floor under a cover drawn face out, and it is the app's own number.
///
/// [kGeneratedCoverMinWidth] is where `generated_cover.dart` stops drawing a title,
/// because at 13.5% of the width it lands under 7pt. A real jacket sets its own type
/// at similar fractions, so the same width is where a face-out cover stops carrying
/// its title. Below it, put up a second board rather than a narrower cover.
const double kCardMinFaceUnits =
    kGeneratedCoverMinWidth / (360 / kCardUnits); // 15.27

/// A spine's width, from `BookVertical`'s own proportions rather than a new number.
///
/// **Borrowed for [kCardLeanStepUnits], not because the card draws spines.** The read pile
/// draws a spine 26 x 124, so a spine as tall as a cover on a two-board card is
/// `26 * (h / 124)` wide — and that is how far a leaning cover shows of itself. Deriving it
/// means a change to the pile's proportions moves the card's overlap, which is the point:
/// the card is a picture of the shelf the reader already has.
const double kCardSpineUnits =
    (26 / 124) * kCardTwoBoardCoverUnits; // 4.87 -> 16.5pt

/// How far a leaning cover advances before the next one.
///
/// **A spine's width, and that is the whole argument for it:** a leaning book shows exactly
/// a spine's worth of itself. [kCardSpineUnits] is borrowed from `BookVertical` for the
/// proportion alone — the card draws no spines. It is the read pile that draws those, and
/// keeping the derivation means the card's overlap is the same measurement as the pile's
/// book rather than a number that looked right.
const double kCardLeanStepUnits = kCardSpineUnits;

/// What a third board would leave for a cover, and it is well under
/// [kCardMinFaceUnits].
///
/// So a three-board card cannot carry a cover that draws its own title, at any count.
/// **The limit on boards is the well's height, not a design preference**, and this is
/// the number that says so. Asserted, so that nobody proposes a third board without
/// tripping over it.
const double kCardThreeBoardFaceUnits =
    ((kCardWellUnits -
                kCardWellPadUnits -
                3 * _shelfCostUnits -
                2 * kCardShelfGapUnits) /
            3 -
        kCardSlackUnits) *
    kDefaultCoverAspect;

/// What one book on the shelf is drawn as.
///
/// **Two kinds, and there is no setting that picks between them** — the count does. A card
/// with room stands its covers apart; a card without leans them. Two rejected designs drew
/// finished books as *spines* instead, and that became a `Covers | Spines` control in the
/// share preview before it was withdrawn: the card exists to be recognised as the reader's
/// own shelf, and a shelf of spines is a different object. A choice between two pictures of
/// one library is a question the product should answer, and it has. See
/// `docs/mockups/card-cover-crop/index.html`, option `shelf`, for what the spine layout
/// held and why it is only a record now.
enum CardShelfItemKind {
  /// A jacket, whole, standing clear of its neighbours.
  face,

  /// A jacket, whole, leaning on the next one along.
  leaningFace,
}

/// One book, placed.
///
/// [index] is **an index into its own list** — `reading` when [reading] is true, the read
/// books otherwise — and never a position on the shelf. It used to be one running number
/// across both groups, which the drawing then had to undo by subtracting the length of the
/// reading list; that is off by exactly the number of open books the shelf could not fit,
/// so a reader with six books on the go got `ordered[-1]` and a `RangeError` where their
/// shelf should be. Two counters cannot do that.
///
/// `offsetUnits` is measured from the start of its own board. For [CardShelfItemKind
/// .leaningFace] the items overlap, so the order they are painted in matters and
/// [depth] carries it: **higher is nearer the front.** Newest first means the leftmost
/// book is the one on top and the one shown whole, which keeps `cardCoverBooks`' order
/// and its documented reason — the leftmost is the one that survives a crop.
class CardShelfItem {
  final int index;
  final CardShelfItemKind kind;
  final double widthUnits;
  final double heightUnits;
  final double offsetUnits;
  final int depth;

  /// True for a book the reader has open. It wears a bookmark and carries no month stamp,
  /// because `cardStampMonth` has no date to print for it.
  final bool reading;

  const CardShelfItem({
    required this.index,
    required this.kind,
    required this.widthUnits,
    required this.heightUnits,
    required this.offsetUnits,
    required this.depth,
    required this.reading,
  });

  double get rightUnits => offsetUnits + widthUnits;

  @override
  String toString() =>
      'CardShelfItem($index, $kind, ${widthUnits.toStringAsFixed(2)}'
      'x${heightUnits.toStringAsFixed(2)} @${offsetUnits.toStringAsFixed(2)})';
}

/// The shelf, solved.
class CardShelfPlan {
  /// True when there were few enough books to make the covers larger than
  /// [kCardFaceUnits]. Refusing to squeeze is not refusing to fill: a two-book card is
  /// still two large covers.
  final bool grown;

  /// The books on each board, in order, first board first.
  final List<List<CardShelfItem>> boards;

  /// Books the shelf is not showing. Printed as a count; **never absorbed by making
  /// anything smaller.**
  final int remainder;

  const CardShelfPlan({
    required this.grown,
    required this.boards,
    required this.remainder,
  });

  Iterable<CardShelfItem> get items => boards.expand((b) => b);

  int get drawn => boards.fold(0, (sum, b) => sum + b.length);

  /// The tallest book on a given board, which is what the board's row has to be.
  double boardHeightUnits(int board) =>
      boards[board].fold(0.0, (tallest, i) => math.max(tallest, i.heightUnits));

  /// How much of [kCardShelfUnits] a board spends, the overflow plate included.
  double boardWidthUnits(int board, {double plateUnits = 0}) {
    final books = boards[board].fold(
      0.0,
      (widest, i) => math.max(widest, i.rightUnits),
    );
    return books + (plateUnits > 0 ? kCardGapUnits + plateUnits : 0);
  }

  /// Total height the shelf occupies.
  ///
  /// [withBoards] false for a caller that draws no board of its own — the in-app hero
  /// tile sits in a stat tile that has furniture already — in which case the air a
  /// board would have needed is not spent either.
  double heightUnits({bool withBoards = true}) {
    var total = 0.0;
    for (var b = 0; b < boards.length; b++) {
      total +=
          boardHeightUnits(b) +
          (withBoards ? kCardBoardUnits + kCardBoardGapUnits : 0) +
          (b > 0 ? kCardShelfGapUnits : 0);
    }
    return total;
  }
}

/// How many items of [width] advancing by [step] fit in [room].
///
/// One formula for all three settings: item `i` occupies `[i * step, i * step +
/// width]`. Written once for the grown regime and the leaning one, so the two cannot
/// drift apart.
int cardShelfFit(double room, double width, double step) {
  // The tolerance is load-bearing rather than defensive, and it is named once so the two
  // comparisons below cannot come to disagree about what "fits" means.
  //
  // On the second: [kCardLeanStepUnits] divides the board almost exactly, and without it a
  // slot is lost to floating point on some counts but not others.
  //
  // On the first: **the grown regime lands exactly on this boundary by construction.** It
  // sizes covers at `(room - gaps) / n` to fill one board, so once the front group has taken
  // its share the room left over is *precisely* one cover wide -- that is algebra, not luck.
  // A bare `room < width` then turns an equality that floating point missed by 1e-15 into a
  // dropped book: with three open books and one finished one, the reader's only finished
  // cover disappears and the plate says `+1`.
  const tolerance = 1e-9;
  if (room < width - tolerance) return 0;
  return 1 + ((room - width) / step + tolerance).floor();
}

/// The most open books the shelf will draw at the front.
///
/// **The rule is a guarantee rather than a fraction: the top board must still be able to
/// draw a finished book.** The shelf exists to show the books the hero counts; an open book
/// is context for them, not the subject. So the front group gets whatever is left of the top
/// board once the seal's corner is held and one whole cover is set aside for the books the
/// figure is actually about — and an open book costs a cover plus the gap that keeps the
/// finished ones clear of it, which is the footprint `_build` charges it.
///
/// **The defect this prevents is the second bug on the reported card.** The front group used
/// to be sized against the *whole* board, which gives five — and five open covers take all
/// 98 units, so a reader with 22 finished books and six on the go saw none of the 22 on the
/// top board, and in the one-board hero tile saw none at all, under a figure reading 22.
/// Half a board was the first fix and gave two; it held, but it was a fraction with nothing
/// behind it, and it missed the third open book by 0.65 units. The guarantee gives three and
/// says why, so the next reader of this file can tell whether a change to it is safe.
///
/// Deliberately not [cardShelfFit]: that helper charges `n - 1` gaps, because it measures
/// books standing in a row. The front group charges `n` — the last open book still needs a
/// gap between it and the first finished one — so the fit here is a plain division. It comes
/// out at 3.86, nowhere near a whole number, so no tolerance is needed to floor it.
///
/// The drawings agree: `docs/mockups/card-cover-crop` states the same guarantee against its
/// own 106-unit board and floors to the same three.
final int kCardReadingMax =
    ((kCardShelfUnits - kCardSealReserveUnits - kCardFaceUnits) /
            (kCardFaceUnits + kCardGapUnits))
        .floor();

/// Solve the shelf.
///
/// [reading] books are drawn first, then [read] books; every one of them is a whole cover.
/// [plateUnits] is the width the overflow count needs, and it is reserved from the last
/// board rather than overhanging the card — a plate clipped by the well's own `ClipRect` is
/// invisible until somebody opens the exported file.
///
/// **Solved twice when it needs two boards, and that is the seal's doing.** The top board
/// is the only one that reaches the embossed seal in the well's corner, so
/// [kCardSealReserveUnits] is taken off *its* right-hand end — but only once it is known
/// that a top board exists. A one-board shelf stands at the bottom of the well, clear of
/// the seal by construction, and reserving from it would spend capacity protecting
/// something nothing was covering. So the bare shelf is solved first and the reservation
/// is applied only if the answer wants a second board.
CardShelfPlan cardShelfPlan({
  required int reading,
  required int read,
  int maxBoards = 2,
  double plateUnits = 0,
}) {
  final bare = _solve(
    reading: reading,
    read: read,
    maxBoards: maxBoards,
    plateUnits: plateUnits,
    reserveUnits: 0,
  );
  if (bare.boards.length <= 1) return bare;
  return _solve(
    reading: reading,
    read: read,
    maxBoards: maxBoards,
    plateUnits: plateUnits,
    reserveUnits: kCardSealReserveUnits,
  );
}

CardShelfPlan _solve({
  required int reading,
  required int read,
  required int maxBoards,
  required double plateUnits,
  required double reserveUnits,
}) {
  assert(reading >= 0 && read >= 0);
  assert(maxBoards >= 1 && maxBoards <= 2);

  // An open book is drawn as a whole cover, so it cannot cost less than one — and it may
  // not cost more than [kCardReadingMax], because the books the hero counts have first
  // claim on the shelf. A reader with more open books than that is a case the card must
  // survive rather than a case it must serve.
  final front = math.min(reading, kCardReadingMax);
  final total = front + read;
  if (total == 0) {
    return const CardShelfPlan(grown: false, boards: [], remainder: 0);
  }

  // ---- Grown: the covers are made larger, and they all stand clear. ----
  //
  // Refusing to squeeze is not refusing to fill: a two-book card is two large covers, not
  // two small ones with the rest of the board empty.
  {
    final grown = _grow(total, maxBoards, reserveUnits);
    if (grown != null) {
      return _build(
        grown: true,
        reading: front,
        read: read,
        faceUnits: grown.width,
        faceHeightUnits: grown.height,
        readUnits: grown.width,
        readStepUnits: grown.width + kCardGapUnits,
        readKind: CardShelfItemKind.face,
        maxBoards: grown.boards,
        // Balanced, not greedy. `_grow` sized the covers assuming the books divide
        // evenly across the boards it asked for, so filling the first board to the brim
        // would overflow it by everything the second was meant to carry. The fixed path
        // wants the opposite -- fill one board, then start the next -- which is why the
        // policy is a parameter rather than a rule.
        perBoard: (total + grown.boards - 1) ~/ grown.boards,
        plateUnits: 0,
        reserveUnits: reserveUnits,
      );
    }
  }

  // ---- Fixed. Nothing below here changes size with the count. ----
  //
  // The covers stop growing and start leaning instead: past this point the *step* absorbs
  // the count, so a reader who finishes their ninth book does not watch the other eight
  // shrink.
  return _build(
    grown: false,
    reading: front,
    read: read,
    faceUnits: kCardFaceUnits,
    faceHeightUnits: kCardTwoBoardCoverUnits,
    readUnits: kCardFaceUnits,
    readStepUnits: kCardLeanStepUnits,
    readKind: CardShelfItemKind.leaningFace,
    maxBoards: maxBoards,
    perBoard: null,
    plateUnits: plateUnits,
    reserveUnits: reserveUnits,
  );
}

/// The largest side-by-side cover at which every book still fits, or null if there is
/// no such size at or above [kCardMinFaceUnits].
///
/// [reserveUnits] is measured against the *tight* board, which is the top one when the
/// seal's corner is held — sizing against the roomy one would produce covers the top board
/// cannot carry.
({double width, double height, int boards})? _grow(
  int n,
  int maxBoards,
  double reserveUnits,
) {
  for (var boards = 1; boards <= maxBoards; boards++) {
    final per = (n + boards - 1) ~/ boards;
    final cap = boards == 1 ? kCardOneBoardCoverUnits : kCardTwoBoardCoverUnits;
    final room = kCardShelfUnits - (boards == 1 ? 0 : reserveUnits);
    var width = (room - kCardGapUnits * (per - 1)) / per;
    if (width / kDefaultCoverAspect > cap) width = cap * kDefaultCoverAspect;
    if (width >= kCardMinFaceUnits) {
      return (
        width: width,
        height: width / kDefaultCoverAspect,
        boards: boards,
      );
    }
  }
  return null;
}

CardShelfPlan _build({
  required bool grown,
  required int reading,
  required int read,
  required double faceUnits,
  required double faceHeightUnits,
  required double readUnits,
  required double readStepUnits,
  required CardShelfItemKind readKind,
  required int maxBoards,
  required double plateUnits,

  /// Room held clear at the right-hand end of the **top** board, for the seal.
  required double reserveUnits,

  /// Total items a board may carry, when the sizes were chosen on the assumption of an
  /// even split. Null fills each board in turn instead.
  required int? perBoard,
}) {
  // The room the *read* books have. The open books stand at the front of the first
  // board and each carries its own gap, so they take it out of that board and out of
  // no other. Computing it here rather than at both call sites is not tidiness: the
  // grown path forgot to subtract it once, and the row hung 12 units off the card.
  //
  // [reserveUnits] comes off the same board and from the other end — the seal is in the
  // well's top-right corner — so the top board pays for both and the bottom board pays
  // for neither.
  final frontUnits = reading * (faceUnits + kCardGapUnits);
  final rooms = <double>[
    kCardShelfUnits - frontUnits - reserveUnits,
    for (var b = 1; b < maxBoards; b++) kCardShelfUnits,
  ];

  int roomFor(int b, {bool withPlate = false}) {
    final fits = cardShelfFit(
      rooms[b] - (withPlate ? plateUnits + kCardGapUnits : 0),
      readUnits,
      readStepUnits,
    );
    // A balanced split also has to leave room for the open books it shares a board
    // with, or the first board would carry `perBoard` read books *plus* the front
    // group.
    if (perBoard == null) return fits;
    return math.min(fits, math.max(0, perBoard - (b == 0 ? reading : 0)));
  }

  final capacities = [for (var b = 0; b < maxBoards; b++) roomFor(b)];

  // The plate is paid for out of the same 98 units, and only once there is something to
  // put on it — so capacity is computed twice: once assuming every book fits, and again
  // with the plate reserved from the last board if it turns out they do not.
  var total = capacities.fold(0, (a, c) => a + c);
  if (plateUnits > 0 && read > total) {
    capacities[maxBoards - 1] = roomFor(maxBoards - 1, withPlate: true);
    total = capacities.fold(0, (a, c) => a + c);
  }

  final drawnRead = math.min(read, total);
  final boards = <List<CardShelfItem>>[];
  // Counted separately, and that is the fix for a crash rather than tidiness: see
  // [CardShelfItem.index]. Each item is numbered within the list it will be looked up in.
  var readingIndex = 0;
  var readIndex = 0;
  var placed = 0;

  for (var b = 0; b < maxBoards; b++) {
    final row = <CardShelfItem>[];
    var x = 0.0;

    if (b == 0) {
      for (var i = 0; i < reading; i++) {
        row.add(
          CardShelfItem(
            index: readingIndex++,
            kind: readKind == CardShelfItemKind.leaningFace
                ? CardShelfItemKind.leaningFace
                : CardShelfItemKind.face,
            widthUnits: faceUnits,
            heightUnits: faceHeightUnits,
            offsetUnits: x,
            depth: 0,
            reading: true,
          ),
        );
        x += faceUnits + kCardGapUnits;
      }
    }

    final take = math.min(capacities[b], drawnRead - placed);
    for (var i = 0; i < take; i++) {
      row.add(
        CardShelfItem(
          index: readIndex++,
          kind: readKind,
          widthUnits: readUnits,
          heightUnits: faceHeightUnits,
          offsetUnits: x,
          depth: 0,
          reading: false,
        ),
      );
      x += readStepUnits;
    }
    placed += take;

    if (row.isEmpty) break;
    // Nearest the front on the left, so the newest book is the whole one.
    for (var i = 0; i < row.length; i++) {
      row[i] = CardShelfItem(
        index: row[i].index,
        kind: row[i].kind,
        widthUnits: row[i].widthUnits,
        heightUnits: row[i].heightUnits,
        offsetUnits: row[i].offsetUnits,
        depth: row.length - i,
        reading: row[i].reading,
      );
    }
    boards.add(row);
    if (placed >= drawnRead) break;
  }

  return CardShelfPlan(
    grown: grown,
    boards: boards,
    remainder: read - drawnRead,
  );
}

/// How much a book may vary in size, so a row of them is not a bar chart.
///
/// **Applied to both dimensions from one hash, and that is not a style preference.**
/// The shipped row perturbed width and height independently — `+ hash % 3` and
/// `+ hash ~/ 3 % 4` — which moved the box's *aspect* between 0.30 and 0.49, so every
/// cover was cropped by a different amount and the row read as a rendering fault
/// rather than as a shelf. A single scale cannot do that.
///
/// The plan itself is exact; this is applied by whatever draws it, which is why the
/// rule lives here next to the reason for it rather than at the call site.
const double kCardShelfJitter = 0.1;

/// The scale to draw a given book at. Keyed on the book, not its position, so a cover
/// keeps its size when the reader finishes another one and everything shifts along.
double cardShelfScaleFor(String isbn) =>
    1 - ((bookHash(isbn) % 5) / 5) * kCardShelfJitter;

/// How many books the shelf holds, with [reading] of them open.
///
/// Asked rather than solved. A closed form would be a second copy of [cardShelfPlan]'s
/// arithmetic and would eventually disagree with it; this cannot.
int cardShelfCapacity({
  int reading = 0,
  int maxBoards = 2,
  double plateUnits = 0,
}) {
  var n = math.max(1, reading);
  while (n < 600) {
    final plan = cardShelfPlan(
      reading: reading,
      read: n - reading,
      maxBoards: maxBoards,
      plateUnits: plateUnits,
    );
    if (plan.remainder > 0) return n - 1;
    n++;
  }
  return n;
}
