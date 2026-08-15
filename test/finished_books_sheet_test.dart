// Widget tests for the "Books read" bottom sheet.
//
// The sheet is pinned below the library: it reports its (possibly collapsed)
// height to the parent Column so the library above only ever gets the leftover
// space. These tests guard both halves of that contract — the sheet is fully
// visible without scrolling, and dragging/tapping it snaps between its natural
// (max) height and the collapsed handle+title height while the library grows.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';
import 'package:bookworm_friends/ui/widgets/finished_books_sheet.dart';

const _libraryKey = Key('library');

List<Book> _books(int count) => List.generate(
  count,
  (i) => Book(
    id: '$i',
    userId: 'u',
    shelfId: 's',
    isbn: '$i',
    title: 'Book $i',
    thumbnail: '',
    status: 2,
    position: i,
    createdAt: DateTime(2024),
  ),
);

Widget _wrap(List<Book> books, {ValueNotifier<bool>? editMode}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(key: _libraryKey, color: const Color(0xffE9ECEF)),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: editMode ?? ValueNotifier(false),
            builder: (context, isEditMode, _) => FinishedBooksSheet(
              books: books,
              isEditMode: isEditMode,
              filterYear: 0,
              filterMonth: 0,
              onFilterPressed: () {},
            ),
          ),
        ],
      ),
    ),
  );
}

Rect _sheetRect(WidgetTester tester) =>
    tester.getRect(find.byType(FinishedBooksSheet));

double _libraryHeight(WidgetTester tester) =>
    tester.getSize(find.byKey(_libraryKey)).height;

/// Drags the sheet by [dy] (positive = downwards) starting from its title row.
Future<void> _dragSheet(WidgetTester tester, double dy) async {
  await tester.drag(find.text('Books read'), Offset(0, dy));
  await tester.pumpAndSettle();
}

/// The drag handle sits at the top-center of the sheet.
Offset _handleCenter(WidgetTester tester) {
  final sheet = _sheetRect(tester);
  return Offset(sheet.center.dx, sheet.top + 12);
}

