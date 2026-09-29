// The one control in the merged status sheet, and the properties that make it safe.
//
// **The tap is the whole defence.** This control was drawn once before as
// `band-scrubber` in `docs/mockups/streaks/index.html` and rejected three times over,
// because "a stray touch could silently rewrite your position". The house answer there
// was arming — tap to arm, then drag, with a Cancel — and the inert tap reaches the same
// safety one tap cheaper. So the first case here is a tap at 80% of the width reporting
// nothing, and it is the case that must never be "fixed" by adding a tap handler.
//
// **`null` is not `0`.** Null means "never asked" and `0` means "opened it and got
// nowhere". The origin of this track means the first, which is what makes
// Reading -> Not started reachable; `0%` stays reachable only from the percent wheel's
// own `0` stop. A test drags to the far left and asserts the report is `null` rather
// than `0`, and another asserts that an assistive decrement off the lowest stop lands
// there too.
//
// **The assistive path does what the touch path refuses**, deliberately: an explicit
// increment aimed at a focused slider is not a stray touch. Both are exercised here so
// that the asymmetry is on the record as intended rather than as an omission.
//
// The harness echoes `onChanged` back into `progress`, because the widget is controlled
// the way `Slider` is: the thumb follows the field, so a parent that swallows the
// callback gets a thumb that does not move. Testing it any other way would test a
// contract the widget does not have.
//
// `useNativeGlass` is false under `flutter test` (which reports Android), so the
// fallback glass is the path every case here takes. That is the path most phones take
// too, which is why it gets a case of its own.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_bookmark.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_track.dart';

/// The phone the 48pt budget was measured against, minus the sheet's own 24pt insets:
/// 375 - 2x24 = 327. Rounded to a flat 375 here so the arithmetic in each case is
/// legible, and pinned rather than left to the 800x600 default test surface — the
/// default is wider than any phone, so a control that only overflows on a real one
/// would pass.
const double _kBox = 375;

/// Every value the track has asked for, in order.
final List<double?> reports = <double?>[];

