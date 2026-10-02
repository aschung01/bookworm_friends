// The Card tab does not stretch on an iPad.
//
// **This is the one sheet neither existing cap reached.** Every *modal* sheet inherits
// Material 3's `maxWidth: 640`, and the pages that need one go behind
// `CenteredContent` — but the Card lives in the *persistent* `LibrarySheet`, which is
// full-width by design, so a hero card and three tiles spread across all 1032 points of
// an iPad with a dead white half-page underneath. It is what
// `docs/store/screenshots/1.1.0/capture/en-US/ipad13/02-library-card.png` shows, and it went
// unnoticed because nothing in the suite laid this sheet out wider than a phone.
//
// Two caps, not one, because the header and the body are padded differently: the title
// sits `kLibrarySheetGutter` (25) inside the card and the hero `_bodyGutter` (9). The
// gap between them is 16 on every phone, so each cap discounts the gutter that already
// surrounds it and both land on one centre line. Capping both at a bare
// `kContentMaxWidth` would instead centre the two boxes on the same line and make the
// title flush with the hero — a different object from the one the phone draws.
//
// Measured on `ReadFilter` and `LibraryCardBody` rather than on the `CenteredContent`
// widgets: `CenteredContent` is an `Align`, so its own rect is the full available width
// and only its child reports the cap.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/library_card/library_card_body.dart';
import 'package:bookworm_friends/ui/widgets/library_card_sheet.dart';
import 'package:bookworm_friends/ui/widgets/read_filter.dart';

/// iPad 13" portrait, and the narrowest phone the app supports.
const _ipad = Size(1032, 1376);
const _phone = Size(393, 852);

/// `kContentMaxWidth` (640) less twice the gutter that already surrounds each box.
/// Literals rather than arithmetic on the constants, which would restate the
/// implementation and pass whatever it did.
const _headerContentMax = 590.0; // 640 - 25 * 2
const _bodyContentMax = 622.0; // 640 -  9 * 2

Book _read(String id) => Book(
  id: id,
  userId: 'u',
  shelfId: 's',
  isbn: id,
  title: 'Book $id',
  thumbnail: '',
  status: 2,
  position: 0,
  startDate: DateTime(2026, 1, 1),
  finishDate: DateTime(2026, 1, 6),
  createdAt: DateTime(2024),
  authors: const ['An Author'],
);

Future<void> _pump(WidgetTester tester, Size surface) async {
  // Pinned to 1 so every figure below is the logical point the layout reasons about;
  // the harness default of 3 would make each assertion a division.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = surface;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox.expand()),
            LibraryCardSheet(
              books: [_read('a'), _read('b')],
              filterYear: 0,
              isEditMode: false,
              maxExtent: surface.height,
              onFilterChanged: (_) {},
              streak: 3,
              longestStreak: 9,
              readToday: true,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Given an iPad, When the Card is open, Then neither half stretches',
    (tester) async {
      await _pump(tester, _ipad);

      final header = tester.getRect(find.byType(ReadFilter));
      final body = tester.getRect(find.byType(LibraryCardBody));

      expect(header.width, _headerContentMax);
      expect(body.width, _bodyContentMax);

      // The whole point of the fix: 1032 of iPad, and the card occupies 622 of it.
      expect(body.width, lessThan(_ipad.width * 0.65));
    },
  );

  testWidgets(
    'Given an iPad, When both halves are capped, Then they share one centre line',
    (tester) async {
      await _pump(tester, _ipad);

      final header = tester.getRect(find.byType(ReadFilter));
      final body = tester.getRect(find.byType(LibraryCardBody));

      // Two independent caps, so agreeing is a result rather than a construction —
      // and the failure this guards is the pair drifting apart by up to 50pt.
      expect(header.center.dx, closeTo(body.center.dx, 0.5));
      expect(body.center.dx, closeTo(_ipad.width / 2, 0.5));
    },
  );

  testWidgets(
    'Given an iPad, When the title is drawn, Then it stays 16 inside the hero',
    (tester) async {
      await _pump(tester, _ipad);

      final header = tester.getRect(find.byType(ReadFilter));
      final body = tester.getRect(find.byType(LibraryCardBody));

      // 25 - 9. The relationship a phone draws, preserved rather than flattened: a
      // bare `kContentMaxWidth` on both would make this 0 and the title flush with
      // the hero.
      expect(header.left - body.left, closeTo(16, 0.5));
    },
  );

  testWidgets('Given a phone, When the Card is open, Then neither cap binds', (
    tester,
  ) async {
    await _pump(tester, _phone);

    final header = tester.getRect(find.byType(ReadFilter));
    final body = tester.getRect(find.byType(LibraryCardBody));

    // A cap needs no breakpoint precisely because it is a no-op here — see
    // `CenteredContent`, which is deliberately not gated behind `isTabletLayout`.
    expect(body.width, lessThan(_bodyContentMax));
    expect(header.width, lessThan(_headerContentMax));

    // And it still uses the room it has, which is what a cap applied at the wrong
    // level would quietly take away.
    expect(body.width, greaterThan(_phone.width * 0.9));
    expect(header.center.dx, closeTo(body.center.dx, 0.5));
  });
}
