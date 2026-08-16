// Widget tests for the sheet chrome itself, driven with a body that has nothing
// to do with read books.
//
// `finished_books_sheet_test.dart` covers the Library tab's sheet end to end.
// This file exists because the shell gives every tab its own sheet over one
// shared library background, so the handle, the two snap positions and the
// spring have to hold for *any* contents — not just for a pile of covers whose
// height happens to make the numbers work.
//
// The sharp assertion is that the collapsed position is exactly "handle plus
// header, no body". A sheet that collapsed to some fraction of its content would
// pass every test in the other file and still strand a tab's body underneath.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/library_sheet.dart';

const _libraryKey = Key('library');
const _headerKey = Key('header');
const _bodyKey = Key('body');

/// Tall enough that a collapse is unmistakable, and a round number so the
/// arithmetic in the assertions stays readable.
const double _bodyHeight = 200;

Widget _wrap({ValueNotifier<bool>? editMode, double bodyHeight = _bodyHeight}) {
  return MaterialApp(
    home: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(key: _libraryKey, color: const Color(0xffE9ECEF)),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: editMode ?? ValueNotifier(false),
            builder: (context, isEditMode, _) => LibrarySheet(
              isEditMode: isEditMode,
              header: const Row(
                key: _headerKey,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  LibrarySheetTitle(title: 'Friends', count: 4),
                  Icon(Icons.person_add),
                ],
              ),
              body: SizedBox(
                key: _bodyKey,
                height: bodyHeight,
                child: const Center(child: Text('Everyone')),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Rect _sheetRect(WidgetTester tester) =>
    tester.getRect(find.byType(LibrarySheet));

double _libraryHeight(WidgetTester tester) =>
    tester.getSize(find.byKey(_libraryKey)).height;

/// The drag handle sits at the top-center of the sheet.
Offset _handleCenter(WidgetTester tester) {
  final sheet = _sheetRect(tester);
  return Offset(sheet.center.dx, sheet.top + 12);
}

Future<void> _dragSheet(WidgetTester tester, double dy) async {
  await tester.drag(find.text('Friends'), Offset(0, dy));
  await tester.pumpAndSettle();
}

void main() {
  group('LibrarySheet with an arbitrary body', () {
    testWidgets(
      'Given a plain body, When first laid out, Then the sheet is pinned to the '
      'bottom at its natural height and the library takes the rest',
      (tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        final body = tester.getRect(find.byType(Scaffold));
        final sheet = _sheetRect(tester);

        expect(sheet.bottom, moreOrLessEquals(body.bottom));
        expect(find.text('Friends'), findsOneWidget);
        expect(find.text('4'), findsOneWidget);
        expect(find.text('Everyone'), findsOneWidget);
        expect(
          _libraryHeight(tester),
          moreOrLessEquals(body.height - sheet.height),
        );
      },
    );

    testWidgets(
      'Given a body of a known height, When collapsed, Then exactly the body is '
      'given up and the handle and header remain',
      (tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        final expanded = _sheetRect(tester).height;

        await _dragSheet(tester, 300);
        final collapsed = _sheetRect(tester);

        // The collapsed position is the header, not a fraction of the content.
        expect(collapsed.height, closeTo(expanded - _bodyHeight, 0.5));
        expect(
          collapsed.height,
          closeTo(tester.getSize(find.byKey(_headerKey)).height + 25 + 6, 0.5),
          reason: 'handle (10 + 5 + 10) and the header gutter (6) are chrome',
        );
        expect(find.text('Friends'), findsOneWidget);

        // Nothing of the body is left inside the sheet: it starts where the
        // sheet ends, clipped away rather than squeezed.
        expect(
          tester.getRect(find.byKey(_bodyKey)).top,
          closeTo(collapsed.bottom, 0.5),
        );
      },
    );

    testWidgets(
      'Given a collapsed sheet, When dragged up, Then it snaps back to its '
      'natural height',
      (tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        final expanded = _sheetRect(tester).height;

        await _dragSheet(tester, 300);
        expect(_sheetRect(tester).height, lessThan(expanded));

        await _dragSheet(tester, -300);
        expect(_sheetRect(tester).height, closeTo(expanded, 0.5));
      },
    );

    testWidgets(
      'Given a taller body, When collapsed, Then the collapsed height is '
      'unchanged — it depends on the header alone',
      (tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        await _dragSheet(tester, 300);
        final collapsedShort = _sheetRect(tester).height;

        await tester.pumpWidget(_wrap(bodyHeight: _bodyHeight * 2));
        await tester.pumpAndSettle();
        await _dragSheet(tester, 300);

        expect(_sheetRect(tester).height, closeTo(collapsedShort, 0.5));
      },
    );

    testWidgets(
      'Given an expanded sheet, When edit mode starts, Then it springs shut, '
      'goes inert, and reopens when editing ends',
      (tester) async {
        final editMode = ValueNotifier(false);
        addTearDown(editMode.dispose);

        await tester.pumpWidget(_wrap(editMode: editMode));
        await tester.pumpAndSettle();
        final expanded = _sheetRect(tester).height;
        final expandedLibrary = _libraryHeight(tester);

        editMode.value = true;
        await tester.pumpAndSettle();
        final collapsed = _sheetRect(tester).height;

        expect(collapsed, closeTo(expanded - _bodyHeight, 0.5));
        expect(_libraryHeight(tester), greaterThan(expandedLibrary));

        // Inert: neither a drag nor a tap on the handle reopens it.
        await _dragSheet(tester, -300);
        expect(_sheetRect(tester).height, closeTo(collapsed, 0.5));
        await tester.tapAt(_handleCenter(tester));
        await tester.pumpAndSettle();
        expect(_sheetRect(tester).height, closeTo(collapsed, 0.5));

        editMode.value = false;
        await tester.pumpAndSettle();
        expect(_sheetRect(tester).height, closeTo(expanded, 0.5));
      },
    );

    testWidgets(
      'Given a collapsed sheet, When it springs open, Then it overshoots before '
      'settling',
      (tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        await _dragSheet(tester, 300);

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