Future<void> _pump(
  WidgetTester tester, {
  double? progress,
  ValueNotifier<double?>? value,
  bool reducedMotion = false,
  double textScale = 1,
  double width = _kBox,
  String? semanticsLabel,
}) async {
  final held = value ?? ValueNotifier<double?>(progress);
  addTearDown(held.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reducedMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(
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
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Where the thumb is, as the left edge of the ribbon's box.
double _thumbX(WidgetTester tester) =>
    tester.getTopLeft(find.byType(ReadingBookmark)).dx;

Rect _trackRect(WidgetTester tester) =>
    tester.getRect(find.byType(ReadingTrack));

/// A point inside the band that takes touches, [atFraction] along it.
///
/// Only the top 24pt of the control's 48 is the thumb row; the rest is the gap and the
/// end labels, and they take nothing. `tester.getCenter(find.byType(ReadingTrack))`
/// lands in the gap, so every gesture aimed there misses the recognizer and any case
/// asserting that nothing happened passes without touching the control.
Offset _inBand(WidgetTester tester, {double atFraction = 0.5}) {
  final rect = _trackRect(tester);
  return Offset(rect.left + rect.width * atFraction, rect.top + 12);
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

void main() {
  setUp(reports.clear);

  group('the tap is inert', () {
    testWidgets('Given a tap at 80% of the width, Then nothing is reported', (
      tester,
    ) async {
      await _pump(tester, progress: 0.46);
      final before = _thumbX(tester);

      await tester.tapAt(_inBand(tester, atFraction: 0.8));
      await tester.pumpAndSettle();

      expect(reports, isEmpty);
      expect(_thumbX(tester), before);
    });

    testWidgets('Given a vertical drag, Then nothing is reported', (
      tester,
    ) async {
      // The sheet this lives in may scroll. A control that swallowed a vertical pan
      // would take the sheet's own gesture with it.
      await _pump(tester, progress: 0.46);
      // **From inside the thumb row, not the widget's centre.** The control is 48pt
      // tall and only its top 24 take touches, so `drag(find.byType(ReadingTrack))`
      // aims at the gap between the groove and the labels and misses the recognizer
      // entirely — a case that would pass without ever reaching the code it tests.
      await tester.dragFrom(_inBand(tester), const Offset(0, 120));
      await tester.pumpAndSettle();

      expect(reports, isEmpty);
    });

    testWidgets('Given a long press with no travel, Then nothing is reported', (
      tester,
    ) async {
      // A finger resting on the bar is the stray touch the rejection was about, and it
      // is not the same event as a tap: the pointer is down for 500ms.
      await _pump(tester, progress: 0.46);
      await tester.longPressAt(_inBand(tester, atFraction: 0.8));
      await tester.pumpAndSettle();

      expect(reports, isEmpty);
    });
  });

  group('a drag moves it', () {
    testWidgets('Given a drag right, Then the position rises with the finger', (
      tester,
    ) async {
      await _pump(tester, progress: 0.46);
      final before = _thumbX(tester);

      await tester.dragFrom(
        tester.getCenter(find.byType(ReadingBookmark)),
        const Offset(100, 0),
      );
      await tester.pumpAndSettle();

      // 100pt of a 364.2pt travel is 27.5%, so the landing stop is in the low 70s.
      // Asserted as a window rather than a value because the drag starts at the box's
      // centre, which is a quarter of a point off the ribbon's.
      expect(reports.last, isNotNull);
      expect(reports.last, greaterThan(0.70));
      expect(reports.last, lessThan(0.77));
      expect(_thumbX(tester), greaterThan(before));
    });

    testWidgets('reports whole percents, so the wheel can round-trip them', (
      tester,
    ) async {
      // The origin has to be a stop a finger can land on rather than an exact 0.0, and
      // a value the wheel's 101 stops cannot represent would be shown as one number
      // and saved as another.
      await _pump(tester, progress: 0.46);
      await tester.dragFrom(
        tester.getCenter(find.byType(ReadingBookmark)),
        const Offset(37, 0),
      );
      await tester.pumpAndSettle();

      for (final value in reports) {
        if (value == null) continue;
        expect(value * 100, closeTo((value * 100).roundToDouble(), 1e-9));
      }
    });

    testWidgets('Given a drag to the far left, Then it reports null, not 0', (
      tester,
    ) async {
      await _pump(tester, progress: 0.46);

      await tester.dragFrom(
        tester.getCenter(find.byType(ReadingBookmark)),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();

      expect(reports.last, isNull);
      // The distinction is the point: `0.0` would claim the reader opened the book and
      // got nowhere, which is a different fact and one only the percent wheel can state.
      expect(reports.last, isNot(0.0));
    });

    testWidgets('Given a drag to the far right, Then it reports exactly 1', (
      tester,
    ) async {
      await _pump(tester, progress: 0.46);

      await tester.dragFrom(
        tester.getCenter(find.byType(ReadingBookmark)),
        const Offset(400, 0),
      );
      await tester.pumpAndSettle();

      // Finished is a place you arrive at, not a value that happens to cross 1.0 —
      // which is the clearest thing this control buys over an inline wheel.
      expect(reports.last, 1.0);
    });

    testWidgets('Given a drag shorter than the slop, Then nothing is reported', (
      tester,
    ) async {
      // The narrowest version of the rejected defect: a finger that lands on the bar
      // and shifts a few points while lifting. `kTouchSlop` is the line, measured by
      // this widget rather than by the recognizer — see `_onDragStart`.
      await _pump(tester, progress: 0.5);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ReadingBookmark)),
      );
      await gesture.moveBy(const Offset(6, 0));
      await gesture.moveBy(const Offset(4, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(reports, isEmpty);
    });

    testWidgets(
      'Given a drag that returns to where it began, Then the value does too',
      (tester) async {
        await _pump(tester, progress: 0.5);
        final centre = tester.getCenter(find.byType(ReadingBookmark));
        final gesture = await tester.startGesture(centre);
        // Past the slop, then back to where it started.
        await gesture.moveBy(const Offset(40, 0));
        await gesture.moveTo(centre);
        await gesture.up();
        await tester.pumpAndSettle();

        // Net zero. The intermediate stops *are* reported, because the thumb has to
        // follow the finger; what must not happen is the same stop being reported twice
        // in a row, since the sheet's Save is its dirty indicator.
        expect(reports.last, closeTo(0.5, 1e-9));
        for (var i = 1; i < reports.length; i++) {
          expect(reports[i], isNot(reports[i - 1]));
        }
      },
    );
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
    testWidgets('Given increase, Then the position steps up by 5%', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, progress: 0.46);

      await _assist(tester, SemanticsAction.increase);

      expect(reports.last, closeTo(0.51, 1e-9));
      handle.dispose();
    });

    testWidgets('Given decrease, Then the position steps down by 5%', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, progress: 0.46);

      await _assist(tester, SemanticsAction.decrease);

      expect(reports.last, closeTo(0.41, 1e-9));
      handle.dispose();
    });

    testWidgets('Given decrease off the lowest stop, Then it reaches null', (
      tester,
    ) async {
      // The assistive path has to be able to say "Not started" too, or a VoiceOver
      // reader can leave Reading only by opening the percent wheel.
      final handle = tester.ensureSemantics();
      await _pump(tester, progress: 0.03);

      await _assist(tester, SemanticsAction.decrease);

      expect(reports.last, isNull);
      handle.dispose();
    });

    testWidgets('Given 0%, Then decrease still reaches null', (tester) async {
      // `0%` sits *on* the origin without being it, so there is one step left. A reader
      // who set `0%` from the percent wheel and wants Not started back can reach it by
      // drag; gating the action on the thumb's position rather than on the value left
      // VoiceOver unable to, which is the asymmetry this control must not have.
      final handle = tester.ensureSemantics();
      await _pump(tester, progress: 0);

      expect(
        tester
            .getSemantics(find.byType(ReadingTrack))
            .getSemanticsData()
            .hasAction(SemanticsAction.decrease),
        isTrue,
      );
      await _assist(tester, SemanticsAction.decrease);

      expect(reports.last, isNull);
      handle.dispose();
    });

    testWidgets('the node is a slider, and speaks the end words at the ends', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, progress: null, semanticsLabel: 'How far in');
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ReadingTrack)),
      );

      expect(_slider, findsOne);
      var node = tester.getSemantics(find.byType(ReadingTrack));
      expect(node.label, 'How far in');
      // At the origin the value *is* the left-hand end label, which is the reason the
      // ends borrow the status strings and the reason they are excluded from semantics.
      expect(node.value, l10n.statusInterested);
      // Nowhere further down to go, so the action is absent rather than a no-op.
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.decrease),
        isFalse,
      );
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
      );

      await _assist(tester, SemanticsAction.increase);
      expect(reports.last, closeTo(0.05, 1e-9));

      await _pump(tester, progress: 1);
      node = tester.getSemantics(find.byType(ReadingTrack));
      expect(node.value, l10n.statusFinished);
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.increase),
        isFalse,
      );
      handle.dispose();
    });

    testWidgets('the end labels are not offered as their own nodes', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, progress: 0.46);

      expect(find.bySemanticsLabel('Finished'), findsNothing);
      handle.dispose();
    });
  });

  group('reduced motion', () {
    testWidgets(
      'Given the flag, Then an external value arrives without a glide',
      (tester) async {
        final held = ValueNotifier<double?>(0.1);
        await _pump(tester, value: held, reducedMotion: true);

        held.value = 0.9;
        await tester.pump();
        final immediate = _thumbX(tester);
        await tester.pumpAndSettle();

        expect(immediate, _thumbX(tester));
      },
    );

    testWidgets('Without the flag, Then it glides there instead', (
      tester,
    ) async {
      // The counterpart, so the case above is testing the flag rather than an absence
      // of animation anywhere in the widget.
      final held = ValueNotifier<double?>(0.1);
      await _pump(tester, value: held);
      final start = _thumbX(tester);

      held.value = 0.9;
      await tester.pump();
      final immediate = _thumbX(tester);
      await tester.pumpAndSettle();

      expect(immediate, closeTo(start, 0.01));
      expect(_thumbX(tester), greaterThan(immediate));
    });

    testWidgets('a drag never lags the finger, flag or no flag', (
      tester,
    ) async {
      // The value arriving *is* the drag, so a glide towards it would put the thumb a
      // fixed distance behind the finger for the whole gesture.
      await _pump(tester, progress: 0.1);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ReadingBookmark)),
      );
      await gesture.moveBy(const Offset(150, 0));
      await tester.pump();
      final underFinger = _thumbX(tester);
      await gesture.up();
      await tester.pumpAndSettle();

      final settled = _thumbX(tester);
      expect(underFinger, closeTo(settled, 0.01));
    });
  });

  group('it measures 48pt, which is what the merged sheet is shorter by', () {
    testWidgets(
      'Given default text scale, Then the rendered height is the published one',
      (tester) async {
        await _pump(tester, progress: 0.46);

        expect(ReadingTrack.height, closeTo(48, 1e-9));
        // Held to the *layout*, not to the arithmetic: the published figure is the one
        // the sheet's height budget spends, so it has to be what a frame actually
        // measures. `38 * 0.8 + 1.6 + 16`.
        expect(_trackRect(tester).height, closeTo(ReadingTrack.height, 0.01));
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

    testWidgets('Given 2x text scale in a 375pt box, Then it does not overflow', (
      tester,
    ) async {
      await _pump(tester, progress: 0.46, textScale: 2);

      expect(tester.takeException(), isNull);
      // Taller than 48, which is correct: the labels are allowed to grow, so nothing
      // here is a fixed-height box that could clip them.
      expect(_trackRect(tester).height, greaterThan(ReadingTrack.height));
      expect(_trackRect(tester).width, closeTo(_kBox, 0.01));
    });

    testWidgets(
      'Given 2x text scale in a narrow box, Then it still does not overflow',
      (tester) async {
        // Korean sets shorter than English here, so the failing case is a long English
        // label in a squeezed measure rather than a translation.
        await _pump(tester, progress: 0.46, textScale: 2, width: 240);

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('the drawing', () {
    testWidgets(
      'the thumb is the app\'s own ribbon, not a second drawing of one',
      (tester) async {
        await _pump(tester, progress: 0.46);
        expect(find.byType(ReadingBookmark), findsOneWidget);
      },
    );

    test('the mirrored ribbon geometry still adds up to the asset box', () {
      // `reading_track.dart` derives the visible ribbon by taking the bleed off
      // `kReadingBookmarkWidth` and `kReadingBookmarkHeight`, because the bleed figures
      // themselves are private in `reading_bookmark.dart`. The results have to be the
      // `13.5 x 30` that file's doc describes, or the thumb's travel is measured against
      // the wrong edge and the groove is centred on the wrong middle.
      expect(kReadingBookmarkWidth - 4 - 4.5, closeTo(13.5, 1e-9));
      expect(kReadingBookmarkHeight - 8, closeTo(30, 1e-9));
    });

    testWidgets('the groove spans the full width, and is not sized by its fill', (
      tester,
    ) async {
      // The defect the celebration's progress bar shipped with: a `ColoredBox` around a
      // `FractionallySizedBox` inside a width-less box collapsed onto the fill, so the
      // track was exactly as long as the filled part and drew as a floating dash.
      // Measuring the fill cannot catch that — an overflow box sizes itself to the
      // constraints it is handed — so this measures the groove.
      await _pump(tester, progress: 0.1);
      expect(
        tester.getSize(find.byType(ClipRRect).first).width,
        closeTo(_kBox, 0.01),
      );
    });

    testWidgets('a null position draws no fill, and 0% draws one', (
      tester,
    ) async {
      // "Not started" is an empty groove with the thumb at the origin — both where the
      // drag begins and what the state looks like. `0%` is a real position and gets a
      // real, if tiny, fill.
      await _pump(tester, progress: null);
      final bare = find.descendant(
        of: find.byType(ClipRRect).first,
        matching: find.byType(DecoratedBox),
      );
      final withoutFill = bare.evaluate().length;

      await _pump(tester, progress: 0);
      expect(bare.evaluate().length, greaterThan(withoutFill));
    });

    testWidgets('the fallback glass is the path a test takes', (tester) async {
      // `useNativeGlass` is false here and on every phone below iOS 26, so this is the
      // path that has to render sensibly: a blur behind app-drawn content, which is the
      // pair `shelf_picker_popover.dart` uses.
      await _pump(tester, progress: 0.46);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the thumb sits at the origin for a null position', (
      tester,
    ) async {
      // Measured to the *visible* ribbon: the asset carries 4pt of empty box down its
      // left-hand side, so the box starts 3.2pt left of the groove at this scale and
      // the ribbon's own edge lands exactly on it.
      await _pump(tester, progress: null);
      expect(
        _thumbX(tester) - _trackRect(tester).left,
        closeTo(-4 * 0.8, 0.01),
      );
    });

    testWidgets('the thumb sits inside the far end at 100%', (tester) async {
      // Its visible right edge lands on the groove's, so the mark never leaves the
      // track it reads.
      await _pump(tester, progress: 1);
      final rect = _trackRect(tester);
      final ribbonRight = _thumbX(tester) + 4 * 0.8 + 13.5 * 0.8;
      expect(ribbonRight - rect.left, closeTo(rect.width, 0.01));
    });
  });
}
