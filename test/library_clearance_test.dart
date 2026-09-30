// How much library is left between the bar and the sheet?
//
// The design record flags this as an open question with a number attached: the
// mockup measured 38.8px of clearance under the bar on your own library and
// 5.8px on a friend's, and said explicitly that it should be measured in Flutter
// rather than trusted. This file is that measurement.
//
// The mockup's tightness came from its own idiom: `.rail` and `.bar` are in flow
// while `.sheet` is `position: absolute; bottom: 0` with a percentage height, so
// adding a rail row pushes the bar down without moving the sheet up and the gap
// between them absorbs the whole difference. Flutter does not lay out that way --
// the rail is in the app bar, the sheet reports its height, and the library is
// `Expanded` between them -- so the same pressure lands somewhere else and has to
// be measured, not translated.
//
// The band is the library's own viewport, so `RefreshIndicator` (which wraps
// exactly the shelf list) is the handle on it.
//
// **Phase 2 measures this twice, because the sheet now has two real states.**
// Collapsed is handle + header + the spine pile, which is what Phase 1 called
// expanded -- so the collapsed numbers barely moved and the first two tests below
// are the Phase 1 ones. Expanded is the case that can eat the library, and it now
// does: the rule that kept one shelf row visible behind an expanded sheet is gone,
// because a year of covers is worth the whole band. So the last two tests assert the
// opposite of what they used to -- the sheet takes all of it -- and the sharp part
// moved to the boundary: exactly the band and not a point more, or the `Column`
// holding the sheet and the library overflows.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/library_card/stat_tile.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/read_month_grid.dart';
import 'package:bookworm_friends/ui/widgets/shell_tab_bar.dart';

import 'support/home_page_harness.dart';

/// A small modern phone in logical pixels — the smallest surface the app has to
/// work on, and the one where the clearance is tightest.
const _smallPhone = Size(375, 667);

