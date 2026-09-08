// The gate that stops a native glass control from staying native under something.
//
// The *visible* half of this cannot be tested here: `useNativeGlass` is false
// under `flutter test` (the binding reports Android), so `AdaptiveIconButton`
// renders its Material fallback either way. What is testable is the signal it
// reads, and the chain that feeds it — `ShellRouteObserver` bumps
// `CNTabBarRouteObserver.anyModalDepth` for a pushed sheet and `glassPageDepth`
// for a pushed page, and every `ModalCoverBuilder` that mounted below either one
// reports itself covered until that thing has finished leaving.
//
// Why it matters on device: a `UiKitView` under a Flutter sheet leaks its own
// rectangle through the sheet's scrim, which is what turned the ✕ on the Add Book
// sheet into a grey square while Book Info was open — and Flutter's barrier does
// not block taps to it either.
//
// **The page half exists because the modal half cannot see a page.**
// `_isAnyModal` matches a `PopupRoute` or a type name containing
// Sheet/Popup/Dialog, deliberately mirroring the package's predicate — and
// `AppRoutes.shareCard`, which the Card sheet's glass share button pushes, is a
// `CupertinoPageRoute` with `fullscreenDialog: true`. A flag, not a type name. The
// route's own `secondaryAnimation` was tried first and is worse than useless here:
// `canTransitionTo` is false for a fullscreen dialog ("don't perform outgoing
// animation"), so the covered route is never told anything at all.

import 'dart:async';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/providers/shell_chrome_provider.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';

import 'support/prefs.dart';

