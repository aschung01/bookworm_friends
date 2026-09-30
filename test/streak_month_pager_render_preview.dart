// Not a test — a renderer. Writes PNGs of the streak page's month card to
// build/month_pager_preview/ so the pager can be judged by eye.
//
//   flutter test test/streak_month_pager_render_preview.dart
//
// **Two things here can only be answered by looking, and one of them has a shipped
// precedent for going wrong silently.** The pager's disabled half is a disc and a chevron at
// 4% and 35% of `secondaryText`; whether that reads as "not available" rather than as "failed
// to load" is a contrast judgement on two grounds, and the dark theme's `secondaryText` is a
// different colour from the light one's. And a *past* month draws a hollow dot on every
// unrecorded day — up to thirty of them where the current month only ever shows a handful —
// so the one thing the grid exists to say, where the thread broke, has to survive being
// surrounded by its own gap marks. `read_week_row_render_preview.dart` records the row that
// shipped wrong twice with a green suite for exactly this sort of reason.
//
// The whole page rather than the card alone, because `_MonthCard` is private and because the
// card's ground, its heading and the flame above it are the context the pager is judged in.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
// `FontLoader` lives here, not in `flutter_test`.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/reading_days_provider.dart';
import 'package:bookworm_friends/ui/pages/reading_streak_page.dart';

import 'still_streak_flame.dart';
import 'support/home_page_harness.dart';

/// The log, keyed off the real clock because the page is.
///
/// The pager's bounds are derived from the oldest row, so a fixed date would draw a pager in
/// whatever state that date happens to produce rather than the one a reader sees today.
final _today = DateTime.now();
final _lastMonth = DateTime(_today.year, _today.month - 1);

/// Two months of records: a short run in this one, a patchy month behind it.
///
/// The patchy month is the point — it is what fills a grid with hollow dots, which is the
/// state the current month can hardly ever reach.
final _log = <DateTime, String?>{
  for (var back = 0; back < 3; back++)
    DateTime(_today.year, _today.month, _today.day - back): back.isEven
        ? 'open-a'
        : 'open-b',
  for (final day in const [2, 3, 4, 9, 10, 17, 18, 19, 20, 26])
    DateTime(_lastMonth.year, _lastMonth.month, day): day > 12
        ? 'open-b'
        : 'shelved',
};

/// Today only: the state in which both steps are unavailable at once.
final _oneDay = <DateTime, String?>{
  DateTime(_today.year, _today.month, _today.day): 'open-a',
};

class _FakeReadingDays extends ReadingDaysNotifier {
  _FakeReadingDays(this.initial);

  final Map<DateTime, String?> initial;

  @override
  Future<Map<DateTime, String?>> build() async => initial;
}

final _shelves = [
  testShelf('reading', [
    testBook('open-a', 'reading', title: 'The Dispossessed', status: 1),
    testBook('open-b', 'reading', title: 'Piranesi', status: 1, position: 1),
  ]),
  testShelf('other', [testBook('shelved', 'other', title: 'Middlemarch')]),
];

Widget _host(ThemeData theme, Map<DateTime, String?> log, String label) {
  return ProviderScope(
    // **Keyed, and this shot sequence was wrong without it.** Successive `pumpWidget` calls
    // build a structurally identical tree, so Riverpod updated the scope in place and the
    // month card kept the `_monthsBack` it had been stepped to — which made the "nowhere to go"
    // shot come back showing last month with a different log's stamps still on it. A distinct
    // key forces a fresh subtree, which is a fresh scope and a fresh card.
    key: ValueKey(label),
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      readingDaysProvider.overrideWith(() => _FakeReadingDays(log)),
      libraryProvider.overrideWith(() => FakeLibraryNotifier(_shelves)),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // The boundary is above the page rather than inside it, so the `Scaffold`'s own
      // `pageBackground` is inside the capture. A card's hairline and a 4% disc against a
      // transparent matte is the one comparison that makes both look fine.
      home: const RepaintBoundary(
        key: ValueKey('shot'),
        child: ReadingStreakPage(),
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

/// Registers the app's real sans, so the heading and the numerals are type rather than Ahem
/// boxes. One cut, because `FontLoader` carries no weight information.
///
/// **And `MaterialIcons`, which a widget test does not get for free.** Both chevrons are
/// `IconData`, so without this the pager renders as two Ahem boxes on two discs — which looks
/// exactly like a control that failed to load, and is the one thing these shots exist to rule
/// out. Skipped rather than fatal if the artifact is not where it is expected: a missing icon
/// font degrades this preview, it does not invalidate it.
Future<void> _loadRealFonts() async {
  final bytes = File('assets/fonts/Pretendard-Bold.otf').readAsBytesSync();
  final loader = FontLoader('Pretendard')
    ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();

  // `$FLUTTER_ROOT` is not exported to a test, and `Platform.resolvedExecutable` is the
  // engine's `flutter_tester` rather than `dart` — so the cache is found by walking up from
  // whichever of the two is running until `artifacts/material_fonts` appears beside a parent.
  var dir = File(Platform.resolvedExecutable).parent;
  File? icons;
  for (var up = 0; up < 8; up++) {
    final candidate = File(
      '${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (candidate.existsSync()) {
      icons = candidate;
      break;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  if (icons == null) {
    // ignore: avoid_print
    print('MaterialIcons not found; the two chevrons will render as boxes');
    return;
  }
  final iconLoader = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.view(Uint8List.fromList(icons.readAsBytesSync()).buffer),
      ),
    );
  await iconLoader.load();
}

void main() {
  setUpAll(_loadRealFonts);
  // The page's flame loops forever once the artboard resolves, so `pumpAndSettle` would never
  // return on a machine that has run `dart run rive_native:setup`. Called directly in `main`
  // because it registers a `setUp` of its own, which cannot be done from inside one.
  useStillStreakFlame();

  testWidgets('render the month pager at both ends and on both grounds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final dir = Directory('build/month_pager_preview')
      ..createSync(recursive: true);

    // 1. This month: back is available, forward is not.
    await tester.pumpWidget(_host(AppTheme.light, _log, '1'));
    await tester.pumpAndSettle();
    await _shoot(tester, dir, '1_this_month_light');

    // 2. Last month: the far end of the log, and a grid full of gap dots.
    await tester.tap(find.byKey(kStreakMonthPreviousKey));
    await tester.pumpAndSettle();
    await _shoot(tester, dir, '2_last_month_light');

    await tester.pumpWidget(_host(AppTheme.dark, _log, '3'));
    await tester.pumpAndSettle();
    await _shoot(tester, dir, '3_this_month_dark');

    await tester.tap(find.byKey(kStreakMonthPreviousKey));
    await tester.pumpAndSettle();
    await _shoot(tester, dir, '4_last_month_dark');

    // 3. One recorded day: neither step is available, which is what a new reader sees and the
    // state in which a dimmed control most easily reads as a broken one.
    await tester.pumpWidget(_host(AppTheme.light, _oneDay, '5'));
    await tester.pumpAndSettle();
    await _shoot(tester, dir, '5_nowhere_to_go_light');

    // ignore: avoid_print
    print('wrote ${dir.absolute.path}');
  });
}
