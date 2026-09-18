// The light over the Reading shelf.
//
// **The one thing this file exists for is the copy.** `reading_shelf_lamp.dart` restates
// the Library Card's bloom colours instead of importing them, deliberately: the card's
// light is tuned against a near-black stock and this one against #E9ECEF, so the two must
// be free to diverge. A deliberate copy and an accidental one look identical in the
// source, so the pair is pinned here — if the candle is ever retuned, this test is what
// makes somebody look at the shelf rather than let it silently follow or silently drift.
//
// The rest is the rule `card_lighting.dart` is emphatic about: a warm point source
// *scales* what a surface already reflects, so a lit cover keeps its own hue. That is a
// claim about a matrix, and a matrix is exactly the kind of thing that can be wrong in a
// way nobody notices.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/reading_shelf_lamp.dart';

/// The lamp's gradient, read back off a rendered one.
RadialGradient _gradientOf(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byType(ReadingShelfLamp),
      matching: find.byType(DecoratedBox),
    ),
  );
  return (box.decoration as BoxDecoration).gradient! as RadialGradient;
}

Future<void> _pumpLamp(WidgetTester tester, Size size) => tester.pumpWidget(
  Center(
    child: SizedBox(
      width: size.width,
      height: size.height,
      child: const ReadingShelfLamp(),
    ),
  ),
);

/// The book height the layer cases are measured at, and so the height the fade distance
/// is derived from.
const double _kTestBookHeight = 127;

/// The alpha the bloom's brightest stop is currently drawn at — the light's strength, read
/// off the frame rather than off the notifier that set it.
double _alphaOf(WidgetTester tester) => _gradientOf(tester).colors.first.a;

