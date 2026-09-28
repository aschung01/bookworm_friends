// Apple publish proportions for a Sign in with Apple button, and state that "App
// Review evaluates all custom Sign in with Apple buttons". This one is custom, it is
// the first thing on the first screen, and per `docs/store/listing-1.1.0.md` the
// review notes tell the reviewer it is their only way into the app. So the
// proportions are pinned rather than eyeballed.
//
// The version this replaced got three things wrong at once, and none of them were
// visible as a test failure:
//
//   * it drew `appleBlackIcon.svg`, which was Apple's *logo-only button* artwork --
//     an opaque white 44x44 plate with a black apple on it -- inside a black button,
//     so what read as the logo was the plate;
//   * it asked for `height: 20` on a 56-unit canvas holding a 19-unit glyph, putting
//     the Apple logo at 6.8pt in a 48pt button: 14%, against Apple's 43.2%;
//   * it let the title inherit Material's 14pt, which is 29% of the button where
//     Apple specify 43%.
//
// Two of the three are ratios, so they are asserted as ratios — a future change to
// `kSignInButtonHeight` alone should not fail this file. The absolute sizes are checked
// once each as well, because the ratios came out of Apple's artwork and a ratio that is
// right of the wrong base is still the wrong button.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/ui/pages/auth_page.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';

/// Replaced wholesale: the real `build()` reaches for `Supabase.instance`, which no
/// widget test initialises.
class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState.unauthenticated();
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authProvider.overrideWith(_FakeAuthNotifier.new)],
      child: MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AuthPage(),
      ),
    ),
  );
  // One frame, not `pumpAndSettle`: the page posts a frame callback that checks the
  // auth state, and settling would also wait on the SVG loads, which nothing here
  // needs resolved.
  await tester.pump();
}

/// The button's own box, which is what both ratios are fractions of.
///
/// The first `SizedBox` ancestor with a height, rather than the nearest ancestor:
/// `ElevatedButton.icon` nests unconstrained ones of its own between the label and
/// the box `_SignInButton` sets.
double _buttonHeight(WidgetTester tester, String label) {
  final boxes = tester.widgetList<SizedBox>(
    find.ancestor(of: find.text(label), matching: find.byType(SizedBox)),
  );
  return boxes.firstWhere((box) => box.height != null).height!;
}

void main() {
  group('the Apple logo is the size Apple specify', () {
    testWidgets(
      'Given Apple size the logo off the button, When the sign-in page is built, '
      'Then the glyph is 43.2% of the button height',
      (tester) async {
        await _pump(tester);

        final logo = tester.widget<AppleLogo>(find.byType(AppleLogo));
        final height = _buttonHeight(tester, 'Continue with Apple');

        expect(height, kSignInButtonHeight);
        expect(logo.height / height, closeTo(kSignInContentRatio, 0.001));
        // The absolute figure too, so the regression this replaced stays legible:
        // the old button drew the glyph at 6.8pt. 19 is not arbitrary -- it is
        // Apple's artwork measured in its own units, which a 44pt button maps 1:1.
        expect(logo.height, closeTo(19, 0.01));
      },
    );

    testWidgets(
      'Given the title size lives in a token and the ratio in a constant, When '
      'both are read, Then they still agree',
      (tester) async {
        // The one seam this fix introduced. `text_style_test.dart` forbids a
        // `fontSize` at a call site, so 19pt lives in `AppTextStyles.signIn` while
        // the 19/44 justifying it lives in `auth_page.dart` -- two files that can be
        // edited independently. This is what stops them drifting.
        expect(
          AppTextStyles.signIn.fontSize,
          kSignInButtonHeight * kSignInContentRatio,
        );
      },
    );

    testWidgets(
      'Given a tint floods everything opaque in an asset, When the logo asset is '
      'read, Then it holds one path and no plate',
      (tester) async {
        final svg = File('assets/icons/appleLogo.svg').readAsStringSync();

        // The plate is the whole reason the old files could not be tinted and read
        // as a pale square on a black button. `<rect>` returning is the regression.
        expect(svg.contains('<rect'), isFalse);
        expect('<path'.allMatches(svg).length, 1);
        // Cropped tight to the glyph -- the caller sizes the glyph, so padding here
        // would silently shrink it again.
        expect(svg.contains('viewBox="20.5 16 15 19"'), isTrue);
      },
    );
  });

  group('the title is the size Apple specify', () {
    testWidgets(
      'Given Apple tie the title to the button height, When the sign-in page is '
      'built, Then the rendered title is 43% of it',
      (tester) async {
        await _pump(tester);

        for (final label in ['Continue with Apple', 'Continue with Google']) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(label),
          );
          final size = paragraph.text.style!.fontSize!;
          expect(
            size / _buttonHeight(tester, label),
            closeTo(kSignInContentRatio, 0.001),
            reason: '$label should be 43% of the button height',
          );
        }
      },
    );

    testWidgets(
      'Given Apple allow only three titles, When the page is built, Then the '
      'button uses one of them verbatim',
      (tester) async {
        await _pump(tester);

        // "Titles. Use only Sign in with Apple, Sign up with Apple, or Continue
        // with Apple." Pinned because it is a localised string and a well-meaning
        // rewrite of the ARB would break a guideline rather than a layout.
        expect(find.text('Continue with Apple'), findsOneWidget);
      },
    );
  });

  testWidgets(
    'Given Apple require the logo and title to match, When the page is built, '
    'Then both are white on the black button',
    (tester) async {
      await _pump(tester);

      final logo = tester.widget<AppleLogo>(find.byType(AppleLogo));
      final button = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Continue with Apple'),
          matching: find.byType(ElevatedButton),
        ),
      );

      // "Within a button, both items must be either black or white; don't use
      // custom colors."
      expect(logo.color, Colors.white);
      expect(button.style!.foregroundColor!.resolve({}), Colors.white);
      expect(button.style!.backgroundColor!.resolve({}), Colors.black);
    },
  );
}
