// Widget tests for the read view — the Library tab's sheet.
//
// Phase 2 gave this sheet two genuinely different states rather than one body
// clipped at two heights, so what is asserted here changed shape with it:
//
//   collapsed  handle + header (title, count, popover filter) + the spine pile
//   expanded   handle + header + year capsules + covers grouped by month
//
// Note what that means for the old tests: before Phase 2 the pile *was* the
// expanded state and collapsed showed nothing but the title. Today's expanded is
// new and today's collapsed is what used to be expanded. The snap positions are
// therefore both different numbers, and the drag is a content swap rather than a
// reveal.
//
// There are now *three* snap positions rather than two — collapsed, medium and the
// whole band — which is why the tests that want the top one drag much further than
// they used to: a release settles on the nearest detent, and a modest drag up from
// the pile lands on the medium one. "Expanded" is still one content state; medium and
// full are two heights of it.
//
// The sheet reads as sitting above the library and never strands anything, which
// `library_sheet_layout_test.dart` and `library_clearance_test.dart` pin from the
// outside; this file is about the read view's own states.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/finished_books_sheet.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/read_month_grid.dart';
import 'package:bookworm_friends/ui/widgets/read_pile.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';

const _libraryKey = Key('library');

/// Surface tall enough that the expanded cap leaves the pile's height behind it,
/// so collapsed and expanded are clearly different numbers.
const _surface = Size(390, 800);

/// Real "now", since neither the sheet nor `readFilterYears` takes a seam for
/// one. Anything that cares whether a fixture year *is* the current year is
/// relative to this, so it does not quietly start failing a year from now.
final _currentYear = DateTime.now().year;

Book _read(String id, String title, DateTime? finished) => Book(
  id: id,
  userId: 'u',
  shelfId: 's',
  isbn: id,
  title: title,
  thumbnail: '',
  status: 2,
  position: 0,
  finishDate: finished,
  createdAt: DateTime(2024),
);

/// Two months in 2026, one in 2025, and one undated — enough for grouping, the
/// year capsules and the undated group all to be visible at once.
List<Book> _books() => [
  _read('a', 'Dune', DateTime(2026, 3, 4)),
  _read('b', 'Circe', DateTime(2026, 3, 19)),
  _read('c', 'Beloved', DateTime(2026, 2, 8)),
  _read('d', 'Snow', DateTime(2025, 11, 2)),
  _read('e', 'Almond', null),
];

/// Enough books that the grid scrolls a long way **and still scrolls once
/// filtered to 2026** — a year that fits the viewport clamps its own offset back
/// to zero, which would pass the scroll tests for the wrong reason.
List<Book> _manyBooks() => [
  for (var month = 1; month <= 12; month++)
    for (var i = 0; i < 6; i++)
      _read('26-$month-$i', 'Book $month.$i', DateTime(2026, month, 1 + i)),
  _read('25-a', 'Snow', DateTime(2025, 11, 2)),
];

class _Host extends StatefulWidget {
  final List<Book> books;
  final ValueNotifier<bool>? editMode;
  final double bottomReserve;

  /// Which year the sheet starts on. A seam for the states that are only
  /// reachable with a year already chosen — collapsed, the filter is a popover,
  /// and driving a platform menu to set it up would test the menu instead.
  final int initialYear;

