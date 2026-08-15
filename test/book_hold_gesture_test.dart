// Tests for the two-stage hold.
//
// Stage one turns the book. Stage two fires `onLongPress`, which on the home
// shelves enters edit mode. The turn therefore doubles as a progress indicator
// for the hold, which is the reason the threshold is 700ms rather than the
// platform's 500ms — at 500ms the book would sit fully turned for only ~100ms.
//
// The turn angle is read straight off the rendered `BookChassis`, so these
// assert the real composed geometry rather than an internal flag.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/book/book_chassis.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';

double _turn(WidgetTester tester) =>
    tester.widget<BookChassis>(find.byType(BookChassis)).turn;

Future<void> _pump(
  WidgetTester tester, {
  VoidCallback? onTap,
  VoidCallback? onLongPress,
  bool pressEffect = true,
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          disableAnimations: disableAnimations,
        ),
        child: Scaffold(
          body: Center(
            child: BookWidget(
              imageUrl: '',
              isbn: '9788936434120',
              title: '아몬드',
              height: 130,
              onTap: onTap,
              onLongPress: onLongPress,
              pressEffect: pressEffect,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('stage one — the turn', () {
    testWidgets('a book at rest is flat', (tester) async {
      await _pump(tester);
      expect(_turn(tester), 0);
    });

    testWidgets('a quick tap never turns the book', (tester) async {
      // Releasing before the hold threshold must leave no rotation behind, so
      // ordinary navigation taps stay visually quiet.
      var tapped = false;
      await _pump(tester, onTap: () => tapped = true);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BookWidget)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(_turn(tester), 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
      expect(_turn(tester), 0);
    });

    testWidgets('holding past the threshold turns the book', (tester) async {
      await _pump(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BookWidget)),
      );
      // First pump crosses the hold delay and starts the controller; the
      // animation then needs further frames to actually advance, so settle it.
      await tester.pump(kBookHoldDelay + const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(_turn(tester), closeTo(kBookTurnAngle, 1e-6));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('releasing mid-hold returns the book to flat and taps', (
      tester,
    ) async {
      var tapped = false;
      await _pump(tester, onTap: () => tapped = true);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BookWidget)),
      );
      await tester.pump(kBookHoldDelay + const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 130));
      expect(_turn(tester), greaterThan(0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_turn(tester), 0);
      // Holding to inspect and letting go still navigates, matching the
      // behaviour before this change.
      expect(tapped, isTrue);
    });

    testWidgets('a cancelled gesture returns to flat without navigating', (
      tester,
    ) async {
      // What happens when the horizontal shelf list wins the gesture and starts
      // scrolling: the book must not fire a tap.
      var tapped = false;
      await _pump(tester, onTap: () => tapped = true);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BookWidget)),
      );
      await tester.pump(kBookHoldDelay + const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 130));
      expect(_turn(tester), greaterThan(0));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(_turn(tester), 0);
      expect(tapped, isFalse);
    });
  });

  group('stage two — long press', () {
    testWidgets('does not fire before the threshold', (tester) async {
      var fired = false;
      await _pump(tester, onLongPress: () => fired = true);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BookWidget)),
      );
      await tester.pump(kBookStageTwoDelay - const Duration(milliseconds: 1));
      expect(fired, isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('fires at the threshold', (tester) async {
      var fired = false;
      await _pump(tester, onLongPress: () => fired = true);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BookWidget)),
      );
      await tester.pump(kBookStageTwoDelay + const Duration(milliseconds: 1));
      expect(fired, isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('returns the book to flat as it fires', (tester) async {
      // Edit mode starts a wiggle animation, which would fight a turned book.
      await _pump(tester, onLongPress: () {});
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BookWidget)),
      );
      await tester.pump(kBookStageTwoDelay + const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(_turn(tester), 0);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('suppresses the tap that follows on release', (tester) async {
      // A tap recogniser has no upper time bound, so without suppression a long
      // hold would enter edit mode AND push the details route.
      var tapped = false;
      var fired = false;
      await _pump(
        tester,
        onTap: () => tapped = true,
        onLongPress: () => fired = true,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BookWidget)),
      );
      await tester.pump(kBookStageTwoDelay + const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(fired, isTrue);
      expect(tapped, isFalse);
    });

    testWidgets('does not fire after the book is disposed mid-hold', (
      tester,
    ) async {
      // A book scrolled out of the list while held must not enter edit mode.
      var fired = false;
      await _pump(tester, onLongPress: () => fired = true);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BookWidget)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 800));
      expect(fired, isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('pressEffect: false', () {
    testWidgets('disables the turn', (tester) async {
      // Edit mode passes this, where holding belongs to the reorder drag.
      await _pump(tester, pressEffect: false);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BookWidget)),
      );
      await tester.pump(kBookHoldDelay + const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_turn(tester), 0);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('disables stage two', (tester) async {
      var fired = false;
      await _pump(tester, onLongPress: () => fired = true, pressEffect: false);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BookWidget)),
      );
      await tester.pump(const Duration(milliseconds: 900));
      expect(fired, isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('reduced motion', () {
    testWidgets('skips the turn but still reaches stage two', (tester) async {
      var fired = false;
      await _pump(
        tester,
        onLongPress: () => fired = true,
        disableAnimations: true,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BookWidget)),
      );
      await tester.pump(kBookHoldDelay + const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_turn(tester), 0);
      await tester.pump(const Duration(milliseconds: 400));
      expect(fired, isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
