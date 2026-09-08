// Tests for the Card tab's sheet: what the header offers and when.
//
// The body's figures and geometry are covered in `library_card_body_test.dart` and
// `library_card_stats_test.dart`; this file is about the three decisions the *sheet*
// makes, all of which are about absence:
//
//  * the share affordance appears whenever there is a library worth sharing, at
//    *every* snap position — the sheet has one header, so collapsing shortens the
//    viewport onto the same chrome rather than swapping it. It is gated on the
//    *library*, not on the selected year: `readFilterYears` offers years a reader has
//    finished nothing in, and a button that disappeared when one of them was picked
//    took the header's shape with it. It goes inert there instead;
//  * the year capsules are there at every position too, and for every library — the
//    rail is what names the card's scope, and the filter keeps applying whether or not
//    it is drawn. `readFilterYears` fills any gap up to the current year even when a
//    reader's books do not — a reader with books only in one past year still gets
//    an empty current-year option, because that year exists whether or not they
//    have read anything in it yet. It no longer waits for a second year before
//    appearing: an empty library and a one-year library get the rail too, so the
//    header's shape does not depend on how much has been read.
//  * neither is live while the library is being edited.
//
// The capsules are asserted through the `useNativeGlass` gate rather than by pumping
// the native control: `flutter test` reports Android, so the Flutter fallback is what
// runs here. `test/read_filter_test.dart` has the pattern this follows.
//
// The sheet opens at its **medium** detent, which is open, so the expanded header is
// what a plain `_pump` renders; `collapsed: true` is what asks for `card-down`. Where
// that position sits against the library is measured in `library_clearance_test.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/library_card/share_library_card.dart';
import 'package:bookworm_friends/ui/widgets/library_card/stat_tile.dart';
import 'package:bookworm_friends/ui/widgets/library_card_sheet.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/read_filter.dart';

import 'support/sheet_card.dart';

const _surface = Size(400, 900);

/// Real "now", since neither the sheet nor `readFilterYears` takes a seam for
/// one. Fixtures below are relative to it rather than to a fixed year, so the
/// gap-filled range they expect does not quietly drift out of date.
final _currentYear = DateTime.now().year;

Book _read(
  String id,
  DateTime finish, {
  int spanDays = 5,
  List<String> authors = const [],
}) => Book(
  id: id,
  userId: 'u',
  shelfId: 's',
  isbn: id,
  title: 'Book $id',
  thumbnail: '',
  status: 2,
  position: 0,
  startDate: finish.subtract(Duration(days: spanDays)),
  finishDate: finish,
  createdAt: DateTime(2024),
  authors: authors,
);

