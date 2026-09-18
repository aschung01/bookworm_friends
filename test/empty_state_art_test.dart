import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/empty_state_art.dart';

/// The empty-state art is one alpha stencil per piece, tinted at runtime.
///
/// That is a deliberate choice with a history: the light and dark sets were
/// originally generated separately and **drifted into different drawings** — the
/// no-match state was a dashed slot on one theme and a solid book on the other.
/// Baking chalk coverage into alpha made a single file serve both, which removes
/// the drift by construction. These tests guard the properties that keep it
/// removed, because the failure mode is silent: two assets that disagree still
/// render fine, they are just no longer the same illustration.
void main() {
  group('the assets on disk', () {
    test(
      'Given each artwork, When its path is resolved, Then the 1x file and both '
      'density variants exist',
      () {
        for (final art in EmptyStateArtwork.values) {
          expect(
            File(art.path).existsSync(),
            isTrue,
            reason:
                '${art.name}: missing ${art.path} — run '
                'python3 scripts/cut_empty_state_assets.py',
          );
          // Flutter picks these by device pixel ratio. A missing 3.0x is not an
          // error at runtime, it just silently renders the 1x upscaled and the
          // chalk grain turns to mush on every modern phone.
          for (final scale in const ['2.0x', '3.0x']) {
            final variant = 'assets/icons/empty/$scale/${art.asset}.png';
            expect(
              File(variant).existsSync(),
              isTrue,
              reason: '${art.name}: missing $variant',
            );
          }
        }
      },
    );

    test(
      'Given pubspec.yaml, When the assets are declared, Then every artwork path '
      'is listed',
      () {
        // Only the 1x path needs declaring — Flutter finds the N.0x siblings
        // itself — but if the 1x line is missing the asset is absent from the
        // bundle entirely and the widget renders an error box in release.
        final pubspec = File('pubspec.yaml').readAsStringSync();
        for (final art in EmptyStateArtwork.values) {
          expect(
            pubspec,
            contains('- ${art.path}'),
            reason: '${art.name} is not declared in pubspec.yaml',
          );
        }
      },
    );

    test('Given the six states, When their assets are compared, Then each is a '
        'distinct file', () {
      // Two states pointing at one drawing would be a copy-paste slip in the
      // enum, and it looks intentional on screen.
      final assets = EmptyStateArtwork.values.map((a) => a.asset).toList();
      expect(assets.toSet().length, assets.length, reason: 'duplicate asset');
    });
  });

  group('theming', () {
    /// Pumps one artwork under a real app theme and returns the rendered image.
    ///
    /// `pumpAndSettle`, not `pump`: `MaterialApp` wraps its theme in an
    /// `AnimatedTheme`, so on the first frame after a theme swap `Theme.of`
    /// still returns the *previous* theme lerped towards the new one. Reading the
    /// tint before that settles compares light against light and the assertion
    /// below passes or fails for the wrong reason.
    Future<Image> pumpArt(
      WidgetTester tester,
      EmptyStateArtwork art, {
      required ThemeData theme,
      Color? color,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(body: EmptyStateArt(art, size: 40, color: color)),
        ),
      );
      await tester.pumpAndSettle();
      return tester.widget<Image>(find.byType(Image));
    }

    testWidgets(
      'Given light and dark themes, When the same artwork is drawn, Then it is '
      'one asset tinted two ways',
      (tester) async {
        final light = await pumpArt(
          tester,
          EmptyStateArtwork.noMatch,
          theme: AppTheme.light,
        );
        final lightAsset = (light.image as AssetImage).assetName;
        final lightTint = light.color;

        final dark = await pumpArt(
          tester,
          EmptyStateArtwork.noMatch,
          theme: AppTheme.dark,
        );
        final darkAsset = (dark.image as AssetImage).assetName;

        expect(
          darkAsset,
          lightAsset,
          reason:
              'both themes must draw the same file — a per-theme asset pair is '
              'what previously drifted into two different illustrations',
        );
        expect(
          dark.color,
          isNot(lightTint),
          reason: 'the tint is what differs between themes, not the geometry',
        );
        expect(lightTint, AppColors.light.secondaryText);
        expect(dark.color, AppColors.dark.secondaryText);
      },
    );

    testWidgets(
      'Given a stencil asset, When it is tinted, Then srcIn is used so only its '
      'alpha survives',
      (tester) async {
        final image = await pumpArt(
          tester,
          EmptyStateArtwork.noFriends,
          theme: AppTheme.light,
        );
        // The assets carry a flat RGB and put the chalk grain in alpha. Any
        // blend mode that reads source colour would paint that flat grey over
        // the tint and the theming would silently stop working.
        expect(image.colorBlendMode, BlendMode.srcIn);
      },
    );

    testWidgets(
      'Given a surface with its own palette, When a colour is passed, Then it '
      'overrides the theme ink',
      (tester) async {
        // The scanner's failure card is always dark even in the light theme, so
        // it supplies its own palette rather than the app's.
        final image = await pumpArt(
          tester,
          EmptyStateArtwork.noMatch,
          theme: AppTheme.light,
          color: AppColors.dark.secondaryText,
        );
        expect(image.color, AppColors.dark.secondaryText);
      },
    );
  });

  group('accessibility', () {
    testWidgets(
      'Given art with no label, When it is rendered, Then it is excluded from '
      'semantics',
      (tester) async {
        // Every use sits directly above text that already names the state, so
        // announcing the image too would just repeat it.
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: EmptyStateArt(EmptyStateArtwork.noNote, size: 48),
            ),
          ),
        );
        expect(
          tester.widget<Image>(find.byType(Image)).excludeFromSemantics,
          isTrue,
        );
      },
    );

    testWidgets(
      'Given a semantic label, When it is rendered, Then the image is announced',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: EmptyStateArt(
                EmptyStateArtwork.noNote,
                size: 48,
                semanticLabel: 'No notes yet',
              ),
            ),
          ),
        );
        final image = tester.widget<Image>(find.byType(Image));
        expect(image.excludeFromSemantics, isFalse);
        expect(image.semanticLabel, 'No notes yet');
      },
    );
  });
}
