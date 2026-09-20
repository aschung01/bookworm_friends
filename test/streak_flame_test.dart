/// The flame's two paths: the Rive artboard, and life without it.
///
/// **This file exists because the graceful path was not graceful.** `RiveWidgetBuilder`
/// documents a `RiveFailed` state, and a missing asset does not reach it — `FileLoader.file`
/// throws `RiveFileLoaderException` out of `initState`, which takes down the subtree. The
/// first cut of `StreakFlame` handed the asset name straight to `FileLoader` and broke fifteen
/// cases in `streak_celebration_test.dart` the moment it was wired in. So the contract worth
/// pinning is not "Rive renders", which no widget test can prove without the artboard and the
/// native library: it is **that the absence of the artboard costs nothing**.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_flame.dart';

Future<void> _pump(WidgetTester tester, {required Widget fallback}) async {
  final controller = AnimationController(
    duration: const Duration(milliseconds: 300),
    vsync: tester,
  );
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: StreakFlame(
            progress: controller,
            size: 152,
            fallback: (context) => fallback,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('with no artboard, the fallback draws and nothing throws', (
    tester,
  ) async {
    // The state of the repo today, and of any checkout until the `.riv` is authored. It has
    // to be an ordinary render rather than an error, because the celebration is presented
    // over the streak page and an exception here would take that page with it.
    await _pump(
      tester,
      fallback: const Text('hand-built', key: ValueKey('fallback')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('fallback')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the fallback is what shows while the asset is being resolved', (
    tester,
  ) async {
    // Reading an asset costs a frame or two, and this is the *first* beat of the sequence: a
    // hole where the flame belongs would be more visible than the swap when it lands. So the
    // first frame is already the fallback rather than a gap or a spinner.
    await _pump(
      tester,
      fallback: const Text('hand-built', key: ValueKey('fallback')),
    );

    // No settle: this is the frame before the resolve completes.
    expect(find.byKey(const ValueKey('fallback')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  test('the artboard contract is named in one place', () {
    // The three strings a builder has to match in the editor. Constants rather than literals
    // at the call site, so `docs/streak-flame-rive.md` and the code cannot disagree about
    // what the state machine or the bound property is called — a typo there is a silent
    // fallback, which is the failure mode hardest to notice.
    expect(kStreakFlameAsset, 'assets/rive/streak_flame.riv');
    expect(kStreakFlameStateMachine, 'Ignite');
    expect(kStreakFlameProgressProperty, 'progress');
  });
}
