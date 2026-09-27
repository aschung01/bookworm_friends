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

import 'package:bookworm_friends/ui/widgets/streak/streak_celebration.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_flame.dart';

/// Where along `Ignite` to sample, as percentages of the 1300ms window.
///
/// **Not the same numbers as `sheet.py`'s, and they do not need to be.** They used to be the
/// blend state's own axis values, which the CLI sheet also had to address directly; now both
/// scripts sample *time*, so either can pick its own points. These are chosen to land on the
/// beats, and they moved when the flame gained a strain: the shut book, the cover swinging,
/// the small flame it starts from, the second strain's peak, the burst, rest.
const List<int> _samples = [0, 23, 38, 59, 77, 100];

/// The box the celebration hands the flame: [StreakFlame.stageSize] is its height, and the
/// width follows the artboard's 6:5.
///
/// **The strip has to be laid out from the width, not the height, and it was not.** The box was
/// square while the artboard was; widening the artboard to 360×300 to give the burst spray room
/// made each cell 302.4 wide, and a surface sized `stage * samples * 2` then overflowed the row
/// by exactly one cell.
const double _stage = StreakFlame.stageSize;
final double _stageWidth = StreakFlame.stageWidthFor(_stage);

void main() {
  testWidgets('the flame draws, across the ignition', (tester) async {
    if (!await _artboardLoads()) {
      markTestSkipped('rive_native is not set up here; nothing to render');
      return;
    }

    tester.view.physicalSize = Size(
      _stageWidth * _samples.length * 2,
      _stage * 2 + 40,
    );
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ColoredBox(
          // The ground the celebration paints. **White now, and the constant rather than a
          // literal.** This used to be `kCandleGlow` with a note arguing the opposite — that
          // a golden shot on white would flatter a halo that cannot be seen on cream. The
          // screen moved to white, so the warning inverts: the halo really is fainter here,
          // and this golden is now the place that shows it rather than the place that hides
          // it. Regenerate and *look* at the pool under the book.
          color: kStreakCelebrationGround,
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
                      SizedBox(width: _stageWidth, height: _stage),
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
