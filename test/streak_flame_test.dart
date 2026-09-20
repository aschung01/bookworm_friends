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
/// `rive/streak_flame/sheet.py` and a simulator.
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
  required AnimationController controller,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: StreakFlame(
            progress: controller,
            size: 152,
            fallback: (context) => const Text('hand-built', key: _fallbackKey),
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
    await _pump(tester, controller: _controller(tester));
    await tester.pumpAndSettle();

    final artboard = find.byType(rive.RiveWidget);
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
    await _pump(tester, controller: _controller(tester));

    // No settle: this is the frame before the resolve completes.
    expect(find.byKey(_fallbackKey), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the artboard does not tick on once the sequence has landed', (
    tester,
  ) async {
    // **`pumpAndSettle` completing *is* the assertion.** A 1D blend state reports itself as
    // always advancing, so `RiveWidgetController.advance` returns true forever unless `active`
    // is cleared — and a widget that always wants another frame repaints at 60fps on a screen
    // a reader opens nightly and then leaves sitting there. It also hangs every test that
    // pumps this screen for its full timeout, which is how the defect was found.
    final controller = _controller(tester);
    await _pump(tester, controller: controller);
    await tester.pumpAndSettle();

    controller.forward();
    await tester.pumpAndSettle();

    expect(controller.value, 1);
    expect(tester.takeException(), isNull);
  });

  test('the artboard is a Rive file, and names what the code looks for', () {
    // **The guard against the failure mode that has no symptom.** A typo in the state machine
    // or the bound property is not an error anywhere: `StreakFlame` treats every failure as a
    // missing artboard and quietly draws the fallback, so the app keeps working and the
    // drawing simply never appears. Reading the bytes needs no native library, so unlike the
    // cases above this one holds on every machine.
    final bytes = File(kStreakFlameAsset).readAsBytesSync();

    expect(bytes.length, greaterThan(1024), reason: 'suspiciously small');
    expect(
      String.fromCharCodes(bytes.take(4)),
      'RIVE',
      reason: 'not a Rive file — did rive/streak_flame/build.sh run?',
    );

    // Rive stores exported names as plain strings, so the contract is greppable in the binary.
    final text = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
    expect(text, contains(kStreakFlameStateMachine));
    expect(text, contains(kStreakFlameProgressProperty));
  });

  test('the artboard contract is named in one place', () {
    // Constants rather than literals at the call site, so the scene, the build script and the
    // code cannot disagree about what the state machine or the bound property is called.
    expect(kStreakFlameAsset, 'assets/rive/streak_flame.riv');
    expect(kStreakFlameStateMachine, 'Ignite');
    expect(kStreakFlameProgressProperty, 'progress');
  });

  test('the drawing renders where the library is available', () async {
    // Skipped rather than asserted where `rive_native` is absent — see the note at the top of
    // this file. Where it *is* available this is the only case that proves the file decodes,
    // exposes the named state machine and hands back a view model with `progress` on it.
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

    final machine = artboard!.stateMachine(kStreakFlameStateMachine);
    expect(
      machine,
      isNotNull,
      reason:
          'the artboard has no state machine called $kStreakFlameStateMachine',
    );

    final viewModel = file.defaultArtboardViewModel(artboard);
    expect(viewModel, isNotNull, reason: 'the artboard exports no view model');

    final instance = viewModel!.createDefaultInstance();
    expect(instance, isNotNull);
    expect(
      instance!.number(kStreakFlameProgressProperty),
      isNotNull,
      reason:
          'the view model has no Number called $kStreakFlameProgressProperty',
    );
  });
}
