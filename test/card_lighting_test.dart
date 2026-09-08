// Tests for Candlelight: the card's one delight toggle.
//
// **What is asserted here is that it is a light rather than a filter.** A filter adds
// something that was not on the object; a light finds what was. So the claims are about
// *reveals* — the seal goes from a shape in the stock to a mark on it, the gilt appears,
// and each cover gains the month it was finished — and about the one thing the light is
// not allowed to cost, which is the strip.
//
// The strip's own contrast lives in `library_card_contrast_test.dart` beside the daylight
// version, because that file already owns the compositing arithmetic and a second copy of
// it would be a second definition of AA.
//
// The last group rasterises. That is the only way to assert the claim the plan cared
// about most — **the export carries whatever is on screen** — because everything else here
// would pass just as well for a toggle wired only to the preview.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/library_card_stats.dart';
import 'package:bookworm_friends/services/widget_png_renderer.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_cover_row.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_shelf_plan.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/library_card/shareable_library_card.dart';

/// The width the row is given, matching the exported card's own 360pt. The stamp tier
/// boundary is a function of how wide a cover comes out, so this cannot be arbitrary.
const double _rowWidth = 360;

Book _read(String isbn, DateTime finish) => Book(
  id: isbn,
  userId: 'u',
  shelfId: 's',
  isbn: isbn,
  title: 'Title $isbn',
  thumbnail: '',
  status: 2,
  position: 0,
  startDate: finish.subtract(const Duration(days: 5)),
  finishDate: finish,
  createdAt: DateTime(2024),
);

/// [count] books, all finished in March so every stamp reads the same and the assertion
/// is about presence rather than about `DateFormat`.
List<Book> _books(int count) => [
  for (var i = 0; i < count; i++) _read('b$i', DateTime(2026, 3, 1 + i)),
];

