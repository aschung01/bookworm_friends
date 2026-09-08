// Widget tests for the sheet's **sideways** gesture: turning the page.
//
// `LibrarySheet` moves on two axes now. Vertically it snaps between detents, which
// `library_sheet_test.dart` covers. Horizontally it steps along a series its caller
// describes — one year of several, for the read view and the Card — and slides the
// body a page's width to answer. This file is about that second axis, driven with a
// body that has nothing to do with years: the mechanism is the sheet's, and the two
// tabs that use it are covered end to end in their own files.
//
// Four assertions here are the sharp ones.
//
// The first is that the gesture belongs to the **whole card**, header included. That
// is the reason it lives in the sheet rather than in a wrapper around a body: a
// reader swipes wherever their thumb is.
//
// The second is that a turn is **committed on release, not on distance alone**, and
// that a swipe which does not earn one leaves the page exactly where it found it. A
// page that drifted back to centre while the index had already moved would look
// identical for one frame and be wrong for good.
//
// The third is that the two pages travel **locked one span apart**. They are driven
// off a single value for exactly this reason, and the test measures the gap rather
// than trusting it: two animations of the same duration would pass a screenshot at
// both ends and show a seam of empty card in the middle.
//
// The fourth is that a page change the sheet did *not* ask for — a tap on the year
// rail — arrives **instantly**. The rail has already answered the tap, and a page
// that slid in afterwards would read as the sheet moving of its own accord.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/library_sheet.dart';

/// The width a page turn travels: the screen's, which is what the sheet measures a
/// turn against. Named here so the surface below and the assertions cannot disagree.
const double _span = 390;

/// A phone-shaped surface, so the page span is a number the assertions can state.
const _surface = Size(_span, 800);

/// Far enough past `_pageCommitFraction` of [_span] (78pt) that the commit is not
/// resting on a rounding, and short of the span so the page has somewhere to travel.
const Offset _swipeLeft = Offset(-200, 0);
const Offset _swipeRight = Offset(200, 0);

/// Comfortably short of the commit distance, and comfortably past the drag slop, so
/// what it proves is the threshold rather than the gesture never being recognised.
const Offset _nudgeLeft = Offset(-55, 0);

const double _cap = 600;
const double _mid = 400;