Profile _friend(String id, String name) => Profile(
  id: id,
  username: name,
  emoji: '🦊',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

List<Book> _readBooks() => [
  testBook(
    'r1',
    's1',
    position: 1,
    title: 'Dune',
    status: bookStatusFinished,
    finishDate: DateTime(2026, 3, 4),
  ),
  testBook(
    'r2',
    's1',
    position: 2,
    title: 'Circe',
    status: bookStatusFinished,
    finishDate: DateTime(2025, 11, 2),
  ),
];

/// Enough read books, across enough months, that an uncapped grid would be
/// taller than any phone.
List<Book> _manyReadBooks() => List.generate(
  40,
  (i) => testBook(
    'r$i',
    's1',
    position: i,
    title: 'Book $i',
    status: bookStatusFinished,
    finishDate: DateTime(2026 - (i ~/ 12), 1 + (i % 12), 1 + (i % 27)),
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  TextScaler? textScaler,
  Size? surfaceSize,
  List<Book>? readBooks,
  List<Book>? setAsideBooks,
}) => pumpHome(
  tester,
  textScaler: textScaler,
  surfaceSize: surfaceSize,
  extraOverrides: [
    finishedBooksProvider.overrideWith(
      (ref) async => readBooks ?? _readBooks(),
    ),
    userFinishedBooksProvider.overrideWith(
      (ref, userId) async => readBooks ?? _readBooks(),
    ),
    // The read sheet's second query, on both paths. Empty by default: what these
    // tests measure is the row the *chevron* is in, and a set-aside book changes the
    // count rather than the chrome — `setAsideBooks` below is the seam for a case
    // that wants one.
    setAsideBooksProvider.overrideWith(
      (ref) async => setAsideBooks ?? const <Book>[],
    ),
    userSetAsideBooksProvider.overrideWith(
      (ref, userId) async => setAsideBooks ?? const <Book>[],
    ),
    userLibraryProvider.overrideWith((ref, id) async => singleBookLibrary()),
    friendsProvider.overrideWith((ref) async => [_friend('f1', 'jisoo')]),
  ],
);

/// The band of library you can actually see: from the top of the library area down
/// to the top of the sheet floating over it.
///
/// It used to be the library's own height, because the two were siblings in a
/// `Column` and the sheet's height *was* the library's loss. The sheet floats now,
/// so the library's box is the whole screen on every tab and measuring it would
/// report the same number for a collapsed sheet and a full-screen one.
double _clearance(WidgetTester tester) =>
    tester.getRect(find.byType(LibrarySheet)).top -
    tester.getRect(find.byType(RefreshIndicator)).top;

/// Expands the sheet by tapping the grab handle, which is the one gesture that
/// cannot be mistaken for a shelf scroll.
///
/// Only for a sheet that opens *collapsed*. The tap toggles the two ends, so from
/// anywhere open it puts the sheet away instead — see [_dragCardToTop].
Future<void> _expand(WidgetTester tester) async {
  await tester.tap(find.byType(SheetGrabHandle));
  await tester.pumpAndSettle();
}

/// Takes the Card's sheet from the medium detent it opens at to the whole band.
///
/// A drag rather than a handle tap, because the Card no longer opens collapsed: the
/// tap would shut it. Far enough to clear halfway between the two positions, since a
/// release settles on the nearest detent; past the cap the drag is rubber-banded and
/// the nearest is still the cap, so overshooting is safe.
Future<void> _dragCardToTop(WidgetTester tester) async {
  await tester.drag(find.text('Library Card'), const Offset(0, -400));
  await tester.pumpAndSettle();
}

/// Puts an open sheet away — the same gesture as [_expand], and that is the point:
/// the handle toggles the two ends, so on a sheet resting anywhere open it collapses.
Future<void> _collapse(WidgetTester tester) => _expand(tester);

/// Selects a tab on the floating bar.
Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(ShellTabBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Library left between the bar and the sheet', () {
    testWidgets('Given your own library and a friend\'s, When laid out, Then both leave a '
        'usable band of library', (tester) async {
      await _pump(tester, surfaceSize: _smallPhone);
      final own = _clearance(tester);

      await enterVisit(tester, 'jisoo');
      final visiting = _clearance(tester);

      // Measured on a 375x667 phone: **320pt on both**, where a visit used to come
      // out 10pt *taller* than your own library at 329. The arithmetic is the
      // change in the design: a visit used to cost the `FriendRail`'s 48pt row and
      // to free the tab bar's 78pt reservation. It now costs neither and frees
      // neither — one bar row and one reserve on every screen — and her read view
      // carries no chrome yours does not, because the way back up a level is a tap
      // on the Friends tab rather than a control in the sheet's header.
      //
      // That is a ~30pt downgrade against the old visit, accepted deliberately:
      // `decided.html` counted the tab bar's band as something a visit *buys*, and
      // a bar that no longer changes what any tab means has to be on screen to be
      // an exit.
      for (final entry in {'own': own, 'visiting': visiting}.entries) {
        expect(
          entry.value,
          greaterThan(150),
          reason:
              '${entry.key}: the library must still read as a library, not a '
              'sliver between two bars',
        );
      }
      expect(
        visiting,
        closeTo(own, 1),
        reason:
            'same chrome, same band: if these drift apart, something has been '
            'added to a friend\'s read view that your own does not have',
      );
    });

    testWidgets('Given the Friends sheet, When it is at either level, Then the library is '
        'not squeezed away', (tester) async {
      // The assertion this file never had. The Friends tab was the one sheet whose
      // band nothing measured, which mattered least when it was a list you passed
      // through and matters most now that it is the shell's only switcher — and it
      // has two levels, at different detents, with different chrome.
      await _pump(tester, surfaceSize: _smallPhone);
      await _selectTab(tester, 'Friends');

      // Level 1 opens at the medium detent — 65% of the band — which is the
      // deepest any sheet goes without being dragged, so it is the floor.
      final list = _clearance(tester);
      expect(
        list,
        greaterThan(100),
        reason:
            'the switcher opens at 65% of the band and the library behind it '
            'still has to read as a library',
      );

      await tester.tap(find.text('jisoo'));
      await tester.pumpAndSettle();

      // Level 2 is the read view, which rests on its pile, so it gives most of it
      // back. The spring between the two is what makes the drill-in read as one.
      final friend = _clearance(tester);
      expect(
        friend,
        greaterThan(list),
        reason:
            'dropping to the pile is the whole point of the level change: her '
            'library is what you came to see',
      );
    });

    testWidgets(
      'Given the largest text scale on the smallest phone, When visiting, Then '
      'the library is not squeezed away',
      (tester) async {
        // The worst case the app can actually be put in. The read pile is a
        // fixed-height row so the sheet cannot grow with the number of books,
        // but its header does grow with text scale, and that is what eats the
        // band.
        await _pump(
          tester,
          surfaceSize: _smallPhone,
          textScaler: const TextScaler.linear(2),
        );
        await enterVisit(tester, 'jisoo');

        // Measured: 299, against 320 at the default scale. The header is the only part
        // of the sheet that grows with text size, and it costs ~21pt.
        expect(
          _clearance(tester),
          greaterThan(100),
          reason:
              'at accessibility text sizes the sheet header grows; the library '
              'must keep enough height to be a library',
        );
        expect(
          tester.takeException(),
          isNull,
          reason:
              'and the header must not overflow, which is what a third control in '
              'this row did when the level had a back button of its own',
        );
      },
    );

    testWidgets('Given far more read books than fit, When expanded, Then the sheet takes the '
        'whole band and nothing overflows', (tester) async {
      // Before this the bound was the cap, which set one shelf row aside; before
      // *that* it was the pile, a fixed-height row that took as much room for
      // forty books as for two. The grid ended the second era and this change ends
      // the first: expanded is the whole band, and what has to hold is the
      // boundary. A point over and the `Column` holding the sheet and the library
      // overflows; a point under and there is a seam of library above a sheet that
      // claims to be full.
      await _pump(
        tester,
        surfaceSize: _smallPhone,
        readBooks: _manyReadBooks(),
      );
      await _expand(tester);

      expect(find.byType(ReadMonthGrid), findsOneWidget);

      expect(
        _clearance(tester),
        lessThanOrEqualTo(0),
        reason:
            'forty books must not make the sheet taller than the band, and they '
            'must not leave it short of the band either',
      );
      expect(
        tester.getRect(find.byType(LibrarySheet)).top,
        closeTo(28, 1.5),
        reason:
            'the whole band means the middle of the library bar, not the top of '
            'the screen: the sheet rises over the shell\'s bar, which is behind '
            'it in the stack rather than above it, but stops short of covering it '
            'entirely',
      );
      expect(
        tester.takeException(),
        isNull,
        reason:
            'and this is the test that would see an overflow, because the sheet '
            'now has no slack left to absorb one',
      );
    });

    testWidgets(
      'Given the largest text scale on the smallest phone, When expanded, Then it '
      'still fits the band exactly and nothing overflows',
      (tester) async {
        // The month headers scale and the sheet no longer has a shelf row of slack
        // to absorb them, so the worst case is worth re-measuring rather than
        // inheriting.
        await _pump(
          tester,
          surfaceSize: _smallPhone,
          textScaler: const TextScaler.linear(2),
          readBooks: _manyReadBooks(),
        );
        await _expand(tester);

        expect(tester.getRect(find.byType(LibrarySheet)).top, closeTo(28, 1.5));
        expect(
          tester.takeException(),
          isNull,
          reason:
              'nothing in the sheet may overflow at accessibility sizes. Note the '
              'test font makes every glyph one em wide, so "All time" measures '
              '224pt here against ~125 on a device — this is a strict upper '
              'bound, and it is what forced the collapsed header\'s two halves '
              'to both be flexible',
        );
      },
    );

    testWidgets('Given the largest text scale, a two-digit count and the filter chevron, When '
        'expanded, Then the title row does not overflow', (tester) async {
      // **The row this file exists for, with one more fixed thing in it.** The
      // collapsed header's two halves were both made flexible because the year
      // popover's label starved the title of the room its own count needed; the
      // expanded header now adds a chevron beside that count, and the chevron does
      // not shrink. 40 read books make the count two digits, which is the case that
      // costs the most — and the test font draws every glyph one em wide, so
      // `Books finished` measures far wider here than on a device.
      await _pump(
        tester,
        surfaceSize: _smallPhone,
        textScaler: const TextScaler.linear(2),
        readBooks: _manyReadBooks(),
      );
      await _expand(tester);

      final title = find.byType(LibrarySheetTitle);
      expect(
        find.descendant(
          of: title,
          matching: find.byIcon(Icons.keyboard_arrow_down),
        ),
        findsOneWidget,
        reason:
            'if the chevron is not there this measures the row without the thing '
            'it was written for',
      );
      expect(
        tester.widget<LibrarySheetTitle>(title).count,
        greaterThanOrEqualTo(10),
        reason:
            'and a two-digit count, which is the wider of the two cases. The '
            'fixture spreads 40 books over three years and the sheet opens on the '
            'current one, so this is the dozen in it rather than all forty',
      );
      expect(
        tester.takeException(),
        isNull,
        reason:
            'the title ellipsizes and the row holds; an overflow here is the '
            'chevron having taken the room the count needed',
      );

      // The whole row, chevron included, has to be inside the sheet's gutters — an
      // overflow is not the only way to lose the end of it, as a label drawn past
      // the right edge of the card would be clipped rather than reported.
      final sheet = tester.getRect(find.byType(LibrarySheet));
      final row = tester.getRect(title);
      expect(row.left, greaterThanOrEqualTo(sheet.left));
      expect(row.right, lessThanOrEqualTo(sheet.right));
    });

    testWidgets('Given the collapsed sheet, When the filter chevron joins the year popover, '
        'Then the row holds and the library pays 9pt for it', (tester) async {
      // **The row that actually pays for the collapsed chevron, and the reason it is
      // measured here rather than asserted in the sheet's own file.** The collapsed
      // sheet's height is its header plus `ReadPile.extent`, so a taller header is a
      // shorter library — and this is the only file that watches that number.
      //
      // Measured on the smallest phone: the title row goes **21 -> 30** and the clearance
      // **324 -> 315**. The 30 is the control's box, so the cost is the box minus the
      // line it sits on.
      //
      // **It is the fallback that pays, and the fallback is not what ships.** On iOS 26
      // the year popover beside it is a 36pt `CNPopupMenuButton`, so this row is already
      // 36 tall and the 30pt box is free; `flutter test` reports Android, so what is
      // measured here is the strict case. At 2x text it is free on both paths — the title
      // is 43pt by itself, which is the case the two above cover.
      await _pump(
        tester,
        surfaceSize: _smallPhone,
        readBooks: _manyReadBooks(),
      );

      final title = find.byType(LibrarySheetTitle);
      expect(
        find.descendant(
          of: title,
          matching: find.byIcon(Icons.keyboard_arrow_down),
        ),
        findsOneWidget,
        reason:
            'without the chevron this measures the row it was written to replace',
      );
      expect(
        tester.getRect(title).height,
        closeTo(30, 0.5),
        reason:
            'the control is a 30pt box around an 18pt glyph, and it sets the row '
            'height because the 17pt title line is 21',
      );
      expect(
        _clearance(tester),
        closeTo(315, 1),
        reason:
            'so the library keeps 315 of the 324 it had. A number rather than a '
            'bound, because this is a cost that was accepted at a size and should '
            'be re-argued rather than allowed to creep',
      );
      expect(tester.takeException(), isNull);

      // Two flexible halves and one fixed control between them: the title ellipsizes,
      // and the end of the row stays inside the card.
      final sheet = tester.getRect(find.byType(LibrarySheet));
      final row = tester.getRect(title);
      expect(row.left, greaterThanOrEqualTo(sheet.left));
      expect(row.right, lessThanOrEqualTo(sheet.right));
    });

    testWidgets(
      'Given the largest text scale on the smallest phone, When collapsed with the '
      'chevron, Then it costs nothing and nothing overflows',
      (tester) async {
        // The half of the claim above that says the cost is scale-dependent: at 2x the
        // title's own line is 43pt, so the 30pt box disappears inside it and the
        // collapsed header is the height it always was. This is also the row where the
        // year popover's label is widest, which is what made both halves flexible.
        await _pump(
          tester,
          surfaceSize: _smallPhone,
          textScaler: const TextScaler.linear(2),
          readBooks: _manyReadBooks(),
        );

        final title = find.byType(LibrarySheetTitle);
        expect(
          tester.getRect(title).height,
          closeTo(43, 0.5),
          reason: 'the text sets the row height here, not the control',
        );
        expect(
          tester.widget<LibrarySheetTitle>(title).count,
          greaterThanOrEqualTo(10),
          reason: 'and a two-digit count, the wider of the two cases',
        );
        expect(tester.takeException(), isNull);

        final sheet = tester.getRect(find.byType(LibrarySheet));
        expect(
          tester.getRect(title).right,
          lessThanOrEqualTo(sheet.right),
          reason:
              'the test font draws every glyph one em wide, so this is a strict '
              'upper bound on how much room the title wants',
        );
      },
    );
  });

  // Phase 3 measures a third case, and the measurement changed the design. The
  // Card tab's sheet was first built on Phase 1's uncapped path, on the reasoning
  // that a card which has to scroll is a card that says too much — `card-down`
  // draws it collapsing to its title, and its contents are short. At 2x text on a
  // 375x667 phone that overflowed the library view's column by 95pt: every figure
  // and label on the card is text, and all of it scales. `card-open` is drawn at
  // **h:74**, a tall sheet with the tiles at the top, so the cap was right in the
  // drawing before it was right in the code. The Card now shares the read view's
  // `sheetExpandedExtent` and scrolls its body, and these two tests are what hold
  // it there — with the cap since raised from "the band less one shelf row" to the
  // whole band, which is why they now measure zero library rather than one shelf.
  //
  // The Card also does not *open* at the cap: it rests at the medium detent, so these
  // two have to drag it up before they can measure the cap at all. Where it rests is
  // the first test in the group.
  group('Library left behind the Library Card', () {
    /// Read books shaped so the card shows every tile it can: two books by one
    /// author, both with real spans, so pace and most-read author both clear.
    List<Book> cardBooks() => [
      testBook(
        'c1',
        's1',
        position: 1,
        title: 'The Vegetarian',
        status: bookStatusFinished,
        startDate: DateTime(2026, 2, 20),
        finishDate: DateTime(2026, 3, 4),
        authors: const ['한강'],
      ),
      testBook(
        'c2',
        's1',
        position: 2,
        title: 'Human Acts',
        status: bookStatusFinished,
        startDate: DateTime(2025, 10, 20),
        finishDate: DateTime(2025, 11, 2),
        authors: const ['한강'],
      ),
    ];

    Future<void> openCard(WidgetTester tester) async {
      await tester.tap(
        find.descendant(
          of: find.byType(ShellTabBar),
          matching: find.text('Card'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Given the Card tab, When it is opened, Then the sheet rests at its middle '
        'position, showing the card with a strip of library behind it', (tester) async {
      // Both ends were tried first and both were wrong. Expanded was defensible while
      // it meant a card-shaped sheet with a shelf of library behind it; once expanded
      // became the whole band, opening the tab covered the library completely with a
      // card whose content does not fill it — a screen of empty white with no cover
      // left to long-press, so an edit could not be started from the Card tab at all.
      // Collapsed fixed that and overshot: the Card has no pile to rest on, so
      // `card-down` is a title and nothing else, and the tab opened showing none of
      // the card. The middle position is the one that shows both.
      await _pump(tester, surfaceSize: _smallPhone, readBooks: cardBooks());
      await openCard(tester);

      final resting = _clearance(tester);
      expect(
        find.byType(StatTile),
        findsWidgets,
        reason: 'it opens showing the card, not just its title',
      );
      expect(
        resting,
        greaterThan(100),
        reason:
            'and the library is still behind it, which is the whole point of the '
            'middle position over the cap',
      );

      // Against `card-down` measured on the same phone, rather than a bare number: the
      // two positions differ by the height of the card, and a sheet that had quietly
      // gone back to opening collapsed would report the same clearance twice.
      await _collapse(tester);
      expect(
        _clearance(tester),
        greaterThan(resting + 100),
        reason:
            'collapsed leaves far more library than the resting position does; '
            'equal numbers would mean the sheet opened at `card-down`',
      );
    });

    testWidgets('Given the fullest card, When dragged up, Then the sheet takes the '
        'whole band', (tester) async {
      // Sharp for the same reason the read view's is: the number is not a property
      // of the card's contents but of `sheetExpandedExtent`, which is now the whole
      // band. The card is far shorter than that, so what this proves is that the
      // *cap* decides the sheet's height — and that the two capped sheets still
      // agree about it, because two of them disagreeing would show as the library
      // jumping on a tab switch.
      await _pump(tester, surfaceSize: _smallPhone, readBooks: cardBooks());
      await openCard(tester);
      await _dragCardToTop(tester);

      expect(_clearance(tester), lessThanOrEqualTo(0));
      expect(tester.getRect(find.byType(LibrarySheet)).top, closeTo(28, 1.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Given the largest text scale on the smallest phone, When the Card is '
      'expanded, Then the card still fits and nothing overflows',
      (tester) async {
        // The case that would break an uncapped sheet: every figure and label on
        // the card is new text that scales, and at 2x the test font makes each
        // glyph one em wide, so this is a strict upper bound on the real thing.
        await _pump(
          tester,
          surfaceSize: _smallPhone,
          textScaler: const TextScaler.linear(2),
          readBooks: cardBooks(),
        );
        await openCard(tester);
        await _dragCardToTop(tester);

        expect(tester.getRect(find.byType(LibrarySheet)).top, closeTo(28, 1.5));
        expect(
          tester.takeException(),
          isNull,
          reason:
              'no tile, label or figure may overflow at accessibility sizes — '
              'uncapped, this overflowed the library view by 95pt',
        );
      },
    );
  });
}
