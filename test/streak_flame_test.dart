/// The flame's two paths: the Rive artboard, and life without it.
///
/// **Both paths are live on real machines, which is why nothing here asserts one of them.**
/// `rive` parses through `rive_native`, whose dynamic library is downloaded by
/// `dart run rive_native:setup` into `build/` — and `build/` is gitignored, so a fresh
/// checkout, a new worktree or a CI runner has the `.riv` but not the library to read it with.
/// There, `File.asset` fails, the widget draws the fallback, and that is correct behaviour
/// rather than a broken test. A case that asserted `findsOneWidget` on the fallback passed for
/// weeks and then failed the hour the artboard landed; a case that asserts the artboard
/// renders would fail on every machine that has not run the setup. So the cases below assert
/// what is true on both: that *something* draws, that it is never an exception, and that the
/// names the two sides agree on actually appear in the file.
///
/// The one thing no widget test can judge is whether the drawing looks right. That is
/// `rive/streak_flame/sheet.py`, `rive/streak_flame/motion.py` and a simulator.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive/rive.dart' as rive;

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_flame.dart';

const ValueKey<String> _fallbackKey = ValueKey('fallback');

Future<void> _pump(
  WidgetTester tester, {
  required AnimationController progress,
  Animation<double>? liveness,
  bool reducedMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Scaffold(
          body: Center(
            child: StreakFlame(
              progress: progress,
              liveness: liveness ?? const AlwaysStoppedAnimation(0),
              size: 152,
              fallback: (context) =>
                  const Text('hand-built', key: _fallbackKey),
            ),
          ),
        ),
      ),
    ),
  );
}