/// Pumps an app wired to the real observer, with a [ModalCoverBuilder] recording
/// every value it is handed.
///
/// [inSheet] decides which side of the gate is under test: the builder either
/// lives on the page (and is covered by the sheet) or inside the sheet itself
/// (and must not call itself covered by the sheet it is part of).
Future<List<bool>> _pump(
  WidgetTester tester, {
  required bool inSheet,
  required void Function(BuildContext pageContext) capturePage,
}) async {
  final reported = <bool>[];
  Widget probe() => ModalCoverBuilder(
    builder: (_, covered) {
      reported.add(covered);
      return const SizedBox.shrink();
    },
  );

  await tester.pumpWidget(
    ProviderScope(
      // `ShareCardPage` reads the card's stored display setting.
      overrides: [await sharedPreferencesOverride()],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          navigatorObservers: [ref.watch(shellRouteObserverProvider)],
          home: Builder(
            builder: (context) {
              capturePage(context);
              return Scaffold(body: inSheet ? const SizedBox() : probe());
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return reported;
}

void main() {
  // The counter is process-wide, like the package's own. One test leaving it above
  // zero would make every later test's control believe it was born covered.
  setUp(() => glassPageDepth.value = 0);

  testWidgets(
    'Given a control on the page, When a sheet is pushed over it, Then it '
    'reports itself covered until the sheet has left',
    (tester) async {
      late BuildContext page;
      final reported = await _pump(
        tester,
        inSheet: false,
        capturePage: (context) => page = context,
      );

      expect(reported.last, isFalse, reason: 'nothing is over it yet');

      CNBottomSheet.show<void>(
        context: page,
        builder: (_) => const SizedBox(height: 120),
      );
      await tester.pumpAndSettle();
      expect(
        reported.last,
        isTrue,
        reason:
            'the sheet is above the route this control mounted in, so its glass '
            'has to go -- this is the ✕ on Add Book under Book Info',
      );

      Navigator.of(page).pop();
      await tester.pumpAndSettle();
      expect(
        reported.last,
        isFalse,
        reason:
            'released only once the sheet is gone; releasing at the start of the '
            'close lets the glass halo leak for the frames before its pixels '
            'clear',
      );
    },
  );

  testWidgets(
    'Given a control inside the newest sheet, When that sheet is up, Then it is '
    'not covered by it',
    (tester) async {
      late BuildContext page;
      final reported = <bool>[];
      await _pump(
        tester,
        inSheet: true,
        capturePage: (context) => page = context,
      );

      CNBottomSheet.show<void>(
        context: page,
        builder: (_) => ModalCoverBuilder(
          builder: (_, covered) {
            reported.add(covered);
            return const SizedBox(height: 120);
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(reported, isNotEmpty, reason: 'the sheet body should have built');
      expect(
        reported,
        everyElement(isFalse),
        reason:
            'a control is covered by what is above it, not by the sheet it is '
            'part of -- without the mount-depth gate every glass control inside '
            'a sheet would degrade the moment it appeared',
      );

      Navigator.of(page).pop();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Given a control on the page, When a full-screen page is pushed over it, '
      'Then it reports itself covered until that page has left', (tester) async {
    // The Card sheet's glass share button, pushing `AppRoutes.shareCard`. Built
    // the same way the route table builds it, because both halves of that
    // construction are what defeat the alternatives: `CupertinoPageRoute` is not
    // matched by the modal predicate's type-name sniffing, and `fullscreenDialog`
    // is what makes `canTransitionTo` false and the route's own
    // `secondaryAnimation` stay dismissed.
    late BuildContext page;
    final reported = await _pump(
      tester,
      inSheet: false,
      capturePage: (context) => page = context,
    );

    expect(reported.last, isFalse, reason: 'nothing is over it yet');

    unawaited(
      Navigator.of(page).push(
        CupertinoPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const Scaffold(body: SizedBox()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      reported.last,
      isTrue,
      reason:
          'a live platform view under an opaque page is the same bleed as one '
          'under a sheet, and this is the door the modal counter does not watch',
    );

    Navigator.of(page).pop();
    await tester.pumpAndSettle();
    expect(
      reported.last,
      isFalse,
      reason: 'released once the page is gone, as the sheet case is',
    );
  });

  testWidgets(
    'Given a control inside the pushed page, When that page is up, Then it is '
    'not covered by the page it is part of',
    (tester) async {
      // The mount-depth gate, for pages. Without it every glass control on
      // `ShareCardPage` itself — its ✕ and its framing toggle are both
      // `AdaptiveIconButton`s — would degrade the moment the screen opened, which
      // is the whole screen's chrome going flat.
      late BuildContext page;
      final reported = <bool>[];
      await _pump(
        tester,
        inSheet: true,
        capturePage: (context) => page = context,
      );

      unawaited(
        Navigator.of(page).push(
          CupertinoPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => Scaffold(
              body: ModalCoverBuilder(
                builder: (_, covered) {
                  reported.add(covered);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(reported, isNotEmpty, reason: 'the page should have built');
      expect(
        reported,
        everyElement(isFalse),
        reason:
            'a control is covered by what is above it, not by the page it is part '
            'of -- the observer counts a route before its content mounts, which is '
            'what makes the mount depth already include this page',
      );

      Navigator.of(page).pop();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Given pages pushed and popped, When the dust settles, Then the counter is '
    'back where it started',
    (tester) async {
      // A counter that drifted upward would leave every glass control in the app
      // permanently degraded, and one that drifted below zero would leave them all
      // permanently glass. Neither failure shows up in a single interaction.
      late BuildContext page;
      await _pump(
        tester,
        inSheet: false,
        capturePage: (context) => page = context,
      );
      final atRest = glassPageDepth.value;

      for (var i = 0; i < 3; i++) {
        unawaited(
          Navigator.of(page).push(
            CupertinoPageRoute<void>(
              builder: (_) => const Scaffold(body: SizedBox()),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(glassPageDepth.value, atRest + 3);

      for (var i = 0; i < 3; i++) {
        Navigator.of(page).pop();
        await tester.pumpAndSettle();
      }
      expect(glassPageDepth.value, atRest);
    },
  );
}
