// A render of the band's reading-period card, which is the one object in this feature
// whose defect was "too messy" -- a verdict no assertion can carry.
//
// Four values fitted into the card for one round and wrapped onto two lines. The fix was to
// cut one of each redundant pair (start date vs elapsed days; percent vs page) and leave one
// green value, and the only way to judge that is to look at the states side by side.
//
//     flutter test test/reading_period_row_render_preview.dart
//     open build/period_row_preview
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/reading_period_row.dart';

/// The band's own content width on a 390pt phone, so the card is measured in the box it
/// actually gets rather than in a box that flatters it.
const double _kBandWidth = 333;

Future<ByteData> _font(String path) async =>
    ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);

/// The real sans, in the two cuts this card draws: the badge and the values are w400 and
/// `subtitle` is w600. Without them every glyph is an Ahem square and "messy" is
/// unjudgeable, because the test font is about 40% wider than Pretendard.
Future<void> _loadRealFonts() async {
  await (FontLoader('Pretendard')
        ..addFont(_font('assets/fonts/Pretendard-Regular.otf'))
        ..addFont(_font('assets/fonts/Pretendard-SemiBold.otf')))
      .load();

  // **The icon font, which is the one nobody remembers.** `flutter test` replaces every
  // font with Ahem, icons included, so without this the card's chevron renders as an empty
  // square -- which looks like a missing glyph in the app and is the detail this frame is
  // partly here to judge.
  final icons = _materialIcons();
  if (icons == null) {
    stdout.writeln('no MaterialIcons font found; the chevron will be a square');
    return;
  }
  await (FontLoader('MaterialIcons')..addFont(_font(icons.path))).load();
}

/// The SDK's icon font, found by walking up from whatever binary is running us: under
/// `flutter test` that is `flutter_tester`, three levels under `bin/cache/artifacts`.
File? _materialIcons() {
  var dir = Directory(Platform.resolvedExecutable).parent;
  for (var up = 0; up < 8; up++) {
    final font = File(
      '${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (font.existsSync()) return font;
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  return null;
}

Widget _host(
  ThemeData theme,
  AppColors colors,
  List<Widget> rows,
) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: theme,
  // **A `Material` ancestor, which is what carries the text style.** Without one every
  // `Text` here falls back to `MaterialApp`'s `_errorTextStyle` -- red, with a yellow
  // double underline -- and the first render of this frame came back covered in both.
  // That reads exactly like a defect in the card and is a defect in the harness: colours
  // set explicitly (`brandText`, `secondaryText`) survive it, so only the spans that
  // inherit go red and the frame looks selectively broken. `Material` is where
  // `AnimatedDefaultTextStyle` comes from, so this line is the fix and a `ColoredBox` is
  // not.
  home: RepaintBoundary(
    key: const ValueKey('shot'),
    child: Material(
      color: colors.pageBackground,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in rows) ...[
              SizedBox(width: _kBandWidth, child: row),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(_loadRealFonts);

  testWidgets("render the band's period card in every state", (tester) async {
    tester.view.physicalSize = const Size(390, 520) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final dir = Directory('build/period_row_preview')
      ..createSync(recursive: true);

    final start = DateTime(2026, 9, 13);
    final rows = <Widget>[
      // Reading, with a page count: the state in the screenshot that was called messy.
      ReadingPeriodRow(
        status: bookStatusReading,
        startDate: start,
        progress: 0.71,
        pageCount: 432,
        onTap: () {},
      ),
      // Reading, no count -- about two books in three. The percent stands alone.
      ReadingPeriodRow(
        status: bookStatusReading,
        startDate: start,
        progress: 0.71,
        onTap: () {},
      ),
      // Reading, no position yet: the range is back, because there is no position to
      // replace it with.
      ReadingPeriodRow(
        status: bookStatusReading,
        startDate: start,
        onTap: () {},
      ),
      // Finished: no position worth printing, so the range is the whole record.
      ReadingPeriodRow(
        status: bookStatusFinished,
        startDate: start,
        finishDate: DateTime(2026, 9, 28),
        progress: 1,
        pageCount: 432,
        onTap: () {},
      ),
      // Set aside: the position is the news about this book, so it wins over the range.
      ReadingPeriodRow(
        status: bookStatusSetAside,
        startDate: start,
        finishDate: DateTime(2026, 9, 28),
        progress: 0.46,
        pageCount: 432,
        onTap: () {},
      ),
      // A friend's book: reads, draws no handle.
      ReadingPeriodRow(
        status: bookStatusReading,
        startDate: start,
        progress: 0.71,
        pageCount: 432,
      ),
    ];

    for (final theme in {
      'light': (AppTheme.light, AppColors.light),
      'dark': (AppTheme.dark, AppColors.dark),
    }.entries) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_host(theme.value.$1, theme.value.$2, rows));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('shot')),
      );
      late Uint8List png;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        png = data!.buffer.asUint8List();
      });
      File('${dir.path}/${theme.key}.png').writeAsBytesSync(png);
    }
    stdout.writeln('wrote ${dir.path}/{light,dark}.png');
  });
}
