// Not a test — a renderer. Writes PNGs of the flame mark to build/flame_mark/ so it can be
// judged by eye, and so it can be compared against the Rive artboard it is generated from
// (`../../.venv/bin/python rive/streak_flame/icon.py --sheet`).
//
// **This exists because the mark's whole claim is a resemblance.** `StreakFlameMark` is
// generated from the same point lists as `assets/rive/streak_flame.riv`, and a test can assert
// that the tables are the length they should be and that the path closes — neither of which
// says whether the thing came out as a flame. Only looking does.
//
// Drawn at every size the app actually uses, because the answer is different at each: 18pt on
// a filled button, 19.5pt in the library bar's chip, 44pt on the streak page's hero, and 76pt
// as the celebration's fallback. A two-tone mark that reads at 76 can be mud at 18.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_flame_mark.dart';

/// The four sizes in `lib/`, and what each one is.
///
/// A list of pairs rather than a `Map<double, String>`, because a `double` has no primitive
/// equality and a const map keyed on one will not compile.
const _sizes = <(double, String)>[
  (18, 'button'),
  (19.5, 'chip'),
  (44, 'hero'),
  (76, 'celebration'),
];

Widget _row(String label, Color color, {Color? core, Color? on}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 10),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      SizedBox(
        width: 96,
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
      for (final entry in _sizes)
        Padding(
          padding: const EdgeInsets.only(right: 18),
          child: ColoredBox(
            color: on ?? Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: StreakFlameMark(
                size: entry.$1,
                color: color,
                coreColor: core,
              ),
            ),
          ),
        ),
    ],
  ),
);

Widget _host(ThemeData theme) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: theme,
  home: Builder(
    builder: (context) {
      final colors = context.colors;
      return Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('shot'),
          child: ColoredBox(
            color: colors.pageBackground,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The page's hero and the chip, hot. **`kCandleFlame`, not `colors.flame`:**
                  // every streak surface moved to the artboard's amber on instruction, so the
                  // theme token this row used to pass is no longer drawn anywhere. Kept as a
                  // separate row from `candle` below because the *core* differs — here it is
                  // derived by lifting lightness, there it is the artboard's own `#FFD479`, and
                  // whether those two read as the same flame is a thing to look at.
                  _row('hot (derived core)', kCandleFlame),
                  // The chip, cold: the mark has to survive being a neutral too.
                  _row('secondary', colors.secondaryText),
                  // The record button: white body on the brand fill, core handed the
                  // fill's own green back so it punches through instead of disappearing
                  // into the white.
                  _row(
                    'white on fill',
                    Colors.white,
                    core: colors.brandFill,
                    on: colors.brandFill,
                  ),
                  // The celebration, and the artboard's own pair — the one place the mark
                  // is drawn beside the drawing it was generated from.
                  _row('candle', kCandleFlame, core: const Color(0xFFFFD479)),
                  // Mid-ignition: the body lerping out of dormant, core derived from it.
                  _row(
                    'igniting (40%)',
                    Color.lerp(
                      kCandleStockTop.withValues(alpha: 0.32),
                      kCandleFlame,
                      0.4,
                    )!,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  ),
);

Future<void> _shoot(WidgetTester tester, String name) async {
  final dir = Directory('build/flame_mark')..createSync(recursive: true);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  late Uint8List png;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    png = data!.buffer.asUint8List();
  });
  File('${dir.path}/$name.png').writeAsBytesSync(png);
}

void main() {
  testWidgets('render the flame mark at every size it is used at', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(560 * 3, 620 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(AppTheme.light));
    await tester.pumpAndSettle();
    await _shoot(tester, '1_light');

    await tester.pumpWidget(_host(AppTheme.dark));
    await tester.pumpAndSettle();
    await _shoot(tester, '2_dark');
  });
}
