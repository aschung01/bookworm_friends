// Guards for the library card's shelf geometry.
//
// These are the same assertions as `docs/mockups/card-cover-crop/verify.js`, against
// the shipped arithmetic instead of the drawing's. **Keep the two in step**: the
// mockup is the design record for this file, and a drawing that disagrees with the
// code is worse than no drawing.
//
// Almost every test here asserts that something does NOT happen, because the design is
// a refusal. Two earlier versions absorbed a large library by making things smaller —
// one shrank the overlap step until covers were 9.4pt slivers of jacket, the other
// thinned spines until they stopped carrying titles — and both were rejected in favour
// of printing a count. So the load-bearing tests are the floors: no size below the
// fixed one, at any count, in any setting.
//
// The defect all of this replaces was invisible to a widget test. `_tierFor` handed out
// 0.36-aspect boxes for 0.67-aspect covers and `BoxFit.cover` cropped 20.7pt off each
// one, and a test asserting "the cover is 17pt wide" passed throughout, because 17pt
// was what the code meant to do. Which is why the geometry is a pure function now.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book/generated_cover.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_shelf_plan.dart';

/// Points per drawing unit on the exported card, for the assertions that are about a
/// physical size rather than a proportion.
const double _u = 360 / kCardUnits;

/// Counts to sweep. Spans every regime boundary — the one/two board split, the point
/// where leaning starts, the reported card's 22, and well past any real library.
const List<int> _counts = [
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  10,
  11,
  12,
  22,
  30,
  40,
  60,
  90,
  200,
  500,
];

CardShelfPlan _plan(int read, {int reading = 0, double plateUnits = 7.5}) =>
    cardShelfPlan(reading: reading, read: read, plateUnits: plateUnits);

