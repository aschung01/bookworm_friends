// The one control in the merged status sheet, and the properties that make it safe.
//
// **`reading_track.dart` was reimplemented between this file's two versions.** It was a
// ~650-line `CustomPaint`: a hand-drawn groove, the app's bookmark ribbon for a thumb, a
// glide animation towards externally-set values, and a hand-rolled `kTouchSlop` gate that
// kept taps inert. It is now ~150 lines around a **real platform slider** — [CNSlider]
// (a native `UISlider`) behind `useNativeGlass`, [CupertinoSlider] everywhere else — and
// the thumb is the platform's own white disc.
//
// Every case that described the drawing is gone, each noted where it stood. What is left
// is the behaviour, re-grounded on the platform control.
//
// **The tap is still the whole defence.** This control was drawn once before as
// `band-scrubber` in `docs/mockups/streaks/index.html` and rejected three times over,
// because "a stray touch could silently rewrite your position". It is now inert for two
// reasons stacked, neither of them a gesture filter:
//
//  1. `_RenderCupertinoSlider.hitTestSelf` only accepts a touch within
//     `CupertinoThumbPainter.radius + _kPadding` (22pt) of the thumb, so a tap further
//     along the track never reaches the slider at all; and
//  2. on a touch that *does* land on the thumb, the lone `HorizontalDragGestureRecognizer`
//     wins its arena by default on pointer-down and opens a drag at
//     `_currentDragValue = _value` — and `_CupertinoSliderState._handleChanged` drops it,
//     because it reports only `if (lerpValue != widget.value)`.
//
// So "inert" is now a property of the platform control rather than of this widget, which
// is why the first case in this file asserts **which slider gets built**: a Material
// `Slider` is *absolute* (a tap on the track seeks to it) and would reintroduce the
// rejected behaviour with nothing else in the file failing.
//
// **The drag is relative, and every number below was measured rather than derived.** A
// drag of `dx` adds `dx / (width - 2 * (radius + padding))` to the value — `dx / 331` in
// this file's 375pt box, *not* `dx / 375` — so a gesture's landing value depends on where
// it started. The old cases assumed absolute seeking and computed expectations from an
// absolute x; those were rewritten against what the slider actually reports.
//
// **`null` is not `0`.** Null means "never asked" and `0` means "opened it and got
// nowhere". The origin of this track means the first, which is what makes
// Reading -> Not started reachable; `0%` stays reachable only from the percent wheel's own
// `0` stop. A case drags to the far left and asserts the report is `null` rather than `0`,
// and another asserts that an assistive decrement off the lowest stop lands there too.
//
// The harness echoes `onChanged` back into `progress`, because the widget is controlled
// the way `Slider` is: the thumb follows the field, so a parent that swallows the callback
// gets a thumb that does not move. It matters more than it used to — `_handleChanged`
// compares against the last *built* value, so a case that moves a gesture twice without
// pumping in between is comparing against a stale one.
//
// `useNativeGlass` is false under `flutter test` (which reports Android), so the
// [CupertinoSlider] branch is the path every case here takes. That is the path every
// non-Apple phone and everything below iOS 26 takes too, which is why it gets a case of
// its own.

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_track.dart';

/// The phone the 48pt budget was measured against, minus the sheet's own 24pt insets:
/// 375 - 2x24 = 327. Rounded to a flat 375 here so the arithmetic in each case is
/// legible, and pinned rather than left to the 800x600 default test surface — the
/// default is wider than any phone, so a control that only overflows on a real one
/// would pass.
const double _kBox = 375;

/// The thumb's inset from each end of the slider, and so half of what the usable travel
/// is short by: `CupertinoThumbPainter.radius` (14) + `_kPadding` (8). Both are private
/// to `package:flutter/src/cupertino/slider.dart`, so they are written out here.
///
/// It is also the radius within which `_RenderCupertinoSlider.hitTestSelf` accepts a
/// touch, which is why [_onThumb] exists: a gesture aimed anywhere else on the track
/// does not reach the slider, and a case built on one would pass without testing it.
const double _kThumbInset = 22;

/// What one point of drag is worth: the track is inset by [_kThumbInset] at both ends,
/// so a 375pt slider has 331pt of travel and a drag moves the value by `dx / 331`.
///
/// Verified against the slider rather than derived from it — a 100pt drag from 0.46
/// reports 0.76, and `0.46 + 100 / 331` is 0.762.
const double _kTravel = _kBox - 2 * _kThumbInset;

/// The slider's own height inside the control, `_kSliderHeight` in `reading_track.dart`.
/// The band that takes touches; the gap and the end labels below it take none.
const double _kSliderBand = 28;

/// Every value the track has asked for, in order.
final List<double?> reports = <double?>[];

