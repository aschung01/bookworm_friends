// `AdaptiveGlassCircle`, and the thing it deliberately does *not* do.
//
// This widget exists because `AdaptiveIconButton` cannot serve content that is not an
// SF Symbol — the reader's avatar is an emoji or a photograph. The difference sounds
// cosmetic and is not: a symbol handed to `CNButton` lives *inside* the `UIButton`, so
// UIKit transforms it along with the glass on press. Content layered over the platform
// view gets none of that.
//
// **Three attempts were made to mirror that press in Flutter, and each shipped a
// worse defect than the mismatch it was fixing** — an invented scale factor, then
// square corners from the rectangular overlay quad the overflow landed in, then a
// fixed clip that disagreed with the native disc and read as the button *gaining*
// padding when pressed. The class doc records all three. The content is now left
// alone, and these tests pin that: no scale, no clip, no press state.
//
// The guard matters because the failure is invisible to CI. `useNativeGlass` is false
// under `flutter test`, so the glass path never renders on the fallback machine, and
// every one of those three defects was found by eye on a device.
//
// **Two platforms, because the widget has two renderings and they disagree on
// purpose.** `flutter test` reports Android, so the fallback is what runs unless
// `debugDefaultTargetPlatformOverride` says otherwise; the glass path additionally
// needs a host that reports glass support, hence `if (!useNativeGlass) return`. Same
// shape as `read_filter_test.dart`, which documents the reasoning at length.

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';

Future<void> _asPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

/// [fillsDisc] stands in for the avatar's glass path, where the content is sized to
/// the whole diameter and so has somewhere to overflow to when it scales. The default
/// is a bare `Text`, which is smaller than the disc and would hide the clipping bug.
Widget _wrap({
  VoidCallback? onPressed,
  bool withCallback = true,
  bool fillsDisc = false,
}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: Center(
      child: AdaptiveGlassCircle(
        diameter: 44,
        semanticLabel: 'Profile',
        onPressed: withCallback ? (onPressed ?? () {}) : null,
        builder: (context, glass) => fillsDisc
            ? Container(
                key: const Key('mark'),
                width: 44,
                height: 44,
                color: const Color(0xFFFF0000),
              )
            : Text(glass ? 'on-glass' : 'on-material', key: const Key('mark')),
      ),
    ),
  ),
);

Finder _mark() => find.byKey(const Key('mark'));

/// The content's painted box, which is what every claim below is really about.
Rect _markRect(WidgetTester tester) => tester.getRect(_mark());

void main() {
  group('the glass path', () {
    testWidgets(
      'Given content that fills the disc, When the button is pressed, Then the '
      'content does not move at all',
      (tester) async {
        // **The regression guard.** Three separate attempts to animate this on press
        // are recorded on the class, and the last one is why the test reads this way:
        // a fixed clip plus a growing mark disagreed with the native disc, and the
        // button looked like it *gained* padding under the finger. Any future
        // transform reintroduces one of the three, so the assertion is that the box
        // is untouched — not that some particular scale is applied.
        await _asPlatform(TargetPlatform.iOS, () async {
          if (!useNativeGlass) return;

          await tester.pumpWidget(_wrap(fillsDisc: true));
          await tester.pumpAndSettle();

          final atRest = _markRect(tester);
          expect(
            atRest,
            tester.getRect(find.byType(AdaptiveGlassCircle)),
            reason: 'the avatar is the disc, so it starts flush with it',
          );

          final gesture = await tester.startGesture(
            tester.getCenter(find.byType(AdaptiveGlassCircle)),
          );
          await tester.pumpAndSettle();

          expect(
            _markRect(tester),
            atRest,
            reason:
                'the press belongs to UIKit; Flutter guessing at it is what put '
                'padding under the finger',
          );

          await gesture.up();
          await tester.pumpAndSettle();
          expect(_markRect(tester), atRest);
        });
      },
    );

    testWidgets(
      'Given the glass path, When it renders, Then nothing scales or clips the content',
      (tester) async {
        // The structural form of the same guard, so a reviewer can see at a glance
        // that the press machinery is gone rather than merely inert. `ClipOval` is
        // named because it was the third fix: it cured the square corners the second
        // fix caused, and caused the padding the user reported.
        await _asPlatform(TargetPlatform.iOS, () async {
          if (!useNativeGlass) return;

          await tester.pumpWidget(_wrap(fillsDisc: true));
          await tester.pumpAndSettle();

          expect(find.byType(AnimatedScale), findsNothing);
          expect(
            find.descendant(
              of: find.byType(AdaptiveGlassCircle),
              matching: find.byType(ClipOval),
            ),
            findsNothing,
          );
        });
      },
    );

    testWidgets(
      'Given the glass path, When it renders, Then the tap still belongs to the '
      'native button',
      (tester) async {
        // The tap was always UIKit's, and it stays UIKit's now that the Flutter press
        // machinery is gone: the content sits under `IgnorePointer` and nothing else
        // in this subtree joins the arena.
        await _asPlatform(TargetPlatform.iOS, () async {
          if (!useNativeGlass) return;

          var taps = 0;
          await tester.pumpWidget(_wrap(onPressed: () => taps++));
          await tester.pumpAndSettle();

          expect(_mark(), findsOneWidget);
          expect(find.text('on-glass'), findsOneWidget);

          tester.widget<CNButton>(find.byType(CNButton)).onPressed!();
          expect(taps, 1);
        });
      },
    );
  });

  group('the fallback path', () {
    testWidgets(
      'Given no glass, When the circle is pressed, Then the content does not scale',
      (tester) async {
        // Unchanged, and never the problem: the fallback is an `IconButton`, which
        // brings its own press response. Kept because it is the half CI actually
        // renders — `useNativeGlass` is false here, so every glass test above is
        // skipped on a non-iOS-26 machine and this is the only one that runs.
        await _asPlatform(TargetPlatform.android, () async {
          await tester.pumpWidget(_wrap());
          await tester.pumpAndSettle();

          expect(find.text('on-material'), findsOneWidget);
          expect(
            find.ancestor(of: _mark(), matching: find.byType(AnimatedScale)),
            findsNothing,
          );

          final gesture = await tester.startGesture(
            tester.getCenter(find.byType(AdaptiveGlassCircle)),
          );
          await tester.pumpAndSettle();
          await gesture.up();
          await tester.pumpAndSettle();
        });
      },
    );

    testWidgets(
      'Given the fallback, When it is tapped, Then the callback still fires',
      (tester) async {
        await _asPlatform(TargetPlatform.android, () async {
          var taps = 0;
          await tester.pumpWidget(_wrap(onPressed: () => taps++));
          await tester.pumpAndSettle();

          await tester.tap(find.byType(AdaptiveGlassCircle));
          expect(taps, 1);
        });
      },
    );
  });
}