void main() {
  group('the sizes are derived, not chosen', () {
    test('a leaning cover advances by exactly a spine width', () {
      // Where the overlap comes from: a leaning book shows exactly a spine's worth of
      // itself. The card draws no spines — the read pile does — so this is a proportion
      // borrowed, and if it ever stops being true the constant has to say why.
      expect(kCardLeanStepUnits, kCardSpineUnits);
    });

    test('and that spine is BookVertical scaled to the card', () {
      // 26 x 124 is the read pile's spine, so a change there moves the card's overlap.
      expect(
        kCardSpineUnits,
        closeTo((26 / 124) * kCardTwoBoardCoverUnits, 1e-12),
      );
      expect(kCardSpineUnits * _u, closeTo(16.5, 0.1));
    });

    test('a cover is the widest a two-board card can carry', () {
      expect(
        kCardFaceUnits,
        closeTo(kCardTwoBoardCoverUnits * kDefaultCoverAspect, 1e-12),
      );
      expect(kCardFaceUnits * _u, closeTo(52.6, 0.2));
    });

    test('the cover floor is the app own generated-cover floor', () {
      // Not a new number: `generated_cover.dart` stops drawing a title below this
      // width, and a real jacket sets its type at similar fractions.
      expect(kCardMinFaceUnits * _u, closeTo(kGeneratedCoverMinWidth, 0.01));
    });

    test('two boards clear that floor, and only just', () {
      // Both halves matter. If the first fails the layout is illegal by its own rule;
      // if the second starts passing by a wide margin, something has quietly grown the
      // well and the third-board argument below needs re-checking.
      expect(kCardFaceUnits, greaterThanOrEqualTo(kCardMinFaceUnits));
      expect((kCardFaceUnits - kCardMinFaceUnits) * _u, lessThan(3));
    });

    test('a third board cannot carry a cover that draws its own title', () {
      // The limit on boards is the well height, not taste. This is the number that
      // says so, and it is asserted so a third board cannot be proposed without
      // tripping over it.
      expect(kCardThreeBoardFaceUnits, lessThan(kCardMinFaceUnits));
      expect(kCardThreeBoardFaceUnits * _u, lessThan(40));
    });

    test('the air under the bottom board is spent out of slack, not covers', () {
      // The gap `_Well` leaves under the bottom board looks as though it has to cost
      // cover height, and it does not: a two-board shelf leaves `2 * kCardSlackUnits`
      // sitting unspent *above* the top board, and the gap is taken from there. Both
      // halves are pinned, because the tempting way to add a floor gap is to subtract it
      // inside [kCardTwoBoardCoverUnits] instead — which would move every capacity in
      // this file.
      final tallest = cardShelfPlan(reading: 0, read: 90).heightUnits();
      expect(
        kCardWellUnits - kCardWellPadUnits - tallest,
        closeTo(2 * kCardSlackUnits, 1e-9),
        reason:
            'the well inner box less the shelf is the slack the gap comes out of',
      );
      expect(
        kCardShelfFloorUnits,
        lessThanOrEqualTo(2 * kCardSlackUnits),
        reason:
            '`_Well` passes the row no maxHeight, so a shelf that no longer fits is not '
            'scaled down -- it is clipped at the top by the well own ClipRect, with '
            'nothing on screen to say so',
      );
      // And the gap is exactly the shadow's reach: offset plus blur. Any less and the
      // well's `ClipRect` eats the bottom board's shadow while the top board keeps its
      // own, which reads as a bug rather than as furniture.
      expect(kCardShelfFloorUnits, closeTo(2 * kCardBoardShadowUnits, 1e-12));
    });
  });

  group('nothing is squeezed', () {
    test('a read book is never drawn narrower than its fixed size', () {
      // THE refusal, and the one assertion that would have failed on both rejected
      // designs at almost every count.
      for (final n in _counts) {
        final plan = _plan(n, reading: 2);
        for (final item in plan.items.where((i) => !i.reading)) {
          expect(
            item.widthUnits,
            greaterThanOrEqualTo(kCardFaceUnits - 1e-9),
            reason: 'read book at n=$n is ${item.widthUnits} units',
          );
        }
      }
    });

    test('an open book is a whole cover, at any count', () {
      // The books being held are the reason the finished ones are on the card at all, so
      // nothing the count does to the shelf may reach them.
      for (final n in _counts) {
        final plan = _plan(n, reading: 2);
        final open = plan.items.where((i) => i.reading).toList();
        expect(open, hasLength(2), reason: 'n=$n');
        for (final item in open) {
          expect(item.widthUnits, greaterThanOrEqualTo(kCardFaceUnits - 1e-9));
        }
      }
    });

    test('every book is accounted for', () {
      // Drawn or counted. Never silently dropped — which is the failure mode the
      // remainder exists to prevent.
      for (final n in _counts) {
        final plan = _plan(n, reading: 2);
        expect(plan.drawn + plan.remainder, 2 + n, reason: 'n=$n');
      }
    });

    test('every cover keeps the app own aspect', () {
      // The whole defect, in one line. No box on this shelf may disagree with
      // `kDefaultCoverAspect`, because `BoxFit.cover` resolves a disagreement by
      // throwing artwork away.
      for (final n in _counts) {
        for (final item in _plan(n, reading: 2).items) {
          expect(
            item.widthUnits / item.heightUnits,
            closeTo(kDefaultCoverAspect, 1e-9),
            reason: 'n=$n',
          );
        }
      }
    });

    test('the shelf fits inside the card, in both axes', () {
      // A row that overflows is a clipped cover in an image that has already left
      // the phone: the one failure mode with no recovery.
      for (final n in _counts) {
        final plan = _plan(n, reading: 2);
        for (var b = 0; b < plan.boards.length; b++) {
          expect(
            plan.boardWidthUnits(
              b,
              plateUnits: b == plan.boards.length - 1 && plan.remainder > 0
                  ? 7.5
                  : 0,
            ),
            lessThanOrEqualTo(kCardUnits + 1e-9),
            reason: 'board $b at n=$n',
          );
        }
        expect(
          plan.heightUnits(),
          lessThanOrEqualTo(
            kCardWellUnits - kCardWellPadUnits - kCardShelfFloorUnits + 1e-9,
          ),
          reason: 'height at n=$n',
        );
      }
    });

    test('a second board goes up only when the first is full', () {
      for (final n in _counts) {
        final plan = _plan(n, reading: 2);
        if (plan.boards.length > 1) {
          expect(plan.boards.first, isNotEmpty, reason: 'n=$n');
          expect(plan.boards[1], isNotEmpty, reason: 'n=$n');
        }
      }
    });

    test('never more than two boards, at any count', () {
      for (final n in _counts) {
        expect(_plan(n, reading: 2).boards.length, lessThan(3));
      }
    });
  });

  group('capacity is a fact, not a target', () {
    test('the shelf holds what the design record says', () {
      // The number in the mockup's capacity table **with the seal's corner held** — see
      // [kCardSealReserveUnits], which costs three books off the 34 an unreserved shelf
      // carried. If it moves, either the geometry or the reservation changed and the seal
      // decision was made on stale information.
      expect(cardShelfCapacity(), 31);
    });

    test('and with two books open', () {
      // The other column of the same table. Two is what the median reader has open, and
      // an open cover and the reserve come out of the same board.
      expect(cardShelfCapacity(reading: 2), 26);
    });

    test('and with three, which is as many as the shelf will draw', () {
      // The column [kCardReadingMax] added. **Typed on both sides**: the mockup's own
      // engine reaches 24 against its 106-unit board and this file reaches it against 98,
      // so a change to either has to be argued for in both places.
      expect(cardShelfCapacity(reading: 3), 24);
    });

    test('and an open book never costs more than the one before it', () {
      // **A non-monotonic capacity is the defect here**, not a small one: it would mean a
      // reader who opens one more book watches covers already on their shelf disappear.
      // Sizing the front group against the whole board did exactly that -- capacity fell
      // to 4 at four open books -- because [cardShelfFit] was reading an exact fit as a
      // miss. Walked one book at a time rather than spot-checked, so the cliff cannot
      // hide between two sampled counts.
      var last = cardShelfCapacity(reading: 0);
      for (var open = 1; open <= kCardReadingMax; open++) {
        final cap = cardShelfCapacity(reading: open);
        expect(
          cap,
          lessThanOrEqualTo(last),
          reason: '$open open books hold $cap where ${open - 1} held $last',
        );
        last = cap;
      }
    });

    test('the books the hero counts keep first claim on the shelf', () {
      // **The second bug on the reported card.** The front group used to be sized against
      // the whole board, so five open covers took all 98 units: the reader saw none of
      // their 22 finished books on the top board, and none at all in the one-board hero
      // tile, under a figure reading 22.
      //
      // Three is not a fraction of the board but the answer to a question -- how many open
      // books still leave the top board able to draw a finished one, once the seal's corner
      // is held -- so if this number moves, the rule in [kCardReadingMax] moved with it.
      expect(kCardReadingMax, 3);

      for (final open in [0, 1, 2, 3, 5, 8, 40]) {
        final plan = _plan(22, reading: open);
        expect(
          plan.items.where((i) => i.reading).length,
          math.min(open, kCardReadingMax),
          reason: 'a reader with $open open books is a case to survive, not serve',
        );

        // **The guarantee itself, and it is the whole reason for the rule.** The top board
        // is the one the open books stand on and the one the seal's corner comes out of, so
        // it is the board that can be left with nothing of what the card is about.
        expect(
          plan.boards.first.where((i) => !i.reading).length,
          greaterThan(0),
          reason:
              'with $open open books the top board still carries a finished '
              'cover, or the card is a shelf of unfinished books under a '
              'figure counting finished ones',
        );
      }
    });

    test('the third open book is paid for in capacity, not in hidden books', () {
      // Raising the cap from two cost two slots (26 -> 24), and this pins where that lands
      // for the reader in the report: a shelf of 22 finished books stops being drawn whole
      // once three are open. **The shortfall is stated, never absorbed** -- the plate says
      // how many are missing, which is the rule the whole shelf is built on.
      final two = _plan(22, reading: 2);
      expect(two.remainder, 0, reason: 'two open: 22 finished still all fit');

      final three = _plan(22, reading: 3);
      expect(three.items.where((i) => !i.reading).length, 20);
      expect(three.remainder, 2);
      expect(
        three.items.where((i) => !i.reading).length + three.remainder,
        22,
        reason: 'every finished book is either drawn or counted, never lost',
      );
    });

    test('one board is enough for the hero tile, whatever is open', () {
      // The in-app preview draws one board. It was the worst case of the same defect:
      // five open covers filled the only board there was.
      final plan = cardShelfPlan(
        reading: 6,
        read: 22,
        maxBoards: 1,
        plateUnits: 7.5,
      );
      expect(plan.items.where((i) => i.reading).length, kCardReadingMax);
      expect(
        plan.items.where((i) => !i.reading).length,
        greaterThan(0),
        reason:
            'a shelf of nothing but unfinished books under a count of finished '
            'ones is the one thing the tile must not draw',
      );
    });

    test('an exact fit is a fit, and the grown shelf lands on one', () {
      // **Naming the defect: a dropped book at three open and one finished.** [_grow] sizes
      // covers to fill a single board, so the room left after the front group has taken its
      // share is *precisely* one cover wide -- algebra, not luck. [cardShelfFit] used to
      // compare `room < width` with no tolerance, so an equality missed by 1e-15 read as a
      // miss and the reader's only finished cover vanished behind a `+1`.
      expect(
        cardShelfFit(kCardFaceUnits, kCardFaceUnits, kCardLeanStepUnits),
        1,
        reason: 'room exactly one cover wide holds exactly one cover',
      );

      final plan = cardShelfPlan(reading: kCardReadingMax, read: 1);
      expect(
        plan.items.where((i) => !i.reading).length,
        1,
        reason: 'the one book the figure is counting is on the shelf',
      );
      expect(plan.remainder, 0);
    });

    test('capacity has a clean edge', () {
      final cap = cardShelfCapacity(plateUnits: 7.5);
      expect(_plan(cap).remainder, 0, reason: 'should hold $cap');
      expect(
        _plan(cap + 1).remainder,
        greaterThan(0),
        reason: 'should not hold ${cap + 1}',
      );
    });

    test('an open book costs a slot, never the size of anything else', () {
      final none = cardShelfCapacity(plateUnits: 7.5);
      final two = cardShelfCapacity(reading: 2, plateUnits: 7.5);
      expect(two, lessThan(none));
      // The read books are the same size either way. This is the price being paid in
      // capacity rather than in crowding, which is the whole design.
      expect(
        _plan(200, reading: 2).items.last.widthUnits,
        closeTo(_plan(200, reading: 0).items.last.widthUnits, 1e-9),
      );
    });

    test('the plate is reserved out of the board, not overhung', () {
      // A plate clipped by the well's own ClipRect is invisible until somebody opens
      // the exported file. It was, once.
      for (final n in [200, 500]) {
        final plan = _plan(n, reading: 2);
        expect(plan.remainder, greaterThan(0), reason: 'at $n');
        expect(
          plan.boardWidthUnits(plan.boards.length - 1, plateUnits: 7.5),
          lessThanOrEqualTo(kCardUnits + 1e-9),
          reason: 'at $n',
        );
      }
    });
  });

  group('overlapping is permission to lean, not an instruction', () {
    test('nothing leans below nine books', () {
      // Which is why the side-by-side setting could go without anything being lost for
      // the reader it was aimed at: below nine books the shelf it drew is the shelf this
      // one draws. The covers are grown to fill the board and stand clear.
      //
      // Nine and not eleven since the seal's corner is held: at nine the top board is
      // [kCardSealReserveUnits] narrower, and five grown covers no longer clear
      // [kCardMinFaceUnits] in what is left. What a nine-book card draws instead is one
      // board of nine leaning covers — which is what an eleven-book card has always drawn,
      // so the threshold moved rather than a new layout appearing.
      for (var n = 1; n <= 8; n++) {
        final plan = _plan(n);
        expect(plan.grown, isTrue, reason: 'n=$n');
        expect(
          plan.items.map((i) => i.kind),
          isNot(contains(CardShelfItemKind.leaningFace)),
          reason: 'n=$n',
        );
      }
    });

    test('and they lean from nine', () {
      expect(_plan(9).items.last.kind, CardShelfItemKind.leaningFace);
    });

    test('leaning books are painted newest-first, nearest the front', () {
      // Which end is on top decides which cover is whole. Leftmost wins, so
      // `cardCoverBooks`' newest-first order survives and its documented reason with
      // it: the leftmost is the one that survives a crop.
      final plan = _plan(22);
      final row = plan.boards.first;
      expect(row.first.index, 0);
      for (var i = 1; i < row.length; i++) {
        expect(row[i].depth, lessThan(row[i - 1].depth));
        expect(row[i].offsetUnits, greaterThan(row[i - 1].offsetUnits));
      }
    });
  });

  group('refusing to squeeze is not refusing to fill', () {
    test('a two-book card is two large covers', () {
      final plan = _plan(2);
      expect(plan.grown, isTrue);
      expect(plan.boards, hasLength(1));
      expect(plan.items.first.widthUnits, greaterThan(kCardFaceUnits));
    });

    test('the grown covers match the tier the card already shipped', () {
      // A two-book card must not change size the day the row's unit was fixed. The
      // shipped first tier drew 62.8 x 94.2pt; this is the same card.
      final plan = _plan(2);
      expect(plan.items.first.widthUnits * _u, closeTo(62.8, 0.5));
      expect(plan.items.first.heightUnits * _u, closeTo(94.2, 0.5));
    });

    test('growth stops at the floor rather than going under it', () {
      // The last grown count, and the first fixed one. Between them the shelf changes
      // strategy, and it must not change size discontinuously downward.
      var lastGrown = 0;
      for (var n = 1; n <= 30; n++) {
        if (_plan(n).grown) {
          lastGrown = n;
        }
      }
      expect(lastGrown, 8);
      final grown = _plan(lastGrown);
      expect(
        grown.items.first.widthUnits,
        greaterThanOrEqualTo(kCardMinFaceUnits - 1e-9),
      );
    });
  });

  group('the seal\'s corner is held, and only when there is a top board', () {
    // **The shelf was standing in front of the thing Candlelight exists to reveal.**
    // `sealOpacity` is 0.1 in daylight and 1.0 under a candle, and the 18th overlapping
    // book left 38% of the disc showing while a full row of spines left 15%. The corner is
    // now held at every count — which is what these assert, along with the two things that
    // make the price bearable: it is paid by the top board alone, and not at all by a card
    // small enough to need one board.

    /// Where the seal's disc starts, measured along a board from its left-hand end.
    ///
    /// The well insets the shelf by [kCardWellPadUnits] on both sides and the seal sits
    /// [kCardWellPadUnits] in from the card's right edge, so the disc's left edge is its own
    /// width in from the board's right-hand end. Derived rather than measured off the
    /// drawing: a seal that moved would have to move this.
    const sealStart = kCardShelfUnits - kCardSealUnits;

    test('the reserve is the seal and one gap, and nothing else', () {
      // A book stopping flush against the disc reads as a collision rather than as a shelf
      // that ends there, so the gap is part of the reservation and not slack.
      expect(kCardSealReserveUnits, kCardSealUnits + kCardGapUnits);
      expect(kCardSealReserveUnits, closeTo(16.6, 1e-9));
    });

    test('no book on the top board reaches the seal, at any count', () {
      for (final n in _counts) {
        for (final open in [0, 2]) {
          final plan = _plan(n, reading: open);
          if (plan.boards.length < 2) continue;
          expect(
            plan.boardWidthUnits(0),
            lessThanOrEqualTo(sealStart - kCardGapUnits + 1e-9),
            reason: 'at n=$n with $open open',
          );
        }
      }
    });

    test('the bottom board keeps the whole 98 units', () {
      // The seal is in the well's *top* corner, so the reserve is the top board's to pay.
      // Taking it from both would double a cost the drawing priced once.
      final plan = _plan(90);
      expect(plan.boards.length, 2);
      expect(
        plan.boardWidthUnits(1),
        greaterThan(sealStart),
        reason: 'the bottom row is allowed to run under the seal, and does',
      );
    });

    test('a one-board card pays nothing for it', () {
      // A shelf that fits on one board stands at the bottom of the well, clear of the seal
      // by construction — [cardShelfPlan] solves the bare shelf first for exactly this
      // reason. Reserving from it would spend capacity protecting something nothing was
      // covering, and seventeen is where that is worth the most: the last count before a
      // second board, using room the reserve would have taken.
      final plan = _plan(17);
      expect(plan.boards.length, 1);
      expect(
        plan.boardWidthUnits(0),
        greaterThan(kCardShelfUnits - kCardSealReserveUnits),
      );
      expect(plan.remainder, 0);
    });

    test('and the hero tile pays nothing either', () {
      // One board by construction, in a stat tile that has no seal in it.
      final tile = cardShelfPlan(
        reading: 2,
        read: 22,
        maxBoards: 1,
        plateUnits: 7.5,
      );
      expect(tile.boards.length, 1);
      expect(
        tile.boardWidthUnits(0, plateUnits: 7.5),
        greaterThan(kCardShelfUnits - kCardSealReserveUnits),
      );
    });
  });

  group('the jitter varies size and never aspect', () {
    test('one scale, applied to both dimensions', () {
      // The shipped row perturbed width and height independently, which moved the
      // aspect between 0.30 and 0.49 and cropped every cover by a different amount.
      // A single scale cannot do that, and this is the guard that keeps it single.
      for (final isbn in ['9788936434120', '9780451524935', 'OL12345W', '']) {
        final s = cardShelfScaleFor(isbn);
        expect(s, lessThanOrEqualTo(1));
        expect(s, greaterThan(1 - kCardShelfJitter));
        // Scaling both dimensions by the same factor cannot change the ratio.
        expect(
          (kCardFaceUnits * s) / (kCardTwoBoardCoverUnits * s),
          closeTo(kDefaultCoverAspect, 1e-12),
        );
      }
    });

    test('it is keyed on the book, not its position', () {
      // So a cover keeps its size when the reader finishes another one and everything
      // shifts along.
      expect(
        cardShelfScaleFor('9788936434120'),
        cardShelfScaleFor('9788936434120'),
      );
      expect(bookHash('9788936434120'), 848182861);
    });
  });

  group('degenerate cases', () {
    test('an empty shelf is empty, not a crash', () {
      final plan = cardShelfPlan(reading: 0, read: 0);
      expect(plan.boards, isEmpty);
      expect(plan.drawn, 0);
      expect(plan.remainder, 0);
    });

    test('more open books than a board holds is survived, not served', () {
      // Not a case the card serves — nobody reads twelve books at once — but it must
      // not overflow the artifact if the data says so.
      final plan = _plan(0, reading: 12);
      expect(plan.boardWidthUnits(0), lessThanOrEqualTo(kCardUnits + 1e-9));
    });

    test('one board can be asked for, for the in-app tile', () {
      final plan = cardShelfPlan(
        reading: 0,
        read: 40,
        maxBoards: 1,
        plateUnits: 7.5,
      );
      expect(plan.boards, hasLength(1));
      expect(plan.remainder, greaterThan(0));
    });
  });
}
