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
// headers* and the snap positions still land exactly — a target computed against
// the header the sheet is leaving is wrong by the difference between them.
//
// The third group is the floating gutter, and it has two sharp assertions. The
// first is that the gap is *free*: the sheet's box is the same size at every
// position and its contents never move, because the lift is spent out of the
// reserve the sheet already keeps below them. A gutter that grew the box would pass
// a screenshot and shrink the library behind it on every drag.
//
// The second is what the gap is measured against, which is the **screen** and not
// the expanded snap position. Both anchors look identical on a sheet whose expanded
// state fills the screen, and they differ on every sheet ours actually has: those
// stop short so a shelf stays visible, so they must stay slightly inset rather than
// going full width while showing three quarters of the screen. `Then a taller sheet
// has a smaller gap` is the test that separates the two, and it is the one the first
// version of this failed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/library_sheet.dart';

import 'support/sheet_card.dart';

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

/// `LibrarySheet._gutterInset` — how far the card pulls in from the sides and the
/// bottom at the collapsed position. Duplicated rather than exposed: it is a
/// number a test should state independently, or it only proves the field equals
/// itself.
const double _gutterInset = 14;

/// Room for chrome floating over the sheet, which is what the bottom lift is paid
/// out of. Comfortably more than [_gutterInset], as the shell's own reservation is
/// (~58 on the fallback path, ~91 on the native one).
const double _reserve = 60;