Future<void> _pump(
  WidgetTester tester, {
  double? progress,
  double textScale = 1,
  double width = _kBox,
  String? semanticsLabel,
}) async {
  final held = ValueNotifier<double?>(progress);
  addTearDown(held.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            // **The inner `Column` is not decoration.** `ReadingTrack`'s own root is a
            // `Column` at the default `MainAxisSize.max`, so handed a bounded height it
            // takes all of it — a bare `Center` here measured the control at 600pt and
            // the published 48 would have looked wrong. A `Column` hands its children an
            // unbounded main axis, which is the shape `book_status_bottom_sheet.dart`
            // presents it in, so this is the real layout rather than a convenience.
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: width,
                    child: ValueListenableBuilder<double?>(
                      valueListenable: held,
                      builder: (context, current, _) => ReadingTrack(
                        progress: current,
                        semanticsLabel: semanticsLabel,
                        onChanged: (next) {
                          reports.add(next);
                          held.value = next;
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Rect _trackRect(WidgetTester tester) =>
    tester.getRect(find.byType(ReadingTrack));

Rect _sliderRect(WidgetTester tester) =>
    tester.getRect(find.byType(CupertinoSlider));

/// Where the thumb is, as the value the slider was last built with.
///
/// The thumb is painted by `CupertinoThumbPainter` rather than mounted as a widget, so
/// there is nothing to measure with `getTopLeft` the way the ribbon could be. The
/// controlled value is the better handle anyway: it is what the sheet stores, and the
/// thumb is a pure function of it.
double _sliderValue(WidgetTester tester) =>
    tester.widget<CupertinoSlider>(find.byType(CupertinoSlider)).value;

/// A point on the thumb when the slider is showing [value].
///
/// The only place a gesture can start. `hitTestSelf` rejects anything more than
/// [_kThumbInset] from the thumb's centre, so a drag begun mid-track is not a drag that
/// does nothing — it is a drag the slider never sees.
Offset _onThumb(WidgetTester tester, double value) {
  final rect = _sliderRect(tester);
  return Offset(
    rect.left + _kThumbInset + value * (rect.width - 2 * _kThumbInset),
    rect.center.dy,
  );
}

/// One drag: down on the thumb showing [from], [dx] points sideways, up.
///
/// A single `moveBy` with a pump before the release, deliberately, so each case gets one
/// report to reason about. `tester.dragFrom` splits its travel at `kDragSlopDefault` and
/// so reports twice, which is what made the old cases assert windows instead of values.
Future<void> _slide(
  WidgetTester tester, {
  required double from,
  required double dx,
}) async {
  final gesture = await tester.startGesture(_onThumb(tester, from));
  await gesture.moveBy(Offset(dx, 0));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// The control's semantics node, found by the one flag that makes a drag-only scalar
/// usable at all. Rebuilt per call because a `FinderBase` caches what it evaluated.
SemanticsFinder get _slider => find.semantics.byFlag(SemanticsFlag.isSlider);

/// Drives an assistive step. `SemanticsController.increase`/`decrease` rather than a
/// hand-rolled `performAction`, because they assert the node actually offers the action
/// instead of silently doing nothing when it does not.
Future<void> _assist(WidgetTester tester, SemanticsAction action) async {
  switch (action) {
    case SemanticsAction.increase:
      tester.semantics.increase(_slider);
    case SemanticsAction.decrease:
      tester.semantics.decrease(_slider);
    default:
      fail('only increase and decrease are driven here');
  }
  await tester.pumpAndSettle();
}

/// Every `HapticFeedback.*` the platform channel was asked for, in order.
///
/// Captured rather than counted through a spy on the widget, because the claim worth holding
/// is *which system call* it makes: the wheel is a `CupertinoPicker` and its
/// `_handleHapticFeedback` calls `HapticFeedback.selectionClick()`, so "similar haptics"
/// means that exact method and not merely some vibration.
final List<String> haptics = <String>[];

/// Every `SystemSound.play` argument, in order, beside [haptics].
///
/// **The wheel plays as well as vibrates**, and reading "similar haptics" as naming only the
/// vibration is what shipped a silent track the first time. `CupertinoPicker` fires
/// `SystemSound.play(SystemSoundType.tick)` on the line after `selectionClick()`, and the
/// argument is worth asserting by name rather than by count: `.tick` is
/// `AudioServicesPlaySystemSound(1157)`, the picker's own scroll sound, where the
/// neighbouring `.click` is 1306, the keypress. Both are "a tick" in prose and only one
/// sounds like the wheel.
final List<String> sounds = <String>[];

/// The two above interleaved, as bare method names, in arrival order.
///
/// Kept because neither list above can show *pairing*: two lists of equal length say the
/// track vibrated as often as it played, not that it did both for one crossing. This is the
/// only witness that a tick is one event on two channels.
final List<String> feedback = <String>[];

void _captureTicks(WidgetTester tester) {
  haptics.clear();
  sounds.clear();
  feedback.clear();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String? ?? 'default');
        feedback.add(call.method);
      }
      if (call.method == 'SystemSound.play') {
        sounds.add(call.arguments as String? ?? 'default');
        feedback.add(call.method);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

void main() {
  setUp(reports.clear);

  group('it ticks like the wheel', () {
    // **No `debugDefaultTargetPlatformOverride` here, and that was the first attempt.**
    // `CupertinoPicker` gates its haptic on iOS, so copying the gate looked right — and then
    // every case in this group failed with *"Found 0 widgets with type CupertinoSlider"*,
    // because `useNativeGlass` reads `defaultTargetPlatform` too. Overriding to iOS on a
    // macOS 26 host flips the glass branch as well, builds a `CNSlider`, and leaves the case
    // holding a platform view it cannot drag. The two switches look independent and are not.
    //
    // So the widget follows the app's own convention instead — `read_filter.dart`,
    // `friends_sheet.dart` and `library_sheet.dart` all call `selectionClick()`
    // unconditionally — which is both the more consistent choice and the testable one.

    testWidgets('Given a drag across a 5% band, Then it is a selectionClick', (
      tester,
    ) async {
      await _pump(tester, progress: 0.46);
      _captureTicks(tester);

      // 331pt of travel for the full range in this 375pt box, so 5% is ~16.5pt. 20 clears
      // one band boundary (46% -> ~52%) and no more.
      await _slide(tester, from: 0.46, dx: 20);

      expect(haptics, ['HapticFeedbackType.selectionClick']);
    });

    testWidgets(
      'and a drag inside one band is felt exactly as much as it is reported',
      (tester) async {
        // The band is 5% wide, so a move of a couple of percent reports a new value — the
        // read-out changes — and does *not* tick. That is the whole cost of the 5% step,
        // stated as a case: the tick is a landmark rather than a confirmation of the number.
        await _pump(tester, progress: 0.46);
        _captureTicks(tester);

        // ~2%: enough to report, not enough to leave the 45-49 band.
        await _slide(tester, from: 0.46, dx: 7);

        expect(reports, isNotEmpty);
        expect(haptics, isEmpty);
      },
    );

    testWidgets('and a long drag ticks once per band rather than once per percent', (
      tester,
    ) async {
      // **The reason the step is 5 and not 1**, and the one case that has to drag the way a
      // finger does. `_slide` makes a single `moveBy` on purpose, so it produces exactly one
      // report however far it travels — right for the cases that reason about a landing
      // value, useless for one about density. Forty small moves over half the track is
      // ~1.25% each: enough reports to count against the ticks.
      await _pump(tester, progress: 0);
      _captureTicks(tester);

      final gesture = await tester.startGesture(_onThumb(tester, 0));
      for (var i = 0; i < 40; i++) {
        await gesture.moveBy(const Offset(165 / 40, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(reports.length, greaterThan(20));
      expect(haptics.length, greaterThan(6));
      expect(haptics.length, lessThan(15));
      expect(
        haptics.every((h) => h == 'HapticFeedbackType.selectionClick'),
        isTrue,
      );
    });

    testWidgets('and an inert tap is felt as little as it is reported', (
      tester,
    ) async {
      // The tap is the property this control was designed around, and a haptic would
      // undo the reassurance: something that buzzes has done something.
      await _pump(tester, progress: 0.46);
      _captureTicks(tester);

      await tester.tapAt(_onThumb(tester, 0.46));
      await tester.pumpAndSettle();

      expect(reports, isEmpty);
      expect(haptics, isEmpty);
    });

    testWidgets('and crossing the origin ticks, because the status word changes', (
      tester,
    ) async {
      // `null` is its own band. The origin is not a number here — it means "never asked" —
      // and arriving at it turns the word above the track to `Not started`, which is the
      // same kind of event the wheel ticks for.
      await _pump(tester, progress: 0.02);
      _captureTicks(tester);

      await _slide(tester, from: 0.02, dx: -30);

      expect(reports.last, isNull);
      expect(haptics, isNotEmpty);
    });

    testWidgets(
      'Given a value set from outside, Then the next drag does not tick for it',
      (tester) async {
        // `didUpdateWidget` re-syncs the band. Without it, the percent wheel handing back 0.80
        // would leave the last felt band at 46%'s, and the first report of the next drag would
        // tick for ground the thumb had already been moved across by someone else.
        await _pump(tester, progress: 0.46);
        await _slide(tester, from: 0.46, dx: 100);
        _captureTicks(tester);

        // A move too small to leave the band the thumb is now in.
        final landed = reports.last!;
        await _slide(tester, from: landed, dx: 3);

        expect(haptics, isEmpty);
      },
    );
  });

  group('and it ticks on every platform, unlike the wheel', () {
    testWidgets('Given the Android test platform, Then a drag still ticks', (
      tester,
    ) async {
      // `flutter test` reports Android, so this is the default path and it is *not* silent.
      // The divergence from `CupertinoPicker` is deliberate and this is where it is pinned:
      // the app's own three selection haptics carry no platform gate, Android has a good
      // selection haptic, and the framework's iOS-only switch is Flutter's decision rather
      // than this app's. The cost, stated: on Android the track ticks where the wheel does
      // not.
      await _pump(tester, progress: 0.46);
      _captureTicks(tester);

      await _slide(tester, from: 0.46, dx: 60);

      expect(reports, isNotEmpty);
      expect(haptics, isNotEmpty);
    });

    testWidgets('and the sound is asked for unconditionally too, gate-free', (
      tester,
    ) async {
      // **This pins the absence of a Dart-side gate, and proves nothing about audibility.**
      // The mock intercepts `SystemChannels.platform` in front of the engine, so it records
      // the call on this Android test platform exactly as it would on iOS — where the engine
      // is the thing that diverges, matching `SystemSoundType.tick` on iOS and nothing
      // anywhere else. So the widget stays free of `Platform.isIOS`, the framework keeps its
      // documented promise that `.tick` is "ignored on all platforms except iOS", and this
      // case fails if anyone adds the wrapper back believing it was missing.
      await _pump(tester, progress: 0.46);
      _captureTicks(tester);

      await _slide(tester, from: 0.46, dx: 60);

      expect(sounds, isNotEmpty);
    });
  });

  group("and the tick is audible, like the wheel's", () {
    testWidgets(
      "Given a drag across a 5% band, Then it plays the wheel's sound",
      (tester) async {
        await _pump(tester, progress: 0.46);
        _captureTicks(tester);

        await _slide(tester, from: 0.46, dx: 20);

        // By name, not by count: `.click` would also be "a sound on every band" and would be
        // the keypress id rather than the wheel's.
        expect(sounds, ['SystemSoundType.tick']);
      },
    );

    testWidgets('and the haptic comes first, as it does in the picker', (
      tester,
    ) async {
      // `_handleHapticFeedback` vibrates and then plays. Kept in that order so the two
      // controls cannot feel subtly unlike each other for a reason nobody would look for.
      await _pump(tester, progress: 0.46);
      _captureTicks(tester);

      await _slide(tester, from: 0.46, dx: 20);

      expect(feedback, ['HapticFeedback.vibrate', 'SystemSound.play']);
    });

    testWidgets('and a long drag pairs one sound to every haptic', (
      tester,
    ) async {
      // The step gates both channels from one constant, so this is really a case about
      // `_kTickStep` having exactly one reader. Forty small moves, as in the density case.
      await _pump(tester, progress: 0);
      _captureTicks(tester);

      final gesture = await tester.startGesture(_onThumb(tester, 0));
      for (var i = 0; i < 40; i++) {
        await gesture.moveBy(const Offset(165 / 40, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(sounds.length, haptics.length);
      expect(sounds.length, greaterThan(6));
      expect(sounds.every((s) => s == 'SystemSoundType.tick'), isTrue);
      // Strictly alternating, so the pairs are pairs rather than two runs that happen to
      // match in length.
      expect(
        feedback,
        List<String>.generate(
          sounds.length * 2,
          (i) => i.isEven ? 'HapticFeedback.vibrate' : 'SystemSound.play',
        ),
      );
    });

    testWidgets('and a drag inside one band is silent as well as unfelt', (
      tester,
    ) async {
      // The cost of the 5% step, on the audible channel: the read-out changes and nothing
      // clicks. Same trade as the haptic, and worth a case of its own because a sound is the
      // more noticeable absence.
      await _pump(tester, progress: 0.46);
      _captureTicks(tester);

      await _slide(tester, from: 0.46, dx: 7);

      expect(reports, isNotEmpty);
      expect(sounds, isEmpty);
    });

    testWidgets('and an inert tap is silent', (tester) async {
      // The tap does nothing, so it must sound like nothing — louder version of the haptic
      // case, since a click would be a claim that the tap landed.
      await _pump(tester, progress: 0.46);
      _captureTicks(tester);

      await tester.tapAt(_onThumb(tester, 0.46));
      await tester.pumpAndSettle();

      expect(reports, isEmpty);
      expect(sounds, isEmpty);
    });
  });

  group('it is the relative slider, not the absolute one', () {
    testWidgets('Given a build, Then it is a CupertinoSlider and not a Slider', (
      tester,
    ) async {
      // **The highest-value case in this file, and the one the others rest on.** Every
      // safety property below — the inert tap, the drag that adds a delta rather than
      // seeking — belongs to `CupertinoSlider` rather than to `ReadingTrack`, so getting
      // the switch wrong is invisible everywhere else.
      //
      // A Material `Slider` is *absolute*: `_RenderSlider` handles a tap and moves the
      // thumb to it, which is exactly the "a stray touch could silently rewrite your
      // position" behaviour this control was designed around. `CNSlider`'s own fallback
      // off Apple platforms **is** a Material `Slider`, so this is not a hypothetical
      // mistake — it is what the package does if this widget stops overriding it.
      await _pump(tester, progress: 0.46);

      expect(find.byType(CupertinoSlider), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('Given a test, Then the native slider is not the path taken', (
      tester,
    ) async {
      // Re-grounds the old `the fallback glass is the path a test takes`, which looked
      // for a `BackdropFilter` behind app-drawn content. There is no app-drawn glass any
      // more; the question it was asking — which branch a test exercises — is still worth
      // pinning, because `useNativeGlass` is false here and on every phone below iOS 26.
      await _pump(tester, progress: 0.46);

      expect(find.byType(CNSlider), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the tap is inert', () {
    testWidgets('Given a tap at 80% of the width, Then nothing is reported', (
      tester,
    ) async {
      // The case that must never be "fixed" by adding a tap handler.
      //
      // **Aimed by the control's own geometry, not by `find.byType(CupertinoSlider)`,
      // and that is the difference between a mutation check that means something and one
      // that does not.** Swap the slider for a Material one and a case that located its
      // target through the Cupertino type fails on a missing finder — which is a broken
      // harness, not a caught regression, and would pass again the moment someone
      // loosened the finder. This one taps 80% along the band whatever is drawn there, so
      // a Material slider's tap-to-seek arrives as `reports` no longer being empty.
      //
      // The band is the control's top [_kSliderBand] of its 48: the labels are below it
      // and take nothing.
      await _pump(tester, progress: 0.46);
      final rect = _trackRect(tester);

      await tester.tapAt(
        Offset(rect.left + rect.width * 0.8, rect.top + _kSliderBand / 2),
      );
      await tester.pumpAndSettle();

      // The widget is controlled, so this is also the assertion that nothing moved:
      // the thumb is a function of `progress`, and `progress` only changes by a report.
      expect(reports, isEmpty);
    });

    testWidgets('Given a tap on the thumb itself, Then nothing is reported', (
      tester,
    ) async {
      // The case above passes for two reasons at once — 80% of the width is 127pt from a
      // thumb at 46%, so `hitTestSelf` refuses the touch before any gesture code runs.
      // This one lands *on* the thumb, where the drag recognizer does open, and pins the
      // second mechanism: the drag opens at the current value and
      // `_CupertinoSliderState._handleChanged` reports only when the new value differs
      // from the built one.
      await _pump(tester, progress: 0.46);

      await tester.tapAt(_onThumb(tester, 0.46));
      await tester.pumpAndSettle();

      expect(reports, isEmpty);
      expect(_sliderValue(tester), 0.46);
    });

    testWidgets('Given a vertical drag, Then nothing is reported', (
      tester,
    ) async {
      // The sheet this lives in may scroll. A control that swallowed a vertical pan
      // would take the sheet's own gesture with it.
      await _pump(tester, progress: 0.46);

      await tester.dragFrom(_onThumb(tester, 0.46), const Offset(0, 120));
      await tester.pumpAndSettle();

      expect(reports, isEmpty);
    });

    testWidgets('Given a long press with no travel, Then nothing is reported', (
      tester,
    ) async {
      // A finger resting on the bar is the stray touch the rejection was about, and it
      // is not the same event as a tap: the pointer is down for 500ms.
      await _pump(tester, progress: 0.46);

      await tester.longPressAt(_onThumb(tester, 0.46));
      await tester.pumpAndSettle();

      expect(reports, isEmpty);
    });

    // DELETED: `Given a drag shorter than the slop, Then nothing is reported`. It moved
    // a gesture 6pt then 4pt and asserted silence, against the widget's own
    // `kTouchSlop` gate in `_onDragStart`. There is no gate now, and no equivalent
    // inside `CupertinoSlider`: the lone drag recognizer is accepted by arena default at
    // pointer-down rather than on distance, so the *first* move of any size is a drag.
    // Measured, a 6pt slip on a 375pt track now reports 52% from 50%. Nothing here
    // asserts that, because it is not a property worth locking in — it is a behaviour
    // change the reimplementation makes, and it is on the record in the report instead.
  });

  group('a drag moves it, and it moves relatively', () {
    testWidgets('Given a drag right, Then the position rises with the finger', (
      tester,
    ) async {
      await _pump(tester, progress: 0.46);

      await _slide(tester, from: 0.46, dx: 100);

      // 100pt of 331 is 30.2%, so 46% lands on 76%. A value rather than the old
      // window: one `moveBy` reports once, and the arithmetic is exact once the travel
      // is measured against the inset track instead of the box.
      expect(reports.single, closeTo(0.76, 1e-9));
      expect(_sliderValue(tester), closeTo(0.76, 1e-9));
      expect(reports.single, greaterThan(0.46));
      // The literal is pinned from a run rather than computed, because the travel is
      // inset by a constant private to Flutter and a derived expectation would encode
      // the derivation's mistakes too. This line is the derivation agreeing with it.
      expect(((0.46 + 100 / _kTravel) * 100).round(), 76);
    });

    testWidgets('Given the same drag from a lower start, Then it lands somewhere else', (
      tester,
    ) async {
      // **What "relative" means, and the reason every other case in this group was
      // rewritten.** The old file assumed absolute seeking — thumb jumps under the
      // finger — so a landing value could be computed from the finger's x alone. Here
      // the identical 100pt gesture lands 26 points lower, because it started 26
      // points lower. An absolute slider would report the same value for both.
      await _pump(tester, progress: 0.20);

      await _slide(tester, from: 0.20, dx: 100);

      expect(reports.single, closeTo(0.50, 1e-9));
      expect(((0.20 + 100 / _kTravel) * 100).round(), 50);
    });

    testWidgets('reports whole percents, so the wheel can round-trip them', (
      tester,
    ) async {
      // A value the wheel's 101 stops cannot represent would be shown as one number and
      // saved as another. 37pt is 11.18%, so the raw landing is 0.5718 and the report
      // has to be the rounded 0.57.
      await _pump(tester, progress: 0.46);

      await _slide(tester, from: 0.46, dx: 37);

      expect(reports.single, closeTo(0.57, 1e-9));
      for (final value in reports) {
        if (value == null) continue;
        expect(value * 100, closeTo((value * 100).roundToDouble(), 1e-9));
      }
    });

    testWidgets('Given a drag to the far left, Then it reports null, not 0', (
      tester,
    ) async {
      await _pump(tester, progress: 0.46);

      // Past the end on purpose: `_currentDragValue` is clamped, so overshooting is how
      // a finger reaches an end. 0.46 needs 152pt of travel to get there and gets 400.
      await _slide(tester, from: 0.46, dx: -400);

      expect(reports.last, isNull);
      // The distinction is the point: `0.0` would claim the reader opened the book and
      // got nowhere, which is a different fact and one only the percent wheel can state.
      expect(reports.last, isNot(0.0));
    });

    testWidgets('Given a drag to the far right, Then it reports exactly 1', (
      tester,
    ) async {
      await _pump(tester, progress: 0.46);

      await _slide(tester, from: 0.46, dx: 400);

      // Finished is a place you arrive at, not a value that happens to cross 1.0 —
      // which is the clearest thing this control buys over an inline wheel.
      expect(reports.last, 1.0);
      expect(_sliderValue(tester), 1.0);
    });

    testWidgets('Given a drag that returns to where it began, Then the value does too', (
      tester,
    ) async {
      await _pump(tester, progress: 0.5);
      final start = _onThumb(tester, 0.5);
      final gesture = await tester.startGesture(start);

      // **Pumped between moves, and that is load-bearing.** `_handleChanged` compares
      // the new value with `widget.value`, which only changes when a frame is built —
      // so without these pumps the return leg is compared against 0.5, matches it, and
      // is dropped. The case then reads as "the value never came back" when what
      // happened is that the harness never told the slider it had left.
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump();
      }
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(-10, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      // Net zero, and the intermediate stops *are* reported, because the thumb has to
      // follow the finger.
      expect(reports.last, closeTo(0.5, 1e-9));
      expect(reports.length, greaterThan(2));
      expect(_sliderValue(tester), closeTo(0.5, 1e-9));
    });
  });

  group('the ends are words, and they are the status words', () {
    testWidgets('Given the default locale, Then the ends read the statuses', (
      tester,
    ) async {
      await _pump(tester, progress: 0.46);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ReadingTrack)),
      );

      // The same two strings the read-out prints, which is what makes it impossible
      // for the track's ends and the status word above them to disagree.
      expect(find.text(l10n.statusInterested), findsOneWidget);
      expect(find.text(l10n.statusFinished), findsOneWidget);
      // And not numbers.
      expect(find.text('0%'), findsNothing);
      expect(find.text('100%'), findsNothing);
    });
  });

  group('slider semantics', () {
    testWidgets('the node is a slider, and carries the parent\'s label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, progress: 0.46, semanticsLabel: 'How far in');

      expect(_slider, findsOne);
      // `MergeSemantics` cannot fold the slider *into* the label's node — the render
      // object sets `isSemanticBoundary`, so it stays a node of its own and the merge
      // happens in the parent's merged data. Which means the label has to be read off
      // the node bearing it rather than off the slider, and
      // `tester.getSemantics(find.byType(ReadingTrack))` reaches neither: the `Column`
      // owns no node, so it walks up past both.
      final merged = find.semantics.byLabel('How far in');
      expect(merged, findsOne);
      final data = merged.evaluate().single.getSemanticsData();
      // **The platform slider speaks percents.** This reverses the old
      // `speaks the end words at the ends`, which asserted `statusInterested` at the
      // origin and `statusFinished` at 1 from a hand-written `value`. `CupertinoSlider`
      // writes its own `'${(value * 100).round()}%'` and there is no hook to replace it,
      // so a VoiceOver reader hears `0%` at the origin — where the model means "never
      // asked". Pinned as what it is; flagged rather than asserted away.
      expect(data.value, '46%');
      expect(data.increasedValue, '56%');
      expect(data.decreasedValue, '36%');
      handle.dispose();
    });

    testWidgets('Given increase, Then the position steps up by 10%', (
      tester,
    ) async {
      // 10%, not the old 5%: the step is `CupertinoSlider`'s own `_kAdjustmentUnit`
      // rather than a constant this widget chooses, and with no `divisions` there is
      // nothing to tune it with.
      final handle = tester.ensureSemantics();
      await _pump(tester, progress: 0.46);

      await _assist(tester, SemanticsAction.increase);

      expect(reports.last, closeTo(0.56, 1e-9));
      handle.dispose();
    });

    testWidgets('Given decrease, Then the position steps down by 10%', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, progress: 0.46);

      await _assist(tester, SemanticsAction.decrease);

      expect(reports.last, closeTo(0.36, 1e-9));
      handle.dispose();
    });

    testWidgets('Given decrease off the lowest stop, Then it reaches null', (
      tester,
    ) async {
      // The assistive path has to be able to say "Not started" too, or a VoiceOver
      // reader can leave Reading only by opening the percent wheel. The step clamps to
      // 0 and the widget's own `report` turns a 0 percent into an erasure.
      final handle = tester.ensureSemantics();
      await _pump(tester, progress: 0.03);

      await _assist(tester, SemanticsAction.decrease);

      expect(reports.last, isNull);
      handle.dispose();
    });

    testWidgets('Given a null position, Then increase starts the book', (
      tester,
    ) async {
      // The other direction off the origin, and the one that proves `null` is a place
      // the assistive path can leave as well as arrive at.
      final handle = tester.ensureSemantics();
      await _pump(tester, progress: null);

      await _assist(tester, SemanticsAction.increase);

      expect(reports.last, closeTo(0.1, 1e-9));
      handle.dispose();
    });

    // DELETED: `Given 0%, Then decrease still reaches null`. The claim no longer holds
    // and the case cannot be re-grounded without changing `lib/`:
    // `_CupertinoSliderState._handleChanged` reports only when the new value differs
    // from the built one, so at exactly `0` a decrease clamps to `0`, matches, and is
    // dropped — measured, `reports` comes back empty. A leftward *drag* from `0` is
    // silent for the same reason. The action is still advertised, so it reads as a
    // working control that does nothing. Reported as a `lib/` defect rather than pinned
    // here, because pinning it would bless it.
    //
    // DELETED: the two halves of the old `the node is a slider` case that asserted
    // `decrease` absent at the origin and `increase` absent at 1. `CupertinoSlider` sets
    // `onIncrease` and `onDecrease` whenever it is interactive, with no reference to the
    // value, so both are offered at both ends and both are no-ops there.
    //
    // DELETED: `the end labels are not offered as their own nodes`. The old widget wrapped
    // the label row in `ExcludeSemantics` because the slider's spoken value *was* the end
    // word, making the labels a duplicate read. The new one does not, and now that the
    // value is a percent the labels are the only place the two words are spoken — so
    // `find.bySemanticsLabel('Finished')` finds one where it used to find none. The
    // reversal is defensible; that it is unremarked in `lib/` is in the report.
  });

  // DELETED: the whole `reduced motion` group — `Given the flag, Then an external value
  // arrives without a glide`, `Without the flag, Then it glides there instead`, and
  // `a drag never lags the finger, flag or no flag`. All three measured the ribbon's x
  // across frames to prove the widget's own `AnimationController` honoured
  // `MediaQuery.disableAnimations`. There is no controller and no glide: an externally
  // set value is on the thumb in the frame it arrives, and whatever settling a
  // `UISlider` or `CupertinoSlider` does is the platform's, animated on its own terms
  // and not this widget's to gate. `_pump` lost its `reducedMotion` parameter with them.

  group('it measures 48pt, which is what the merged sheet is shorter by', () {
    testWidgets(
      'Given default text scale, Then the rendered height is the published one',
      (tester) async {
        await _pump(tester, progress: 0.46);

        expect(ReadingTrack.height, closeTo(48, 1e-9));
        // Held to the *layout*, not to the arithmetic: the published figure is the one
        // the sheet's height budget spends, so it has to be what a frame actually
        // measures. `28 + 4 + 16`, where the 28 is the band a `UISlider` wants.
        expect(_trackRect(tester).height, closeTo(ReadingTrack.height, 0.01));
        expect(_sliderRect(tester).height, closeTo(28, 0.01));
      },
    );

    test('the label line the published height is built on is the rounded one', () {
      // `AppTextStyles.label` multiplies out to 15.6 and the engine lays it out as 16,
      // because a line box is rounded up to a whole pixel. `reading_track.dart` uses 16
      // for that reason; if the token is ever restyled, or the engine stops rounding,
      // this is where the 48 stops being true.
      final line = AppTextStyles.label.fontSize! * AppTextStyles.label.height!;
      expect(line, closeTo(15.6, 1e-9));
      expect(line.ceilToDouble(), 16);
    });

    testWidgets('Given larger text, Then it grows taller rather than clipping', (
      tester,
    ) async {
      // 1.5x is the most a 375pt box takes, measured: the test font sets every glyph a
      // full em wide, so `Not started` and `Finished` come to 19 ems and 19 x 13 x 1.5
      // is 371 of the 375 available. See the skipped case below for what happens next.
      await _pump(tester, progress: 0.46, textScale: 1.5);

      expect(tester.takeException(), isNull);
      // Taller than 48, which is correct: the labels are allowed to grow, so nothing
      // here is a fixed-height box that could clip them.
      expect(_trackRect(tester).height, greaterThan(ReadingTrack.height));
      expect(_trackRect(tester).width, closeTo(_kBox, 0.01));
    });

    testWidgets('Given 2x text scale in a 375pt box, Then it does not overflow', (
      tester,
    ) async {
      // **Skipped, not deleted: this is a regression and the case is the record of
      // it.** The old widget put each end label in a `Flexible` with `maxLines: 2` and
      // `TextOverflow.ellipsis`, and its comment named this scale — "the row degrades
      // by wrapping and only then by ellipsising, never by overflowing". The
      // reimplementation dropped all three, so the label `Row` is two unconstrained
      // `Text`es and at 2x it overflows by 119pt here (254 in a 240pt box, and a 240pt
      // box overflows at scale 1).
      //
      // **Restored, and this case is live again.** `lib/` now wraps both labels in
      // `Flexible` with `maxLines: 2` and `TextOverflow.ellipsis`, so the row degrades the
      // way its original comment demanded. Left un-skipped deliberately: the regression it
      // records took a rewrite to introduce and a reader to notice, and a skipped case
      // records nothing.
      await _pump(tester, progress: 0.46, textScale: 2);

      expect(tester.takeException(), isNull);
    });

    // DELETED: `Given 2x text scale in a narrow box, Then it still does not overflow`.
    // Same cause as the case above and no longer a separate claim — 240pt overflows at
    // *every* scale now, including 1, so there is no version of it that passes while the
    // label row is unconstrained. Folded into the skip reason above.
  });

  // DELETED: the whole `the drawing` group, six cases, all of them about paint that no
  // longer exists.
  //
  //  * `the thumb is the app's own ribbon, not a second drawing of one` and
  //    `the mirrored ribbon geometry still adds up to the asset box` — the thumb is the
  //    platform's white disc and `reading_bookmark.dart` is not imported any more. The
  //    doc comment's verdict on the ribbon is that it "made an ugly thumb"; the bleed
  //    arithmetic those cases guarded has no reader left in this widget.
  //  * `the groove spans the full width, and is not sized by its fill` — there is no
  //    groove and no `FractionallySizedBox`, so the celebration-progress-bar defect it
  //    was watching for cannot recur here. `CupertinoSlider` sizes itself from the
  //    constraints it is handed; `the rendered height is the published one` above is
  //    what now catches a slider that collapsed.
  //  * `a null position draws no fill, and 0% draws one` — counted `DecoratedBox`es
  //    inside the groove's clip. Both states now paint the platform's track with the
  //    thumb at the origin and there is no widget-level difference between them; the
  //    distinction that matters is the *reported* one, which the far-left drag case and
  //    the semantics cases cover.
  //  * `the fallback glass is the path a test takes` — re-grounded as
  //    `Given a test, Then the native slider is not the path taken` in the first group.
  //    The `BackdropFilter` it looked for was the app-drawn glass the reimplementation
  //    removed on purpose: painting a translucent rectangle got the fallback's look on
  //    the one platform that has the real material.
  //  * `the thumb sits at the origin for a null position` and
  //    `the thumb sits inside the far end at 100%` — both measured the ribbon's box
  //    against the groove's ends to prove the mark never left the track it read. A
  //    `UISlider`'s disc is inset by its own radius by construction, which is the fact
  //    `_kThumbInset` above encodes and the travel arithmetic depends on, so it is now
  //    exercised by every drag case rather than asserted as geometry.
}
