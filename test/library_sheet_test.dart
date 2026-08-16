// Widget tests for the sheet chrome itself, driven with a body that has nothing
// to do with read books.
//
// `finished_books_sheet_test.dart` covers the Library tab's sheet end to end.
// This file exists because the shell gives every tab its own sheet over one
// shared library background, so the handle, the two snap positions and the
// spring have to hold for *any* contents — not just for a pile of covers whose
// height happens to make the numbers work.
//
// Phase 2 split this into two shapes, and the split is the point:
//
//   no `collapsedBody`   collapsed is exactly handle + header, and the body is
//                        clipped away rather than squeezed. This is what the Card
//                        and Friends tabs get, and it is Phase 1 unchanged.
//   a `collapsedBody`    collapsed is handle + header + that body, and expanded is
//                        a *cap* rather than the content's natural height, so the
//                        body scrolls inside it. This is what the read view gets.
//
// The sharp assertion in the first shape is still that collapsed is "handle plus
// header, no body": a sheet that collapsed to some fraction of its content would
// pass every test in the other file and still strand a tab's body underneath. The
// sharp assertion in the second is that the two states may have *different
// headers* and the snap positions still land exactly — a target measured against
// the header the sheet is leaving is wrong by the difference between them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/library_sheet.dart';

const _libraryKey = Key('library');
const _headerKey = Key('header');
const _bodyKey = Key('body');
const _expandedHeaderKey = Key('expandedHeader');
const _collapsedBodyKey = Key('collapsedBody');

/// Tall enough that a collapse is unmistakable, and a round number so the
/// arithmetic in the assertions stays readable.
const double _bodyHeight = 200;

/// The chrome a collapse always keeps: the grab handle (10 + 5 + 10) and the
/// gutter below the header (6).
const double _chrome = 25 + 6;

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

/// Height of the minimal body the two-state sheet rests on — the read view's
/// spine pile, stripped to a box of a known size.
const double _collapsedBodyHeight = 90;

/// The expanded cap. Deliberately far shorter than the body's content, so the
/// body has to scroll.
const double _cap = 300;