Widget _wrap({
  ValueNotifier<bool>? editMode,
  double bodyHeight = _bodyHeight,
  double bottomReserve = 0,
}) {
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
              bottomReserve: bottomReserve,
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

/// The medium detent used by the detent group. Clear of both ends by well more than
/// the gap below which the sheet drops it.
const double _mid = 220;

/// A sheet shaped like the read view: a minimal body at rest, a body taller than
/// the cap when expanded, and a header that grows by 40pt on the way.
Widget _wrapTwoState({
  ValueNotifier<bool>? editMode,
  double bottomReserve = 0,
  double? midExtent,
  LibrarySheetDetent initialDetent = LibrarySheetDetent.collapsed,
}) {
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
              initialDetent: initialDetent,
              bottomReserve: bottomReserve,
              expandedExtent: _cap,
              midExtent: midExtent,
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

/// A sheet shaped like Friends and the Card: capped, floored, and stating **no**
/// collapsed body — so one scrollable body shows at every position and the collapsed
/// one is a short viewport onto it.
///
/// The body is sized to fall between the two viewports on purpose: taller than the
/// collapsed slot, so it scrolls there, and shorter than the slot the cap leaves, so a
/// viewport laid out at the cap would hold all of it and force the offset to zero.
/// That gap is exactly where the bug lived.
Widget _wrapOneBody({double bottomReserve = 0}) {
  return MaterialApp(
    home: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(key: _libraryKey, color: const Color(0xffE9ECEF)),
          ),
          LibrarySheet(
            initialDetent: LibrarySheetDetent.collapsed,
            expandedExtent: _cap,
            bottomReserve: bottomReserve,
            // Floored, as all three of the shell's sheets are: without it collapsed is
            // the header alone and there is no viewport to scroll.
            minHeightFraction: 0.3,
            header: const Row(
              key: _headerKey,
              children: [LibrarySheetTitle(title: 'Friends', count: 7)],
            ),
            body: ListView(
              key: _bodyKey,
              // **Deliberately opted out of the sheet's gesture coordination**, and
              // `AlwaysScrollableScrollPhysics` is the only thing that does it. The
              // shell's own bodies leave physics unset and pass `primary: false`, which
              // lets the sheet freeze them below the cap so a swipe up opens the sheet
              // instead of scrolling the list — see `_SheetBodyScrollBehavior`.
              //
              // A `physics:` argument does not *replace* the ambient one, it becomes
              // its child, and `shouldAcceptUserOffset` is answered by whichever link
              // in that chain overrides it — so `ClampingScrollPhysics` here changes
              // nothing and the body stays frozen. `Always` is one of the two that do
              // override it, which is exactly why an unannotated vertical `ListView`
              // ignored the gate in the first place.
              //
              // This group is about the *slot the body is laid out in*, not about who
              // wins the gesture, and it needs an offset at a position where the real
              // sheets refuse to give one.
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < 5; i++) const SizedBox(height: 40),
              ],
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
  double bottomReserve = 0,
}) async {
  await tester.pumpWidget(
    _wrapTwoState(editMode: editMode, bottomReserve: bottomReserve),
  );
  // Settles the post-frame callback that puts a sheet opening anywhere but the cap
  // at its position.
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

  // The third snap position, and the machinery it needed. Everything here is about
  // *which* position a release picks and what the sheet is laid out at once it gets
  // there; `finished_books_sheet_test.dart` covers the same ground end to end on the
  // read view's real grid.
  group('LibrarySheet\'s medium detent', () {
    Future<void> pump(WidgetTester tester, {double? midExtent = _mid}) async {
      await tester.pumpWidget(_wrapTwoState(midExtent: midExtent));
      await tester.pumpAndSettle();
    }

    /// Lays out a sheet asked to *open* at the medium detent, one frame only.
    ///
    /// A single pump rather than a settle, because the frame is the assertion: an
    /// opening position that needed a post-frame correction would be at the cap here.
    Future<void> pumpOpeningAtMedium(
      WidgetTester tester, {
      double? midExtent = _mid,
    }) async {
      await tester.pumpWidget(
        _wrapTwoState(
          midExtent: midExtent,
          initialDetent: LibrarySheetDetent.medium,
        ),
      );
      await tester.pump();
    }

    /// Drags the sheet until it is about [target] tall and releases it slowly, so the
    /// release carries no fling velocity and the sheet settles on the nearest detent.
    ///
    /// Two moves, because the first is eaten by the touch slop and is therefore not a
    /// known distance. The second is, which is what makes [target] mean anything.
    Future<void> dragTo(WidgetTester tester, double target) async {
      final from = _sheetRect(tester).height;
      final gesture = await tester.startGesture(_handleCenter(tester));
      await gesture.moveBy(const Offset(0, -20));
      await gesture.moveBy(Offset(0, -(target - from)));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    /// A point clear of the boundary between the collapsed and medium detents, so a
    /// release there can only mean the medium one.
    double insideMediumBasin(double collapsed) => (collapsed + _mid) / 2 + 20;

    /// Flings the sheet [distance] points up and releases it.
    ///
    /// Hand-rolled rather than `tester.fling`, which derives its timestamps from
    /// `distance / speed` and then rounds them to whole milliseconds: over a short
    /// distance at a fling's speed every sample lands in the same millisecond or two,
    /// and what the velocity tracker's least-squares fit makes of that is luck. The
    /// same gesture read as a fling once and as a slow drag the next time, from a
    /// starting height 0.0003pt different.
    ///
    /// Four samples 8ms apart is ~31 x [distance] px/s, comfortably past the sheet's
    /// fling threshold, and the sheet itself only travels [distance] less the touch
    /// slop — which is the point, since this is testing that a fling does *not* need
    /// to cover the distance to advance.
    Future<void> flingUp(WidgetTester tester, double distance) async {
      final gesture = await tester.startGesture(_handleCenter(tester));
      var elapsed = Duration.zero;
      for (var i = 0; i < 4; i++) {
        elapsed += const Duration(milliseconds: 8);
        await gesture.moveBy(Offset(0, -distance / 4), timeStamp: elapsed);
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets(
      'Given a medium detent, When a drag is released nearer to it than to either '
      'end, Then that is where the sheet settles',
      (tester) async {
        await pump(tester);
        final collapsed = _sheetRect(tester).height;

        await dragTo(tester, insideMediumBasin(collapsed));

        expect(_sheetRect(tester).height, closeTo(_mid, 1));
        expect(
          find.byKey(_bodyKey),
          findsOneWidget,
          reason:
              'medium is a second height of the expanded state, not a third state: '
              'the expanded body is what is on screen',
        );
      },
    );

    testWidgets(
      'Given the medium detent, When measured, Then the body is given the height '
      'the sheet is showing rather than the cap',
      (tester) async {
        // The reason a capped sheet is laid out at its detent instead of always at the
        // cap and clipped. A viewport 80pt taller than the card puts the last of the
        // body below the card's bottom edge, where no scroll offset can reach it.
        await pump(tester);
        final collapsed = _sheetRect(tester).height;
        await dragTo(tester, insideMediumBasin(collapsed));

        final sheet = _sheetRect(tester);
        expect(sheet.height, closeTo(_mid, 1));
        expect(
          tester.getRect(find.byKey(_bodyKey)).bottom,
          closeTo(sheet.bottom, 1),
          reason:
              'laid out at the cap instead, the body would run '
              '${_cap - _mid}pt past the bottom of the card',
        );
      },
    );

    testWidgets(
      'Given the medium detent, When dragged a little further up, Then it takes the '
      'cap',
      (tester) async {
        await pump(tester);
        final collapsed = _sheetRect(tester).height;
        await dragTo(tester, insideMediumBasin(collapsed));

        await dragTo(tester, (_mid + _cap) / 2 + 15);

        expect(_sheetRect(tester).height, closeTo(_cap, 1));
      },
    );

    testWidgets(
      'Given the expanded sheet, When dragged down a little, Then it stops at the '
      'medium detent instead of collapsing',
      (tester) async {
        await pump(tester);
        await _toggle(tester);
        expect(_sheetRect(tester).height, closeTo(_cap, 1));

        await dragTo(tester, _mid + 5);

        expect(_sheetRect(tester).height, closeTo(_mid, 1));
        expect(
          find.byKey(_collapsedBodyKey),
          findsNothing,
          reason: 'it has not collapsed, so the collapsed body is not back',
        );
      },
    );

    testWidgets(
      'Given a fling, When it is released, Then it advances exactly one detent',
      (tester) async {
        // "Fast means all the way" would leave the medium detent reachable only by a
        // slow, deliberate drag, because every flick from collapsed would blow past it.
        // 40pt is well short of either detent, so what moves the sheet here is the
        // velocity and not the distance.
        await pump(tester);

        await flingUp(tester, 40);
        expect(_sheetRect(tester).height, closeTo(_mid, 1));

        await flingUp(tester, 40);
        expect(
          _sheetRect(tester).height,
          closeTo(_cap, 1),
          reason: 'a second fling carries on to the top',
        );
      },
    );

    testWidgets(
      'Given the handle, When tapped, Then it toggles the two ends and never lands '
      'on the medium detent',
      (tester) async {
        // Drag-only, which is also how iOS behaves. A tap that cycled all three would
        // mean two taps to put the sheet away, and putting it away is the handle's job.
        await pump(tester);
        final collapsed = _sheetRect(tester).height;

        await _toggle(tester);
        expect(_sheetRect(tester).height, closeTo(_cap, 1));

        await _toggle(tester);
        expect(_sheetRect(tester).height, closeTo(collapsed, 1));

        // And from the medium detent it shuts rather than advancing to the cap.
        await dragTo(tester, insideMediumBasin(collapsed));
        expect(_sheetRect(tester).height, closeTo(_mid, 1));

        await _toggle(tester);
        expect(_sheetRect(tester).height, closeTo(collapsed, 1));
      },
    );

    testWidgets(
      'Given a medium detent too close to the cap, When a drag is released beside '
      'it, Then it has been dropped and the sheet takes the cap',
      (tester) async {
        // A detent a few points from its neighbour is not a position, it is somewhere
        // the sheet appears to refuse to leave: the spring between the two is over
        // before it reads as motion. Dropping it is the honest outcome, and it is a
        // real case — a small phone at an accessibility text size can leave a band with
        // no room for three positions in it.
        await pump(tester, midExtent: _cap - 10);

        await dragTo(tester, _cap - 5);

        expect(
          _sheetRect(tester).height,
          closeTo(_cap, 1),
          reason:
              'a live detent at ${_cap - 10} would have caught this release; with '
              'only two left, the nearest is the cap',
        );
      },
    );

    // Opening *at* the medium detent, which is what the Card tab does. Its own
    // position is covered end to end in `library_clearance_test.dart`; these two are
    // about the mechanics, and the first is about a single frame.
    testWidgets(
      'Given a sheet asked to open at the medium detent, When its first frame is '
      'laid out, Then it is already there rather than at the cap',
      (tester) async {
        // The medium detent is a number the caller gave, not a measurement, so it can
        // be applied before the first frame — and it has to be. Corrected after layout
        // instead, the sheet's first frame would be the whole cap, and a frame of
        // full-height sheet is exactly the flash that opening at medium avoids.
        await pumpOpeningAtMedium(tester);

        expect(_sheetRect(tester).height, closeTo(_mid, 1));
        expect(
          find.byKey(_bodyKey),
          findsOneWidget,
          reason: 'medium is a height of the expanded state, so it opens open',
        );

        await tester.pumpAndSettle();
        expect(
          _sheetRect(tester).height,
          closeTo(_mid, 1),
          reason: 'and it stays there once everything has settled',
        );
      },
    );

    testWidgets(
      'Given a sheet asked to open at a medium detent it has no room for, When it '
      'settles, Then it opens at the cap instead of somewhere between',
      (tester) async {
        // Same fallback [_heightOf] uses everywhere else: a dropped detent means the
        // sheet has two positions, and an open sheet with two positions is at the cap.
        await pumpOpeningAtMedium(tester, midExtent: _cap - 10);
        await tester.pumpAndSettle();

        expect(_sheetRect(tester).height, closeTo(_cap, 1));
      },
    );
  });

  group('LibrarySheet\'s floating gutter', () {
    Future<void> pump(
      WidgetTester tester, {
      double bodyHeight = _bodyHeight,
    }) async {
      await tester.pumpWidget(
        _wrap(bottomReserve: _reserve, bodyHeight: bodyHeight),
      );
      await tester.pumpAndSettle();
    }

    /// The gap between the sheet's box and the card inside it, on the left.
    double gap(WidgetTester tester) =>
        sheetCardRect(tester).left - _sheetRect(tester).left;

    testWidgets(
      'Given the sheet is collapsed, When measured, Then the card floats: inset '
      'from both sides, lifted off the bottom, all four corners rounded',
      (tester) async {
        await pump(tester);
        await _dragSheet(tester, 300);

        final sheet = _sheetRect(tester);
        final card = sheetCardRect(tester);

        expect(card.left - sheet.left, closeTo(_gutterInset, 0.5));
        expect(sheet.right - card.right, closeTo(_gutterInset, 0.5));
        expect(sheet.bottom - card.bottom, closeTo(_gutterInset, 0.5));
        expect(
          card.top,
          closeTo(sheet.top, 0.5),
          reason:
              'only three edges pull in — the top edge is where the library '
              'stops, and a gap there would be a seam between two backgrounds',
        );
        expect(sheetCardRadius(tester).bottomLeft.y, greaterThan(0));
      },
    );

    testWidgets(
      'Given an expanded position well short of the screen, When measured, Then '
      'the card is neither flush nor as inset as it was collapsed',
      (tester) async {
        // The rule, stated on one sheet: expanded is a snap position, not a claim
        // on the whole screen. This one covers well under half of it, so it stays
        // visibly a card.
        await pump(tester);
        final expanded = gap(tester);

        await _dragSheet(tester, 300);
        final collapsed = gap(tester);

        expect(collapsed, closeTo(_gutterInset, 0.5));
        expect(expanded, greaterThan(0.5));
        expect(expanded, lessThan(collapsed - 0.5));
        expect(
          sheetCardRect(tester).width,
          lessThan(_sheetRect(tester).width - 0.5),
          reason:
              'and a sheet that is not covering the screen must not be as wide '
              'as one that is',
        );
      },
    );

    testWidgets(
      'Given two sheets at their expanded positions, When one is taller, Then its '
      'gap is the smaller — the gutter tracks the screen, not the snap position',
      (tester) async {
        // What separates the two anchors. Measured against the expanded snap
        // position, both of these are "fully open" and both would be flush; the
        // taller one covers more screen, so it must be further along in closing
        // the gap.
        await pump(tester, bodyHeight: 120);
        final short = gap(tester);

        await pump(tester, bodyHeight: 360);
        final tall = gap(tester);

        expect(tall, lessThan(short - 0.5));
        expect(short, lessThan(_gutterInset));
      },
    );

    testWidgets(
      'Given a sheet tall enough to cover the screen, When expanded, Then it is '
      'flush and full width with square bottom corners',
      (tester) async {
        // The other end of the same rule, and the reason the gutter is not simply
        // "always a bit inset": a sheet that does fill the screen has no gap to
        // show, its bottom corners are the display's own to round, and the flush
        // full-width state has to remain reachable.
        //
        // The body height is derived rather than guessed: everything the sheet
        // adds to it — handle, header, reserve — is a constant, so one measurement
        // at any height gives the body that lands the box exactly on the screen.
        await pump(tester, bodyHeight: 100);
        final screen = tester.getRect(find.byType(Scaffold)).height;
        final chrome = _sheetRect(tester).height - 100;

        await pump(tester, bodyHeight: screen - chrome);

        final sheet = _sheetRect(tester);
        final card = sheetCardRect(tester);
        expect(sheet.height, closeTo(screen, 0.5));
        expect(card.left, closeTo(sheet.left, 0.5));
        expect(card.right, closeTo(sheet.right, 0.5));
        expect(card.bottom, closeTo(sheet.bottom, 0.5));
        expect(sheetCardRadius(tester).bottomLeft.y, closeTo(0, 0.01));
        expect(
          sheetCardRadius(tester).topLeft.y,
          closeTo(20, 0.01),
          reason:
              'and the top corners hold the card\'s own radius, this screen '
              'having no rounded corner of its own to open up to',
        );
      },
    );

    testWidgets(
      'Given a screen with rounded corners, When the card floats, Then its bottom '
      'corners are concentric with the screen\'s rather than its own',
      (tester) async {
        // A 20pt corner inside the display's 55 does not read as a smaller radius,
        // it reads as the wrong shape — which is what a device screenshot of the
        // first version showed. Concentric means inner = outer - gap.
        //
        // The home-indicator inset is the signal that there is a rounded corner to
        // be concentric with, so faking it is what turns this on. It is also part
        // of the reserve, which is why the lift is still the full gutter here.
        tester.view.viewPadding = const FakeViewPadding(bottom: 34 * 3);
        tester.view.padding = const FakeViewPadding(bottom: 34 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        await pump(tester);
        await _dragSheet(tester, 300);

        final sheet = _sheetRect(tester);
        final card = sheetCardRect(tester);
        expect(sheet.bottom - card.bottom, closeTo(_gutterInset, 0.5));
        expect(
          sheetCardRadius(tester).bottomLeft.y,
          closeTo(55 - _gutterInset, 0.5),
        );
        expect(
          sheetCardRadius(tester).topLeft.y,
          closeTo(55 - _gutterInset, 0.5),
          reason:
              'and the top corners are the same arc, top and bottom being one '
              'shape rather than two radii on one card',
        );
      },
    );

    testWidgets(
      'Given a screen with rounded corners, When the card goes flush, Then its top '
      'corners open up to the display\'s own radius',
      (tester) async {
        // The other half of "one arc, top and bottom". Flush, the bottom corners
        // hand their rounding to the display\'s mask and draw nothing; the top
        // corners have no mask to hand it to, so matching means drawing the arc the
        // mask is drawing below them — the gap, and with it the concentric
        // subtraction, having closed.
        tester.view.viewPadding = const FakeViewPadding(bottom: 34 * 3);
        tester.view.padding = const FakeViewPadding(bottom: 34 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        await pump(tester, bodyHeight: 100);
        final screen = tester.getRect(find.byType(Scaffold)).height;
        final chrome = _sheetRect(tester).height - 100;

        await pump(tester, bodyHeight: screen - chrome);

        expect(
          sheetCardRect(tester).bottom,
          closeTo(_sheetRect(tester).bottom, 0.5),
          reason:
              'the card has to actually be flush for the rest to mean anything',
        );
        expect(sheetCardRadius(tester).bottomLeft.y, closeTo(0, 0.01));
        expect(sheetCardRadius(tester).topLeft.y, closeTo(55, 0.5));
      },
    );

    testWidgets(
      'Given the gap, When it closes, Then the sheet\'s box is unchanged and its '
      'contents have not moved',
      (tester) async {
        // The invariant that makes the gutter free. The lift is spent out of the
        // reserve *inside* the card, so the box stays the size it would be with no
        // gutter at all and the header keeps its distance from the bottom of the
        // screen. Grown instead, every drag would resize the library behind it and
        // slide the reserved band the floating tab bar sits in.
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        await _dragSheet(tester, 300);
        final withoutReserve = _sheetRect(tester).height;

        await pump(tester);
        await _dragSheet(tester, 300);
        final sheet = _sheetRect(tester);

        expect(sheet.height, closeTo(withoutReserve + _reserve, 0.5));
        expect(
          sheet.bottom - (tester.getRect(find.byKey(_headerKey)).bottom + 6),
          closeTo(_reserve, 0.5),
          reason:
              'the full reserve still separates the last of the content from the '
              'bottom of the screen; the 6 is the header\'s own gutter',
        );
        expect(
          sheetCardRect(tester).bottom - (sheet.bottom - _reserve),
          closeTo(_reserve - _gutterInset, 0.5),
          reason:
              'so what shortened is the empty band inside the card, by exactly '
              'the lift',
        );
      },
    );

    testWidgets(
      'Given the sheet is dragged rather than snapped, When it is between '
      'positions, Then the gap is partly closed',
      (tester) async {
        // Continuous, not per-state: the drawing this comes from closes the gap
        // under the finger, and a gutter that flipped at the midpoint would read
        // as the sheet changing shape rather than being resized.
        await pump(tester);
        await _dragSheet(tester, 300);

        final gesture = await tester.startGesture(_handleCenter(tester));
        // The first move is eaten by the touch slop, so it is not a known
        // distance; the second is what makes the two samples comparable.
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump();
        final early = gap(tester);
        await gesture.moveBy(const Offset(0, -60));
        await tester.pump();
        final later = gap(tester);

        expect(later, lessThan(early));
        expect(later, greaterThan(0));
        expect(
          later,
          lessThan(_gutterInset - 0.5),
          reason:
              'partway up the sheet is neither inset by the full gutter nor '
              'flush — it is somewhere in between',
        );

        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          gap(tester),
          closeTo(_gutterInset, 0.5),
          reason:
              'released short of halfway it springs back to collapsed, and the '
              'gap comes back with it',
        );
      },
    );

    testWidgets(
      'Given a sheet with no reserve to spend, When collapsed, Then it does not '
      'lift off the bottom edge',
      (tester) async {
        // The honest fallback rather than an omission: with nothing reserved below
        // the content, lifting could only come out of the content or out of the
        // library. The sides are free, so those still pull in.
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        await _dragSheet(tester, 300);

        final sheet = _sheetRect(tester);
        final card = sheetCardRect(tester);

        expect(card.bottom, closeTo(sheet.bottom, 0.5));
        expect(
          sheetCardRadius(tester).bottomLeft.y,
          closeTo(0, 0.01),
          reason:
              'and a corner rounded against an edge it is still flush with is a '
              'notch cut out of the sheet, so the bottom corners follow the lift '
              'rather than the drag',
        );
        expect(card.left - sheet.left, closeTo(_gutterInset, 0.5));
      },
    );
  });

  group('LibrarySheet\'s reserved band is passed under, not left empty', () {
    testWidgets(
      'Given a reserved band, When collapsed, Then the clip is the card and the '
      'body runs into the band rather than stopping above it',
      (tester) async {
        // An empty strip of card behind a translucent bar is the one thing that
        // reads as a Flutter sheet rather than an iOS one: the reference shows the
        // next row of its list continuing under the bar, cut off by the sheet's own
        // bottom edge. Which edge the content is clipped at is the whole difference,
        // and it comes down to the order of two wrappers.
        await tester.pumpWidget(_wrap(bottomReserve: _reserve));
        await tester.pumpAndSettle();
        await _dragSheet(tester, 300);

        final card = sheetCardRect(tester);
        final clip = tester.getRect(find.byType(ClipRSuperellipse));
        final body = tester.getRect(find.byKey(_bodyKey));

        expect(
          clip.bottom,
          closeTo(card.bottom, 0.5),
          reason:
              'the clip is the card. Inside the reserved band instead, it would '
              'stop ${(_reserve - _gutterInset).round()}pt higher and the band '
              'would be blank',
        );
        expect(
          body.top,
          lessThan(card.bottom - 0.5),
          reason: 'and the body begins inside it',
        );
        expect(
          body.bottom,
          greaterThan(card.bottom),
          reason:
              'running past the card\'s bottom edge, which is what cuts it off',
        );
      },
    );

    testWidgets(
      'Given a capped sheet with a reserved band, When expanded, Then the body\'s '
      'viewport runs the band\'s length past its slot, and the box is unchanged',
      (tester) async {
        // The capped case is the one that matters, because that body is a scroll
        // view: its viewport has to reach the card's bottom edge for rows to pass
        // under the bar, while every snap position stays measured in content that
        // stops above it. Growing the box instead would have taken the band out of
        // the library twice.
        await _pumpTwoState(tester, bottomReserve: _reserve);
        await _toggle(tester);

        final expandedHeader = tester
            .getSize(find.byKey(_expandedHeaderKey))
            .height;

        expect(
          tester.getSize(find.byKey(_bodyKey)).height,
          closeTo(_cap - _chrome - expandedHeader + _reserve, 0.5),
          reason:
              'the slot the cap leaves, plus the band — without the band the last '
              'row would stop dead above the bar',
        );
        expect(
          _sheetRect(tester).height,
          closeTo(_cap + _reserve, 0.5),
          reason:
              'and the box is still the cap plus the band, so the library behind '
              'it is unaffected by any of this',
        );
        expect(
          tester.getRect(find.byKey(_bodyKey)).bottom,
          greaterThan(sheetCardRect(tester).bottom),
          reason: 'the viewport is cut off by the card, not by its own slot',
        );
      },
    );
  });

  // A sheet stating no `collapsedBody` shows one body at every position, and the
  // collapsed one is just a shorter viewport onto it. Which means the body has a
  // scroll offset there, and that offset is the thing this group is about: it used to
  // be destroyed by the sheet so much as twitching.
  group('a capped sheet with one body keeps its place while the sheet moves', () {
    testWidgets('Given a body scrolled at the collapsed position, When the sheet is nudged, '
        'Then the offset and the viewport are both unchanged', (tester) async {
      // The bug this pins, measured on Friends with seven friends: the body was laid
      // out at the *cap* on every frame the sheet was not at rest, so a 30pt drag
      // took the viewport from 115 to 501 on its first frame. At 501 the whole list
      // fits, `maxScrollExtent` goes to zero, and the offset is clamped to zero with
      // it — so the list was back at the top by the time the sheet settled, on every
      // touch that moved the sheet at all. The body's slot now follows the state the
      // sheet is *showing*, not the cap.
      await tester.pumpWidget(_wrapOneBody());
      await tester.pumpAndSettle();

      final scrollable = find.descendant(
        of: find.byKey(_bodyKey),
        matching: find.byType(Scrollable),
      );
      await tester.drag(find.byKey(_bodyKey), const Offset(0, -40));
      await tester.pumpAndSettle();

      final position = tester.state<ScrollableState>(scrollable).position;
      final scrolled = position.pixels;
      final viewport = position.viewportDimension;
      expect(
        scrolled,
        greaterThan(1),
        reason:
            'the collapsed viewport has to be scrollable in the first place, or '
            'the rest of this proves nothing',
      );

      // A partial drag on the header: enough to take the sheet off its detent,
      // nowhere near the halfway point where it would start showing the expanded
      // state and a taller viewport would be the honest answer.
      final nudge = await tester.startGesture(
        tester.getCenter(find.text('Friends')),
      );
      await nudge.moveBy(const Offset(0, -30));
      await tester.pump();

      expect(
        position.pixels,
        closeTo(scrolled, 0.5),
        reason:
            'the sheet moving is not a reason to scroll the body to the top',
      );
      expect(
        position.viewportDimension,
        closeTo(viewport, 0.5),
        reason:
            'and the slot it scrolls inside has not resized, which is what took '
            'the offset with it',
      );

      await nudge.up();
      await tester.pumpAndSettle();
      expect(
        position.pixels,
        closeTo(scrolled, 0.5),
        reason: 'still there once it has sprung back to the detent it left',
      );
    });
  });
}
