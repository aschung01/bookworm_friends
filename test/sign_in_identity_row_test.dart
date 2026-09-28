import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/models/sign_in_provider.dart';
import 'package:bookworm_friends/ui/widgets/sign_in_identity_row.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shape GoTrue actually returns for the account this was written against: opened
/// on Google in 2022, Apple linked in 2026 when Sign in with Apple matched its verified
/// email. Note `provider` stayed `"google"` -- that is the whole defect.
const _googleThenApple = <String, dynamic>{
  'provider': 'google',
  'providers': ['google', 'apple'],
};

Widget _host(Map<String, dynamic>? appMetadata, {ThemeData? theme}) =>
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(
        body: SignInIdentityRow(
          appMetadata: appMetadata,
          email: 'aschung1005@gmail.com',
        ),
      ),
    );

void main() {
  group('linkedSignInProviders', () {
    test('reads the list, not the singular field', () {
      expect(linkedSignInProviders(_googleThenApple), ['google', 'apple']);
    });

    test('keeps the order the doors were added in', () {
      expect(
        linkedSignInProviders(const {
          'provider': 'apple',
          'providers': ['apple', 'google'],
        }),
        ['apple', 'google'],
      );
    });

    test('falls back to the singular field when there is no list', () {
      expect(linkedSignInProviders(const {'provider': 'google'}), ['google']);
    });

    test('falls back when the list is present but empty', () {
      expect(
        linkedSignInProviders(const {
          'provider': 'apple',
          'providers': <dynamic>[],
        }),
        ['apple'],
      );
    });

    test('drops non-string and empty entries', () {
      expect(
        linkedSignInProviders(const {
          'providers': ['google', 7, '', null, 'apple'],
        }),
        ['google', 'apple'],
      );
    });

    test('is empty for no metadata and for metadata naming nothing', () {
      expect(linkedSignInProviders(null), isEmpty);
      expect(linkedSignInProviders(const {}), isEmpty);
      expect(linkedSignInProviders(const {'provider': ''}), isEmpty);
    });
  });

  group('SignInIdentityRow', () {
    testWidgets('a linked account wears both marks', (tester) async {
      await tester.pumpWidget(_host(_googleThenApple));

      expect(find.byType(GoogleIcon), findsOneWidget);
      expect(find.byType(AppleLogo), findsOneWidget);
      expect(find.text('aschung1005@gmail.com'), findsOneWidget);
    });

    testWidgets('the marks are in the order the doors were added', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_googleThenApple));

      // Both marks sit in one `Row`, so "Google first" is a claim about x position and
      // nothing else. Asserting on child index would pass on a row that laid out
      // right-to-left.
      expect(
        tester.getTopLeft(find.byType(GoogleIcon)).dx,
        lessThan(tester.getTopLeft(find.byType(AppleLogo)).dx),
      );
    });

    testWidgets('one door draws one mark', (tester) async {
      await tester.pumpWidget(
        _host(const {
          'provider': 'apple',
          'providers': ['apple'],
        }),
      );

      expect(find.byType(AppleLogo), findsOneWidget);
      expect(find.byType(GoogleIcon), findsNothing);
    });

    testWidgets('an unrecognised provider draws no mark at all', (
      tester,
    ) async {
      // The old `provider == 'apple' ? Apple : Google` labelled this account Google.
      // There is one `email` identity in the live database, so it is reachable.
      await tester.pumpWidget(
        _host(const {
          'provider': 'email',
          'providers': ['email'],
        }),
      );

      expect(find.byType(AppleLogo), findsNothing);
      expect(find.byType(GoogleIcon), findsNothing);
      expect(find.text('aschung1005@gmail.com'), findsOneWidget);
    });

    testWidgets('no session draws the row without marks', (tester) async {
      await tester.pumpWidget(_host(null));

      expect(find.byType(AppleLogo), findsNothing);
      expect(find.byType(GoogleIcon), findsNothing);
    });

    testWidgets('the apple mark is tinted to the body ink of its theme', (
      tester,
    ) async {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        await tester.pumpWidget(_host(_googleThenApple, theme: theme));

        final context = tester.element(find.byType(SignInIdentityRow));
        expect(
          tester.widget<AppleLogo>(find.byType(AppleLogo)).color,
          context.colors.primaryText,
          reason: 'a fixed black glyph is invisible on the dark surface',
        );
      }
    });
  });
}
