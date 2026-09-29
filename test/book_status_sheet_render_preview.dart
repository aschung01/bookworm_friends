// A render of the merged status-and-progress sheet, which is the screen every reader
// report about this feature has been about.
//
// Four of them, and not one was reachable by an assertion: the thumb was the app's
// bookmark ribbon and looked like a notched shape hung off a bar; the secondary action was
// left-aligned; the heading was the book's title; and the band's card below was "too
// messy". A green suite said nothing about any of them.
//
//     flutter test test/book_status_sheet_render_preview.dart
//     open build/status_sheet_preview
//
// **The slider here is `CupertinoSlider`, not `CNSlider`.** `useNativeGlass` is false under
// `flutter test` — it reports Android — so this frame shows the fallback branch, which is
// what Android and every test see. The native glass track can only be judged on an iOS 26
// device or simulator. What this frame *can* settle is everything else: the thumb's shape,
// the heading, the read-out, where `Stop reading this` sits, and whether the whole sheet
// fits the shortest phone in both themes and both locales.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/library_provider.dart'
    show bookStatusFinished, bookStatusReading, bookStatusSetAside;
import 'package:bookworm_friends/ui/widgets/bottom_sheets/book_status_bottom_sheet.dart';

/// The shortest phone the app supports. The sheet's tallest state measures 287 of this, so
/// a frame that fits here fits everywhere.
const Size _kSurface = Size(375, 667);

const int _kPageCount = 432;

/// The whole app, so the boundary sits **above the `Navigator`** and therefore captures a
/// modal route. A boundary placed inside `home:` renders the page the sheet covers.
const _shot = ValueKey('shot');

Future<void> _loadAppFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifest =
      json.decode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(family['family'] as String);
    for (final font in (family['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

Future<void> _shoot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_shot),
  );
  late Uint8List png;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    png = data!.buffer.asUint8List();
  });
  File('build/status_sheet_preview/$name.png').writeAsBytesSync(png);
}

Future<void> _open(
  WidgetTester tester, {
  required ThemeData theme,
  required Locale locale,
  int currentStatus = 0,
  DateTime? startDate,
  DateTime? finishDate,
  double? progress,
  int? pageCount,
}) async {
  tester.view.physicalSize = _kSurface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme,
      builder: (context, child) => RepaintBoundary(key: _shot, child: child),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showBookStatusBottomSheet(
                context,
                currentStatus: currentStatus,
                startDate: startDate,
                finishDate: finishDate,
                progress: progress,
                pageCount: pageCount,
                onSave: (_) {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(_loadAppFonts);

  setUpAll(() {
    Directory('build/status_sheet_preview').createSync(recursive: true);
  });

  final start = DateTime(2026, 9, 13);

  // The Reading state is the richest one — track off the origin, a two-part read-out, the
  // dates, and the only state that offers `Stop reading this` — so it is the one drawn in
  // every theme and locale.
  for (final theme in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    for (final locale in {'en': 'en', 'ko': 'ko'}.entries) {
      testWidgets('Reading, ${theme.key}, ${locale.key}', (tester) async {
        await _open(
          tester,
          theme: theme.value,
          locale: Locale(locale.value),
          currentStatus: bookStatusReading,
          startDate: start,
          progress: 0.71,
          pageCount: _kPageCount,
        );
        await _shoot(tester, 'reading_${theme.key}_${locale.key}');
      });
    }
  }

  // The other three states, in one theme: what changes between them is the words, the
  // dates and whether the secondary action is offered, none of which is theme-dependent.
  testWidgets('Not started, light, en', (tester) async {
    await _open(tester, theme: AppTheme.light, locale: const Locale('en'));
    await _shoot(tester, 'notstarted_light_en');
  });

  testWidgets('Finished, light, en', (tester) async {
    await _open(
      tester,
      theme: AppTheme.light,
      locale: const Locale('en'),
      currentStatus: bookStatusFinished,
      startDate: start,
      finishDate: DateTime(2026, 9, 28),
      progress: 1,
      pageCount: _kPageCount,
    );
    await _shoot(tester, 'finished_light_en');
  });

  testWidgets('Set aside, light, en', (tester) async {
    await _open(
      tester,
      theme: AppTheme.light,
      locale: const Locale('en'),
      currentStatus: bookStatusSetAside,
      startDate: start,
      finishDate: DateTime(2026, 9, 28),
      progress: 0.46,
      pageCount: _kPageCount,
    );
    await _shoot(tester, 'setaside_light_en');
  });

  tearDownAll(() {
    stdout.writeln('wrote build/status_sheet_preview/*.png');
  });
}
