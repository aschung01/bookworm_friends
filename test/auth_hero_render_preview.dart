// Not a test — a renderer. Writes PNGs of the sign-in screen to build/auth_preview/ so
// the mascot hero can be judged by eye.
//
//   flutter test test/auth_hero_render_preview.dart
//
// **Separate from `sign_in_button_render_preview.dart` for one reason: that file cannot
// draw a raster.** Its own note says so — "`BrandMark` comes out as a bare green plate
// here ... an `Image.asset` needs more than the async window below to resolve" — and the
// mascot is an `Image.asset` too, so the preview that already pumps this screen is
// structurally unable to show the thing this change adds. `precacheImage` inside
// `runAsync` is the missing piece; with it, both the cat AND the chalk book appear.
//
// Two phone heights, because the hero's size is *computed* rather than fixed and the
// small one is the case that can break. `_MascotHero` solves the cat's height from the
// room left under the lockup: an iPhone 15 leaves ~230pt and takes the full 265, an
// iPhone SE leaves ~173 and must shrink to ~188. If that arithmetic is wrong the failure
// is a cat overlapping `Continue with Google`, which no assertion in this repo states and
// only looking will catch.
//
// Both themes, because the cut-out is a fixed neutral grey on a ground that inverts. The
// grey was chosen against the widget's dark tiles (`CHARACTER.md`, "The fur is a neutral
// grey"), and dark mode's `pageBackground` is #121212 — so light mode is the trade being
// checked here and dark mode is the easy one.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
// `FontLoader` lives here, not in `flutter_test`.
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/ui/pages/auth_page.dart';
import 'package:bookworm_friends/ui/widgets/brand_mark.dart';

/// Unauthenticated, so `AuthPage` stays put instead of pushing the home route.
class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState.unauthenticated();
}

Widget _host(ThemeData theme) => ProviderScope(
  overrides: [authProvider.overrideWith(_FakeAuthNotifier.new)],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    localizationsDelegates: const <LocalizationsDelegate<Object>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: const RepaintBoundary(key: ValueKey('shot'), child: AuthPage()),
  ),
);

/// Pumps, then waits for both rasters before the shot.
///
/// `precacheImage` is the whole point: an unresolved `Image.asset` paints *nothing*, and
/// a screen with no cat on it looks exactly like a change that did not work.
Future<void> _pump(WidgetTester tester, Widget host) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(host);
    final context = tester.element(find.byType(AuthPage));
    await precacheImage(const AssetImage(kAuthMascotAsset), context);
    await precacheImage(const AssetImage(kBrandMarkAsset), context);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  });
}

Future<void> _shoot(WidgetTester tester, String name) async {
  final dir = Directory('build/auth_preview')..createSync(recursive: true);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  late Uint8List png;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    png = data!.buffer.asUint8List();
  });
  File('${dir.path}/$name.png').writeAsBytesSync(png);
}

/// One cut per family: `FontLoader` carries no weight information, so several statics of
/// one family let the engine answer any weight with whichever arrived first. GowunBatang
/// is the `hero` wordmark; Pretendard Regular is `signIn`, which is w400.
Future<void> _loadRealFonts() async {
  const faces = <String, String>{
    'Pretendard': 'assets/fonts/Pretendard-Regular.otf',
    'GowunBatang': 'assets/fonts/GowunBatang-Bold.ttf',
  };
  for (final entry in faces.entries) {
    final bytes = File(entry.value).readAsBytesSync();
    final loader = FontLoader(entry.key)
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();
  }
}

/// One case per `testWidgets`, and that is not tidiness.
///
/// Rendering all four from a single case drew the wordmark in the right weight on the
/// FIRST shot and a lighter one on the other three -- `Libstack` came out grey rather
/// than `primaryText`. Repeated `pumpWidget` calls against one tester reuse a warm font
/// cache, and the preview's whole job is to be trusted about what the screen looks like.
/// A fresh case per shot costs a second and removes the question.
void main() {
  setUpAll(_loadRealFonts);

  const cases = <(String, String, Size)>[
    // iPhone 15: the design case, where the cat gets its full 265pt.
    ('1_iphone15_light', 'light', Size(393, 852)),
    ('2_iphone15_dark', 'dark', Size(393, 852)),
    // iPhone SE: the binding case. ~173pt of room, so the cat must shrink to ~188.
    ('3_iphoneSE_light', 'light', Size(375, 667)),
    ('4_iphoneSE_dark', 'dark', Size(375, 667)),
  ];

  for (final (name, brightness, size) in cases) {
    testWidgets('render $name', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = Size(size.width * 2, size.height * 2);

      await _pump(
        tester,
        _host(brightness == 'dark' ? AppTheme.dark : AppTheme.light),
      );
      await _shoot(tester, name);
    });
  }
}