  const _Host({
    required this.books,
    this.editMode,
    this.bottomReserve = 0,
    this.initialYear = 0,
  });

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late int _year = widget.initialYear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(key: _libraryKey, color: const Color(0xffE9ECEF)),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: widget.editMode ?? ValueNotifier(false),
          builder: (context, isEditMode, _) => FinishedBooksSheet(
            books: widget.books,
            isEditMode: isEditMode,
            filterYear: _year,
            maxExtent: _surface.height,
            bottomReserve: widget.bottomReserve,
            onFilterChanged: (year) => setState(() => _year = year),
          ),
        ),
      ],
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  List<Book>? books,
  ValueNotifier<bool>? editMode,
  double bottomReserve = 0,
  int initialYear = 0,
}) async {
  tester.view.physicalSize = _surface * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    // The grid reports each decoded cover's colour back to `books.cover_color`,
    // so it reads `libraryActionsProvider` — which needs a scope to read from.
    // Nothing here overrides it: no cover in this test ever decodes, so the
    // callback is never reached, and a bare scope is closer to how the sheet
    // actually runs than no scope at all.
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: _Host(
            books: books ?? _books(),
            editMode: editMode,
            initialYear: initialYear,
            bottomReserve: bottomReserve,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Rect _sheetRect(WidgetTester tester) =>
    tester.getRect(find.byType(FinishedBooksSheet));

double _libraryHeight(WidgetTester tester) =>
    tester.getSize(find.byKey(_libraryKey)).height;

Offset _handleCenter(WidgetTester tester) {
  final sheet = _sheetRect(tester);
  return Offset(sheet.center.dx, sheet.top + 12);
}

Future<void> _drag(WidgetTester tester, double dy) async {
  await tester.drag(find.text('Books read'), Offset(0, dy));
  await tester.pumpAndSettle();
}

/// Drags the sheet to its **top** detent in one gesture.
///
/// Far further than the medium-detent tests drag, and that is the point: a release
/// settles on the nearest detent, so a drag has to get past halfway between medium
/// and the top to reach the top. Overshooting is safe — past the cap the drag is
/// rubber-banded and the nearest detent is still the top.
Future<void> _dragToTop(WidgetTester tester) => _drag(tester, -700);

/// The medium detent's height on this host. The band is the whole surface here — no
/// app bar, no home indicator — so the sheet's box is exactly this.
final double _midExtent = sheetMidExtent(_surface.height);

/// How far the month grid is scrolled.
///
/// The grid's own viewport, which is the **first** `Scrollable` under it: each
/// month's covers are a `GridView` inside the list, and those never scroll, so
/// picking one of them by accident would read a permanent zero.
double _gridOffset(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ReadMonthGrid),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position
    .pixels;

/// Asserts the grid's empty message sits at the middle of the body the card is
/// **showing**, wherever the sheet happens to be.
///
/// The visible body runs from the grid's own top — which is where the chrome ends,
/// whatever height the header is at this text scale — to the card's bottom edge,
/// which on this host is the sheet's own: there is no tab bar and no home indicator
/// to reserve a band for.
void _expectCentredInVisibleBody(
  WidgetTester tester,
  String message, {
  required String where,
}) {
  final bodyTop = tester.getRect(find.byType(ReadMonthGrid)).top;
  expect(
    tester.getRect(find.text(message)).center.dy,
    moreOrLessEquals((bodyTop + _sheetRect(tester).bottom) / 2, epsilon: 1),
    reason: 'the message left the middle of the visible card $where',
  );
}

/// How far the pile's shelf sits above the bottom of the sheet's box.
///
/// The pile's own shelf, not one of the library's: the host behind the sheet is a bare
/// [Container], so this is the only one on screen either way, but scoping it says which
/// one is meant.
double _shelfGapFromBottom(WidgetTester tester) =>
    _sheetRect(tester).bottom -
    tester
        .getRect(
          find.descendant(
            of: find.byType(ReadPile),
            matching: find.byType(ShelfWidget),
          ),
        )
        .bottom;

void main() {
  group('Read view, collapsed', () {
    testWidgets(
      'Given read books, When first laid out, Then the pile is the resting state '
      'and the library takes the leftover height',
      (tester) async {
        await _pump(tester);

        final body = tester.getRect(find.byType(Scaffold));
        final sheet = _sheetRect(tester);

        expect(sheet.bottom, moreOrLessEquals(body.bottom));
        expect(find.text('Books read'), findsOneWidget);
        expect(find.text('5'), findsOneWidget);

        // The pile, not the grid.
        expect(find.byType(ReadPile), findsOneWidget);
        expect(find.byType(BookVertical), findsWidgets);
        expect(find.byType(ReadMonthGrid), findsNothing);

        expect(
          _libraryHeight(tester),
          moreOrLessEquals(body.height - sheet.height),
        );
      },
    );

    testWidgets(
      'Given the collapsed sheet, When measured, Then it is the handle, the header '
      'and exactly the pile',
      (tester) async {
        await _pump(tester);

        // The pile's height is a constant the sheet is told rather than measures,
        // because it needs the collapsed position while the grid is on screen.
        // This is the check that the constant matches what the pile draws.
        expect(
          tester.getSize(find.byType(ReadPile)).height,
          closeTo(ReadPile.extent, 0.5),
        );
      },
    );
    testWidgets('Given more read books than fit across, When the pile is swiped sideways, '
        'Then it scrolls rather than being frozen by the sheet', (tester) async {
      // The collapsed body is the one horizontal scroller in any of the sheets, and
      // it is caught by machinery aimed at vertical drags: `LibrarySheet` freezes its
      // body's scrolling below the cap so a swipe *up* opens the sheet instead of
      // scrolling the list, and it does that through a `ScrollConfiguration`, which
      // reaches every scroll view underneath it. Blanket
      // `NeverScrollableScrollPhysics` froze the pile solid at the very position it
      // exists for. The physics the sheet hands down refuse only the vertical axis,
      // and this is what says so.
      await _pump(tester, books: _manyBooks());

      final pile = find
          .descendant(
            of: find.byType(ReadPile),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(pile).position;
      expect(
        position.maxScrollExtent,
        greaterThan(1),
        reason: 'a pile that fits would prove nothing about being frozen',
      );

      await tester.drag(pile, const Offset(-120, 0));
      await tester.pumpAndSettle();

      expect(
        position.pixels,
        greaterThan(1),
        reason: 'the spines move under the finger',
      );
      expect(
        find.byType(ReadPile),
        findsOneWidget,
        reason: 'and a sideways drag is not a reason for the sheet to open',
      );
    });

    testWidgets(
      'Given the pile, When the sheet is dragged up short of the grid, Then the '
      'shelf stays at the bottom of the card and the room opens above the books',
      (tester) async {
        // The stretch between the collapsed position and halfway to the medium detent
        // is still the pile's: the grid does not swap in until `_swapPoint`. Pinned at
        // `ReadPile.extent` the shelf stopped where the collapsed card used to end and
        // left a growing band of blank card below it, with the books standing in
        // mid-air over the tab bar.
        await _pump(tester);
        final restingGap = _shelfGapFromBottom(tester);
        final restingHeight = _sheetRect(tester).height;

        final gesture = await tester.startGesture(_handleCenter(tester));
        // Two moves: the first is spent winning the gesture arena from the handle's
        // tap, and its delta goes with it — a single `moveBy` leaves the sheet exactly
        // where it was.
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveBy(const Offset(0, -80));
        await tester.pump(const Duration(milliseconds: 16));

        expect(
          find.byType(ReadPile),
          findsOneWidget,
          reason: '80pt short of halfway, so this is still the collapsed state',
        );
        expect(
          _sheetRect(tester).height,
          greaterThan(restingHeight + 60),
          reason:
              'the drag has to have grown the card for the rest to mean anything',
        );
        expect(
          _shelfGapFromBottom(tester),
          moreOrLessEquals(restingGap, epsilon: 0.5),
          reason: 'the shelf follows the bottom edge the finger is dragging',
        );

        final shelf = tester.getRect(
          find.descendant(
            of: find.byType(ReadPile),
            matching: find.byType(ShelfWidget),
          ),
        );
        expect(
          tester.getRect(find.byType(BookVertical).first).bottom,
          moreOrLessEquals(shelf.top, epsilon: 0.5),
          reason:
              'the books stand on the shelf, so the headroom opens above them',
        );

        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          _shelfGapFromBottom(tester),
          moreOrLessEquals(restingGap, epsilon: 0.5),
          reason: 'and it is back where it started once the sheet settles',
        );
      },
    );
  });

  group('Read view, expanded', () {
    testWidgets(
      'Given the pile, When dragged to the top, Then it becomes covers grouped by '
      'month',
      (tester) async {
        await _pump(tester);
        final collapsed = _sheetRect(tester).height;

        await _dragToTop(tester);

        expect(_sheetRect(tester).height, greaterThan(collapsed));
        expect(find.byType(ReadMonthGrid), findsOneWidget);
        expect(
          find.byType(ReadPile),
          findsNothing,
          reason: 'the pile is the collapsed state; expanded is the grid',
        );
        expect(find.byType(BookWidget), findsWidgets);

        // Newest month first, and the undated group last.
        expect(find.text('March 2026'), findsOneWidget);
        expect(find.text('February 2026'), findsOneWidget);
        expect(find.text('November 2025'), findsOneWidget);
        expect(find.text('No finish date'), findsOneWidget);
      },
    );

    testWidgets(
      'Given the expanded sheet, When measured, Then it fills the band it shares '
      'with the library',
      (tester) async {
        // It used to stop one shelf row short, so that a strip of library stayed
        // visible behind it. That rule is gone: a year of covers is worth the whole
        // band, and what keeps this a sheet is the handle, the collapsed detent it
        // launches at, and the app bar it never covers.
        await _pump(tester);
        await _dragToTop(tester);

        // The band is the whole surface here — no app bar in this host — and the
        // sheet's box adds the home-indicator inset, which is 0.
        expect(
          _sheetRect(tester).height,
          closeTo(FinishedBooksSheet.expandedExtentFor(_surface.height), 1),
        );
        expect(
          _libraryHeight(tester),
          closeTo(0, 1),
          reason:
              'exactly the band, not more: a point over and the Column holding '
              'both would overflow',
        );
      },
    );

    testWidgets(
      'Given a band reserved for the tab bar, When expanded, Then the grid carries '
      'it as scroll padding so its last row can clear the bar it passes under',
      (tester) async {
        // The two halves of one decision, and they have to be the same number. The
        // sheet lets the grid's viewport run to the card's bottom edge so rows pass
        // under the floating bar; what stops the *bottom* row being stranded behind
        // it is this padding. `LibrarySheet` cannot add it — padding outside the
        // scroll view would put the gap back and defeat the point.
        const reserve = 60.0;
        await _pump(tester, bottomReserve: reserve);
        await _dragToTop(tester);

        expect(
          tester
              .widget<ReadMonthGrid>(find.byType(ReadMonthGrid))
              .bottomPadding,
          closeTo(16 + reserve, 0.5),
          reason:
              'the 16 the grid always wanted, plus the band the sheet is told to '
              'reserve',
        );
      },
    );

    testWidgets(
      'Given more books than fit, When expanded, Then the grid scrolls inside the '
      'sheet rather than making it taller',
      (tester) async {
        final many = [
          for (var i = 0; i < 60; i++)
            _read('b$i', 'Book $i', DateTime(2026, 1 + (i % 12), 1 + i % 27)),
        ];
        await _pump(tester, books: many);
        await _dragToTop(tester);

        final expected = FinishedBooksSheet.expandedExtentFor(_surface.height);
        expect(_sheetRect(tester).height, closeTo(expected, 1));

        // Scrollable, and lazy: not every one of the sixty covers is built.
        final grid = find.descendant(
          of: find.byType(ReadMonthGrid),
          matching: find.byType(Scrollable),
        );
        expect(grid, findsWidgets);
        expect(
          find.byType(BookWidget).evaluate().length,
          lessThan(60),
          reason: 'the outer list must build only the months that fit',
        );
      },
    );
  });

  // The third snap position. Expanded means the whole band, which is the right ceiling
  // for a year of covers but is also the whole shell gone — so the position that shows
  // most of the grid with a strip of library still behind it was added back as a
  // detent rather than as the cap. See `sheetMidExtent`.
  group('Read view, the medium detent', () {
    testWidgets(
      'Given the pile, When dragged up a little, Then it settles at the medium '
      'detent rather than taking the whole band',
      (tester) async {
        await _pump(tester);
        await _drag(tester, -300);

        expect(
          _sheetRect(tester).height,
          closeTo(_midExtent, 1),
          reason:
              'a release settles on the nearest detent, and this drag ends nearer '
              'the medium one than either end',
        );
        expect(
          _libraryHeight(tester),
          closeTo(_surface.height - _midExtent, 1),
          reason: 'the point of the detent: a strip of library is still there',
        );
        expect(
          find.byType(ReadMonthGrid),
          findsOneWidget,
          reason:
              'medium is a height of the expanded state, not a state of its own',
        );
      },
    );

    testWidgets(
      'Given the medium detent, When dragged up again, Then it takes the whole band',
      (tester) async {
        await _pump(tester);
        await _drag(tester, -300);
        await _drag(tester, -300);

        expect(
          _sheetRect(tester).height,
          closeTo(FinishedBooksSheet.expandedExtentFor(_surface.height), 1),
        );
      },
    );

    testWidgets(
      'Given the expanded sheet, When dragged down a little, Then it stops at the '
      'medium detent instead of collapsing all the way to the pile',
      (tester) async {
        await _pump(tester);
        await _dragToTop(tester);
        await _drag(tester, 200);

        expect(_sheetRect(tester).height, closeTo(_midExtent, 1));
        expect(
          find.byType(ReadPile),
          findsNothing,
          reason: 'it has not collapsed, so the pile is not back',
        );
      },
    );

    testWidgets('Given the medium detent, When the grid is measured, Then its viewport ends '
        'at the card\'s edge rather than below it', (tester) async {
      // The whole reason a capped sheet is laid out at the height it is *showing*
      // rather than at its cap and clipped. Clipping is right for a collapse, which
      // is a reveal nobody rests inside of; at a detent it would leave the grid's
      // viewport a third taller than the visible card, so the last rows would sit
      // below the card's bottom edge with no scroll offset able to bring them up.
      final many = [
        for (var i = 0; i < 60; i++)
          _read('b$i', 'Book $i', DateTime(2026, 1 + (i % 12), 1 + i % 27)),
      ];
      await _pump(tester, books: many);
      await _drag(tester, -300);

      expect(_sheetRect(tester).height, closeTo(_midExtent, 1));
      expect(
        tester.getRect(find.byType(ReadMonthGrid)).bottom,
        closeTo(_sheetRect(tester).bottom, 1),
        reason:
            'laid out at the cap instead, the viewport would run '
            '${FinishedBooksSheet.expandedExtentFor(_surface.height) - _midExtent}pt '
            'past the bottom of the card',
      );
    });
  });

  group('Read view, the filter', () {
    testWidgets(
      'Given several years, When collapsed, Then the filter is a popover in the '
      'header and not a capsule row',
      (tester) async {
        await _pump(tester);

        expect(find.text('All time'), findsOneWidget);
        // A capsule row would show every year at once; the popover shows only the
        // current selection.
        expect(find.text('2025'), findsNothing);
      },
    );

    testWidgets(
      'Given several years, When expanded, Then the years are capsules',
      (tester) async {
        await _pump(tester);
        await _drag(tester, -300);

        expect(find.text('All time'), findsWidgets);
        expect(find.text('2026'), findsWidgets);
        expect(find.text('2025'), findsWidgets);
      },
    );

    testWidgets(
      'Given a year is chosen, When it filters, Then the count and the grid follow '
      'it and the year list does not shrink',
      (tester) async {
        await _pump(tester);
        await _drag(tester, -300);

        await tester.tap(find.text('2025').first);
        await tester.pumpAndSettle();

        // Scoped to the header: the month group shows a count of 1 as well.
        expect(
          tester
              .widget<LibrarySheetTitle>(find.byType(LibrarySheetTitle))
              .count,
          1,
          reason: 'one book read in 2025',
        );
        expect(find.text('November'), findsOneWidget);
        expect(find.text('November 2025'), findsNothing);
        expect(find.text('March 2026'), findsNothing);
        expect(
          find.text('2026'),
          findsWidgets,
          reason:
              'the capsules come from every read book, not the filtered set — '
              'filtering to 2025 must not remove 2026 from the choices',
        );
      },
    );

    testWidgets(
      'Given only one year of reading, and it is the current year, When laid '
      'out, Then the filter is still offered',
      (tester) async {
        // There used to be no filter here: all time and the current year select the
        // same books. The rail is unconditional now — see `readFilterYears` for why
        // a control that comes and goes with the library's contents costs more than
        // a capsule that agrees with its neighbour.
        await _pump(
          tester,
          books: [_read('a', 'Dune', DateTime(_currentYear, 3, 4))],
        );

        expect(find.text('All time'), findsOneWidget);
      },
    );

    testWidgets(
      'Given nothing read at all, When laid out, Then the filter is still offered',
      (tester) async {
        // The case that had no control whatsoever, and the one where it matters most:
        // the sheet opens on the current year, so all time is the only scope that can
        // say "nothing read yet" rather than "nothing read this year".
        await _pump(tester, books: const []);

        expect(find.text('All time'), findsOneWidget);
      },
    );

    testWidgets(
      'Given a year with nothing in it is chosen, When collapsed, Then the pile '
      'says so without claiming nothing was ever read',
      (tester) async {
        // The capsules offer every year back to the earliest finish, so a year
        // with no books in it is a normal thing to be looking at. The reader
        // below has books, just not in the year they are on.
        await _pump(
          tester,
          books: [_read('a', 'Dune', DateTime(_currentYear - 2, 3, 4))],
          initialYear: _currentYear - 1,
        );

        expect(
          find.text('No books recorded for ${_currentYear - 1}'),
          findsOneWidget,
        );
        expect(
          find.text('No books read yet 🥲'),
          findsNothing,
          reason:
              'they have read a book — it is in another year — so the library is '
              'not empty and the filter result is not a verdict on their reading',
        );
      },
    );

    testWidgets(
      'Given a year with nothing in it is chosen, When expanded, Then the grid '
      'says the same thing as the pile',
      (tester) async {
        await _pump(
          tester,
          books: [_read('a', 'Dune', DateTime(_currentYear - 2, 3, 4))],
          initialYear: _currentYear - 1,
        );
        await _dragToTop(tester);

        expect(
          find.text('No books recorded for ${_currentYear - 1}'),
          findsOneWidget,
          reason: 'the two states are one message, not two',
        );
      },
    );

    testWidgets(
      'Given a year with nothing in it is chosen, When the sheet moves between '
      'detents, Then the message stays centred in the height the card is showing',
      (tester) async {
        await _pump(
          tester,
          books: [_read('a', 'Dune', DateTime(_currentYear - 2, 3, 4))],
          initialYear: _currentYear - 1,
        );
        final message = 'No books recorded for ${_currentYear - 1}';

        // A live gesture rather than `_drag`, because at rest there was never
        // anything wrong: the sheet lays its body out at the visible height once
        // settled. The body's box is the *expanded* height for the whole of a drag
        // and a spring, so a message centred in the box spent the gesture parked at
        // the middle of a card that was not open yet and then jumped the moment the
        // sheet landed on a detent — twice per drag.
        final gesture = await tester.startGesture(_handleCenter(tester));
        // In steps, with time passing, so the release below carries a sane velocity
        // rather than an instantaneous one.
        for (var step = 0; step < 6; step++) {
          await gesture.moveBy(const Offset(0, -70));
          await tester.pump(const Duration(milliseconds: 16));
          if (step > 2) {
            // Past the halfway point the grid is the body on screen, which is the
            // state this is about; below it the pile is, and the pile's message is
            // fixed to the pile.
            _expectCentredInVisibleBody(tester, message, where: 'mid-drag');
          }
        }

        await gesture.up();
        // Frame by frame through the spring, overshoot included. One sample would
        // pass on a version that only corrected itself once settled.
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          _expectCentredInVisibleBody(
            tester,
            message,
            where: 'on frame $frame of the spring',
          );
        }

        await tester.pumpAndSettle();
        _expectCentredInVisibleBody(tester, message, where: 'once settled');
      },
    );
  });

  // Where the viewport lands after a filter tap, which is a content question and
  // not an animation one: the grid cuts to the new list rather than transitioning
  // to it, because nothing enters, exits or resizes — the sheet's detents come from
  // the band rather than the content, and the capsule row does not reflow, since a
  // selected label shares its weight with an unselected one and the pill adds no
  // size. What the tap does have to do is start the new list at its top.
  group('Read view, the filter and the scroll position', () {
    testWidgets(
      'Given the grid is scrolled deep into all time, When a year is chosen, Then '
      'the new list starts at its top rather than mid-year',
      (tester) async {
        await _pump(tester, books: _manyBooks());
        await _dragToTop(tester);

        await tester.drag(find.byType(ReadMonthGrid), const Offset(0, -600));
        await tester.pumpAndSettle();
        // Also proves the offset read below is the grid's own viewport and not one
        // of the month grids inside it, which never scroll.
        expect(
          _gridOffset(tester),
          greaterThan(0),
          reason: 'the drag has to have scrolled for the rest to mean anything',
        );

        await tester.tap(find.text('2026').first);
        await tester.pumpAndSettle();

        expect(
          _gridOffset(tester),
          0,
          reason:
              'a year still taller than the viewport would otherwise keep the '
              'offset and open mid-year, with its newest month above the fold',
        );
      },
    );

    testWidgets(
      'Given a year is showing, When all time is chosen again, Then it too starts '
      'at the top',
      (tester) async {
        await _pump(tester, books: _manyBooks());
        await _dragToTop(tester);

        await tester.tap(find.text('2026').first);
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ReadMonthGrid), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(_gridOffset(tester), greaterThan(0));

        await tester.tap(find.text('All time').first);
        await tester.pumpAndSettle();

        expect(_gridOffset(tester), 0);
      },
    );

    testWidgets(
      'Given someone is scrolling, When a book arrives in a new month, Then the '
      'viewport stays where they left it',
      (tester) async {
        await _pump(tester, books: _manyBooks());
        await _dragToTop(tester);

        await tester.drag(find.byType(ReadMonthGrid), const Offset(0, -600));
        await tester.pumpAndSettle();
        final offset = _gridOffset(tester);
        expect(offset, greaterThan(0));

        // A finish logged on another device, or a refresh: same filter, one more
        // book, in a month that was not in the list before.
        await _pump(
          tester,
          books: [
            ..._manyBooks(),
            _read('new', 'Kim Jiyoung', DateTime(2024, 7, 3)),
          ],
        );

        expect(
          _gridOffset(tester),
          offset,
          reason:
              'the reset is keyed on the filter, not on the books — an arriving '
              'row must not yank the list out from under a reader',
        );
      },
    );
  });

  group('Read view, swiping the year', () {
    /// Past the fifth of the card's width that commits a turn, and short of a whole
    /// page. Sent as a plain drag, so what commits it is the distance rather than a
    /// fling.
    const swipe = 200.0;

    /// The count in the sheet's own header, which is the filtered set's size. Scoped
    /// to the header: a month group prints a count too.
    int headerCount(WidgetTester tester) =>
        tester.widget<LibrarySheetTitle>(find.byType(LibrarySheetTitle)).count!;

    testWidgets(
      'Given the expanded grid on all time, When swiped left, Then the next year in '
      'the rail is selected and the grid follows it',
      (tester) async {
        // The rail reads `All time / 2026 / 2025`, and a swipe left moves the content
        // left — revealing what sits to its right, which is the next capsule along.
        // The two orders are the same one on purpose.
        await _pump(tester);
        await _dragToTop(tester);
        expect(headerCount(tester), 5, reason: 'all time, to start');

        await tester.drag(find.byType(ReadMonthGrid), const Offset(-swipe, 0));
        await tester.pumpAndSettle();

        expect(headerCount(tester), 3, reason: 'three books finished in 2026');
        expect(find.text('March 2026'), findsNothing);
        expect(
          find.text('March'),
          findsOneWidget,
          reason: 'a year-filtered grid drops the year from its month headers',
        );
      },
    );

    testWidgets(
      'Given a year, When swiped right, Then it goes back up the rail',
      (tester) async {
        await _pump(tester, initialYear: 2026);
        await _dragToTop(tester);

        await tester.drag(find.byType(ReadMonthGrid), const Offset(swipe, 0));
        await tester.pumpAndSettle();

        expect(headerCount(tester), 5, reason: 'back to all time');
      },
    );

    testWidgets(
      'Given the earliest year in the rail, When swiped left, Then it stays where it '
      'is',
      (tester) async {
        await _pump(tester, initialYear: 2025);
        await _dragToTop(tester);

        await tester.drag(find.byType(ReadMonthGrid), const Offset(-swipe, 0));
        await tester.pumpAndSettle();

        expect(
          headerCount(tester),
          1,
          reason: 'still 2025 — there is nothing past the earliest finish',
        );
      },
    );

    testWidgets(
      'Given a swipe, When the turn is halfway through, Then the year it is leaving '
      'and the year it is arriving at are both on screen',
      (tester) async {
        // The turn is a slide of the grid, not a cut. Both months below belong to
        // years the rail offers separately, so seeing them at once is only possible
        // while two pages are travelling together.
        await _pump(tester);
        await _dragToTop(tester);

        await tester.drag(find.byType(ReadMonthGrid), const Offset(-swipe, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));

        expect(find.byType(ReadMonthGrid), findsNWidgets(2));
        await tester.pumpAndSettle();
        expect(find.byType(ReadMonthGrid), findsOneWidget);
      },
    );

    testWidgets(
      'Given more read books than fit across, When the collapsed pile is swiped '
      'sideways, Then the pile scrolls and the year is left alone',
      (tester) async {
        // The one place the sheet does not take a sideways drag, and it should not:
        // running along the pile is what the gesture means there. The pile wins by
        // being deeper in the tree, and only while it has something to scroll — see
        // the test below for the other half.
        await _pump(tester, books: _manyBooks());
        final before = headerCount(tester);

        await tester.drag(find.byType(ReadPile), const Offset(-swipe, 0));
        await tester.pumpAndSettle();

        expect(headerCount(tester), before);
      },
    );

    testWidgets(
      'Given a pile short enough to fit the card, When it is swiped sideways, Then '
      'the year turns instead',
      (tester) async {
        // The physics the sheet hands its body decline a drag a list has no room to
        // answer, so the gesture falls through to the sheet rather than being
        // swallowed. Nothing new was written for this — it is what
        // `_NoVerticalScrollPhysics` deferring to `super` already meant — but it is
        // the behaviour a reader with five read books actually gets.
        await _pump(tester);
        final pile = find
            .descendant(
              of: find.byType(ReadPile),
              matching: find.byType(Scrollable),
            )
            .first;
        expect(
          tester.state<ScrollableState>(pile).position.maxScrollExtent,
          0,
          reason: 'a pile that could scroll would prove the opposite point',
        );

        await tester.drag(find.byType(ReadPile), const Offset(-swipe, 0));
        await tester.pumpAndSettle();

        expect(headerCount(tester), 3, reason: '2026, the next year along');
      },
    );

    testWidgets(
      'Given the library is being edited, When the sheet is swiped, Then the year is '
      'left alone',
      (tester) async {
        final editMode = ValueNotifier(true);
        addTearDown(editMode.dispose);
        await _pump(tester, editMode: editMode);
        final before = headerCount(tester);

        await tester.drag(find.text('Books read'), const Offset(-swipe, 0));
        await tester.pumpAndSettle();

        expect(headerCount(tester), before);
      },
    );
  });

  group('Read view, unchanged behaviours', () {
    testWidgets(
      'Given no read books, When rendered, Then the empty state shows in place of '
      'the pile',
      (tester) async {
        await _pump(tester, books: const []);

        expect(find.text('No books read yet 🥲'), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
      },
    );

    testWidgets(
      'Given an expanded sheet, When the library enters edit mode, Then it springs '
      'shut and reopens when editing ends',
      (tester) async {
        final editMode = ValueNotifier(false);
        addTearDown(editMode.dispose);

        await _pump(tester, editMode: editMode);
        await _drag(tester, -300);
        final expanded = _sheetRect(tester).height;
        final expandedLibrary = _libraryHeight(tester);

        editMode.value = true;
        await tester.pumpAndSettle();

        expect(_sheetRect(tester).height, lessThan(expanded));
        expect(find.byType(ReadPile), findsOneWidget);
        expect(_libraryHeight(tester), greaterThan(expandedLibrary));

        editMode.value = false;
        await tester.pumpAndSettle();
        expect(_sheetRect(tester).height, closeTo(expanded, 1));
      },
    );

    testWidgets(
      'Given the sheet, When the handle is tapped, Then it toggles between the two '
      'states',
      (tester) async {
        await _pump(tester);
        final collapsed = _sheetRect(tester).height;

        await tester.tapAt(_handleCenter(tester));
        await tester.pumpAndSettle();
        expect(_sheetRect(tester).height, greaterThan(collapsed));
        expect(find.byType(ReadMonthGrid), findsOneWidget);

        await tester.tapAt(_handleCenter(tester));
        await tester.pumpAndSettle();
        expect(_sheetRect(tester).height, closeTo(collapsed, 1));
        expect(find.byType(ReadPile), findsOneWidget);
      },
    );

    testWidgets(
      'Given a collapsed sheet, When it springs open, Then the overshoot stops at '
      'the band rather than stretching past the screen',
      (tester) async {
        // The spring is under-damped and still overshoots — `library_sheet_test.dart`
        // measures that on a sheet with room above it. This one expands to the whole
        // band, and there is nowhere above "all of it" to stretch into: the box is
        // clamped, so the overshoot is absorbed instead of pushing the sheet past the
        // bottom of the `Column` and overflowing the library out of existence.
        await _pump(tester);

        await tester.tapAt(_handleCenter(tester));
        var tallest = 0.0;
        for (var frame = 0; frame < 40; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final height = _sheetRect(tester).height;
          if (height > tallest) tallest = height;
        }
        await tester.pumpAndSettle();

        expect(tallest, closeTo(_sheetRect(tester).height, 1));
        expect(tallest, closeTo(_surface.height, 1));
        expect(
          tester.takeException(),
          isNull,
          reason: 'and nothing overflowed on the way',
        );
      },
    );
  });
}
