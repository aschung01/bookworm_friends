// Not a test — a renderer. Writes PNGs of the sign-in screen to build/signin_preview/
// so the Apple button can be judged by eye.
//
// **This exists because the defect it is checking for passed a green suite.** The
// previous button drew Apple's logo-only *button* artwork — a white plate with a black
// apple — inside a black button at a third of the right size, and nothing in 1710 tests
// noticed, because every assertion was about behaviour and the asset path was just a
// string. `sign_in_button_test.dart` now pins the proportions, but a ratio being right
// still does not say whether the button looks like Apple's. Only looking does.
//
// The settings strip is here for the same reason one level down: that call site drew the
// white-plated file at 18pt, which was invisible against the light theme's white surface
// and a bright square against the dark theme's #1E1E1E. A single-theme render would have
// blessed it.
//
// **`BrandMark` comes out as a bare green plate here, and that is this file's limitation
// rather than a defect.** It composites `assets/branding/app_icon_mark.png`, and an
// `Image.asset` needs more than the async window below to resolve; on device the chalk
// book is there. Don't "fix" the mark because of this render.

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

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/ui/pages/auth_page.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';

class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState.unauthenticated();
}

const _delegates = <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

Widget _signInHost(ThemeData theme) => ProviderScope(
  overrides: [authProvider.overrideWith(_FakeAuthNotifier.new)],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    localizationsDelegates: _delegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: const RepaintBoundary(key: ValueKey('shot'), child: AuthPage()),
  ),
);

/// The Settings provider row, and the old glyph size beside the new one.
///
/// 6.8pt is what the previous asset actually put on screen in a 48pt button, drawn here
/// so the three-times error is visible rather than described.
Widget _stripHost(ThemeData theme) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: theme,
  localizationsDelegates: _delegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) {
      final colors = context.colors;
      return Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('shot'),
          child: ColoredBox(
            color: colors.pageBackground,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The Settings row: glyph tinted to the ink beside it, on `surface`.
                  ColoredBox(
                    color: colors.surface,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppleLogo(height: 18, color: colors.primaryText),
                          const SizedBox(width: 10),
                          Text(
                            'reader@example.com',
                            style: AppTextStyles.label.copyWith(
                              color: colors.primaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Old against new, each glyph in the button height it shipped with,
                  // so the comparison is honest: the old one was 6.8pt in a 48pt
                  // button, the new one 19pt in Apple's recommended 44.
                  for (final entry in const <(double, double, String)>[
                    (48, 6.8, 'was 6.8pt in 48 (14%)'),
                    (44, 19, 'now 19pt in 44 (43%)'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 200,
                            height: entry.$1,
                            color: Colors.black,
                            alignment: Alignment.center,
                            child: AppleLogo(
                              height: entry.$2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            entry.$3,
                            style: AppTextStyles.label.copyWith(
                              color: colors.primaryText,
                            ),
                          ),
                        ],
                      ),
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

/// Pumps inside [WidgetTester.runAsync] on purpose.
///
/// `SvgPicture` resolves its bytes through the asset bundle, and an `SvgPicture` that has
/// not loaded paints *nothing* — so a fake-async pump renders a screen with no logos on
/// it, which looks exactly like the bug being checked for.
Future<void> _pump(WidgetTester tester, Widget host) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(host);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  });
}

Future<void> _shoot(WidgetTester tester, String name) async {
  final dir = Directory('build/signin_preview')..createSync(recursive: true);
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

/// Registers the app's real faces, so the title is type rather than Ahem boxes.
///
/// **Without this the preview is useless for the thing it was written for.** The whole
/// point of raising the title to 43% of the button height is a proportion between the
/// title and the logo beside it, and Ahem draws every glyph as a filled rectangle — so
/// the first render of this file showed two black bars where the labels should be and
/// said nothing about whether the button looks like Apple's.
///
/// One cut per family, deliberately: `FontLoader` carries no weight information, so
/// handing it several Pretendard statics lets the engine answer any weight with whichever
/// arrived first. **Which is why the Pretendard cut here is Regular and not SemiBold** —
/// `AppTextStyles.signIn` is w400, and loading SemiBold would render the button title in
/// the heavier weight the token no longer asks for, i.e. this file would keep showing the
/// version that was rejected. GowunBatang is the `hero` wordmark above the buttons.
///
/// The cost is that the strip's own captions, which ship as `label`'s w600, also draw at
/// 400 here. They are annotation, not subject.
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

void main() {
  setUpAll(_loadRealFonts);

  testWidgets('render the sign-in screen and the provider glyph', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393 * 2, 852 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await _pump(tester, _signInHost(AppTheme.light));
    await _shoot(tester, '1_signin_light');

    await _pump(tester, _signInHost(AppTheme.dark));
    await _shoot(tester, '2_signin_dark');

    // 520, not 420: the widest row is the 200pt swatch plus a 13pt label, and at 420
    // the strip overflowed by 26px. An overflow here paints yellow-and-black stripes
    // into the PNG, which is a preview that misrepresents itself.
    tester.view.physicalSize = const Size(520 * 2, 340 * 2);
    await _pump(tester, _stripHost(AppTheme.light));
    await _shoot(tester, '3_strip_light');

    await _pump(tester, _stripHost(AppTheme.dark));
    await _shoot(tester, '4_strip_dark');
  });
}
