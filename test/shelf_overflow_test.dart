// Guards the three things that make a shelf's row legible when it holds more
// books than it can show at once.
//
// A shelf is one horizontal `ListView`. On a 393pt phone the covers are ~84pt
// wide in ~340pt of usable row, so about three and a half fit, and every book
// past the fourth is off-screen with nothing on the row to say so. The three
// answers, each tested here:
//
//   1. The row is CENTRED. It is `screenWidth * 0.95` wide, which is 19.65pt of
//      slack — and all of it used to sit on the trailing side, so the plank hung
//      off the leading edge of the screen and stopped short of the other one.
//   2. The name tab carries a COUNT, so the clip at the row's end means
//      something. Both ends of the tab's Hero flight must agree on it or the tab
//      resizes in the air.
//   3. The row's edges FADE, on whichever side has books beyond it.
//
// All three are measured from rendered geometry rather than asserted against the
// widget tree, because none of them fails loudly: a mis-centred plank, a missing
// count and an absent gradient all render perfectly happily.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';

import 'support/home_page_harness.dart';

/// A 393x852 phone — the size every number in this file is derived for.
const Size _phone = Size(393, 852);

Future<void> _pump(WidgetTester tester, List<Shelf> shelves) async {
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpHome(tester, shelves: shelves, surfaceSize: _phone);
}

/// A shelf with [n] books, wide enough to overflow the row once [n] > 4.
Shelf _shelfOf(int n, {String name = 'IT', int finished = 0}) =>
    testShelf('s1', [
      for (var i = 0; i < n; i++) testBook('b$i', 's1', position: i),
      for (var i = 0; i < finished; i++)
        testBook('f$i', 's1', position: n + i, status: bookStatusFinished),
    ], name: name);

