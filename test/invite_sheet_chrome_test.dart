// The invite sheet's two pieces of chrome, both of which were wrong on device and
// neither of which any existing test could see.
//
// **The ✕ was 36pt.** That is the size the library's visit bar uses, where the ✕ is
// crowded in beside Poke and every point is contested. Nothing is crowding this one,
// and it is the only way out of a sheet that covers the whole screen — so it belongs
// at 44, which is both the platform's minimum target and what Add Book, Manage
// Shelves, the scanner and the share card all use.
//
// **Share sat under the floating tab bar.** `ShellChrome` hosts that bar *above* the
// navigator so it stays in front of the first modal over the shell — which is what
// this sheet is. `SafeArea` only clears the home-indicator strip, so the primary
// action and the read-aloud code below it were both behind glass. Every other shell
// sheet reserves `ShellTabBarGeometry.reserve` for exactly this; this one did not.
//
// Both are geometry, so both are measured rather than eyeballed. A screenshot review
// had already passed over the second one.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/invite.dart';
import 'package:bookworm_friends/providers/invite_provider.dart';
import 'package:bookworm_friends/providers/shell_chrome_provider.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/invite/invite_sheet.dart';
import 'package:bookworm_friends/ui/widgets/shell_tab_bar.dart';

/// Screen the sheet is measured against — an iPhone 15 in points.
const Size _screen = Size(393, 852);

/// Home-indicator strip. Non-zero deliberately: with it at 0 the fallback bar's
/// reservation and `SafeArea`'s inset would coincide and the bug would hide.
const double _bottomViewPadding = 34;

/// Answers `create()` without a network.
///
/// [gate] stands in for a slow RPC: when set, `create()` does not resolve until it is
/// completed, which is how the "button greyed out on arrival" case is reproduced.
class _FakeInviteActions extends InviteActions {
  _FakeInviteActions(super.ref);

  int creates = 0;
  Completer<void>? gate;

  @override
  Future<Invite> create() async {
    creates += 1;
    if (gate != null) await gate!.future;
    return Invite(
      token: 'K7M2QP4X',
      expiresAt: DateTime(2030),
      maxUses: 10,
      usedCount: 0,
    );
  }
}

/// Stands in for the `share_plus` platform side.
///
/// [fail] reproduces what iOS actually does when it refuses — a `PlatformException`
/// out of the method channel, which is the shape `FPPSharePlusPlugin.m` returns for an
/// unanchored popover. Returning an error string would not exercise the same path.
List<MethodCall> _mockShareChannel(WidgetTester tester, {bool fail = false}) {
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
    call,
  ) async {
    calls.add(call);
    if (fail) {
      throw PlatformException(code: 'error', message: 'sharePositionOrigin');
    }
    return 'com.apple.UIKit.activity.Message';
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    ),
  );
  return calls;
}