AnimationController _controller(WidgetTester tester) {
  final controller = AnimationController(
    duration: const Duration(milliseconds: 300),
    vsync: tester,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// Whether this machine can actually read the artboard.
///
/// Asked by loading it exactly the way the widget does, rather than by probing for the
/// library: the question is not "is a dylib present" but "does this code path succeed here",
/// and only one of those is worth branching on.
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

void main() {
  testWidgets('the flame draws, and never throws, either way', (tester) async {
    // The celebration is presented over the streak page, so an exception here would take that
    // page with it. Exactly one of the two paths must be on screen — "neither" is the bug this
    // guards, and it is the one a missing asset used to cause by throwing out of `initState`.
    await _pump(tester, progress: _controller(tester));
    await tester.pumpAndSettle();

    final artboard = find.byType(rive.RiveArtboardWidget);
    final fallback = find.byKey(_fallbackKey);
    expect(
      artboard.evaluate().length + fallback.evaluate().length,
      1,
      reason: 'expected either the artboard or the fallback, and exactly one',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the fallback is what shows while the asset is being resolved', (
    tester,
  ) async {
    // Reading an asset costs a frame or two, and this is the *first* beat of the sequence: a
    // hole where the flame belongs would be more visible than the swap when it lands. So the
    // first frame is already the fallback rather than a gap or a spinner.
    await _pump(tester, progress: _controller(tester));

    // No settle: this is the frame before the resolve completes.
    expect(find.byKey(_fallbackKey), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the artboard comes to rest when nothing has asked it to live', (
    tester,
  ) async {
    // **`pumpAndSettle` completing *is* the assertion**, and the thing it is asserting is that
    // `_FlamePainter.advance` returns false once the ignition has landed and `liveness` is 0.
    // A painter that always wants another frame repaints at 60fps for as long as the screen is
    // up, and hangs every test that pumps it for the full timeout — which is how the same
    // defect was found in the state-machine version of this widget, where a 1D blend state
    // reported itself as always advancing.
    //
    // With `liveness` above 0 this would *not* complete, and that is deliberate rather than a
    // gap in the coverage: see `kStreakFlameIdleAnimation`. The case below is the one that
    // pins the only place the distinction can be observed without hanging.
    final progress = _controller(tester);
    await _pump(tester, progress: progress);
    await tester.pumpAndSettle();

    progress.forward();
    await tester.pumpAndSettle();

    expect(progress.value, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion gets a still flame, not a looping one', (
    tester,
  ) async {
    // **The gate that cannot live in `streak_celebration.dart`.** Every other beat there is
    // built so that its t=1 state is the resting one, and the screen honours reduced motion by
    // jumping its controller to 1 — which for the liveness beat means *fully mixed in*. So a
    // reader who asked the system to stop animating would be handed the one thing on the
    // screen that never stops. `StreakFlame` forces the mix to zero instead, and this settles
    // rather than timing out because of it.
    final progress = _controller(tester);
    await _pump(
      tester,
      progress: progress,
      liveness: const AlwaysStoppedAnimation(1),
      reducedMotion: true,
    );
    progress.value = 1;
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  test('the artboard is a Rive file, and names what the code looks for', () {
    // **The guard against the failure mode that has no symptom.** A typo in either animation
    // name is not an error anywhere: `animationNamed` returns null, the painter poses nothing,
    // and the artboard sits on its authored rest frame — which is a book lying open with a
    // flame already on it, and looks entirely deliberate. Reading the bytes needs no native
    // library, so unlike the cases above this one holds on every machine.
    final bytes = File(kStreakFlameAsset).readAsBytesSync();

    expect(bytes.length, greaterThan(1024), reason: 'suspiciously small');
    expect(
      String.fromCharCodes(bytes.take(4)),
      'RIVE',
      reason: 'not a Rive file — did rive/streak_flame/build.sh run?',
    );

    // Rive stores exported names as plain strings, so the contract is greppable in the binary.
    final text = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
    expect(text, contains(kStreakFlameIgniteAnimation));
    expect(text, contains(kStreakFlameIdleAnimation));
  });

  test('the artboard contract is named in one place', () {
    // Constants rather than literals at the call site, so the scene, the build script and the
    // code cannot disagree about what the two timelines are called.
    expect(kStreakFlameAsset, 'assets/rive/streak_flame.riv');
    expect(kStreakFlameIgniteAnimation, 'Ignite');
    expect(kStreakFlameIdleAnimation, 'Idle');
  });

  test('the drawing exposes both timelines where the library is available', () async {
    // Skipped rather than asserted where `rive_native` is absent — see the note at the top of
    // this file. Where it *is* available this is the only case that proves the file decodes and
    // hands back both named animations, which is what the byte-grep above can only suggest.
    if (!await _artboardLoads()) {
      markTestSkipped(
        'rive_native is not set up here; the fallback path covers it',
      );
      return;
    }

    final file = await rive.File.asset(
      kStreakFlameAsset,
      riveFactory: kStreakFlameFactory,
    );
    // Nullable as well as throwing: `File.asset` signals some failures by returning null
    // rather than raising, which is why `StreakFlame` needs both a `catch` and a null check.
    expect(file, isNotNull);
    addTearDown(file!.dispose);

    final artboard = file.defaultArtboard();
    expect(artboard, isNotNull);
    addTearDown(artboard!.dispose);

    final ignite = artboard.animationNamed(kStreakFlameIgniteAnimation);
    expect(
      ignite,
      isNotNull,
      reason: 'no animation called $kStreakFlameIgniteAnimation',
    );
    // 54 frames at 60fps. Asserted as a range rather than a number so retiming the
    // choreography is not a test edit, but a timeline that collapsed to nothing — or that
    // grew into something a reader waits through — is caught.
    expect(ignite!.duration, greaterThan(0.5));
    expect(ignite.duration, lessThan(1.5));

    final idle = artboard.animationNamed(kStreakFlameIdleAnimation);
    expect(
      idle,
      isNotNull,
      reason: 'no animation called $kStreakFlameIdleAnimation',
    );
    expect(idle!.duration, greaterThan(0.2));

    ignite.dispose();
    idle.dispose();
  });
}