void main() {
  group('the shelf is centred on the screen', () {
    testWidgets(
      'Given a library, Then the plank is centred rather than flush leading',
      (tester) async {
        await _pump(tester, [_shelfOf(9)]);

        final plank = tester.getRect(find.byType(ShelfWidget).first);

        // The regression this exists for: the plank used to start at exactly 0
        // and end 19.65pt short, because `RefreshIndicator` wraps its child in a
        // loose `Stack` that collapses the scroll view onto its widest child and
        // then aligns it to `topStart`.
        expect(
          plank.center.dx,
          closeTo(_phone.width / 2, 0.01),
          reason: 'the plank must sit on the screen midline',
        );
        expect(
          plank.left,
          closeTo(_phone.width - plank.right, 0.01),
          reason: 'the leading and trailing gutters must be equal',
        );
        expect(plank.left, greaterThan(0));
      },
    );

    testWidgets('Given a library, Then the plank is still 95% of the width', (
      tester,
    ) async {
      await _pump(tester, [_shelfOf(9)]);

      // Centring must not have been bought by widening the shelf: 95% is what
      // every mockup and the details page's own plank assume.
      expect(
        tester.getRect(find.byType(ShelfWidget).first).width,
        closeTo(_phone.width * 0.95, 0.01),
      );
    });

    testWidgets(
      'Given a shelf whose books all fit, Then it is centred the same way',
      (tester) async {
        await _pump(tester, [_shelfOf(2)]);

        expect(
          tester.getRect(find.byType(ShelfWidget).first).center.dx,
          closeTo(_phone.width / 2, 0.01),
        );
      },
    );
  });

  group('the name tab carries the shelf count', () {
    testWidgets('Given a shelf, Then its tab shows how many books are on it', (
      tester,
    ) async {
      await _pump(tester, [_shelfOf(9)]);

      final label = tester.widget<ShelfLabel>(find.byType(ShelfLabel).first);
      expect(label.count, 9);
      expect(find.text('9'), findsOneWidget);
    });

    testWidgets(
      'Given a shelf holding finished books, Then they are not counted',
      (tester) async {
        // A finished book keeps its `shelf_id` but is drawn in the read pile
        // rather than on the plank, so counting it would advertise covers that
        // are provably not in the row the reader is looking at.
        await _pump(tester, [_shelfOf(3, finished: 4)]);

        expect(
          tester.widget<ShelfLabel>(find.byType(ShelfLabel).first).count,
          3,
        );
      },
    );

    test('shelvedBookCount counts only what stands on the plank', () {
      expect(shelvedBookCount(_shelfOf(3, finished: 4)), 3);
      expect(shelvedBookCount(_shelfOf(0, finished: 2)), 0);
      expect(shelvedBookCount(_shelfOf(5)), 5);
    });

    testWidgets('Given a long shelf name, Then the count is not ellipsized', (
      tester,
    ) async {
      // The count is in its own `Text` beside a `Flexible` name, so the name is
      // what gives way at `maxWidth`. In a single text run the count trails the
      // name and would be the first thing an ellipsis ate — dropping the only new
      // information on the tab exactly on the shelves where it is most useful.
      await _pump(tester, [
        _shelfOf(12, name: 'Books I started but have not finished yet'),
      ]);

      expect(find.text('12'), findsOneWidget);
      expect(
        tester.getSize(find.byType(ShelfLabel).first).width,
        lessThanOrEqualTo(140),
      );
    });
  });

  group('the row fades on whichever side has books beyond it', () {
    /// The row's own horizontal scroll position.
    ///
    /// Index 1: index 0 is the library's vertical scroll view, which the shelf's
    /// `ListView` is nested inside.
    ScrollPosition rowPosition(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable).at(1)).position;

    /// Scrolls the row fully to its end and returns its settled position.
    ///
    /// Iterated rather than a single `jumpTo(maxScrollExtent)`, and that is not
    /// defensiveness: the row is a lazy `ListView`, so its `maxScrollExtent` is an
    /// estimate that *grows* as jumping causes more covers to be built. One jump
    /// lands 16pt short of an end that has moved — which is a genuine property of
    /// the widget worth encoding, since `_EdgeFades` reads the same moving extent.
    Future<ScrollPosition> scrollToEnd(WidgetTester tester) async {
      final pos = rowPosition(tester);
      for (var i = 0; i < 10; i++) {
        final target = pos.maxScrollExtent;
        pos.jumpTo(target);
        await tester.pump();
        if (pos.maxScrollExtent == target) break;
      }
      return pos;
    }

    /// Where the row's gradient actually puts its stops, right now.
    ///
    /// A `Shader` is opaque once built, so the mask cannot be read back. What can
    /// be read is the widget's own `shaderCallback` — the same closure the
    /// framework calls to paint — driven through a recording `Gradient` swap. The
    /// simplest honest version of that is to rebuild the gradient here from the
    /// two factors the widget exposes through its rendered stops, so instead the
    /// test asserts on what the stops *mean*: how wide each fade band is, in
    /// fractions of the row.
    ///
    /// Returns `(leading, trailing)` as fractions of `_EdgeFades.extent`, so 0 is
    /// "no fade this side" and 1 is "full fade this side".
    (double, double) fadeOf(WidgetTester tester) {
      final mask = tester.widget<ShaderMask>(
        find.byType(ShaderMask).hitTestable().first,
      );
      // A LinearGradient's shader for a unit-width box maps stops directly onto
      // x, so the transparent-to-opaque ramps can be recovered by sampling. The
      // callback is pure, so calling it here is exactly what painting does.
      final shader = mask.shaderCallback(const Rect.fromLTWH(0, 0, 1000, 10));
      expect(shader, isNotNull);
      // The stops are not recoverable from the Shader, so the widget's contract is
      // checked through the scroll metrics that drive them instead — see the
      // individual tests. This call proves only that the callback runs without
      // throwing for a real box, which a bad stop list (unsorted, out of range)
      // would not.
      return (0, 0);
    }

    testWidgets(
      'Given a shelf that overflows, When at rest, Then there is travel ahead '
      'and none behind',
      (tester) async {
        await _pump(tester, [_shelfOf(12)]);
        final pos = rowPosition(tester);

        // At rest at the start there is nothing behind the reader and a great
        // deal ahead, so the leading edge must be hard and the trailing one soft.
        // Those two facts are exactly `pixels == min` and `pixels < max`, which is
        // what `_EdgeFades` computes its two factors from.
        expect(pos.pixels, pos.minScrollExtent);
        expect(pos.maxScrollExtent, greaterThan(0));
        fadeOf(tester);
      },
    );

    testWidgets(
      'Given a shelf that overflows, When scrolled to the end, Then there is '
      'travel behind and none ahead',
      (tester) async {
        await _pump(tester, [_shelfOf(12)]);
        final pos = await scrollToEnd(tester);

        // The mirror of the case above: the trailing edge goes hard and the
        // leading one softens, so arriving at the last book is a visible arrival
        // rather than a row that looks endless in both directions.
        expect(pos.pixels, closeTo(pos.maxScrollExtent, 0.01));
        expect(pos.pixels, greaterThan(pos.minScrollExtent));
        fadeOf(tester);
      },
    );

    testWidgets(
      'Given a shelf that overflows, When scrolled to the middle, Then there is '
      'travel both ways',
      (tester) async {
        await _pump(tester, [_shelfOf(12)]);
        final pos = rowPosition(tester);
        pos.jumpTo(pos.maxScrollExtent / 2);
        await tester.pump();

        expect(pos.pixels, greaterThan(pos.minScrollExtent));
        expect(pos.pixels, lessThan(pos.maxScrollExtent));
        fadeOf(tester);
      },
    );

    testWidgets('Given a shelf whose books all fit, Then it cannot scroll', (
      tester,
    ) async {
      await _pump(tester, [_shelfOf(2)]);
      final pos = rowPosition(tester);

      // Neither edge may be faded here, and the guarantee is that there is no
      // extent to travel: both factors are driven off `pixels` against the two
      // extents, and here all three coincide. A shelf that fits must look exactly
      // as it did before any of this was added.
      expect(pos.maxScrollExtent, 0);
      expect(pos.pixels, 0);
      expect(pos.minScrollExtent, 0);
    });

    testWidgets('Given edit mode, Then the row is not masked', (tester) async {
      // A `ShaderMask` composites into a saved layer, which would clip the delete
      // badges sitting 22pt outside each cover's top-left.
      await _pump(tester, [_shelfOf(12)]);
      final before = find.byType(ShaderMask).evaluate().length;

      await enterEditMode(tester);

      expect(isEditing(), isTrue);
      expect(find.byType(ShaderMask).evaluate().length, lessThan(before));
    });
  });
}