Future<void> _pump(
  WidgetTester tester, {
  required ValueNotifier<int> page,
  int pageCount = 3,
  ValueNotifier<bool>? editMode,
  List<int>? asked,
  bool paging = true,
}) async {
  tester.view.physicalSize = _surface * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: Container(color: const Color(0xffE9ECEF))),
            ValueListenableBuilder<bool>(
              valueListenable: editMode ?? ValueNotifier(false),
              builder: (context, isEditMode, _) => ValueListenableBuilder<int>(
                valueListenable: page,
                builder: (context, index, _) => LibrarySheet(
                  isEditMode: isEditMode,
                  initialDetent: LibrarySheetDetent.medium,
                  expandedExtent: _cap,
                  midExtent: _mid,
                  minHeightFraction: 0.3,
                  header: const Row(
                    children: [LibrarySheetTitle(title: 'Library Card')],
                  ),
                  pageIndex: index,
                  pageCount: pageCount,
                  onPageChanged: paging
                      ? (next) {
                          asked?.add(next);
                          page.value = next;
                        }
                      : null,
                  body: Center(child: Text('Page $index')),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Rect _sheetRect(WidgetTester tester) =>
    tester.getRect(find.byType(LibrarySheet));

/// Where a page's content sits horizontally. Reads the *text*, which is centred in a
/// body laid out at the sheet's full width, so the difference between two of them is
/// exactly the difference between the two pages' offsets.
double _pageLeft(WidgetTester tester, int index) =>
    tester.getRect(find.text('Page $index')).left;

/// Swipes without a fling, so what commits the turn is the distance alone.
Future<void> _swipe(WidgetTester tester, Finder on, Offset by) async {
  await tester.drag(on, by);
  await tester.pumpAndSettle();
}

void main() {
  group('Turning the page sideways', () {
    testWidgets(
      'Given a page in the middle of the series, When swiped left, Then the next '
      'page arrives and settles at the centre',
      (tester) async {
        final page = ValueNotifier(1);
        final asked = <int>[];
        await _pump(tester, page: page, asked: asked);

        await _swipe(tester, find.text('Page 1'), _swipeLeft);

        expect(asked, [2], reason: 'asked for the next page, once');
        expect(page.value, 2);
        expect(find.text('Page 2'), findsOneWidget);
        expect(
          find.text('Page 1'),
          findsNothing,
          reason: 'the page it left is dropped once the turn is over',
        );
        expect(
          _pageLeft(tester, 2),
          moreOrLessEquals(_sheetRect(tester).center.dx - 24, epsilon: 24),
          reason: 'the arriving page is back at no offset at all',
        );
      },
    );

    testWidgets(
      'Given a page in the middle of the series, When swiped right, Then the '
      'previous page arrives',
      (tester) async {
        final page = ValueNotifier(1);
        final asked = <int>[];
        await _pump(tester, page: page, asked: asked);

        await _swipe(tester, find.text('Page 1'), _swipeRight);

        expect(asked, [0]);
        expect(find.text('Page 0'), findsOneWidget);
      },
    );

    testWidgets(
      'Given the sheet, When swiped across the header rather than the body, Then '
      'the page still turns',
      (tester) async {
        // The reason this gesture lives in the sheet at all. A reader swipes wherever
        // their thumb happens to be, and only the body moves in answer.
        final page = ValueNotifier(0);
        await _pump(tester, page: page);

        await _swipe(tester, find.text('Library Card'), _swipeLeft);

        expect(page.value, 1);
      },
    );

    testWidgets(
      'Given the sheet, When nudged sideways short of the commit distance, Then the '
      'page is put back and nothing is asked for',
      (tester) async {
        final page = ValueNotifier(1);
        final asked = <int>[];
        await _pump(tester, page: page, asked: asked);
        final resting = _pageLeft(tester, 1);

        await _swipe(tester, find.text('Page 1'), _nudgeLeft);

        expect(asked, isEmpty);
        expect(page.value, 1);
        expect(
          _pageLeft(tester, 1),
          moreOrLessEquals(resting, epsilon: 0.5),
          reason: 'a swipe that did not earn a turn leaves no trace',
        );
      },
    );

    testWidgets(
      'Given the last page, When swiped left, Then nothing is asked for and the page '
      'is put back',
      (tester) async {
        final page = ValueNotifier(2);
        final asked = <int>[];
        await _pump(tester, page: page, asked: asked);
        final resting = _pageLeft(tester, 2);

        await _swipe(tester, find.text('Page 2'), _swipeLeft);

        expect(asked, isEmpty, reason: 'there is nothing past the last page');
        expect(_pageLeft(tester, 2), moreOrLessEquals(resting, epsilon: 0.5));
      },
    );

    testWidgets(
      'Given the first page, When swiped right, Then nothing is asked for',
      (tester) async {
        final page = ValueNotifier(0);
        final asked = <int>[];
        await _pump(tester, page: page, asked: asked);

        await _swipe(tester, find.text('Page 0'), _swipeRight);

        expect(asked, isEmpty);
      },
    );

    testWidgets(
      'Given a series of one, When swiped, Then the sheet does not take the gesture',
      (tester) async {
        // 43 of the 55 readers in the migrated data have finished books in a single
        // year, so this is the common case and not the exception. A sheet that
        // swallowed the swipe to do nothing would just feel unresponsive.
        final page = ValueNotifier(0);
        final asked = <int>[];
        await _pump(tester, page: page, pageCount: 1, asked: asked);
        final resting = _pageLeft(tester, 0);

        await _swipe(tester, find.text('Page 0'), _swipeLeft);

        expect(asked, isEmpty);
        expect(_pageLeft(tester, 0), moreOrLessEquals(resting, epsilon: 0.5));
      },
    );

    testWidgets(
      'Given a sheet with no page callback, When swiped, Then nothing moves',
      (tester) async {
        final page = ValueNotifier(0);
        await _pump(tester, page: page, paging: false);
        final resting = _pageLeft(tester, 0);

        await _swipe(tester, find.text('Page 0'), _swipeLeft);

        expect(page.value, 0);
        expect(_pageLeft(tester, 0), moreOrLessEquals(resting, epsilon: 0.5));
      },
    );

    testWidgets(
      'Given the library is being edited, When swiped, Then the sheet is inert '
      'sideways as well as vertically',
      (tester) async {
        final page = ValueNotifier(1);
        final asked = <int>[];
        await _pump(
          tester,
          page: page,
          asked: asked,
          editMode: ValueNotifier(true),
        );

        await _swipe(tester, find.text('Page 1'), _swipeLeft);

        expect(asked, isEmpty);
      },
    );
  });

  group('The motion of a turn', () {
    testWidgets(
      'Given a swipe, When the turn is halfway through, Then both pages are on '
      'screen exactly one span apart',
      (tester) async {
        // The seam between them may never open, which is why one value drives both.
        // Two animations of the same duration would pass at either end of the turn
        // and show a strip of empty card through the middle of it.
        final page = ValueNotifier(0);
        await _pump(tester, page: page);

        await tester.drag(find.text('Page 0'), _swipeLeft);
        // The frame the new page arrives on, then a slice of the spring.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));

        expect(find.text('Page 0'), findsOneWidget);
        expect(find.text('Page 1'), findsOneWidget);
        expect(
          _pageLeft(tester, 1) - _pageLeft(tester, 0),
          moreOrLessEquals(_span, epsilon: 0.5),
          reason: 'the arriving page is exactly a span behind the one leaving',
        );
        expect(
          _pageLeft(tester, 1),
          greaterThan(_pageLeft(tester, 0)),
          reason: 'a swipe left brings the next page in from the right',
        );

        await tester.pumpAndSettle();
        expect(find.text('Page 0'), findsNothing);
      },
    );

    testWidgets(
      'Given a swipe right, When the turn is halfway through, Then the arriving page '
      'comes in from the left',
      (tester) async {
        final page = ValueNotifier(1);
        await _pump(tester, page: page);

        await tester.drag(find.text('Page 1'), _swipeRight);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));

        expect(
          _pageLeft(tester, 0),
          lessThan(_pageLeft(tester, 1)),
          reason: 'the previous page enters from the side it sits on',
        );
        expect(
          _pageLeft(tester, 1) - _pageLeft(tester, 0),
          moreOrLessEquals(_span, epsilon: 0.5),
        );
      },
    );

    testWidgets(
      'Given a page change nobody swiped for, When it arrives, Then it is instant',
      (tester) async {
        // A tap on the year rail. The tap has already been answered — the capsule
        // shrinks under the finger and the selection haptic fires — and a page that
        // then slid in would read as the sheet deciding to move.
        final page = ValueNotifier(0);
        await _pump(tester, page: page);
        final resting = _pageLeft(tester, 0);

        page.value = 1;
        await tester.pump();

        expect(find.text('Page 0'), findsNothing);
        expect(
          _pageLeft(tester, 1),
          moreOrLessEquals(resting, epsilon: 0.5),
          reason: 'the new page is simply there, at no offset',
        );
      },
    );

    testWidgets(
      'Given paging is on, When the sheet is dragged vertically, Then it still snaps '
      'between detents and the page does not turn',
      (tester) async {
        // Both axes share one detector so they compete in the same arena. A vertical
        // drag has to still be a vertical drag.
        final page = ValueNotifier(1);
        final asked = <int>[];
        await _pump(tester, page: page, asked: asked);
        expect(_sheetRect(tester).height, moreOrLessEquals(_mid, epsilon: 1));

        await tester.drag(find.text('Page 1'), const Offset(0, -300));
        await tester.pumpAndSettle();

        expect(_sheetRect(tester).height, moreOrLessEquals(_cap, epsilon: 1));
        expect(asked, isEmpty);
      },
    );
  });
}
