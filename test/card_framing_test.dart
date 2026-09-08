// Tests for framing: how the exported image is composed around the card.
//
// **The single most important claim in this file is that there is one pinned size.**
// The plan expected two — a 4:5 canvas and a 9:16 one for Stories — and Task 4 settled
// that neither Float nor a Story needs a second constant. Everything else here follows
// from that: both framings produce an image of the same dimensions, and the card inside
// them is laid out once at `kShareableCardSize` whichever is chosen.
//
// The card is not re-asserted here. `shareable_library_card_test.dart` owns what is on
// it; this file owns only what surrounds it, which is why the fixture is one book and
// the assertions are about boxes and paint rather than about strings.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/library_card_stats.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_framing.dart';
import 'package:bookworm_friends/ui/widgets/library_card/shareable_library_card.dart';

final _book = Book(
  id: 'a',
  userId: 'u',
  shelfId: 's',
  isbn: 'a',
  title: 'Book a',
  thumbnail: '',
  status: 2,
  position: 0,
  startDate: DateTime(2026, 3, 4),
  finishDate: DateTime(2026, 3, 10),
  createdAt: DateTime(2024),
);

/// Pumps the framed card the way the capture hosts it: sized to the export, with no
/// `Scaffold` above it. See `shareable_library_card_test.dart` for why the missing
/// `Material` matters.
Future<void> _pump(WidgetTester tester, CardFraming framing) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Center(
        child: FramedShareableCard(
          framing: framing,
          card: ShareableLibraryCard(
            stats: libraryCardStats([_book]),
            books: [_book],
            issuedOn: DateTime(2026, 8, 21),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The float ground, found by the gradient it is painted with. There is exactly one
/// gradient outside the card, and the card's own well is inside a `Material` that
/// clips it.
Finder _ground = find.byWidgetPredicate(
  (widget) =>
      widget is DecoratedBox &&
      widget.decoration is BoxDecoration &&
      (widget.decoration as BoxDecoration).gradient is LinearGradient &&
      ((widget.decoration as BoxDecoration).gradient as LinearGradient)
              .colors
              .first ==
          kCardGroundTop,
);

void main() {
  group('one pinned size', () {
    test(
      'Given either framing, When the export is sized, Then it is the same 4:5 canvas',
      () {
        // The claim the plan left open. A second constant would put a second shape of
        // the product into circulation; see `framedCardSize` for the two reasons it is
        // not needed.
        expect(framedCardSize, kShareableCardSize);
        expect(
          framedCardSize.width / framedCardSize.height,
          closeTo(4 / 5, 0.0001),
        );
      },
    );

    testWidgets(
      'Given Fill, When the card is framed, Then the image is the canvas exactly',
      (tester) async {
        await _pump(tester, CardFraming.fill);

        expect(
          tester.getSize(find.byType(FramedShareableCard)),
          framedCardSize,
        );
      },
    );

    testWidgets(
      'Given Float, When the card is framed, Then the image is still the canvas '
      'exactly',
      (tester) async {
        await _pump(tester, CardFraming.float);

        expect(
          tester.getSize(find.byType(FramedShareableCard)),
          framedCardSize,
        );
      },
    );
  });

  group('the toggle changes the ground, never the card', () {
    testWidgets(
      'Given Float, When the card is framed, Then the card is still laid out at the '
      'exported size',
      (tester) async {
        // The whole reason a `FittedBox` scales the card rather than the card being
        // relaid out into a smaller box: the type, the well fraction and the strip's 44
        // columns are laid out once, at one size, so the framing cannot break a line
        // the other framing does not.
        await _pump(tester, CardFraming.float);

        expect(
          tester.getSize(find.byType(ShareableLibraryCard)),
          kShareableCardSize,
        );
      },
    );

    testWidgets(
      'Given Float, When the card is framed, Then it is drawn smaller than the image '
      'by the inset',
      (tester) async {
        await _pump(tester, CardFraming.float);

        final image = tester.getRect(find.byType(FramedShareableCard));
        final card = tester.getRect(find.byType(ShareableLibraryCard));

        // Measured on screen rather than in layout: `getRect` reports the transformed
        // rect, so this is the only assertion that catches a `FittedBox` that failed to
        // scale.
        expect(card.width, lessThan(image.width));
        expect(
          image.left + kCardFloatInset,
          closeTo(card.left, 0.5),
          reason: 'the card pulls in from the edge by exactly the inset',
        );
        expect(image.center.dx, closeTo(card.center.dx, 0.5));
        expect(image.center.dy, closeTo(card.center.dy, 0.5));
      },
    );

    testWidgets(
      'Given Fill, When the card is framed, Then there is no ground at all',
      (tester) async {
        // Not "a ground the colour of nothing" — no element. Fill exists because the
        // app the image lands in supplies its own background, and a border of ours only
        // makes the card look smaller.
        await _pump(tester, CardFraming.fill);

        expect(_ground, findsNothing);
      },
    );

    testWidgets(
      'Given Float, When the ground is painted, Then it is an opaque square-cornered '
      'gradient',
      (tester) async {
        await _pump(tester, CardFraming.float);

        expect(_ground, findsOneWidget);
        final decoration =
            tester.widget<DecoratedBox>(_ground).decoration as BoxDecoration;

        // Square corners, and the reason is the file rather than the drawing: a radius
        // on the outermost element of an exported PNG is a *transparent* corner, and
        // the targets this lands in treat alpha differently. Float is the one framing
        // whose exported edge is fully opaque.
        expect(decoration.borderRadius, isNull);
        expect(decoration.color, isNull);
        final gradient = decoration.gradient as LinearGradient;
        expect(gradient.colors, [kCardGroundTop, kCardGroundBottom]);
        for (final stop in gradient.colors) {
          expect(
            stop.a,
            1.0,
            reason: 'a translucent ground is a transparent PNG',
          );
        }
      },
    );

    testWidgets(
      'Given either framing, When the ground is chosen, Then it is not another cream',
      (tester) async {
        // Two creams would put the card's own edge on a ground of nearly its own value
        // and the inset would stop reading as an inset. Asserted as a real difference
        // rather than trusted to the hexes.
        for (final stop in [kCardGroundTop, kCardGroundBottom]) {
          expect(stop, isNot(kCardStock));
        }
        expect(kCardGroundTop, isNot(kCardGroundBottom));
      },
    );
  });
}
