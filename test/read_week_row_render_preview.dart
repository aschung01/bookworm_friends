// Not a test — a renderer. Writes PNGs of the week row to build/week_preview/ so the
// row can be judged by eye.
//
//   flutter test test/read_week_row_render_preview.dart
//
// **This exists because the row has now shipped wrong twice, and both times the suite
// was green.** Version one drew a box on all seven days; "there are seven cells, each
// stamped in the caller's colour" was true of it. Version two drew four different
// letter-in-a-box treatments; "a missed day has no box at all" was true of it too. What
// was wrong in both cases was the thing no assertion states: the strip did not read as a
// count. That question is answered by looking.
//
// Both palettes, because they are not variants of one drawing. `ReadWeekPalette.page`
// puts a white check on dark green at 5.6:1 on the app's own paper; `.candle` puts a
// white check on mid amber at 2.00:1 on white, which is a deliberate trade and the one
// value on this row most worth re-checking with an eye rather than a number. And the
// page palette twice, because every fill and every label on it is a light-mode assumption
// until it has been seen on a dark ground.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
// `FontLoader` lives here, not in `flutter_test` — which is not obvious and costs a
// compile error every time someone writes one of these previews from memory.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/streak/read_week_row.dart';

/// A Thursday, so the week runs Fri 11 .. Thu 17 Sept 2026 and the seven rakes differ.
final _endingOn = DateTime(2026, 9, 17);

/// The three week shapes worth looking at, and why each one.
const _weeks = <String, List<bool>>{
  // The payoff. Seven marks in a line either read as a count or they do not.
  'full': [true, true, true, true, true, true, true],
  // The affordance. One dashed ring among six filled tokens has to be obviously the
  // thing you tap, without reading as the odd one out in a bad way.
  'waiting': [true, true, true, true, true, true, false],
  // The honest case, and the one the old row handled worst: a gap mid-run plus an
  // unrecorded today. Three states on one strip.
  'gap': [true, false, true, true, false, true, false],
  // What a brand-new reader sees. It must not look like seven failures.
  'empty': [false, false, false, false, false, false, false],
};

Widget _host(ThemeData theme, {required bool candle}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    locale: const Locale('en'),
    home: Builder(
      builder: (context) => Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('shot'),
          // **The ground goes *inside* the boundary, and this was wrong first.** With the
          // colour on the `Scaffold`, it is painted outside the boundary and the capture
          // comes back transparent — so the dark theme's near-black tokens were being
          // judged against a viewer's white matte, which is the one comparison that makes
          // them look fine. Every value on this row is a value *against a ground*.
          child: ColoredBox(
            // The celebration's ground is white by constant; the page's is the theme's paper.
            color: candle ? Colors.white : context.colors.pageBackground,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in _weeks.entries) ...[
                    ReadWeekRow(
                      days: entry.value,
                      endingOn: _endingOn,
                      palette: candle
                          ? ReadWeekPalette.candle
                          : ReadWeekPalette.page(context),
                      // On for the page, off in the celebration — and the celebration's one
                      // tilted cell comes from `decorateLast`, which this frame does not
                      // model. So both grounds are drawn raked here, because the rake is
                      // the reason a square token was chosen and it is faint enough at 34pt
                      // to be worth checking it is visible at all.
                      tilt: true,
                      // The closing beat, on the full week only: the lift is the whole of
                      // what now separates that token from its neighbours, and whether a
                      // shadow alone does that job is exactly a looking question.
                      freshLast: entry.key == 'full',
                    ),
                    const SizedBox(height: 26),
                  ],
                  // The same seven days as the celebration actually draws them: inside the
                  // week card's hairline, unraked, on white. A hairline card on a white
                  // ground is the other thing here that can only be judged by eye.
                  if (candle)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: kCandleStockTop.withValues(alpha: 0.12),
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ReadWeekRow(
                        days: _weeks['full']!,
                        endingOn: _endingOn,
                        palette: ReadWeekPalette.candle,
                        tilt: false,
                        freshLast: true,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _shoot(WidgetTester tester, Directory dir, String name) async {
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

/// Registers the app's real sans so the weekday labels are type rather than Ahem boxes.
///
/// One cut, at `caption`'s w700: `FontLoader` carries no weight information, so handing
/// it several Pretendard statics would let the engine answer any weight with whichever
/// arrived first. The label is the only type on this row.
Future<void> _loadRealFonts() async {
  final bytes = File('assets/fonts/Pretendard-Bold.otf').readAsBytesSync();
  final loader = FontLoader('Pretendard')
    ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
}

void main() {
  setUpAll(_loadRealFonts);

  testWidgets('render the week row on both grounds', (tester) async {
    // 393 is the narrowest phone the app supports; the row is drawn at the page's real
    // content width, because a token's size relative to its share of the row is the
    // proportion the whole option turns on.
    tester.view.physicalSize = const Size(393 * 3, 560 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final dir = Directory('build/week_preview')..createSync(recursive: true);

    await tester.pumpWidget(_host(AppTheme.light, candle: false));
    await tester.pumpAndSettle();
    await _shoot(tester, dir, '1_page_light');

    await tester.pumpWidget(_host(AppTheme.dark, candle: false));
    await tester.pumpAndSettle();
    await _shoot(tester, dir, '2_page_dark');

    await tester.pumpWidget(_host(AppTheme.light, candle: true));
    await tester.pumpAndSettle();
    await _shoot(tester, dir, '3_candle_white');

    // ignore: avoid_print
    print('wrote ${dir.absolute.path}');
  });
}