/// The layer as the library builds it: a light pinned across the top, a scrolling list
/// underneath.
///
/// Tight constraints, because that is what `LibraryPaneFrame` gives it.
Future<void> _pumpLayer(
  WidgetTester tester, {
  bool lit = true,
  bool horizontal = false,
}) => tester.pumpWidget(
  Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ReadingLampLayer(
          lit: lit,
          bookHeight: _kTestBookHeight,
          child: ListView(
            scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
            children: [
              for (var i = 0; i < 30; i++)
                const SizedBox(width: 200, height: 200),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group("the bloom is the candle's, copied on purpose", () {
    test('Given the two bloom lists, Then the hues are the same', () {
      // Hue, not alpha. The shelf's first stop is dimmer than the card's — 0x52 against
      // 0x4D — because there is no dark stock here for a bloom to be read against.
      expect(kReadingLampBloom.length, kCandleBloomColors.length);
      for (var i = 0; i < kReadingLampBloom.length; i++) {
        expect(
          kReadingLampBloom[i].toARGB32() & 0x00FFFFFF,
          kCandleBloomColors[i].toARGB32() & 0x00FFFFFF,
          reason:
              'stop $i is meant to be the candle\'s own colour. If the candle '
              'moved, decide what the shelf should do rather than following it.',
        );
      }
    });

    test('Given the bloom, Then it fades to nothing rather than to a colour', () {
      // The last stop is transparent, which is what lets the light stop with the row's
      // clip instead of ending in a visible edge.
      expect(kReadingLampBloom.last.a, 0);
    });

    test('Given the bloom, Then it is front-loaded', () {
      // An even ramp read as a tinted panel rather than as light: most of the warmth
      // has to be near the source.
      expect(kReadingLampStops.first, 0);
      expect(kReadingLampStops.last, 1);
      expect(kReadingLampStops[1], greaterThan(0.5));
      expect(kReadingLampStops.length, kReadingLampBloom.length);
    });
  });

  group('the lamp is a point above the row', () {
    test('Given the reach, Then it stops short of the whole row', () {
      // The plank carries its own warm pool; the two meeting in the middle flattened
      // the falloff into a single wash.
      expect(kReadingLampExtent, lessThan(1));
      expect(kReadingLampExtent, greaterThan(0.5));
    });

    test('Given the source, Then it sits above the first shelf', () {
      // The difference between a lamp over the books and a panel behind them: the
      // brightest point is off the shelf, in the padding the library leaves above it.
      expect(kReadingLampSourcePadding, greaterThan(0));
    });

    test(
      'Given a book height, Then the wash covers that padding and most of a row',
      () {
        // The height the fixed layer at the top of the library asks for. It has to reach
        // past the padding or a strip of bare `surfaceVariant` shows between the bar and
        // the start of the light — which is what made an earlier draft read as a warm
        // rectangle rather than as a lit room.
        const bookHeight = 127.0;
        final reach = readingLampHeight(bookHeight);
        expect(reach, greaterThan(kReadingLampSourcePadding));
        expect(
          reach,
          closeTo(
            kReadingLampSourcePadding +
                bookRowExtent(bookHeight) * kReadingLampExtent,
            0.001,
          ),
        );
        // And stops short of the plank, so the board's own pool is still a separate thing.
        expect(
          reach,
          lessThan(kReadingLampSourcePadding + bookRowExtent(bookHeight)),
        );
      },
    );

    test('Given the spread, Then the bloom is wider than the row', () {
      // A bloom finishing at the row's edges reads as a vignette. Above 1 the falloff
      // is still climbing when it reaches the clip.
      expect(kReadingLampSpread, greaterThan(1));
    });

    testWidgets('Given a wide row, Then the light comes from the top middle', (
      tester,
    ) async {
      await _pumpLamp(tester, const Size(370, 120));
      expect(_gradientOf(tester).center, Alignment.topCenter);
    });

    testWidgets('Given a wide row, Then the bloom is stretched into an ellipse', (
      tester,
    ) async {
      // A `RadialGradient`'s radius is measured against the box's *shortest* side, so
      // an untransformed circle in a row three times wider than it is tall would reach
      // the plank long before either end of the shelf. This is the transform that fixes
      // that.
      await _pumpLamp(tester, const Size(370, 120));
      final gradient = _gradientOf(tester);

      // Reach is set entirely by the transform, so there is one place the ellipse is
      // decided.
      expect(gradient.radius, 1);

      final m = gradient.transform!.transform(
        const Rect.fromLTWH(0, 0, 370, 120),
      )!;
      // Horizontal: `width * spread`, against the shortest side. Vertical: the height,
      // which *is* the shortest side, so 1.
      expect(m.entry(0, 0), closeTo(370 * kReadingLampSpread / 120, 0.001));
      expect(m.entry(1, 1), closeTo(1, 0.001));
    });

    testWidgets(
      'Given a wide row, Then the stretch leaves the source where it was',
      (tester) async {
        // Scaling about anywhere but the source would move the point the light comes
        // from, which is the whole difference between a lamp and a wash.
        await _pumpLamp(tester, const Size(370, 120));
        const bounds = Rect.fromLTWH(0, 0, 370, 120);
        final m = _gradientOf(tester).transform!.transform(bounds)!;

        final moved = MatrixUtils.transformPoint(
          m,
          Offset(bounds.center.dx, bounds.top),
        );
        expect(moved.dx, closeTo(bounds.center.dx, 0.001));
        expect(moved.dy, closeTo(bounds.top, 0.001));
      },
    );

    testWidgets('Given a row with no size yet, Then nothing divides by zero', (
      tester,
    ) async {
      // Reachable on the first frame of a layout that has not resolved.
      await _pumpLamp(tester, Size.zero);

      expect(tester.takeException(), isNull);
      expect(_gradientOf(tester).transform!.transform(Rect.zero), isNotNull);
    });
  });

  group('the light dims as the Reading shelf scrolls away', () {
    test('Given the shelf at rest, Then the lamp is at full strength', () {
      expect(readingLampIntensity(scrollOffset: 0, fadeDistance: 140), 1);
    });

    test('Given the shelf half gone, Then the light is half out', () {
      // Linear, because the share of the row still inside the light's reach is linear in
      // the offset. An eased ramp would be a flourish over a quantity already known.
      expect(
        readingLampIntensity(scrollOffset: 70, fadeDistance: 140),
        closeTo(0.5, 0.001),
      );
    });

    test('Given the shelf gone, Then the lamp is out and stays out', () {
      expect(readingLampIntensity(scrollOffset: 140, fadeDistance: 140), 0);
      // Clamped, not extrapolated: a long library must not drive this negative.
      expect(readingLampIntensity(scrollOffset: 4000, fadeDistance: 140), 0);
    });

    test(
      'Given a pull-to-refresh overscroll, Then it cannot brighten past full',
      () {
        // `RefreshIndicator` drags the list *down*, so `pixels` goes negative and the shelf
        // moves further under the light rather than out from under it. Full is full.
        expect(readingLampIntensity(scrollOffset: -80, fadeDistance: 140), 1);
      },
    );

    test('Given a library with no size yet, Then nothing divides by zero', () {
      expect(readingLampIntensity(scrollOffset: 12, fadeDistance: 0), 1);
    });

    test('Given the fade, Then it outlasts the light\'s own reach', () {
      // The invariant that keeps the two numbers honest: the lamp must not be out while
      // part of the row is still inside the bloom. Both are the same span, the reach
      // being the shorter by [kReadingLampExtent].
      const bookHeight = 127.0;
      expect(
        readingLampFadeDistance(bookHeight),
        greaterThan(readingLampHeight(bookHeight)),
      );
      expect(
        readingLampFadeDistance(bookHeight),
        closeTo(kReadingLampSourcePadding + bookRowExtent(bookHeight), 0.001),
      );
    });

    testWidgets(
      'Given full strength, Then the tuned colours are what get drawn',
      (tester) async {
        // Identity at 1, so the state the tokens were tuned in is not a recomputation of
        // them.
        await _pumpLamp(tester, const Size(370, 120));
        expect(_gradientOf(tester).colors, kReadingLampBloom);
      },
    );

    testWidgets('Given a dimmed lamp, Then only the alpha moves', (
      tester,
    ) async {
      // Turning a light down is not laying grey over it: the hues stay exactly as tuned,
      // so a dim lamp is the same *colour* of light as a bright one.
      await tester.pumpWidget(
        const Center(
          child: SizedBox(
            width: 370,
            height: 120,
            child: ReadingShelfLamp(intensity: 0.5),
          ),
        ),
      );
      final colors = _gradientOf(tester).colors;

      for (var i = 0; i < colors.length; i++) {
        expect(
          colors[i].toARGB32() & 0x00FFFFFF,
          kReadingLampBloom[i].toARGB32() & 0x00FFFFFF,
          reason: 'stop $i changed hue on the way down',
        );
        expect(colors[i].a, closeTo(kReadingLampBloom[i].a * 0.5, 1 / 255));
      }
      // The stop that was already transparent still is, at every strength.
      expect(colors.last.a, 0);
    });

    testWidgets('Given the library scrolls, Then the light dims without moving', (
      tester,
    ) async {
      // **The whole point of the device, and the one thing no still frame shows.** The
      // lamp is a fixture, so it must not travel with the shelves — and a fixture that
      // kept its full strength would end up lighting a queue shelf.
      await _pumpLayer(tester);
      final restingRect = tester.getRect(find.byType(ReadingShelfLamp));
      expect(_alphaOf(tester), closeTo(kReadingLampBloom.first.a, 1 / 255));

      await tester.drag(find.byType(ListView), const Offset(0, -60));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byType(ReadingShelfLamp)),
        restingRect,
        reason: 'the light moved with the shelves instead of staying put',
      );
      expect(
        _alphaOf(tester),
        closeTo(
          kReadingLampBloom.first.a *
              readingLampIntensity(
                scrollOffset: 60,
                fadeDistance: readingLampFadeDistance(_kTestBookHeight),
              ),
          1 / 255,
        ),
      );
    });

    testWidgets('Given the shelf scrolled away, Then the light is out', (
      tester,
    ) async {
      await _pumpLayer(tester);
      await tester.drag(
        find.byType(ListView),
        Offset(0, -readingLampFadeDistance(_kTestBookHeight) - 40),
      );
      await tester.pumpAndSettle();

      expect(_alphaOf(tester), 0);
    });

    testWidgets('Given a shelf flicked sideways, Then the room does not dim', (
      tester,
    ) async {
      // Every shelf is a horizontal scroll view of its own and its notifications bubble
      // up through this layer too. Without the axis filter, browsing one row would turn
      // the lights down.
      await _pumpLayer(tester, horizontal: true);
      await tester.drag(find.byType(ListView), const Offset(-120, 0));
      await tester.pumpAndSettle();

      expect(_alphaOf(tester), closeTo(kReadingLampBloom.first.a, 1 / 255));
    });

    testWidgets('Given nothing open, Then there is no light to dim', (
      tester,
    ) async {
      // `vanish`: no reading books, no shelf, no lamp. The layer stays so that the offset
      // it tracks survives the shelf coming and going.
      await _pumpLayer(tester, lit: false);
      expect(find.byType(ReadingShelfLamp), findsNothing);
      expect(find.byType(ListView), findsOne);
    });
  });

  group('ReadingLampWash multiplies the cover rather than tinting it', () {
    testWidgets('Given a lit cover, Then a colour matrix is what lights it', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ReadingLampWash(child: SizedBox(width: 10, height: 10)),
      );

      final filter = tester
          .widget<ColorFiltered>(find.byType(ColorFiltered))
          .colorFilter;
      // Not an `Opacity`, not a `ColoredBox`, not a blend mode: those pull every cover
      // toward one colour, which is exactly what `card_lighting.dart` says a blacklight
      // would do and why the card multiplies instead.
      expect(filter.toString(), contains('matrix'));
    });

    test('Given the cover multipliers, Then they are small', () {
      // The covers are the subject; the light is not supposed to be the first thing
      // anyone notices about them.
      expect(kReadingLampCoverBrightness, greaterThan(1));
      expect(kReadingLampCoverBrightness, lessThan(1.15));
      expect(kReadingLampCoverSaturation, greaterThan(1));
      expect(kReadingLampCoverSaturation, lessThan(1.15));
    });

    test('Given a grey, When lit, Then it is brightened and stays grey', () {
      // Saturation is applied about the luminance axis, so a neutral has no chroma to
      // be pushed and only the brightness term can move it. This is the property that
      // fails first if the matrix's rows are ever mis-transcribed.
      final lit = _asTheLampLeavesIt(const Color(0xFF808080));
      expect(lit.r, closeTo(lit.g, 1 / 255));
      expect(lit.g, closeTo(lit.b, 1 / 255));
      expect(lit.r, greaterThan(0x80 / 255));
    });

    test('Given a saturated cover, When lit, Then its hue survives', () {
      const cover = Color(0xFF2E6BD8);
      final lit = _asTheLampLeavesIt(cover);
      // Blue still dominates, and by at least as much as it did: a warm *tint* would
      // have pulled this toward orange, which is the failure the matrix exists to
      // avoid.
      expect(lit.b, greaterThan(lit.r));
      expect(lit.b, greaterThan(lit.g));
      expect(lit.b - lit.r, greaterThanOrEqualTo(cover.b - cover.r));
    });
  });
}

/// [color] as the wash's matrix leaves it.
///
/// The matrix is private to the widget, so this reproduces it from the two published
/// multipliers and the same Rec. 709 weights. The two could in principle drift apart —
/// which is why the widget test above pins that a *matrix* filter is what the wash uses,
/// and why the cases here assert properties (a grey stays grey, a hue survives) rather
/// than exact channel values.
Color _asTheLampLeavesIt(Color c) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  const s = kReadingLampCoverSaturation;
  const b = kReadingLampCoverBrightness;
  final lum = lr * c.r + lg * c.g + lb * c.b;
  // Each channel keeps `s` of itself and takes `1 - s` of the luminance, then the whole
  // thing is scaled by brightness.
  double mix(double own) => (((1 - s) * lum + s * own) * b).clamp(0.0, 1.0);
  return Color.from(alpha: c.a, red: mix(c.r), green: mix(c.g), blue: mix(c.b));
}
