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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/finished_books_sheet.dart';

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
  testBook('r1', 's1', position: 1, title: 'Dune', status: bookStatusFinished),
  testBook('r2', 's1', position: 2, title: 'Circe', status: bookStatusFinished),
];

Future<void> _pump(
  WidgetTester tester, {
  TextScaler? textScaler,
  Size? surfaceSize,
}) => pumpHome(
  tester,
  textScaler: textScaler,
  surfaceSize: surfaceSize,
  extraOverrides: [
    finishedBooksProvider.overrideWith((ref, filter) async => _readBooks()),
    userFinishedBooksProvider.overrideWith((ref, args) async => _readBooks()),
    userLibraryProvider.overrideWith((ref, id) async => singleBookLibrary()),
    followingListProvider.overrideWith((ref) async => [_friend('f1', 'jisoo')]),
  ],
);

double _clearance(WidgetTester tester) =>
    tester.getRect(find.byType(RefreshIndicator)).height;

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
      'Given far more read books than fit, When laid out, Then the pile scrolls '
      'instead of making the sheet taller',
      (tester) async {
        // This is what bounds the clearance. The pile is a horizontally scrolling
        // row of fixed height, so forty books take exactly as much vertical room
        // as two. If it ever becomes a wrap or a grid, the sheet grows with the
        // library and every number in this file stops holding.
        await pumpHome(
          tester,
          surfaceSize: _smallPhone,
          extraOverrides: [
            finishedBooksProvider.overrideWith(
              (ref, filter) async => List.generate(
                40,
                (i) => testBook(
                  'r$i',
                  's1',
                  position: i,
                  title: 'Book $i',
                  status: bookStatusFinished,
                ),
              ),
            ),
          ],
        );

        final pile = find.descendant(
          of: find.byType(FinishedBooksSheet),
          matching: find.byType(ListView),
        );
        expect(tester.widget<ListView>(pile).scrollDirection, Axis.horizontal);
        expect(
          tester.getSize(pile).height,
          closeTo(124 + 13, 0.5),
          reason: 'the pile is a fixed-height row, whatever it contains',
        );
        expect(_clearance(tester), greaterThan(150));
      },
    );
  });
}
