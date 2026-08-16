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
// The sheet reads as sitting above the library and never strands anything, which
// `library_sheet_layout_test.dart` and `library_clearance_test.dart` pin from the
// outside; this file is about the read view's own two states.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/finished_books_sheet.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/read_month_grid.dart';
import 'package:bookworm_friends/ui/widgets/read_pile.dart';

const _libraryKey = Key('library');

/// Surface tall enough that the expanded cap leaves the pile's height behind it,
/// so collapsed and expanded are clearly different numbers.
const _surface = Size(390, 800);

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

class _Host extends StatefulWidget {
  final List<Book> books;
  final ValueNotifier<bool>? editMode;

  const _Host({required this.books, this.editMode});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int _year = 0;

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
}) async {
  tester.view.physicalSize = _surface * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: _Host(books: books ?? _books(), editMode: editMode),
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
  });

  group('Read view, expanded', () {
    testWidgets(
      'Given the pile, When dragged up, Then it becomes covers grouped by month',
      (tester) async {
        await _pump(tester);
        final collapsed = _sheetRect(tester).height;

        await _drag(tester, -300);

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
      'Given the expanded sheet, When measured, Then it stops short of the top so '
      'a shelf stays visible',
      (tester) async {
        await _pump(tester);
        await _drag(tester, -300);

        final expected = FinishedBooksSheet.expandedExtentFor(
          _surface.height,
          bookRowExtent(_surface.height * 0.15),
        );
        // The sheet's box adds the home-indicator inset, which is 0 here.
        expect(_sheetRect(tester).height, closeTo(expected, 1));
        expect(
          _sheetRect(tester).height,
          lessThan(_surface.height),
          reason: 'an expanded sheet that covered everything would be a page',
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
        await _drag(tester, -300);

        final expected = FinishedBooksSheet.expandedExtentFor(
          _surface.height,
          bookRowExtent(_surface.height * 0.15),
        );
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
        expect(find.text('November 2025'), findsOneWidget);
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
      'Given only one year of reading, When laid out, Then there is no filter to '
      'show',
      (tester) async {
        await _pump(tester, books: [_read('a', 'Dune', DateTime(2026, 3, 4))]);

        expect(find.text('All time'), findsNothing);
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
      'Given a collapsed sheet, When it springs open, Then it still overshoots '
      'before settling',
      (tester) async {
        await _pump(tester);

        await tester.tapAt(_handleCenter(tester));
        var tallest = 0.0;
        for (var frame = 0; frame < 40; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final height = _sheetRect(tester).height;
          if (height > tallest) tallest = height;
        }
        await tester.pumpAndSettle();

        expect(tallest, greaterThan(_sheetRect(tester).height + 4));
      },
    );
  });
}
