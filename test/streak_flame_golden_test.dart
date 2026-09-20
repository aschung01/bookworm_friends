/// Renders the streak flame through the real Flutter pipeline, at points across the ignition.
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
/// from it. One image holding every sample rather than one file per sample, because the thing
/// being reviewed is whether the sequence reads as one movement.
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

/// Where along `Ignite` to sample, as percentages of the 900ms window.
///
/// **Not the same numbers as `sheet.py`'s, and they do not need to be.** They used to be the
/// blend state's own axis values, which the CLI sheet also had to address directly; now both
/// scripts sample *time*, so either can pick its own points. These are chosen to land on the
/// beats: the shut book, the cut, the flame's first appearance, its stretch, its settle, rest.
const List<int> _samples = [0, 12, 30, 45, 70, 100];

/// The square the celebration hands the flame, from `_Ignition.stageSize`.
const double _stage = 152;

void main() {
  testWidgets('the flame draws, across the ignition', (tester) async {
    if (!await _artboardLoads()) {
      markTestSkipped('rive_native is not set up here; nothing to render');
      return;
    }

    tester.view.physicalSize = Size(
      _stage * _samples.length * 2,
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
              for (final sample in _samples)
                StreakFlame(
                  // A stopped animation rather than a driven controller: the poses are what is
                  // under review, and a golden that depended on the clock would be reviewing
                  // the sampling instead.
                  progress: AlwaysStoppedAnimation(sample / 100),
                  // **Zero, or this test never finishes.** A live idle loop keeps asking for
                  // frames, which is the point of it and the reason `pumpAndSettle` below would
                  // time out. The loop is reviewed by `rive/streak_flame/motion.py`, which can
                  // watch something that never stops; a golden cannot.
                  liveness: const AlwaysStoppedAnimation(0),
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
      find.byType(rive.RiveArtboardWidget),
      findsNWidgets(_samples.length),
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