Future<void> _pump(
  WidgetTester tester, {
  required List<Book> books,
  int filterYear = 0,
  bool isEditMode = false,
  bool collapsed = false,
  void Function(int)? onFilterChanged,
}) async {
  tester.view.physicalSize = _surface * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  final editing = ValueNotifier(false);
  addTearDown(editing.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox.expand()),
            ValueListenableBuilder<bool>(
              valueListenable: editing,
              builder: (context, value, _) => LibraryCardSheet(
                books: books,
                filterYear: filterYear,
                isEditMode: value,
                maxExtent: _surface.height,
                onFilterChanged: onFilterChanged ?? (_) {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // The Card opens at its medium detent — open, and showing the expanded header — so
  // the tests about that header need no gesture. The ones about `card-down` do: a tap
  // on the handle is what puts an open sheet away.
  if (collapsed) {
    await tester.tap(find.byType(SheetGrabHandle));
    await tester.pumpAndSettle();
  }

  // Applied last, and with a single frame rather than a settle: an edit springs the
  // sheet shut, so settling here would collapse the header the test is about. One frame
  // is the state the reader is actually in on the way down, and the only moment a
  // capsule or the share button could still be reached — which is what makes "inert"
  // worth asserting rather than "gone".
  if (isEditMode) {
    editing.value = true;
    await tester.pump();
  }
}

void main() {
  group('LibraryCardSheet share affordance', () {
    testWidgets(
      'Given finished books, When the sheet rests where it opens, Then share is offered',
      (tester) async {
        await _pump(tester, books: [_read('a', DateTime(2024, 3, 1))]);

        expect(find.byIcon(Icons.ios_share), findsOneWidget);
      },
    );

    testWidgets(
      'Given the expanded header, When share renders, Then it asks for the glass '
      'material the library bar declines',
      (tester) async {
        // Flighty's Passport puts a glass share in this corner and the card is the
        // artifact, so the sheet opts in; the bar's band stays bare icons. Asserted as
        // the flag rather than as pixels because `useNativeGlass` is false under
        // `flutter test` — both paths render the same Material fallback here, so a
        // regression would be invisible to every other test in this file.
        // `library_bar_test.dart` holds the other half.
        await _pump(tester, books: [_read('a', DateTime(2024, 3, 1))]);

        expect(
          tester
              .widget<LibraryCardShareButton>(
                find.byType(LibraryCardShareButton),
              )
              .glass,
          isTrue,
        );
      },
    );

    testWidgets(
      'Given the sheet is collapsed, When the header renders, Then share is still there',
      (tester) async {
        // The inverse of what this file asserted first, and the drawing was on this
        // side all along: `decided.html` gives `card-down` `hdr: { title, share: true }`.
        // A collapsed card is a partially visible card, which is still a card worth
        // sending — and the swap did not even happen at this position, since
        // `_swapPoint` is halfway to the *medium* detent.
        await _pump(
          tester,
          books: [_read('a', DateTime(2024, 3, 1))],
          collapsed: true,
        );

        expect(find.byIcon(Icons.ios_share), findsOneWidget);
      },
    );

    testWidgets('Given a drag from open to collapsed, When it passes the swap point, Then '
        'share is never rebuilt', (tester) async {
      // What one header buys beyond consistency. `LibrarySheet` flips `_showExpanded`
      // partway through the gesture, and while the two headers differed that flip
      // changed the tree's shape under the finger -- destroying and recreating the
      // share button's element. It is a `UiKitView` on iOS 26, so that was a platform
      // view torn down and rebuilt mid-drag, every drag.
      //
      // Asserted as element identity because the cost is the *element*, not the
      // widget: a rebuild with the same shape reuses it, and a shape change does not.
      await _pump(tester, books: [_read('a', DateTime(2024, 3, 1))]);

      final before = tester.element(find.byType(LibraryCardShareButton));

      // Far enough to cross `_swapPoint` and settle at the collapsed detent.
      await tester.drag(find.text('Library Card'), const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(find.byType(LibraryCardShareButton), findsOneWidget);
      expect(
        tester.element(find.byType(LibraryCardShareButton)),
        same(before),
        reason:
            'the header is one widget at every position, so the button survives '
            'the drag rather than being torn down and rebuilt',
      );
    });

    testWidgets(
      'Given a year nothing was finished in, When it is selected, Then share '
      'stays in the header and goes inert',
      (tester) async {
        // The bug this replaces: gated on the *selected year* rather than on the
        // library, the button vanished the moment a reader picked one of the empty
        // years `readFilterYears` offers — so the header changed shape as a side
        // effect of tapping a capsule. Sharing a hero that says 0 is still not
        // something anyone wants to have tapped by accident, which is what `enabled`
        // is for.
        await _pump(
          tester,
          books: [_read('a', DateTime(_currentYear - 2, 3, 1))],
          filterYear: _currentYear,
        );

        expect(find.byIcon(Icons.ios_share), findsOneWidget);
        expect(
          tester
              .widget<LibraryCardShareButton>(
                find.byType(LibraryCardShareButton),
              )
              .enabled,
          isFalse,
          reason: 'there is no card in that year to export',
        );
      },
    );

    testWidgets(
      'Given a year with books in it, When it is selected, Then share is still live',
      (tester) async {
        await _pump(
          tester,
          books: [
            _read('a', DateTime(_currentYear, 3, 1)),
            _read('b', DateTime(_currentYear - 1, 9, 1)),
          ],
          filterYear: _currentYear - 1,
        );

        expect(
          tester
              .widget<LibraryCardShareButton>(
                find.byType(LibraryCardShareButton),
              )
              .enabled,
          isTrue,
        );
      },
    );

    testWidgets(
      'Given nothing finished, When the sheet renders, Then there is nothing to share',
      (tester) async {
        // An empty card is still a card, but sharing a hero that says 0 is not
        // something anyone wants to have tapped by accident.
        await _pump(tester, books: []);

        expect(find.byIcon(Icons.ios_share), findsNothing);
        expect(find.byType(StatTile), findsNothing);
      },
    );

    testWidgets(
      'Given the library is being edited, When the sheet renders, Then share is inert',
      (tester) async {
        await _pump(
          tester,
          books: [_read('a', DateTime(2024, 3, 1))],
          isEditMode: true,
        );

        // The sheet springs shut in edit mode, so the button may not be reachable;
        // what matters is that it cannot fire. A disabled `IconButton` has a null
        // `onPressed`.
        final buttons = find.byType(IconButton).evaluate();
        for (final element in buttons) {
          expect((element.widget as IconButton).onPressed, isNull);
        }
      },
    );
  });

  group('LibraryCardSheet header alignment', () {
    testWidgets('Given the collapsed Card sheet, When its title renders, Then it starts at the '
        'sheet\'s left gutter rather than in the middle', (tester) async {
      // A real bug, found by looking at a device screenshot of the collapsed
      // sheet. The title sat dead centre while the same title sat hard left when
      // the sheet was expanded, because `LibrarySheet`'s chrome column used the
      // default `center` cross-axis alignment: a header that fills the width (the
      // read view's, Friends') is unaffected, and the Card's is a bare
      // `LibrarySheetTitle`, which is a `Row(mainAxisSize: min)` and shrink-wraps.
      //
      // Collapsed on purpose: that bare header is the shape the bug needs, and the
      // Card's expanded header is a `Row` with an `Expanded` title, which never had it.
      //
      // Asserted as a *position*, not by finding an `Align`. The widget tree
      // looked entirely reasonable while this was wrong.
      await _pump(
        tester,
        books: [_read('a', DateTime(2024, 3, 1))],
        collapsed: true,
      );

      // Against the *card*, not the box the sheet occupies: the card floats inset
      // from the screen by however much the sheet falls short of covering it, and
      // the gutter is measured from the edge a reader can see.
      final card = sheetCardRect(tester);
      final title = tester.getRect(find.text('Library Card'));

      // 25 is `LibrarySheet`'s gutter.
      expect(
        title.left - card.left,
        closeTo(25, 0.5),
        reason:
            'the title must begin at the gutter; centred, it would start around '
            '${((card.width - title.width) / 2).round()}',
      );
    });
  });

  group('LibraryCardSheet body gutter', () {
    testWidgets(
      'Given the open Card sheet, When the tiles render, Then they are inset '
      'from the card\'s edges and their text lands on the sheet\'s gutter',
      (tester) async {
        // Found on a device screenshot: the tiles ran flush to the card's left and
        // right edges while the title above them sat at the 25pt gutter, so the one
        // body in this sheet family that is made of boxes was also the one that did
        // not honour the gutter.
        //
        // Measured from the *card's* edge and on both sides, because that is the edge a
        // reader sees, and because a body inset only on the left would still look right
        // in a screenshot of the left half.
        await _pump(tester, books: [_read('a', DateTime(2024, 3, 1))]);

        final card = sheetCardRect(tester);
        final hero = tester.getRect(find.byType(StatTile).first);

        expect(
          hero.left - card.left,
          closeTo(9, 0.5),
          reason: 'flush tiles are the bug this test exists for',
        );
        expect(card.right - hero.right, closeTo(9, 0.5));

        // The point of 9 rather than 25: a tile's own 16pt of padding makes up the
        // difference, so its label begins where the title above it does.
        final label = tester.getRect(find.text('ALL-TIME LIBRARY CARD'));
        final title = tester.getRect(find.text('Library Card'));
        expect(label.left - card.left, closeTo(25, 0.5));
        expect(label.left, closeTo(title.left, 0.5));
      },
    );
  });

  group('LibraryCardSheet year capsules', () {
    testWidgets('Given books finished in the current year only, When the sheet renders, '
        'Then all time and that year are both offered', (tester) async {
      // No capsules used to be drawn here: all time and the current year select
      // the same books, and nothing before or after needs filling in. The rail is
      // unconditional now — the card's scope is worth naming even when there is
      // one of it, and a rail that appears the day a reader crosses into a second
      // year moves the header's furniture at a moment they did not aim at. See
      // `readFilterYears`.
      await _pump(
        tester,
        books: [
          _read('a', DateTime(_currentYear, 3, 1)),
          _read('b', DateTime(_currentYear, 9, 1)),
        ],
      );

      expect(find.byType(ReadFilter), findsOneWidget);
      expect(tester.widget<ReadFilter>(find.byType(ReadFilter)).years, [
        0,
        _currentYear,
      ]);
    });

    testWidgets(
      'Given a library with nothing read in it, When the sheet renders, Then the '
      'rail is still there',
      (tester) async {
        // The case the old gate hid completely. A reader with no finishes had the one
        // read view in the app with no control in it, so "all time" — the only scope
        // that can tell them they have read nothing *at all* rather than nothing this
        // year — was unreachable.
        await _pump(tester, books: const []);

        expect(find.byType(ReadFilter), findsOneWidget);
        expect(
          tester.widget<ReadFilter>(find.byType(ReadFilter)).years,
          [0, _currentYear],
          reason: 'the current year is the one year we know exists',
        );
      },
    );

    testWidgets(
      'Given books finished across two years, When the sheet renders, '
      'Then the capsules appear',
      (tester) async {
        await _pump(
          tester,
          books: [
            _read('a', DateTime(_currentYear, 3, 1)),
            _read('b', DateTime(_currentYear - 1, 9, 1)),
          ],
        );

        expect(find.byType(ReadFilter), findsOneWidget);
        final filter = tester.widget<ReadFilter>(find.byType(ReadFilter));
        expect(
          filter.years,
          [0, _currentYear, _currentYear - 1],
          reason:
              'all time first, then newest year first — ReadFilter\'s order',
        );
        expect(
          filter.expanded,
          isTrue,
          reason:
              'the Card has no collapsed body, so capsules are its only shape',
        );
      },
    );

    testWidgets(
      'Given books finished only in a year before the current one, When the '
      'sheet renders, Then the capsules reach the current year anyway',
      (tester) async {
        await _pump(
          tester,
          books: [_read('a', DateTime(_currentYear - 2, 3, 1))],
        );

        final filter = tester.widget<ReadFilter>(find.byType(ReadFilter));
        expect(
          filter.years,
          [0, _currentYear, _currentYear - 1, _currentYear - 2],
          reason:
              'nobody has finished a book this year or last, but both years '
              'exist and are worth offering — the range is not limited to '
              'years that already have a book in them',
        );
      },
    );

    testWidgets('Given a year is selected, When the sheet renders, '
        'Then the figures and the hero label are that year\'s', (tester) async {
      await _pump(
        tester,
        books: [
          _read('a', DateTime(2024, 3, 1)),
          _read('b', DateTime(2024, 9, 1)),
          _read('c', DateTime(2023, 9, 1)),
        ],
        filterYear: 2023,
      );

      expect(find.text('2023 LIBRARY CARD'), findsOneWidget);
      expect(
        find.text('1'),
        findsOneWidget,
        reason: 'one book finished in 2023, not the three in the library',
      );
    });

    testWidgets(
      'Given the library is being edited, When the capsules render, Then they are inert',
      (tester) async {
        await _pump(
          tester,
          books: [
            _read('a', DateTime(2024, 3, 1)),
            _read('b', DateTime(2023, 9, 1)),
          ],
          isEditMode: true,
        );

        final filter = tester.widget<ReadFilter>(find.byType(ReadFilter));
        expect(filter.enabled, isFalse);
      },
    );

    testWidgets(
      'Given a year nothing was finished in, When it is selected, Then the card is '
      'still there reading zero, rather than being replaced by copy',
      (tester) async {
        // The reported symptom, end to end: the sheet has to hand the body every
        // finished book *unfiltered* alongside the year, or the body cannot tell "you
        // have read nothing" apart from "this year holds nothing" — and it renders a
        // card for the second and a promise only for the first.
        //
        // Read beside the share test above: at this exact moment the button stays put
        // and goes inert. The empty card is what explains why.
        await _pump(
          tester,
          books: [_read('a', DateTime(_currentYear - 2, 3, 1))],
          filterYear: _currentYear,
        );

        expect(find.text('$_currentYear LIBRARY CARD'), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
        expect(find.text('Your reading stats will live here'), findsNothing);
      },
    );

    testWidgets('Given the sheet is collapsed, When the header renders, Then the capsules '
        'are still there', (tester) async {
      // The rail used to belong to the expanded header alone, on the reading that
      // `card-down` is title-only. The filter does not stop applying when the sheet
      // collapses, so dropping the rail left a reader looking at one year's clipped
      // card with nothing on screen naming the year and no way back to all time
      // short of opening the sheet again.
      await _pump(
        tester,
        books: [
          _read('a', DateTime(_currentYear, 3, 1)),
          _read('b', DateTime(_currentYear - 1, 9, 1)),
        ],
        filterYear: _currentYear - 1,
        collapsed: true,
      );

      expect(find.byType(ReadFilter), findsOneWidget);
      expect(
        tester.widget<ReadFilter>(find.byType(ReadFilter)).selected,
        _currentYear - 1,
        reason: 'the collapsed rail shows the year that is actually applied',
      );
      // Inside the card a reader can see, not clipped off below its bottom edge.
      final card = sheetCardRect(tester);
      final rail = tester.getRect(find.byType(ReadFilter));
      expect(rail.bottom, lessThanOrEqualTo(card.bottom + 0.5));
    });
  });

  // Swiping the card sideways is the rail's gesture equivalent: it steps along the
  // same year list, in the same order, and the card slides a page's width to answer.
  // The motion itself belongs to `LibrarySheet` and is measured in
  // `library_sheet_paging_test.dart`; what matters here is that the Card hands it the
  // right series, so a swipe and a tap cannot mean different things.
  //
  // Asserted through `onFilterChanged` rather than by reading the redrawn card,
  // because the year the sheet *asks for* is the whole of its contribution — the
  // shell owns the state, and a test that held it itself would be re-testing the
  // host.
  group('LibraryCardSheet year swipe', () {
    /// Two years plus all-time, so the rail reads `All time / this year / last year`
    /// and both directions have somewhere to go from the middle.
    List<Book> books() => [
      _read('a', DateTime(_currentYear, 3, 1)),
      _read('b', DateTime(_currentYear - 1, 9, 1)),
    ];

    /// Past the fifth of the card's width that commits a turn, and well short of a
    /// whole page.
    const swipe = 200.0;

    testWidgets(
      'Given all time, When the card is swiped left, Then the next year in the rail '
      'is asked for',
      (tester) async {
        final asked = <int>[];
        await _pump(tester, books: books(), onFilterChanged: asked.add);

        await tester.drag(find.byType(StatTile).first, const Offset(-swipe, 0));
        await tester.pumpAndSettle();

        expect(asked, [_currentYear]);
      },
    );

    testWidgets(
      'Given a year, When the card is swiped right, Then it goes back up the rail',
      (tester) async {
        final asked = <int>[];
        await _pump(
          tester,
          books: books(),
          filterYear: _currentYear,
          onFilterChanged: asked.add,
        );

        await tester.drag(find.byType(StatTile).first, const Offset(swipe, 0));
        await tester.pumpAndSettle();

        expect(asked, [0], reason: 'all time leads the rail');
      },
    );

    testWidgets(
      'Given the last year in the rail, When swiped left, Then nothing is asked for',
      (tester) async {
        final asked = <int>[];
        await _pump(
          tester,
          books: books(),
          filterYear: _currentYear - 1,
          onFilterChanged: asked.add,
        );

        await tester.drag(find.byType(StatTile).first, const Offset(-swipe, 0));
        await tester.pumpAndSettle();

        expect(asked, isEmpty, reason: 'there is no year past the earliest');
      },
    );

    testWidgets(
      'Given a single year of reading, When swiped, Then all time and that year are '
      'still a series to move along',
      (tester) async {
        // This used to assert the opposite, behind the same gate the rail was: one
        // option is not a control and one page is not a series. Both are two now —
        // `readFilterYears` always offers all time beside at least the current year —
        // so the swipe has somewhere to go and the sheet is not the odd one out.
        final asked = <int>[];
        await _pump(
          tester,
          books: [_read('a', DateTime(_currentYear, 3, 1))],
          onFilterChanged: asked.add,
        );

        await tester.drag(find.byType(StatTile).first, const Offset(-swipe, 0));
        await tester.pumpAndSettle();

        expect(asked, [_currentYear]);
      },
    );

    testWidgets(
      'Given the sheet is collapsed, When the card is swiped, Then the year still '
      'turns',
      (tester) async {
        // The Card has no collapsed body and nothing inside it scrolls sideways, so
        // the gesture is the card's at every snap position — which is the same reason
        // the rail itself survives a collapse. Swiped across the title, because
        // collapsed there is no tile left inside the card to put a finger on: the
        // gesture belongs to the whole sheet rather than to its body, and this is the
        // position where that difference is the entire feature.
        final asked = <int>[];
        await _pump(
          tester,
          books: books(),
          collapsed: true,
          onFilterChanged: asked.add,
        );

        await tester.drag(find.text('Library Card'), const Offset(-swipe, 0));
        await tester.pumpAndSettle();

        expect(asked, [_currentYear]);
      },
    );

    testWidgets(
      'Given the library is being edited, When the card is swiped, Then nothing is '
      'asked for',
      (tester) async {
        final asked = <int>[];
        await _pump(
          tester,
          books: books(),
          isEditMode: true,
          onFilterChanged: asked.add,
        );

        await tester.drag(find.byType(StatTile).first, const Offset(-swipe, 0));
        await tester.pumpAndSettle();

        expect(asked, isEmpty);
      },
    );
  });
}
