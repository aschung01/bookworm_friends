/// Renders the streak flame through the real Flutter pipeline, at the poses it blends between.
///
/// **The only check in the suite that looks at the drawing.** `streak_flame_test.dart` proves
/// the file decodes and exposes the contract; `rive/streak_flame/sheet.py` proves the scene
/// draws something, but it renders through the Rive CLI's own previewer rather than through the
/// app. Neither one exercises what actually ships: `Factory.flutter` painting the artboard onto
/// a Flutter canvas, inside a `SizedBox` at `stageSize`, over the celebration's cream ground.
/// An artboard that is transparent in the previewer and opaque here would satisfy every other
/// assertion in the suite.
///
///     flutter test --update-goldens test/streak_flame_golden_test.dart
///
/// And then **look at the image**. A golden's value is the review, not the byte comparison; a
/// filmstrip that regressed into six identical frames passes against a baseline regenerated
/// from it. One image holding every pose rather than one file per pose, because the thing being
/// reviewed is whether the sequence reads as one movement.
///
/// Skipped where `rive_native` is absent — see the note at the top of `streak_flame_test.dart`.
/// That makes this a tool for whoever changes the art rather than a gate on CI, which is the
/// same bargain `empty_state_art_golden_test.dart` strikes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive/rive.dart' as rive;

import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_flame.dart';

/// The blend state's own axis values, as percentages of the ignition window.
///
/// Kept in step with `rive/streak_flame/scene.rml` and with `sheet.py`, so the two filmstrips
/// are comparable frame for frame — the CLI's and the app's disagreeing about a pose is worth
/// seeing, and is invisible if they sample different points.
const List<int> _poses = [0, 20, 35, 50, 70, 100];

/// The square the celebration hands the flame, from `_Ignition.stageSize`.
const double _stage = 152;

void main() {
  testWidgets('the flame draws, pose by pose', (tester) async {
    if (!await _artboardLoads()) {
      markTestSkipped('rive_native is not set up here; nothing to render');
      return;
    }

    tester.view.physicalSize = Size(
      _stage * _poses.length * 2,
      _stage * 2 + 40,
    );
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ColoredBox(
          // The ground the celebration paints. **Not white**: the glow is warmer rather than
          // brighter precisely because a lighter halo is invisible on this cream, so a golden
          // shot on white would flatter art that cannot be seen in the app.
          color: kCandleGlow,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final pose in _poses)
                StreakFlame(
                  // A stopped animation rather than a driven controller: the poses are what is
                  // under review, and a golden that depended on the clock would be reviewing
                  // the easing curve's sampling instead.
                  progress: AlwaysStoppedAnimation(pose / 100),
                  size: _stage,
                  fallback: (context) =>
                      const SizedBox.square(dimension: _stage),
                ),
            ],
          ),
        ),
      ),
    );

    // `File.asset` reads through the bundle, which needs the real event loop: a widget test's
    // clock does not run it, so without `runAsync` every frame here is the fallback and the
    // golden captures six empty boxes that then "pass" against an equally empty baseline.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pumpAndSettle();

    expect(
      find.byType(rive.RiveWidget),
      findsNWidgets(_poses.length),
      reason:
          'every frame must be the artboard, or the golden is of the fallback',
    );

    await expectLater(
      find.byType(Row),
      matchesGoldenFile('goldens/streak_flame_poses.png'),
    );
  });
}

/// Whether this machine can read the artboard at all.
Future<bool> _artboardLoads() async {
  try {
    final file = await rive.File.asset(
      kStreakFlameAsset,
      riveFactory: kStreakFlameFactory,
    );
    file?.dispose();
    return file != null;
  } catch (_) {
    return false;
  }
}