/// Pumps the sheet the shape `showInviteSheet` gives it: a full-height box pinned to
/// the bottom of the screen, under a real bottom view padding.
///
/// [barVisible] stands in for the shell. `shellBarVisibleProvider` derives its answer
/// from two route identities that only `HomePage` publishes, so a widget test cannot
/// arrive at `true` honestly — and the whole point of the reservation is what happens
/// when it is true.
Future<_FakeInviteActions> _pump(
  WidgetTester tester, {
  required bool barVisible,
  Completer<void>? gate,
}) async {
  tester.view.physicalSize = _screen * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      inviteActionsProvider.overrideWith(_FakeInviteActions.new),
      shellBarVisibleProvider.overrideWithValue(barVisible),
    ],
  );
  addTearDown(container.dispose);
  final fake = container.read(inviteActionsProvider) as _FakeInviteActions;
  fake.gate = gate;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // A failed share reports through `EasyLoading`, as every other failed action
        // in this app does, and its overlay only exists once this wrapper is in the
        // tree — `destination_row_test.dart` sets it up the same way.
        builder: (context, child) => FlutterEasyLoading(child: child!),
        home: MediaQuery(
          data: const MediaQueryData(
            size: _screen,
            viewPadding: EdgeInsets.only(bottom: _bottomViewPadding),
            padding: EdgeInsets.only(bottom: _bottomViewPadding),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              // `showInviteSheet` hands the sheet the screen less the status bar.
              height: _screen.height - 24,
              child: const Material(child: InviteSheet()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return fake;
}

/// The band of screen the floating tab bar's glass occupies, measured up from the
/// bottom. Read from the same object the bar positions itself with, so this cannot
/// assert against a number the bar has since moved off.
double _glassTop(WidgetTester tester) => const ShellTabBarGeometry(
  // `flutter test` reports Android, so this is the path actually exercised. It is
  // also the conservative one to assert against: the native bar's glass starts
  // higher (83pt vs 92), so clearing the fallback clears both.
  native: false,
  bottomViewPadding: _bottomViewPadding,
).glassTop;

void main() {
  group('the close button', () {
    testWidgets(
      'Given the sheet is open, When the close button is measured, Then its target '
      'is at least the 44pt floor',
      (tester) async {
        await _pump(tester, barVisible: false);

        final button = tester.widget<AdaptiveIconButton>(
          find.byType(AdaptiveIconButton),
        );

        expect(button.diameter, greaterThanOrEqualTo(44));
        // The rendered box, not just the declared field: `AdaptiveIconButton` sizes
        // itself from `diameter` on both paths, and a wrapper that shrank it would
        // pass the check above and still be too small under a thumb.
        expect(
          tester.getSize(find.byType(AdaptiveIconButton)).shortestSide,
          greaterThanOrEqualTo(44),
        );
      },
    );
  });

  group('room for the floating tab bar', () {
    testWidgets(
      'Given the shell bar is in front of the sheet, When the primary action is '
      'measured, Then it sits entirely above the bar glass',
      (tester) async {
        await _pump(tester, barVisible: true);

        // The button is the lowest thing on the sheet now that the read-aloud code is
        // gone, so it is the one that has to clear the bar. 'Continue', not 'Share
        // invite' -- the reference's label; see the note at the button.
        final buttonBottom = tester
            .getRect(find.byType(ElevatedActionButton))
            .bottom;
        final barTop = _screen.height - _glassTop(tester);

        expect(
          buttonBottom,
          lessThanOrEqualTo(barTop),
          reason: 'the sheet\'s only action was behind the tab bar',
        );
      },
    );

    testWidgets(
      'Given no shell bar above the sheet, When the primary action is measured, '
      'Then it does not float on reserved emptiness',
      (tester) async {
        // The reservation is conditional for a reason: this sheet also renders with
        // nothing over it (the mark preview, and any test), and 66pt of dead air at
        // the bottom of those would be the fix overshooting into its own defect.
        await _pump(tester, barVisible: false);

        final buttonBottom = tester
            .getRect(find.byType(ElevatedActionButton))
            .bottom;
        final floor = _screen.height - _bottomViewPadding;

        expect(floor - buttonBottom, lessThan(_glassTop(tester)));
      },
    );
  });

  group('the primary action is live on arrival', () {
    testWidgets(
      'Given the sheet has only just opened, When the button is inspected, Then it is '
      'enabled without waiting for a network call',
      (tester) async {
        // **The reported bug.** `create()` used to run in `initState` with the button
        // gated on its result, so the sheet's only action arrived greyed and woke up a
        // second or more later. The gate here never completes, which is the worst case:
        // even then the button must be pressable.
        final fake = await _pump(
          tester,
          barVisible: false,
          gate: Completer<void>(),
        );

        final button = tester.widget<ElevatedActionButton>(
          find.byType(ElevatedActionButton),
        );
        expect(button.activated, isTrue);
        expect(button.onPressed, isNotNull);
        // Nothing is minted until the reader asks for it, so opening and closing the
        // sheet no longer writes a row to `friend_invites`.
        expect(fake.creates, 0);
      },
    );

    testWidgets(
      'Given a tap is in flight, When it is tapped again, Then only one link is minted',
      (tester) async {
        final gate = Completer<void>();
        final fake = await _pump(tester, barVisible: false, gate: gate);
        _mockShareChannel(tester);

        await tester.tap(find.byType(ElevatedActionButton));
        await tester.pump();
        // Disabled *because a tap is in flight*, which is a state the reader caused --
        // unlike the arrival state above.
        expect(
          tester
              .widget<ElevatedActionButton>(find.byType(ElevatedActionButton))
              .activated,
          isFalse,
        );

        await tester.tap(find.byType(ElevatedActionButton), warnIfMissed: false);
        await tester.pump();
        expect(fake.creates, 1);

        gate.complete();
        await tester.pumpAndSettle();
        // Pressable again once the share sheet has been handed off.
        expect(
          tester
              .widget<ElevatedActionButton>(find.byType(ElevatedActionButton))
              .activated,
          isTrue,
        );
      },
    );
  });

  group('handing the link to the platform', () {
    testWidgets(
      'Given the sheet is open, When Share is tapped, Then the link and an anchor '
      'both reach the platform',
      (tester) async {
        final calls = _mockShareChannel(tester);
        await _pump(tester, barVisible: true);

        await tester.tap(find.byType(ElevatedActionButton));
        await tester.pump();

        expect(calls, hasLength(1));
        final args = calls.single.arguments as Map<Object?, Object?>;

        expect(calls.single.method, 'share');
        expect(args['text'], contains('https://libstack.app/i/K7M2QP4X'));

        // **The anchor is the actual regression guard here.** Without it iOS does not
        // fall back to a centred sheet — `FPPSharePlusPlugin.m:378-393` refuses the
        // presentation outright whenever a popover controller exists and the origin
        // is zero, which is every iPad. The failure is silent, so nothing but this
        // assertion would catch its removal.
        expect(
          args['originWidth'],
          isNotNull,
          reason: 'an unanchored share is a silent no-op on iPad',
        );
        expect(args['originWidth'], greaterThan(0));
        expect(args['originHeight'], greaterThan(0));
      },
    );

    testWidgets(
      'Given the platform refuses the share, When Share is tapped, Then the failure '
      'is surfaced rather than swallowed',
      (tester) async {
        // The defect this whole group exists for: the first version discarded both the
        // result and any exception, so a refused share was indistinguishable from a
        // dead button. "Nothing happened" was the entire bug report.
        _mockShareChannel(tester, fail: true);
        await _pump(tester, barVisible: true);

        await tester.tap(find.byType(ElevatedActionButton));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Two halves, and both matter. The exception must not escape …
        expect(tester.takeException(), isNull);
        // … and the reader must be told, which is the half that separates this from
        // an empty `catch`. Silence was the original defect.
        expect(find.text("Couldn't open the share sheet"), findsOneWidget);
      },
    );
  });
}
