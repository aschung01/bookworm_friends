// Not a test — a renderer. Writes a PNG of the invite sheet's payoff mark to
// build/invite_preview/ so it can be judged by eye.
//
//   flutter test test/invite_mark_render_preview.dart
//
// The mark is the one thing on that sheet no assertion can check. It either sells
// the payoff or it looks like three grey rectangles, and the first version was the
// second — which nothing in the suite noticed, because "there are three shelves" was
// true of both. So this exists for the same reason `library_sheet_render_preview`
// does: some questions are answered by looking.
//
// Rendered in both themes, because the plank, the chip and the books all carry
// shadows and a wash, and every one of those is a light-mode assumption until it has
// been seen on a dark ground.
//
// **Book titles come out as boxes here.** `flutter test` ships the Ahem test font,
// so the Korean in the mark cannot render — what this frame is for is the geometry
// and the colour, not the type.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/invite/invite_sheet.dart';

Widget _frame(ThemeData theme) => ProviderScope(
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        // The sheet's own ground, not the page's: the mark's wash is tuned against
        // what it actually sits on.
        backgroundColor: context.colors.sheetBackground,
        body: const RepaintBoundary(
          key: ValueKey('shot'),
          child: InviteSheet(),
        ),
      ),
    ),
  ),
);

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

void main() {
  testWidgets('render the invite sheet in both themes', (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final dir = Directory('build/invite_preview')..createSync(recursive: true);

    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ]) {
      await tester.pumpWidget(_frame(theme));
      // `pump` is enough: the sheet no longer touches the network on open -- the link
      // is minted when the button is pressed -- so there is nothing in flight to settle.
      // The mark never depended on it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await _shoot(tester, dir, name);
    }
  });
}
