// The sign-in hero's mascot: that it is there, that it is cropped by the bottom edge,
// and above all that it never reaches the buttons.
//
// **The defect these cases exist for cannot be seen in a default-sized harness.**
// `flutter_test`'s surface is 800x600, which is shorter than any phone the app supports
// and *wider* than all of them -- so the lockup sits higher than it ever does on device
// and a mascot that would overlap `Continue with Google` on an iPhone SE has room to
// spare here. Every case below sets a real phone size, and the SE case is the one that
// fails if `_MascotHero`'s arithmetic regresses. This is the same trap
// `streak_celebration_test.dart` records for the celebration.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/ui/pages/auth_page.dart';

class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState.unauthenticated();
}

/// Matches the mascot specifically. `find.byType(Image)` would also catch
/// `BrandMark`'s chalk book, which is the other raster on this screen.
final _mascot = find.byWidgetPredicate(
  (w) =>
      w is Image &&
      w.image is AssetImage &&
      (w.image as AssetImage).assetName == kAuthMascotAsset,
);

Future<Size> _pump(WidgetTester tester, Size phone) async {
  addTearDown(tester.view.reset);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = phone;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authProvider.overrideWith(_FakeAuthNotifier.new)],
      child: const MaterialApp(
        localizationsDelegates: <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: AuthPage(),
      ),
    ),
  );
  await tester.pump();
  return phone;
}

/// The bottom of the lower sign-in button -- the thing the mascot must stay clear of.
double _buttonsBottom(WidgetTester tester) =>
    tester.getRect(find.byType(ElevatedButton).last).bottom;

void main() {
  // 393x852 is an iPhone 15; 375x667 an SE, the shortest phone supported.
  const tall = Size(393, 852);
  const short = Size(375, 667);

  testWidgets('the mascot is drawn, at its design height on a tall phone', (
    tester,
  ) async {
    await _pump(tester, tall);

    expect(_mascot, findsOneWidget);
    expect(
      tester.widget<Image>(_mascot).height,
      kAuthMascotHeight,
      reason: 'a tall phone has room for the full design size',
    );
  });

  testWidgets('its foot is cropped by the screen edge rather than sitting on it', (
    tester,
  ) async {
    await _pump(tester, tall);

    // The overhang IS the crop -- see `_MascotHero`. Asserted as a quantity rather
    // than as "bottom >= height", because a drawing that merely touches the edge is
    // the sticker-on-the-page reading the crop exists to avoid.
    final rect = tester.getRect(_mascot);
    expect(
      rect.bottom - tall.height,
      closeTo(kAuthMascotHeight * kAuthMascotCrop, 0.5),
      reason:
          'the bottom ${(kAuthMascotCrop * 100).round()}% falls past the edge',
    );
  });

  testWidgets('it shrinks on a short phone rather than keeping its size', (
    tester,
  ) async {
    await _pump(tester, short);

    final height = tester.widget<Image>(_mascot).height!;
    expect(
      height,
      lessThan(kAuthMascotHeight),
      reason: 'an SE leaves ~173pt under the buttons, not the ~230 a 15 does',
    );
    // A floor as well as a ceiling: shrinking to a sliver would pass the overlap case
    // below while drawing something not worth drawing, and `_MascotHero` would rather
    // hide it than do that.
    expect(height, greaterThan(kAuthMascotHeight / 3));
  });

  // The whole point. Both phones, because the tall one is where the constant is used
  // and the short one is where the arithmetic is.
  for (final (name, phone) in const <(String, Size)>[
    ('a tall phone', tall),
    ('a short phone', short),
  ]) {
    testWidgets('the mascot never reaches the buttons on $name', (
      tester,
    ) async {
      await _pump(tester, phone);

      expect(
        tester.getRect(_mascot).top,
        greaterThanOrEqualTo(_buttonsBottom(tester) + kAuthMascotGap - 0.5),
        reason: 'the gap under the last button is $kAuthMascotGap at minimum',
      );
    });
  }

  testWidgets('the mascot is decorative, so it is not announced', (
    tester,
  ) async {
    await _pump(tester, tall);

    // The screen already names the app in text; "a cat reading a book" is not
    // something a screen-reader user needs in order to sign in.
    expect(tester.widget<Image>(_mascot).excludeFromSemantics, isTrue);
  });
}
