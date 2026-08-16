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
// are the Phase 1 ones. Expanded is new, and it is the case that can eat the
// library: the month grid would happily grow to the top of the screen, so the
// clearance there is not a consequence of the contents at all but of a deliberate
// cap. What bounds it is `FinishedBooksSheet.expandedExtentFor`, and that is what
// the last two tests assert.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/read_month_grid.dart';

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
    userLibraryProvider.overrideWith((ref, id) async => singleBookLibrary()),
    followingListProvider.overrideWith((ref) async => [_friend('f1', 'jisoo')]),
  ],
);

double _clearance(WidgetTester tester) =>
    tester.getRect(find.byType(RefreshIndicator)).height;

/// One shelf row of books, at the height the library draws it on this surface.
double _shelfRow(Size surface) => bookRowExtent(surface.height * 0.15);

/// Expands the sheet by tapping the grab handle, which is the one gesture that
/// cannot be mistaken for a shelf scroll.
Future<void> _expand(WidgetTester tester) async {
  await tester.tap(find.byType(SheetGrabHandle));
  await tester.pumpAndSettle();
}

void main() {
  group('Library left between the bar and the sheet', () {
    testWidgets(
      'Given your own library and a friend\'s, When laid out, Then both leave a '
      'usable band of library',
      (tester) async {
        await _pump(tester, surfaceSize: _smallPhone);
        final own = _clearance(tester);

        await enterVisit(tester, 'jisoo');
        final visiting = _clearance(tester);

        // Measured on a 375x667 phone: 319 on your own library, 329 on a
        // friend's. The mockup's finding is *inverted* here, and the arithmetic
        // says why: a visit costs the rail's 48pt row but frees the tab bar's
        // 78pt reservation, so it comes out 30pt ahead. The friend screen is the
        // roomier of the two, not the 5.8px sliver the drawing measured.
        for (final entry in {'own': own, 'visiting': visiting}.entries) {
          expect(
            entry.value,
            greaterThan(150),
            reason:
                '${entry.key}: the library must still read as a library, not a '
                'sliver between two bars',
          );
        }
      },
    );

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

        // Measured: 304, against 329 at the default scale. The header is the only
        // part of the sheet that grows with text size, and it costs ~25pt.
        expect(
          _clearance(tester),
          greaterThan(100),
          reason:
              'at accessibility text sizes the sheet header grows; the library '
              'must keep enough height to be a library',
        );
      },
    );

    testWidgets(
      'Given far more read books than fit, When expanded, Then the cap bounds '
      'the sheet and one shelf of library survives',
      (tester) async {
        // This is what bounds the clearance now. Before Phase 2 it was the pile:
        // a horizontally scrolling row of fixed height, so forty books took
        // exactly as much vertical room as two, and the comment here said that a
        // grid would end it. The grid has arrived, and the bound is no longer a
        // property of the contents — it is `expandedExtentFor`, which subtracts
        // one shelf row from what the sheet and library share.
        await _pump(
          tester,
          surfaceSize: _smallPhone,
          readBooks: _manyReadBooks(),
        );
        await _expand(tester);

        expect(find.byType(ReadMonthGrid), findsOneWidget);

        // Sharp on purpose: an uncapped grid would take the whole band and leave
        // nothing, and a cap that forgot the tab bar's reservation would leave
        // 40pt. Only a cap that sets aside exactly one shelf row lands here.
        expect(
          _clearance(tester),
          closeTo(_shelfRow(_smallPhone), 1.5),
          reason:
              'forty books must not make the sheet taller than the cap, and the '
              'cap exists so a shelf of covers stays visible behind it — that is '
              'what makes it a sheet and not a page',
        );
      },
    );

    testWidgets(
      'Given the largest text scale on the smallest phone, When expanded, Then '
      'the shelf still survives and nothing overflows',
      (tester) async {
        // The month headers are new text that scales, and the expanded state is
        // taller than anything Phase 1 had — so the worst case has to be
        // re-measured rather than inherited.
        //
        // Measured on a 375x667 phone: 106.1 of library left, which is exactly
        // `bookRowExtent(667 * 0.15)` and identical to the default text scale.
        // The first version of the cap left 40.1 here — 66pt less, which is the
        // tab bar's whole reservation, taken out of the library instead of the
        // grid.
        await _pump(
          tester,
          surfaceSize: _smallPhone,
          textScaler: const TextScaler.linear(2),
          readBooks: _manyReadBooks(),
        );
        await _expand(tester);

        expect(
          _clearance(tester),
          closeTo(_shelfRow(_smallPhone), 1.5),
          reason:
              'the cap is derived from the shelf row, which does not scale with '
              'text, so accessibility sizes must cost the grid and not the '
              'library',
        );
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
  });
}