Future<void> _pumpRow(
  WidgetTester tester,
  List<Book> books,
  CardLighting lighting,
) async {
  await tester.pumpWidget(
    MaterialApp(
      // The delegates are not decoration here. `cardStampMonth` uses `DateFormat` with a
      // forced `en`, and `intl` throws `LocaleDataException` until a localisation
      // delegate has initialised its date symbols — which the app's own `MaterialApp`
      // always has, and a bare test `MaterialApp` does not.
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Center(
        child: SizedBox(
          width: _rowWidth,
          child: CardCoverRow(
            books: books,
            unit: _rowWidth / kCardShelfUnits,
            lighting: lighting,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpCard(
  WidgetTester tester,
  CardLighting lighting, {
  List<Book>? books,
}) async {
  final fixture = books ?? _books(2);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // No `Scaffold`, matching the condition the capture hosts the card in. See
      // `shareable_library_card_test.dart`.
      home: Center(
        child: ShareableLibraryCard(
          stats: libraryCardStats(fixture),
          books: fixture,
          displayName: 'Alex Smith',
          memberSince: DateTime(2026, 6, 26),
          issuedOn: DateTime(2026, 8, 21),
          lighting: lighting,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the palette is a light, not a filter', () {
    test('Given candlelight, When the palette is built, Then the falloff is in the stock '
        'and not in an overlay', () {
      // The plan's hardest constraint, and the whole reason this is asserted rather
      // than eyeballed: physically the bottom of the card is darkest, the strip is
      // printed there, and the strip is what earns the share. Putting the falloff in
      // the stock puts it *behind* the type — so the card still falls off and nothing
      // on it is dimmed. An overlay with a dark stop would do the opposite.
      final lit = cardPalette(CardLighting.candlelight);
      expect(lit.stock.first, isNot(lit.stock.last));

      for (final stop in kCandleBloomColors) {
        expect(
          stop.r + stop.g + stop.b,
          greaterThan(0),
          reason: 'the bloom carries the highlight only — no black stop',
        );
      }
      expect(kCandleBloomColors.last.a, 0);
    });

    test('Given daylight, When the palette is built, Then the stock is flat', () {
      // Two identical stops rather than a special case in the widget: one code path
      // paints both lighting states, so there is nowhere for a colour to be left
      // behind.
      final day = cardPalette(CardLighting.daylight);
      expect(day.stock.first, day.stock.last);
      expect(day.bloom, isEmpty);
      expect(day.coverLight, isNull);
    });

    test('Given candlelight, When the seal and the gilt are lit, Then both go from '
        'nearly invisible to visible', () {
      // These are Task 2's leftovers and they land here on purpose. The seal was drawn
      // at 10% because that is what an unlit emboss looks like; the gilt is foil at 7%
      // on cream, which is what foil looks like with the lights on. Being found by a
      // raking flame is the point of both, and it is the difference between a reveal
      // and an addition.
      final day = cardPalette(CardLighting.daylight);
      final lit = cardPalette(CardLighting.candlelight);

      expect(day.sealOpacity, lessThan(0.2));
      expect(lit.sealOpacity, 1);
      expect(lit.giltStrong.a, greaterThan(day.giltStrong.a * 3));
    });

    test(
      'Given candlelight, When the strip is inked, Then it is at full strength',
      () {
        // Daylight's strip is 78% ink; the lit one is 100% glow. The card's darkest
        // region is the bottom edge and the strip lives there, so this is the one
        // element the light is not permitted to cost anything.
        expect(cardPalette(CardLighting.candlelight).stripInk.a, 1.0);
        expect(
          cardPalette(CardLighting.candlelight).stripInk.a,
          greaterThan(cardPalette(CardLighting.daylight).stripInk.a),
        );
      },
    );
  });

  group('cover stamps', () {
    testWidgets(
      'Given six covers under a candle, When they are drawn, Then each carries its '
      'finish month',
      (tester) async {
        await _pumpRow(tester, _books(6), CardLighting.candlelight);

        expect(find.byKey(const ValueKey('cover-stamp-b0')), findsOneWidget);
        expect(find.text('MAR'), findsNWidgets(6));
        expect(find.byKey(const ValueKey('cover-mark-b0')), findsNothing);
      },
    );

    testWidgets(
      'Given twelve covers under a candle, When they are drawn, Then the reveal '
      'degrades to a warm mark',
      (tester) async {
        // At twelve covers a cover is 18pt wide in the export and no legible date fits
        // in one, so a stamp per cover would be a row of smudges. Texture is the honest
        // outcome — and a smudge that is trying to be information is worse than texture
        // that is not.
        await _pumpRow(tester, _books(12), CardLighting.candlelight);

        expect(find.text('MAR'), findsNothing);
        expect(find.byKey(const ValueKey('cover-stamp-b0')), findsNothing);
        expect(find.byKey(const ValueKey('cover-mark-b0')), findsOneWidget);
      },
    );

    testWidgets(
      'Given the boundary, When it is crossed, Then it is exactly six',
      (tester) async {
        await _pumpRow(tester, _books(kCardStampMax), CardLighting.candlelight);
        expect(find.text('MAR'), findsNWidgets(kCardStampMax));

        await _pumpRow(
          tester,
          _books(kCardStampMax + 1),
          CardLighting.candlelight,
        );
        expect(find.text('MAR'), findsNothing);
      },
    );

    testWidgets(
      'Given daylight, When six covers are drawn, Then nothing is stamped at all',
      (tester) async {
        // Rejected in review and asserted here so it stays rejected: printing an empty
        // ruled stamp column in daylight and filling it under the flame is more faithful
        // to the object and draws a card that looks unfinished to anyone who never
        // presses the pill.
        await _pumpRow(tester, _books(6), CardLighting.daylight);

        expect(find.text('MAR'), findsNothing);
        expect(find.byKey(const ValueKey('cover-stamp-b0')), findsNothing);
        expect(find.byKey(const ValueKey('cover-mark-b0')), findsNothing);
      },
    );

    testWidgets(
      'Given a book with no finish date, When the row is lit, Then that cover is '
      'unstamped and the rest are not',
      (tester) async {
        // A guard rather than a case that exists today: all 293 finished books in the
        // migrated corpus carry a `finish_date`. An unstamped cover in a stamped row is
        // better than a stamp reading a date nobody recorded.
        final books = [
          ..._books(2),
          Book(
            id: 'undated',
            userId: 'u',
            shelfId: 's',
            isbn: 'undated',
            title: 'Undated',
            thumbnail: '',
            status: 2,
            position: 0,
            createdAt: DateTime(2024),
          ),
        ];
        await _pumpRow(tester, books, CardLighting.candlelight);

        expect(find.text('MAR'), findsNWidgets(2));
        expect(find.byKey(const ValueKey('cover-stamp-undated')), findsNothing);
      },
    );
  });

  group('the card is lit as a whole', () {
    testWidgets(
      'Given candlelight, When the card renders, Then it still says everything the '
      'daylight card says',
      (tester) async {
        // The cost the review accepted is that a lit card is harder for a stranger to
        // read *as a library card*. What is not accepted is losing a field to the dark.
        await _pumpCard(tester, CardLighting.candlelight);

        expect(find.text('MY LIBRARY CARD'), findsOneWidget);
        expect(find.text('Alex Smith'), findsOneWidget);
        expect(find.text('Authority'), findsOneWidget);
        expect(find.textContaining('ISSUED21AUG26'), findsOneWidget);
      },
    );

    testWidgets(
      'Given either lighting, When the card renders, Then it is the same fixed size',
      (tester) async {
        await _pumpCard(tester, CardLighting.daylight);
        expect(
          tester.getSize(find.byType(ShareableLibraryCard)),
          kShareableCardSize,
        );

        await _pumpCard(tester, CardLighting.candlelight);
        expect(
          tester.getSize(find.byType(ShareableLibraryCard)),
          kShareableCardSize,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('the export carries the toggle', () {
    /// Rasterises the card at [lighting] and returns the PNG bytes.
    ///
    /// The same shape `widget_png_renderer_test.dart` uses, and for the same reason:
    /// `toImage` and PNG encoding need real async work, which only runs inside
    /// `runAsync`, and a test cannot pump from in there. So the tree is pumped first and
    /// only the rasterise is wrapped.
    Future<Uint8List> raster(WidgetTester tester, CardLighting lighting) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: ShareableLibraryCard(
                stats: libraryCardStats(_books(2)),
                books: _books(2),
                displayName: 'Alex Smith',
                issuedOn: DateTime(2026, 8, 21),
                lighting: lighting,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // Ratio 1 rather than the export's 3: this is about whether the bytes differ, and
      // a 1080x1350 encode in every run buys nothing.
      final bytes = await tester.runAsync(
        () => rasterizeBoundary(boundary, pixelRatio: 1),
      );
      return bytes!;
    }

    testWidgets(
      'Given the toggle is pressed, When the card is exported, Then the file is a '
      'different image',
      (tester) async {
        // The claim everything else in this file would pass without: a delight toggle
        // wired only to the preview is a toy, and the reader who pressed it is precisely
        // the one about to share.
        final day = await raster(tester, CardLighting.daylight);
        final lit = await raster(tester, CardLighting.candlelight);

        expect(day, isNotEmpty);
        expect(lit, isNotEmpty);
        expect(lit, isNot(day));
      },
    );
  });
}