void main() {
  group('FinishedBooksSheet', () {
    testWidgets(
      'Given finished books, When first laid out, Then the sheet is fully visible and the library takes the leftover height',
      (tester) async {
        await tester.pumpWidget(_wrap(_books(12)));
        await tester.pumpAndSettle();

        final body = tester.getRect(find.byType(Scaffold));
        final sheet = _sheetRect(tester);

        // Pinned to the bottom, entirely on screen, no scrolling needed.
        expect(sheet.bottom, moreOrLessEquals(body.bottom));
        expect(sheet.top, greaterThan(body.top));
        expect(find.text('Books read'), findsOneWidget);
        expect(find.text('12'), findsOneWidget);
        expect(find.byType(BookVertical), findsWidgets);

        // Library height is exactly what the sheet left over.
        expect(
          _libraryHeight(tester),
          moreOrLessEquals(body.height - sheet.height),
        );
      },
    );

    testWidgets(
      'Given an expanded sheet, When dragged down, Then it snaps to the handle+title height and the library grows',
      (tester) async {
        await tester.pumpWidget(_wrap(_books(12)));
        await tester.pumpAndSettle();

        final expandedHeight = _sheetRect(tester).height;
        final expandedLibraryHeight = _libraryHeight(tester);

        await _dragSheet(tester, 200);

        final collapsedHeight = _sheetRect(tester).height;
        expect(collapsedHeight, lessThan(expandedHeight / 2));
        // The handle and title survive the collapse.
        expect(collapsedHeight, greaterThan(20));
        expect(find.text('Books read'), findsOneWidget);
        expect(_sheetRect(tester).bottom, moreOrLessEquals(600));

        // Every pixel the sheet gave up goes to the library.
        expect(
          _libraryHeight(tester) - expandedLibraryHeight,
          moreOrLessEquals(expandedHeight - collapsedHeight),
        );
      },
    );

    testWidgets(
      'Given a collapsed sheet, When dragged up, Then it snaps back to its natural (max) height',
      (tester) async {
        await tester.pumpWidget(_wrap(_books(12)));
        await tester.pumpAndSettle();

        final expandedHeight = _sheetRect(tester).height;

        await _dragSheet(tester, 200);
        expect(_sheetRect(tester).height, lessThan(expandedHeight));

        await _dragSheet(tester, -200);
        expect(_sheetRect(tester).height, moreOrLessEquals(expandedHeight));
      },
    );

    testWidgets(
      'Given an expanded sheet, When the drag handle is tapped, Then it toggles collapsed and back',
      (tester) async {
        await tester.pumpWidget(_wrap(_books(12)));
        await tester.pumpAndSettle();

        final expandedHeight = _sheetRect(tester).height;

        await tester.tapAt(_handleCenter(tester));
        await tester.pumpAndSettle();
        expect(_sheetRect(tester).height, lessThan(expandedHeight));

        await tester.tapAt(_handleCenter(tester));
        await tester.pumpAndSettle();
        expect(_sheetRect(tester).height, moreOrLessEquals(expandedHeight));
      },
    );

    testWidgets(
      'Given no finished books, When rendered, Then the empty state is shown and the sheet still collapses',
      (tester) async {
        await tester.pumpWidget(_wrap(const []));
        await tester.pumpAndSettle();

        expect(find.text('No books read yet 🥲'), findsOneWidget);
        final expandedHeight = _sheetRect(tester).height;

        await _dragSheet(tester, 200);
        expect(_sheetRect(tester).height, lessThan(expandedHeight));
      },
    );

    testWidgets(
      'Given an expanded sheet, When the library enters edit mode, Then it springs shut and reopens when editing ends',
      (tester) async {
        final editMode = ValueNotifier(false);
        addTearDown(editMode.dispose);

        await tester.pumpWidget(_wrap(_books(12), editMode: editMode));
        await tester.pumpAndSettle();
        final expandedHeight = _sheetRect(tester).height;
        final expandedLibraryHeight = _libraryHeight(tester);

        editMode.value = true;
        await tester.pumpAndSettle();

        expect(_sheetRect(tester).height, lessThan(expandedHeight / 2));
        expect(find.text('Books read'), findsOneWidget);
        // The library gets the freed space to edit shelves in.
        expect(_libraryHeight(tester), greaterThan(expandedLibraryHeight));

        editMode.value = false;
        await tester.pumpAndSettle();

        expect(_sheetRect(tester).height, moreOrLessEquals(expandedHeight));
      },
    );

    testWidgets(
      'Given a sheet the user already collapsed, When edit mode ends, Then it stays collapsed',
      (tester) async {
        final editMode = ValueNotifier(false);
        addTearDown(editMode.dispose);

        await tester.pumpWidget(_wrap(_books(12), editMode: editMode));
        await tester.pumpAndSettle();
        await _dragSheet(tester, 200);
        final collapsedHeight = _sheetRect(tester).height;

        editMode.value = true;
        await tester.pumpAndSettle();
        editMode.value = false;
        await tester.pumpAndSettle();

        expect(_sheetRect(tester).height, moreOrLessEquals(collapsedHeight));
      },
    );

    testWidgets(
      'Given the library is in edit mode, When the sheet is dragged or tapped, Then it stays pinned shut',
      (tester) async {
        final editMode = ValueNotifier(false);
        addTearDown(editMode.dispose);

        await tester.pumpWidget(_wrap(_books(12), editMode: editMode));
        await tester.pumpAndSettle();
        editMode.value = true;
        await tester.pumpAndSettle();
        final collapsedHeight = _sheetRect(tester).height;

        await _dragSheet(tester, -200);
        expect(_sheetRect(tester).height, moreOrLessEquals(collapsedHeight));

        await tester.tapAt(_handleCenter(tester));
        await tester.pumpAndSettle();
        expect(_sheetRect(tester).height, moreOrLessEquals(collapsedHeight));
      },
    );

    // The spring is what makes the sheet feel springy: if these two ever stop
    // overshooting, the motion has degenerated into a plain ease.
    testWidgets(
      'Given a collapsed sheet, When it springs open, Then it overshoots the expanded position before settling',
      (tester) async {
        await tester.pumpWidget(_wrap(_books(12)));
        await tester.pumpAndSettle();
        await _dragSheet(tester, 200);

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

    testWidgets(
      'Given an expanded sheet, When it springs closed, Then it dips past the collapsed position before settling',
      (tester) async {
        await tester.pumpWidget(_wrap(_books(12)));
        await tester.pumpAndSettle();

        await tester.tapAt(_handleCenter(tester));
        var lowest = 0.0;
        for (var frame = 0; frame < 40; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          // The title rides along with the sheet, so it tracks the dip even
          // though the laid-out slot stays at the collapsed height.
          final titleTop = tester.getRect(find.text('Books read')).top;
          if (titleTop > lowest) lowest = titleTop;
        }
        await tester.pumpAndSettle();

        expect(
          lowest,
          greaterThan(tester.getRect(find.text('Books read')).top + 4),
        );
      },
    );
  });
}