/// A sheet shaped like the read view: a minimal body at rest, a body taller than
/// the cap when expanded, and a header that grows by 40pt on the way.
Widget _wrapTwoState({ValueNotifier<bool>? editMode}) {
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
              initiallyExpanded: false,
              expandedExtent: _cap,
              collapsedBodyExtent: _collapsedBodyHeight,
              header: const Row(
                key: _headerKey,
                children: [LibrarySheetTitle(title: 'Books read', count: 12)],
              ),
              // 40pt taller than the collapsed header. That difference is what
              // makes the order the snap positions are measured in observable
              // instead of a detail.
              expandedHeader: const Column(
                key: _expandedHeaderKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LibrarySheetTitle(title: 'Books read', count: 12),
                  SizedBox(height: 40),
                ],
              ),
              collapsedBody: const SizedBox(
                key: _collapsedBodyKey,
                height: _collapsedBodyHeight,
              ),
              body: ListView(
                key: _bodyKey,
                children: [
                  for (var i = 0; i < 40; i++) const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _pumpTwoState(
  WidgetTester tester, {
  ValueNotifier<bool>? editMode,
}) async {
  await tester.pumpWidget(_wrapTwoState(editMode: editMode));
  // Settles the post-frame callback that puts an `initiallyExpanded: false` sheet
  // at its collapsed position.
  await tester.pumpAndSettle();
}

/// Taps the grab handle, which toggles between the two snap positions.
Future<void> _toggle(WidgetTester tester) async {
  await tester.tapAt(_handleCenter(tester));
  await tester.pumpAndSettle();
}

void main() {
  group('LibrarySheet with an arbitrary body and no collapsed body', () {
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
          closeTo(tester.getSize(find.byKey(_headerKey)).height + _chrome, 0.5),
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

  group('LibrarySheet with a collapsed body and a capped expanded state', () {
    testWidgets(
      'Given a collapsed body, When resting, Then the collapsed position is the '
      'chrome, the header and that body',
      (tester) async {
        await _pumpTwoState(tester);

        expect(
          _sheetRect(tester).height,
          closeTo(
            tester.getSize(find.byKey(_headerKey)).height +
                _chrome +
                _collapsedBodyHeight,
            0.5,
          ),
          reason:
              'this is the definition that replaces "handle + header": whatever '
              'minimal body a sheet has is part of its resting height',
        );
        expect(find.byKey(_collapsedBodyKey), findsOneWidget);
        expect(
          find.byKey(_bodyKey),
          findsNothing,
          reason:
              'the two states are different subtrees, not one clipped at two '
              'heights — the expanded body must not be built while collapsed',
        );
      },
    );

    testWidgets(
      'Given a body taller than the cap, When expanded, Then the sheet stops at '
      'the cap and the body scrolls inside it',
      (tester) async {
        await _pumpTwoState(tester);
        await _toggle(tester);

        expect(_sheetRect(tester).height, closeTo(_cap, 0.5));
        expect(find.byKey(_bodyKey), findsOneWidget);
        expect(find.byKey(_collapsedBodyKey), findsNothing);

        // Bounded, so it scrolls: the viewport is the cap minus the chrome and
        // the expanded header, and the content is far taller than that.
        final viewport = tester.getSize(find.byKey(_bodyKey)).height;
        expect(
          viewport,
          closeTo(
            _cap -
                _chrome -
                tester.getSize(find.byKey(_expandedHeaderKey)).height,
            0.5,
          ),
        );
        await tester.drag(find.byKey(_bodyKey), const Offset(0, -120));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(_bodyKey)).height,
          closeTo(viewport, 0.5),
          reason: 'scrolling the body must not resize the sheet',
        );
        expect(
          tester
              .state<ScrollableState>(
                find.descendant(
                  of: find.byKey(_bodyKey),
                  matching: find.byType(Scrollable),
                ),
              )
              .position
              .pixels,
          greaterThan(0),
          reason:
              'drag versus scroll is resolved by arena depth: the body\'s scroll '
              'view is deeper than the sheet\'s drag recogniser, so a vertical '
              'drag inside the body scrolls it instead of moving the sheet',
        );
      },
    );

    testWidgets(
      'Given an expanded header taller than the collapsed one, When collapsed '
      'again, Then it lands on the collapsed header exactly',
      (tester) async {
        // The trap this pins. The snap target is measured from the rendered
        // header, so collapsing while the *expanded* header is still on screen
        // aims at a position that is too tall by the difference between the two
        // headers — 40pt here — and the sheet settles there, visibly wrong.
        await _pumpTwoState(tester);
        final resting = _sheetRect(tester).height;

        await _toggle(tester);
        expect(_sheetRect(tester).height, closeTo(_cap, 0.5));

        await _toggle(tester);
        expect(_sheetRect(tester).height, closeTo(resting, 0.5));
        expect(find.byKey(_collapsedBodyKey), findsOneWidget);
      },
    );

    testWidgets(
      'Given the sheet is dragged rather than tapped, When it passes halfway, '
      'Then the body it is heading for is the one shown',
      (tester) async {
        await _pumpTwoState(tester);
        final resting = _sheetRect(tester).height;

        // Short of halfway: still the collapsed body, and it springs back.
        final gesture = await tester.startGesture(_handleCenter(tester));
        await gesture.moveBy(const Offset(0, -(_cap - 40) / 4));
        await tester.pump();
        expect(find.byKey(_collapsedBodyKey), findsOneWidget);

        // Past halfway: swapped, before the finger is even lifted.
        await gesture.moveBy(const Offset(0, -_cap));
        await tester.pump();
        expect(find.byKey(_bodyKey), findsOneWidget);
        expect(find.byKey(_collapsedBodyKey), findsNothing);

        await gesture.up();
        await tester.pumpAndSettle();
        expect(_sheetRect(tester).height, closeTo(_cap, 0.5));
        expect(_sheetRect(tester).height, greaterThan(resting));
      },
    );

    testWidgets(
      'Given the library is edited, When the sheet was expanded, Then it springs '
      'back to the pile and returns to the cap afterwards',
      (tester) async {
        final editMode = ValueNotifier(false);
        addTearDown(editMode.dispose);

        await _pumpTwoState(tester, editMode: editMode);
        await _toggle(tester);
        final expanded = _sheetRect(tester).height;

        editMode.value = true;
        await tester.pumpAndSettle();
        expect(find.byKey(_collapsedBodyKey), findsOneWidget);
        expect(_sheetRect(tester).height, lessThan(expanded));

        editMode.value = false;
        await tester.pumpAndSettle();
        expect(_sheetRect(tester).height, closeTo(expanded, 0.5));
        expect(find.byKey(_bodyKey), findsOneWidget);
      },
    );
  });
}
