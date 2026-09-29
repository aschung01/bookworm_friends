// Tests for the merged status-and-progress sheet — one book's whole reading state, one
// control, one Save.
//
// **This is a rewrite rather than a repair, because the control it was written against is
// gone.** The sheet used to carry a three-segment `BookStatusSelector`, a `ProgressFieldRow`
// that opened the percent wheel on top of it, and an "I read today" checkbox, and most of the
// old file drove the segments. Status is now a *read-out* of the position — `null` is Not
// started, `0 ≤ p < 1` is Reading, `p == 1` is Finished — so there is nothing to pick and the
// cases that picked are meaningless. Five of them survive retargeted, and they are the ones
// worth naming because each encodes a defect rather than a shape:
//
// - a position is handed back **untouched** when the reader did not touch it, which is the
//   everyday case: opening this sheet to fix a date must not rewrite a bookmark;
// - a real start date survives a detour through a status that does not show it;
// - a status change fills in the date the new status needs rather than leaving it empty;
// - only the dates the final status has meaning for are saved;
// - a finish date cannot land before its start.
//
// **The three cases that matter most here are about what does *not* happen.** A tap on the
// track does nothing; Save is absent while the sheet is clean; and nothing at all is reported
// before Save is pressed. The last two are what make "dismissing discards" true rather than
// claimed, and that claim is the whole answer to the objection that killed this control the
// first time it was drawn — `band-scrubber` in `docs/mockups/streaks/index.html`, rejected
// three times over because *"a stray touch could silently rewrite your position"*. So they are
// asserted directly, on the payload, rather than inferred from the absence of a button.
//
// **All three survived `ReadingTrack` being reimplemented around a platform slider, and only
// the gestures beneath them were rewritten.** That is the shape of the repair: the sheet's
// contract is unchanged, so the cases are unchanged, but every drag in the file had to be
// re-grounded on a relative control that accepts a touch only near its thumb — and the drags
// it replaced were reaching no recognizer at all, which means the no-change cases among them
// had stopped testing anything. See _Driving the track_ below.
//
// The sheet reports rather than writes, so `saved` being empty *is* "nothing was written":
// `book_details_tab_view.dart`'s `onSave` is the only writer downstream of it.
//
// **Every case runs at 375×667 with the app's real fonts loaded**, and the two go together.
// `flutter_test`'s default surface is 800×600 — shorter than any phone this app supports, so
// a sheet that overflowed on a real one would pass here — and its default *font* draws every
// glyph as a one-em square, which overflows a date row at 375 and would have made the shortest
// phone untestable for the opposite reason. See [_loadAppFonts] and [_kSurface].

import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/library_provider.dart'
    show bookStatusFinished, bookStatusReading, bookStatusSetAside;
import 'package:bookworm_friends/ui/widgets/book/reading_state_line.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_track.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/book_status_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/date_field_row.dart';
import 'package:bookworm_friends/ui/widgets/status_selector.dart';

typedef _Saved = BookStatusEdit;

/// A book whose derived page and typed page disagree, which is what tells the read-out's
/// two paths apart: 46% of 432 rounds to 199, so a case that means "the stored page" and a
/// case that means "the derived page" cannot pass for each other.
const int _kPageCount = 432;

/// Registers the app's own faces, so the widths this file measures are the widths a phone
/// draws.
///
/// **Without this a 375pt surface is unusable here, and the reason is nothing to do with the
/// sheet.** No `flutter_test_config.dart` loads fonts, so an unregistered family falls back
/// to the test font, whose every glyph is one em square: `Finish date` sets to 11 x 15 = 165
/// rather than about 78, which overflows a [DateFieldRow] on the shortest phone the app
/// supports and made the tallest states unmeasurable at the one size the design asks about.
/// In Pretendard the same row measures 160 of its 299.
///
/// Loaded from `FontManifest.json` rather than by naming files, so a face added to
/// `pubspec.yaml` arrives here without this list going stale. [FontLoader] takes no weight:
/// the engine reads it out of each file, which is why all four Pretendard cuts go into one
/// family. `GowunBatang` and `Nunito` come along and neither sets anything on this sheet --
/// Nunito is subset to digits and would draw no label even if it did.
Future<void> _loadAppFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifest =
      json.decode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(family['family'] as String);
    for (final font in (family['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

String _today() => DateFormat('yyyy.MM.dd').format(DateTime.now());

/// **An iPhone SE: the shortest phone this app supports, and shorter than the 800×600
/// default `flutter_test` hands out.**
///
/// Every case runs here rather than only the fit group, so a sheet that stops fitting fails
/// on whichever assertion is nearest the change instead of only on the one case that
/// measures — and because the failure arrives as a `RenderFlex` overflow naming a widget the
/// case never mentions, which is how moving the streak ladder took out 31 unrelated cases.
///
/// Usable as a default only because [_loadAppFonts] runs first; read its note before
/// widening anything here.
const Size _kSurface = Size(375, 667);

/// Opens the sheet on an iPhone SE — **the shortest phone this app supports, and shorter
/// than the 800×600 default.**
///
/// Sized in every case rather than only in the fit group, so a sheet that stops fitting
/// fails on whichever assertion is nearest the change instead of only on the one case that
/// measures.
///
/// [saved] collects what the sheet hands back, so a case can assert on the payload rather
/// than on the form. An empty list after an interaction is the strongest thing this file
/// says: nothing was reported, so nothing was written.
Future<void> _openSheet(
  WidgetTester tester, {
  int currentStatus = 0,
  DateTime? startDate,
  DateTime? finishDate,
  double? progress,
  int? progressPage,
  int? pageCount,
  List<_Saved>? saved,
  Size surface = _kSurface,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showBookStatusBottomSheet(
                context,
                currentStatus: currentStatus,
                startDate: startDate,
                finishDate: finishDate,
                progress: progress,
                progressPage: progressPage,
                pageCount: pageCount,
                onSave: (edit) => saved?.add(edit),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Taps `Stop reading this` **and answers the confirmation**, which is what setting a book
/// aside now costs.
///
/// The action opens `showStopReadingBottomSheet` rather than flipping the status under the
/// reader's finger — the label is an opaque full-width grey band directly under a tappable
/// date row, so it is easy to hit by accident, and that is the reason rather than the act
/// being weighty. Wrapped so the cases below keep saying *the reader set this book aside*
/// in one line; the confirmation's own behaviour is asserted in its own group.
///
/// `find.text` is an exact match, so `Stop reading` finds the button and not the label that
/// opened it, even though the status sheet is still in the tree underneath.
Future<void> _stopReading(WidgetTester tester) async {
  await tester.tap(find.text('Stop reading this'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Stop reading'));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Driving the track.
//
// **`ReadingTrack` is a platform slider now, and the two facts that matter here are that it
// is *relative* and that it almost nowhere takes a touch.** It was a `CustomPaint` groove
// with the app's bookmark ribbon for a thumb, an absolute mapping — the thumb went under the
// finger — and a hand-rolled `kTouchSlop` gate to keep taps inert. It is now [CNSlider]
// behind `useNativeGlass` and [CupertinoSlider] everywhere else, which is the branch every
// test takes. The sheet's contract did not change; every gesture that exercises it did.

/// The thumb's inset from each end of the slider: `CupertinoThumbPainter.radius` (14) plus
/// `_kPadding` (8), both private to `package:flutter/src/cupertino/slider.dart`.
///
/// **It is also the radius within which `_RenderCupertinoSlider.hitTestSelf` accepts a touch
/// at all**, which is what invalidated this file's earlier drags: they began 2pt from the
/// track's edge, so the slider never saw them — and a no-change case built on a gesture that
/// reaches no recognizer passes without testing anything. A drag has to start on the thumb.
const double _kThumbInset = 22;

/// The slider's own band — `_kSliderHeight` in `reading_track.dart` — and the only part of
/// the control's published 48 that takes a touch. **28 now, where the old thumb row was 24**;
/// the 4pt gap and the 16pt label line below it take nothing, so `getCenter` on the whole
/// control lands among the labels and a case aimed there asserts nothing.
const double _kSliderBand = 28;

/// A point in the slider's band, [atFraction] along the control's width.
///
/// **Aimed by the control's own geometry rather than through `find.byType(CupertinoSlider)`,
/// and that is deliberate**: the inert-tap cases have to keep meaning something if the slider
/// is ever swapped for an absolute one. A finder on the Cupertino type would fail on a
/// missing widget instead, which is a broken harness rather than a caught regression.
Offset _inBand(WidgetTester tester, {double atFraction = 0.5}) {
  final rect = tester.getRect(find.byType(ReadingTrack));
  return Offset(
    rect.left + rect.width * atFraction,
    rect.top + _kSliderBand / 2,
  );
}

/// A point on the thumb as it is currently drawn — the only place a gesture can start.
///
/// The thumb is painted rather than mounted, so there is no widget to measure: its centre is
/// computed from the value the slider was last built with, which is the sheet's own state.
Offset _onThumb(WidgetTester tester) {
  final slider = find.byType(CupertinoSlider);
  final rect = tester.getRect(slider);
  final value = tester.widget<CupertinoSlider>(slider).value;
  return Offset(
    rect.left + _kThumbInset + value * (rect.width - 2 * _kThumbInset),
    rect.center.dy,
  );
}

/// Drags the thumb until the track reads [to], and lifts.
///
/// **A delta from the thumb, because the slider is relative.** A drag of `dx` adds
/// `dx / (width - 2 * _kThumbInset)` to the value — the usable travel is the track less the
/// thumb's inset at each end — so there is no x to aim at, and [to] is a **value** rather
/// than a place in the box. The sheet's 327pt slider leaves 283pt of travel, so one point is
/// 0.353%. Starting on the thumb is not a nicety either; see [_kThumbInset].
///
/// **Two moves, and the first one is thrown away on purpose — this is where the sheet differs
/// from the bare control.** `reading_track_test.dart` drives the same slider with a single
/// `moveBy`, and it can: with nothing else in the arena the lone
/// `HorizontalDragGestureRecognizer` wins by default at pointer-down, so its first move is
/// already an update. Inside this sheet the bottom sheet's own drag-to-dismiss is in the
/// arena too, so the slider has to *earn* the win on distance — and at
/// `DragStartBehavior.start` the offset it accumulated getting there is folded into the
/// origin rather than reported. A single `moveBy` therefore moved the thumb nowhere, which is
/// what every drag case in this file failed on. So: 24pt to win the arena (past the 18pt
/// `kTouchSlop`), then the real delta, which arrives whole.
///
/// The ends are overshot by 8pt rather than hit exactly. `_currentDragValue` is clamped, so
/// overshooting is how a finger reaches an end, and it keeps 0 and 1 clear of a rounding
/// boundary a float could land the wrong side of.
///
/// **Verified against the slider rather than trusted.** Printed from a run inside this
/// sheet: the slider measures 327pt, so the travel is 283, and targets of 0.5, 0.6, 0.8, 1.0
/// and 0.0 arrive as exactly 0.5, 0.6, 0.8, 1.0 and null — the read-out reading `50%`,
/// `60%`, `80%`, `Finished 100%` and `Not started` respectively. They land exactly because
/// the delta is computed from the same inset travel the slider divides by, not because the
/// numbers are round.
Future<void> _dragTrackTo(
  WidgetTester tester,
  double to, {
  bool settle = true,
}) async {
  final slider = find.byType(CupertinoSlider);
  final from = tester.widget<CupertinoSlider>(slider).value;
  final travel = tester.getRect(slider).width - 2 * _kThumbInset;
  final overshoot = to >= 1
      ? 8.0
      : to <= 0
      ? -8.0
      : 0.0;

  await _slideTrack(
    tester,
    dx: (to - from) * travel + overshoot,
    settle: settle,
  );
}

/// The gesture underneath [_dragTrackTo], in raw points, for the one case that cares about
/// points rather than about a value: a slip too small to be a percent.
///
/// One point is 0.353% on the sheet's 283pt of travel, so a few points of drag changes the
/// raw value and rounds to the percent it already was.
Future<void> _slideTrack(
  WidgetTester tester, {
  required double dx,
  bool settle = true,
}) async {
  final sign = dx >= 0 ? 1.0 : -1.0;
  final gesture = await tester.startGesture(_onThumb(tester));
  // Consumed: see the note on [_dragTrackTo].
  await gesture.moveBy(Offset(24 * sign, 0));
  await tester.pump();
  await gesture.moveBy(Offset(dx, 0));
  await tester.pump();
  await gesture.up();
  if (settle) await tester.pumpAndSettle();
}

/// Dismisses whatever sheet is topmost, which is how a reader discards.
Future<void> _dismiss(WidgetTester tester, Finder inSheet) async {
  Navigator.of(tester.element(inSheet)).pop();
  await tester.pumpAndSettle();
}

Finder get _sheet => find.byType(ReadingTrack);
Finder get _save => find.text('Save');

// ---------------------------------------------------------------------------
// Driving the sub-sheets.

/// The value under a wheel's hairlines.
///
/// **Not `find.text`**, which cannot tell a selection from its neighbours: the rows either
/// side are on screen too, so moving from 46 to 45 leaves `46` findable. The selected row is
/// the only one drawn in `AppTextStyles.figure`, so its size is the discriminator.
String _wheelValue(WidgetTester tester) {
  final rows = tester.widgetList<Text>(
    find.descendant(
      of: find.byType(CupertinoPicker),
      matching: find.byType(Text),
    ),
  );
  return rows
      .firstWhere((t) => t.style?.fontSize == AppTextStyles.figure.fontSize)
      .data!;
}

/// Turns the open wheel one stop down. 34 is its item extent.
Future<void> _nudgeWheel(WidgetTester tester, {double by = 34}) async {
  await tester.drag(find.byType(CupertinoPicker), Offset(0, by));
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.text('Confirm'));
  await tester.pumpAndSettle();
}

/// Scrolls one of the date sheet's three columns, forward when [by] is negative.
///
/// **The pause before lifting is what makes this deterministic.** `tester.drag` ends with a
/// fling, and a wheel under `FixedExtentScrollPhysics` carries that momentum past the stop
/// the case aimed at. Holding still for longer than the velocity tracker's horizon before
/// the pointer goes up leaves it estimating nothing to fling with, so the column simply
/// snaps to where the finger left it.
Future<void> _scrollDateColumn(
  WidgetTester tester,
  int column, {
  required double by,
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(CupertinoPicker).at(column)),
  );
  await gesture.moveBy(Offset(0, by));
  await tester.pump(const Duration(milliseconds: 300));
  await gesture.up();
  await tester.pumpAndSettle();
}

/// What a date row currently reads, found by its label so the two rows cannot be confused
/// on a day when they happen to hold the same date — which is exactly the state the
/// finish-before-start clamp produces.
String _dateRowText(WidgetTester tester, String label) {
  final row = find.ancestor(
    of: find.text(label),
    matching: find.byType(DateFieldRow),
  );
  final texts = tester.widgetList<Text>(
    find.descendant(of: row, matching: find.byType(Text)),
  );
  return texts.firstWhere((t) => t.data != label).data!;
}

void main() {
  setUpAll(_loadAppFonts);

  // -------------------------------------------------------------------------
  // The control.
  //
  // This is the group the design's safety argument rests on. The same track was drawn once
  // before and rejected three times — "a stray touch could silently rewrite your position",
  // "being able to rewrite a position irrecoverably" — and the house-approved answer was
  // *arming*: tap to arm, then drag, with a Cancel. An inert tap reaches the same safety one
  // tap cheaper. So the first case here is a tap that changes nothing, and it must never be
  // "fixed" by adding a tap handler to `ReadingTrack`.

  group('the track is inert on tap and live on drag', () {
    testWidgets(
      'Given a tap on the bar, When it lands at 80% of the width, Then nothing changes',
      (tester) async {
        // **The stray touch the rejection was about**, and it is refused before any gesture
        // code runs: 80% of the width is far enough from a thumb at 46% that
        // `_RenderCupertinoSlider.hitTestSelf` declines the pointer outright.
        //
        // It would be an absolute slider's tap-to-seek that broke this, so the point is
        // aimed by the control's geometry rather than by the slider's type — see [_inBand].
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          progress: 0.46,
        );

        await tester.tapAt(_inBand(tester, atFraction: 0.8));
        await tester.pumpAndSettle();

        // The read-out is the position, so an unmoved read-out is an unmoved position.
        expect(find.text('46%'), findsOneWidget);
        expect(find.text('80%'), findsNothing);
        // And the sheet does not even think anything happened, which is the half a reader
        // can see: Save is the only dirty indicator there is.
        expect(_save, findsNothing);
      },
    );

    testWidgets('Given a tap on the thumb itself, Then nothing changes either', (
      tester,
    ) async {
      // **The case above passes for a reason that does not cover the whole control**, so
      // this one lands where the pointer *is* accepted and a drag genuinely opens. It
      // stays inert because the slider is relative: the drag opens at
      // `_currentDragValue = _value` and `_handleChanged` reports only a value that
      // differs from the one it was built with, so a zero-delta gesture computes the
      // value it already had.
      //
      // At the sheet's level that is the claim worth pinning: a reader who puts a finger
      // on the handle and takes it off again has not edited their book.
      await _openSheet(
        tester,
        currentStatus: bookStatusReading,
        progress: 0.46,
        progressPage: 200,
        pageCount: _kPageCount,
      );

      await tester.tapAt(_onThumb(tester));
      await tester.pumpAndSettle();

      expect(find.text('46%'), findsOneWidget);
      expect(_save, findsNothing);
      // And the page provenance survives, which is the subtler half: the sheet treats
      // every report from this control as "the reader answered in percent" and clears
      // `progressPage`, so a report of an unchanged value would silently drop `p.200`.
      expect(find.text('p.200'), findsOneWidget);
    });

    testWidgets('Given a slip too small to be a percent, Then the sheet stays clean', (
      tester,
    ) async {
      // **The nearest thing the platform slider has to the hand-rolled slop gate this
      // control used to carry, and it is the one place `ReadingTrack.report` earns its
      // keep.** `CupertinoSlider` fires `onChanged` for any movement at all, including one
      // smaller than a step: on the sheet's 283pt of travel a percent is 2.83pt, so a 1pt
      // slip changes the raw value and rounds to the percent it already was. `report` drops
      // it.
      //
      // Without that drop the sheet would treat it as an answer — the handler takes every
      // report as "the reader answered in percent" and clears `progressPage` — so a finger
      // that moved a millimetre would drop `p.200` and raise Save. **A dirty sheet with no
      // change in it**, which is the same defect as the percent wheel's `_touched` gate.
      //
      // A tap cannot reach this: `_CupertinoSliderState._handleChanged` already refuses a
      // value equal to the built one, so the tap-on-thumb case above passes with `report`'s
      // guard deleted. This is the case that fails.
      await _openSheet(
        tester,
        currentStatus: bookStatusReading,
        progress: 0.46,
        progressPage: 200,
        pageCount: _kPageCount,
      );

      await _slideTrack(tester, dx: 1);

      expect(find.text('46%'), findsOneWidget);
      expect(find.text('p.200'), findsOneWidget);
      expect(find.text('p.199'), findsNothing);
      expect(_save, findsNothing);
    });

    testWidgets(
      'Given a drag, When the thumb is moved right, Then the read-out follows it',
      (tester) async {
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          progress: 0.46,
        );

        await _dragTrackTo(tester, 0.5);

        expect(find.text('50%'), findsOneWidget);
        expect(find.text('46%'), findsNothing);
      },
    );

    testWidgets(
      'Given a gentle vertical pan, Then the track ignores it and the sheet stays',
      (tester) async {
        // Half of "a vertical drag is not ours". **Started on the thumb**, because anywhere
        // else the slider refuses the pointer and the case would prove only that a gesture
        // the control never received changed nothing. From here the lone horizontal
        // recognizer is in the arena and is handed the moves, and what keeps the value still
        // is that a vertical delta contributes no `dx`. 40pt is under the sheet's dismissal
        // threshold, which isolates the track's half from the sheet's.
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          progress: 0.46,
        );

        await tester.dragFrom(_onThumb(tester), const Offset(0, 40));
        await tester.pumpAndSettle();

        expect(find.byType(ReadingTrack), findsOneWidget);
        expect(find.text('46%'), findsOneWidget);
        expect(_save, findsNothing);
      },
    );

    testWidgets(
      'Given a decisive vertical pan, Then the sheet takes it and nothing is reported',
      (tester) async {
        // The other half, and the one that proves the gesture was not merely ignored but
        // left available: the sheet this control lives in dismisses on a downward drag, so
        // a track that swallowed the pan would trap its parent's own gesture. That the
        // sheet closes *is* the assertion.
        //
        // **This case passed for a weaker reason before the fonts were loaded**, and then
        // broke for the same reason again. `BottomSheet` dismisses on a drag past half its
        // own height, so the distance is only meaningful relative to the sheet: under the
        // test font 160pt fell short and the case saw an unchanged read-out rather than a
        // dismissal, and when the sheet was framed to its tallest state — 275 to 335 — the
        // same 160 fell from 0.58 of the height to 0.48 and stopped dismissing again.
        //
        // So the drag is **measured**, not a literal. 80% of the sheet clears the threshold
        // by a margin no future height change can eat.
        final saved = <_Saved>[];
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          progress: 0.46,
          saved: saved,
        );

        final sheetHeight = tester.getSize(find.byType(AnimatedSize)).height;
        await tester.dragFrom(_onThumb(tester), Offset(0, sheetHeight * 0.8));
        await tester.pumpAndSettle();

        expect(find.byType(ReadingTrack), findsNothing);
        // And a pan that crossed the whole control on its way out wrote nothing, which is
        // the group below's rule arriving by the least deliberate gesture there is.
        expect(saved, isEmpty);
      },
    );

    testWidgets('and there is no status control to pick from', (tester) async {
      // The merge's whole claim: position and status were two controls for one fact. The
      // selector still exists — the add-book sheet keeps it, where nothing has happened
      // yet and there is no position to derive from — so its absence *here* is the
      // assertion.
      await _openSheet(
        tester,
        currentStatus: bookStatusReading,
        progress: 0.46,
      );

      expect(find.byType(BookStatusSelector), findsNothing);
      expect(find.byType(ReadingTrack), findsOneWidget);
      expect(find.byType(ReadingStateLine), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // The heading.

  group('the heading names the hero', () {
    testWidgets('Given the sheet opens, Then it is titled Reading progress', (
      tester,
    ) async {
      // **This reverses what the case here used to assert, and the reasoning that lost is
      // worth keeping.** The heading was the *book's* title, taken as a `bookTitle`
      // parameter, on the grounds that a sheet editing one book's whole state should name
      // it. Two things were wrong with that: it read as a page header rather than a sheet
      // title, and it told the reader something they already knew — they arrived from that
      // book's page, and the book is still on screen behind the sheet.
      //
      // `changeReadingStatus` is equally gone, and for a different reason: it named a
      // control this sheet no longer has.
      await _openSheet(
        tester,
        currentStatus: bookStatusReading,
        progress: 0.46,
      );

      expect(find.text('Reading progress'), findsOneWidget);
      expect(find.text('Change reading status'), findsNothing);
    });

    testWidgets(
      'Given Save arrives, Then the title holds the left edge rather than re-centring',
      (tester) async {
        // Save appears beside the title, so a centred title would slide sideways at the
        // moment the reader is being told their drag will persist.
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          progress: 0.46,
        );
        final before = tester.getTopLeft(find.text('Reading progress')).dx;

        await _dragTrackTo(tester, 0.5);

        expect(_save, findsOneWidget);
        // The `dx` alone. The sheet is bottom-anchored and grows upward, so the whole row
        // rises by the height of the start-date row on the same gesture — asserting the
        // full offset would have been asserting that the sheet does not grow.
        expect(tester.getTopLeft(find.text('Reading progress')).dx, before);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Save.

  group('Save appears only when the sheet is dirty', () {
    testWidgets(
      'Given a sheet nobody has touched, Then there is no Save to press',
      (tester) async {
        // **The important half.** A Save that is always there says nothing, and its
        // arrival is the only unsaved-changes indicator this sheet has — there is no
        // disabled state, no dot and no banner.
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          startDate: DateTime(2024, 3, 14),
          progress: 0.46,
          pageCount: _kPageCount,
        );

        expect(_save, findsNothing);
      },
    );

    testWidgets('Given a drag, Then Save arrives', (tester) async {
      await _openSheet(
        tester,
        currentStatus: bookStatusReading,
        progress: 0.46,
      );
      expect(_save, findsNothing);

      await _dragTrackTo(tester, 0.5);

      expect(_save, findsOneWidget);
    });

    testWidgets('Given a sub-sheet Confirm, Then Save arrives', (tester) async {
      // The wheel hands its answer back rather than writing it, so the sheet has to be the
      // thing that notices. Without this, a reader who answered the wheel would be looking
      // at a changed read-out with no way to commit it.
      await _openSheet(
        tester,
        currentStatus: bookStatusReading,
        progress: 0.46,
      );

      await tester.tap(find.text('46%'));
      await tester.pumpAndSettle();
      await _nudgeWheel(tester);
      await _confirm(tester);

      expect(find.text('45%'), findsOneWidget);
      expect(_save, findsOneWidget);
    });

    testWidgets('Given a drag away and back to where it started, Then Save leaves again', (
      tester,
    ) async {
      // Dirty is a comparison against the values the sheet opened with, not a flag per
      // field. A reader who drags the thumb away and back has changed nothing, and a
      // Save that stayed behind would be claiming otherwise.
      //
      // **The start date has to already exist for this case to be about the position.**
      // Without one the first drag defaults it to today — correctly, since a status that
      // needs a date gets one — and the sheet is then permanently dirty on a field the
      // case never mentions. That is the rule three groups down showing up here as a trap.
      await _openSheet(
        tester,
        currentStatus: bookStatusReading,
        startDate: DateTime(2024, 3, 14),
        progress: 0.5,
      );

      await _dragTrackTo(tester, 0.8);
      expect(_save, findsOneWidget);

      await _dragTrackTo(tester, 0.5);

      expect(find.text('50%'), findsOneWidget);
      expect(_save, findsNothing);
    });

    testWidgets(
      'Given a date sheet confirmed on the date it opened with, Then Save stays away',
      (tester) async {
        // The no-op guard the percent wheel already has, from the other side: agreeing
        // with a pre-filled value is not an edit. The equivalent bug there walked
        // bookmarks back a page merely for being looked at.
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          startDate: DateTime(2024, 3, 14),
          progress: 0.46,
        );

        await tester.tap(find.text('Start date'));
        await tester.pumpAndSettle();
        await _confirm(tester);

        expect(find.text('2024.03.14'), findsOneWidget);
        expect(_save, findsNothing);
      },
    );
  });

  // -------------------------------------------------------------------------
  // The one that makes the drag safe.

  group('nothing is written before Save', () {
    testWidgets(
      'Given a drag, When the sheet is dismissed, Then no edit is reported at all',
      (tester) async {
        // **This is the answer to the objection that killed this control the first time.**
        // A drag that persisted on release would make "dismissing discards" false for the
        // one gesture the rejection was about, so it is asserted on the payload rather
        // than inferred: the sheet reports nothing, so its caller writes nothing.
        final saved = <_Saved>[];
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          progress: 0.46,
          saved: saved,
        );

        await _dragTrackTo(tester, 0.5);
        expect(find.text('50%'), findsOneWidget);
        expect(_save, findsOneWidget);

        await _dismiss(tester, _sheet);

        expect(saved, isEmpty);
      },
    );

    testWidgets(
      'Given a drag to the origin, When the sheet is dismissed, Then nothing is reported',
      (tester) async {
        // The erasing direction of the same rule, and the one with teeth: this is the
        // gesture that would drop a position rather than move it, so a sheet that wrote on
        // release would make it irrecoverable — which is the second wording of the
        // original rejection.
        final saved = <_Saved>[];
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          progress: 0.46,
          saved: saved,
        );

        await _dragTrackTo(tester, 0.0);
        expect(find.text('Not started'), findsWidgets);

        await _dismiss(tester, _sheet);

        expect(saved, isEmpty);
      },
    );

    testWidgets(
      'Given a wheel Confirm, When the sheet is dismissed, Then nothing is reported',
      (tester) async {
        // The wheel's Confirm commits to *this sheet*, not to the column. Two levels of
        // confirmation for one write looks redundant until you notice the alternative: a
        // nested sheet that wrote would mean the outer sheet's dismissal discarded some of
        // its own state and not the rest.
        final saved = <_Saved>[];
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          progress: 0.46,
          saved: saved,
        );

        await tester.tap(find.text('46%'));
        await tester.pumpAndSettle();
        await _nudgeWheel(tester);
        await _confirm(tester);
        expect(find.text('45%'), findsOneWidget);

        await _dismiss(tester, _sheet);

        expect(saved, isEmpty);
      },
    );

    testWidgets(
      'Given a total-pages Confirm, When the sheet is dismissed, Then nothing is reported',
      (tester) async {
        // `page_count` goes out through a different writer from the rest of the payload —
        // it is a fact about the object rather than about the reading — so "Save is the
        // only writer" has to be true of it separately.
        final saved = <_Saved>[];
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          progress: 0.46,
          pageCount: _kPageCount,
          saved: saved,
        );

        await tester.tap(find.text('/ $_kPageCount'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(CupertinoTextField), '500');
        await tester.pumpAndSettle();
        await _confirm(tester);
        expect(find.text('/ 500'), findsOneWidget);

        await _dismiss(tester, _sheet);

        expect(saved, isEmpty);
      },
    );

    testWidgets(
      'Given Stop reading this, When the sheet is dismissed, Then nothing is reported',
      (tester) async {
        // The sheet's only text action is a text action, not a command. Grey and
        // ordinary-looking, and it still goes through Save like everything else.
        final saved = <_Saved>[];
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          startDate: DateTime(2024, 3, 14),
          progress: 0.46,
          saved: saved,
        );

        await _stopReading(tester);
        expect(find.text('Set aside'), findsOneWidget);

        await _dismiss(tester, _sheet);

        expect(saved, isEmpty);
      },
    );
  });

  // -------------------------------------------------------------------------
  // The read-out.
  //
  // Four positions, four words, and no control touched for any of them. `currentStatus` is
  // deliberately *wrong* for the position each case ends at, so a sheet that echoed the
  // status it was handed would fail rather than coincide.

  group('the status word is derived from the position', () {
    testWidgets(
      'Given a drag to the origin, Then it reads Not started and shows no numerals',
      (tester) async {
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          progress: 0.46,
          pageCount: _kPageCount,
        );

        await _dragTrackTo(tester, 0.0);

        // Twice: the word above and the track's own left end label, which borrow the same
        // localised string so the two cannot disagree.
        expect(find.text('Not started'), findsNWidgets(2));
        expect(find.text('Reading'), findsNothing);
        // A book nobody has opened has no percent and no page, so the read-out is the word
        // alone — not `0%`, which is a claim about having started.
        expect(find.textContaining('%'), findsNothing);
        expect(find.textContaining('p.'), findsNothing);
      },
    );

    testWidgets('Given a drag off the origin, Then it reads Reading', (
      tester,
    ) async {
      // A book resumes by moving the thumb, which is why there is no "Start reading"
      // anywhere on this sheet: that button would name a transition the gesture performs.
      await _openSheet(tester, currentStatus: 0);
      expect(find.text('Reading'), findsNothing);

      await _dragTrackTo(tester, 0.5);

      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('Given a drag to the far end, Then it reads Finished', (
      tester,
    ) async {
      await _openSheet(
        tester,
        currentStatus: bookStatusReading,
        progress: 0.46,
      );

      await _dragTrackTo(tester, 1.0);

      // Twice, for the same reason Not started is: the word and the track's right end.
      expect(find.text('Finished'), findsNWidgets(2));
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets(
      'Given the wheel is taken to its 0 stop, Then it reads Reading 0% rather than Not started',
      (tester) async {
        // **`null` is not `0`.** Null means "never asked" and `0` means "opened it and got
        // nowhere" — two states the model keeps apart on purpose. The track's leftmost
        // pixel can only mean one of them, and it means null, because that is the state a
        // reader needs a gesture for. `0%` survives one tap further on, through the
        // wheel's own `0` stop, and the read-out is what keeps the two legible: the thumb
        // sits at the origin for both.
        await _openSheet(tester, currentStatus: 0, progress: 0.01);

        await tester.tap(find.text('1%'));
        await tester.pumpAndSettle();
        await _nudgeWheel(tester);
        expect(_wheelValue(tester), '0');
        await _confirm(tester);

        expect(find.text('0%'), findsOneWidget);
        expect(find.text('Reading'), findsOneWidget);
        // The left end label still says it; the read-out must not.
        expect(find.text('Not started'), findsOneWidget);
      },
    );

    testWidgets(
      'Given a book at 46% of 432, Then the line reads the derived page inside the total',
      (tester) async {
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          progress: 0.46,
          pageCount: _kPageCount,
        );

        expect(find.text('46%'), findsOneWidget);
        // Approximate on purpose: the wheel has 101 stops, so at 432 pages one stop is 4.3
        // pages and an exact page is not expressible. The tilde is where that is admitted.
        expect(find.text('p.199'), findsOneWidget);
        expect(find.text('/ $_kPageCount'), findsOneWidget);
      },
    );

    testWidgets(
      'Given the reader typed a page, Then the line prints that page and not the derived one',
      (tester) async {
        // The obvious "improvement" is to derive the page whenever the book has a count,
        // which would put `p.199` where the reader said p.200.
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          progress: 200 / _kPageCount,
          progressPage: 200,
          pageCount: _kPageCount,
        );

        expect(find.text('p.200'), findsOneWidget);
        expect(find.text('p.199'), findsNothing);
      },
    );
  });

  // -------------------------------------------------------------------------
  // What one Save carries, and what it leaves alone.
  //
  // The payload is a record of two dates, a fraction, a page, a flag and a total, so a
  // transposition of any pair would compile. These cases are about what *did not* move at
  // least as much as what did.

  group('the position leaves through Save exactly as the reader left it', () {
    testWidgets(
      'Given the reader never touched the position, When saved, Then it is passed through',
      (tester) async {
        // **The isolation that matters most, because it is the everyday case**: a reader
        // opening this sheet to close a book must not have their bookmark rewritten as a
        // side effect. Carried over from the old file, where the dirtying act was a status
        // segment; here it is the one text action.
        final saved = <_Saved>[];
        final start = DateTime(2024, 3, 14);
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          startDate: start,
          progress: 0.46,
          progressPage: 200,
          pageCount: _kPageCount,
          saved: saved,
        );

        await _stopReading(tester);
        await tester.tap(_save);
        await tester.pumpAndSettle();

        expect(saved, hasLength(1));
        expect(saved.single.progress, 0.46);
        expect(saved.single.progressPage, 200);
        // **Not `clearProgress`.** Untouched and erased are two different instructions,
        // and the column's own writer treats null as "leave it alone" — so without this
        // flag there would be no way to say "erase" at all.
        expect(saved.single.clearProgress, isFalse);
      },
    );

    testWidgets(
      'Given a drag to the origin, When saved, Then clearProgress is true',
      (tester) async {
        // The origin is Not started, and Not started has no position. A null `progress`
        // alone cannot say that, because null already means "do not write this column".
        final saved = <_Saved>[];
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          startDate: DateTime(2024, 3, 14),
          progress: 0.46,
          progressPage: 200,
          pageCount: _kPageCount,
          saved: saved,
        );

        await _dragTrackTo(tester, 0.0);
        await tester.tap(_save);
        await tester.pumpAndSettle();

        expect(saved.single.clearProgress, isTrue);
        expect(saved.single.progress, isNull);
        // The page goes with it. A book with no position cannot still claim the reader
        // said p.200.
        expect(saved.single.progressPage, isNull);
        expect(saved.single.status, 0);
      },
    );

    testWidgets(
      'Given a book that never had a position, When dragged and saved, Then clearProgress is false',
      (tester) async {
        // There is nothing to erase, so the flag would be a no-op instruction on a column
        // that is already null — and it is derived from the pair rather than from the
        // gesture, which is what makes that true without a special case.
        final saved = <_Saved>[];
        await _openSheet(tester, currentStatus: 0, saved: saved);

        await _dragTrackTo(tester, 0.5);
        await tester.tap(_save);
        await tester.pumpAndSettle();

        expect(saved.single.progress, closeTo(0.5, 1e-9));
        expect(saved.single.clearProgress, isFalse);
      },
    );

    testWidgets(
      'Given a dragged position, When saved, Then the typed page is cleared with it',
      (tester) async {
        // Clearing the page is news rather than an omission: a book last set to p.200 and
        // then dragged to 60% must stop claiming the reader said p.200, or every read-out
        // in the app prints a page from the wrong place in the book.
        final saved = <_Saved>[];
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          startDate: DateTime(2024, 3, 14),
          progress: 200 / _kPageCount,
          progressPage: 200,
          pageCount: _kPageCount,
          saved: saved,
        );
        expect(find.text('p.200'), findsOneWidget);

        await _dragTrackTo(tester, 0.6);
        await tester.tap(_save);
        await tester.pumpAndSettle();

        expect(saved.single.progress, closeTo(0.6, 1e-9));
        expect(saved.single.progressPage, isNull);
        expect(saved.single.clearProgress, isFalse);
      },
    );

    testWidgets(
      'Given the wheel is dismissed rather than confirmed, Then the old position survives',
      (tester) async {
        // Turning the wheel is not answering it. Carried over unchanged in spirit from the
        // old file — only the door changed.
        final saved = <_Saved>[];
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          startDate: DateTime(2024, 3, 14),
          progress: 0.46,
          saved: saved,
        );

        await tester.tap(find.text('46%'));
        await tester.pumpAndSettle();
        await _nudgeWheel(tester);
        await _dismiss(tester, find.byType(CupertinoPicker));

        expect(find.text('46%'), findsOneWidget);
        // And the sheet is still clean, so there is nothing to press.
        expect(_save, findsNothing);
        expect(saved, isEmpty);
      },
    );
  });

  // -------------------------------------------------------------------------
  // The one text action.

  group('the commit row at the foot', () {
    Finder reset() => find.text('Reset');

    testWidgets('Given a clean sheet, Then neither button is drawn', (
      tester,
    ) async {
      // Save's arrival is still the whole dirty indicator, and Reset arrives with it: there is
      // nothing to put back on a sheet nobody has changed.
      await _openSheet(
        tester,
        currentStatus: bookStatusReading,
        startDate: DateTime(2024, 3, 14),
        progress: 0.46,
      );

      expect(_save, findsNothing);
      expect(reset(), findsNothing);
    });

    testWidgets('Given a drag, Then both arrive below the track', (
      tester,
    ) async {
      // **The position is the case.** Save sat in the title row at 92×32, above the read-out
      // and the track; it was asked for at the foot. Asserted as geometry rather than by
      // finding a parent widget, because "at the foot" is the claim and a `Column` index is
      // not — and because the *reason* the move was free is geometric: anything that appears
      // below the track cannot push the track, which is what let the title row's pinned
      // height go.
      await _openSheet(
        tester,
        currentStatus: bookStatusReading,
        startDate: DateTime(2024, 3, 14),
        progress: 0.46,
      );

      final trackBefore = tester.getRect(find.byType(ReadingTrack));
      await _dragTrackTo(tester, 0.8);

      expect(_save, findsOneWidget);
      expect(reset(), findsOneWidget);
      expect(
        tester.getRect(_save).top,
        greaterThan(tester.getRect(find.byType(ReadingTrack)).bottom),
      );
      expect(
        tester.getRect(reset()).center.dx,
        lessThan(tester.getRect(_save).center.dx),
      );
      // And the arrival moved nothing, which is the property the frame exists for.
      expect(tester.getRect(find.byType(ReadingTrack)), trackBefore);
    });

    testWidgets('Given slack in the frame, Then the row is flush with the sheet foot', (
      tester,
    ) async {
      // **The defect a reader photographed.** Reading and dirty is 287 of content in a 336
      // frame, and top-aligned the spare 49pt fell *below* the commit row — buttons asked
      // for "at the bottom of the sheet", drawn most of the way up it. The `Spacer` moved
      // the slack above them.
      //
      // Both halves are asserted, because the first alone passes on a sheet with no slack
      // at all: the row is flush with the content box, *and* there is a real gap above it.
      await _openSheet(
        tester,
        currentStatus: bookStatusReading,
        startDate: DateTime(2024, 3, 14),
        progress: 0.46,
        pageCount: _kPageCount,
      );
      await _dragTrackTo(tester, 0.8);

      final box = tester.getRect(find.byType(AnimatedSize));
      // The **button**, not its label: `_save` finds the `Text`, whose box is ~14pt
      // shorter than the 44pt button around it, so measuring the label reports a row
      // 14pt clear of a foot it is actually flush with.
      final row = tester.getRect(
        find.widgetWithText(ElevatedActionButton, 'Save'),
      );
      expect(row.bottom, moreOrLessEquals(box.bottom, epsilon: 0.5));

      final action = tester.getRect(find.text('Stop reading this'));
      expect(
        row.top - action.bottom,
        greaterThan(40),
        reason: 'the slack is above the row, not below it',
      );
    });

    testWidgets('Given Reset, Then every field goes back and the row withdraws', (
      tester,
    ) async {
      // Reset restores the sheet's *arguments*, which is the same set `dirty` compares
      // against — so a reset sheet is clean by construction and the row cannot survive its
      // own press. A snapshot taken any later would leave the buttons on screen.
      final saved = <_Saved>[];
      final start = DateTime(2024, 3, 14);
      await _openSheet(
        tester,
        currentStatus: bookStatusReading,
        startDate: start,
        progress: 0.46,
        progressPage: 200,
        pageCount: _kPageCount,
        saved: saved,
      );

      await _dragTrackTo(tester, 0.8);
      expect(find.text('46%'), findsNothing);

      await tester.tap(reset());
      await tester.pumpAndSettle();

      expect(find.text('46%'), findsOneWidget);
      expect(_dateRowText(tester, 'Start date'), '2024.03.14');
      expect(_save, findsNothing);
      expect(reset(), findsNothing);
      expect(saved, isEmpty);
    });

    testWidgets('and Reset puts a status change back too', (tester) async {
      // The status is not a field the reader types, so it is the one most likely to be left
      // out of a hand-written reset. Set aside is reached through the confirmation, which
      // makes it the furthest thing from the buttons.
      await _openSheet(
        tester,
        currentStatus: bookStatusReading,
        startDate: DateTime(2024, 3, 14),
        progress: 0.46,
      );

      await _stopReading(tester);
      expect(find.text('Set aside'), findsOneWidget);

      await tester.tap(reset());
      await tester.pumpAndSettle();

      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('Set aside'), findsNothing);
      // The finish date the confirmation filled in went with it.
      expect(find.text('Finish date'), findsNothing);
      expect(find.text('Stop reading this'), findsOneWidget);
    });

    testWidgets('and Reset is not Cancel — the sheet stays open', (
      tester,
    ) async {
      // Dismissing already discards, so a button that dismissed would be a second spelling of
      // a gesture the reader has. This one is for someone who over-dragged the track and wants
      // the old value back *and* to carry on.
      await _openSheet(
        tester,
        currentStatus: bookStatusReading,
        startDate: DateTime(2024, 3, 14),
        progress: 0.46,
      );

      await _dragTrackTo(tester, 0.8);
      await tester.tap(reset());
      await tester.pumpAndSettle();

      expect(find.byType(ReadingTrack), findsOneWidget);
    });
  });

  group('the confirmation behind Stop reading this', () {
    Future<void> _openReading(WidgetTester tester, List<_Saved> saved) =>
        _openSheet(
          tester,
          currentStatus: bookStatusReading,
          startDate: DateTime(2024, 3, 14),
          progress: 0.46,
          saved: saved,
        );

    testWidgets('Given a tap, Then it asks before anything changes', (
      tester,
    ) async {
      // **The status does not move while the question is on screen.** A confirmation that
      // flipped the state behind itself and then offered Cancel would be asking about
      // something it had already done.
      final saved = <_Saved>[];
      await _openReading(tester, saved);

      await tester.tap(find.text('Stop reading this'));
      await tester.pumpAndSettle();

      expect(find.text('Stop reading this?'), findsOneWidget);
      // Both sheets are in the tree, so the status sheet below still reads Reading.
      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('Set aside'), findsNothing);
      expect(_save, findsNothing);
      expect(saved, isEmpty);
    });

    testWidgets('Given Cancel, Then the book is untouched and clean', (
      tester,
    ) async {
      final saved = <_Saved>[];
      await _openReading(tester, saved);

      await tester.tap(find.text('Stop reading this'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Stop reading this?'), findsNothing);
      expect(find.text('Reading'), findsOneWidget);
      // Clean, not merely unsaved: Cancel must not leave a Save behind offering to write a
      // change the reader just declined.
      expect(_save, findsNothing);
      expect(saved, isEmpty);
      expect(find.text('Stop reading this'), findsOneWidget);
    });

    testWidgets(
      'Given it is confirmed, Then the status moves and still nothing is written',
      (tester) async {
        // **The confirmation is a question, not a second commit path.** This is the case
        // that pins it: `Save` is the only writer in this sheet, and that invariant is the
        // whole answer to the objection which killed the drag control the first time it was
        // drawn — *"a stray touch could silently rewrite your position."* Committing straight
        // from the confirmation was the obvious alternative and would have to be argued
        // against the reason the sheet exists.
        final saved = <_Saved>[];
        await _openReading(tester, saved);

        await _stopReading(tester);

        expect(find.text('Set aside'), findsOneWidget);
        expect(_save, findsOneWidget);
        expect(saved, isEmpty);
      },
    );

    testWidgets(
      'Given it is confirmed, When the status sheet is dismissed, Then it is discarded',
      (tester) async {
        // Dismissing discards, for this like for every other answer the form holds. The
        // confirmation does not make the change durable; Save does.
        final saved = <_Saved>[];
        await _openReading(tester, saved);

        await _stopReading(tester);
        await _dismiss(tester, _sheet);

        expect(saved, isEmpty);
      },
    );

    testWidgets('and it is not dressed as a deletion', (tester) async {
      // The delete sheet's affirmative is red because a deleted book is gone. This one moves
      // a book between two shelves it can move back from in one tap, and `statusSetAside` is
      // worded to keep judgement out of it — so a red button here would contradict every
      // string in the flow.
      await _openReading(tester, <_Saved>[]);

      await tester.tap(find.text('Stop reading this'));
      await tester.pumpAndSettle();

      final action = tester.widget<ElevatedActionButton>(
        find.widgetWithText(ElevatedActionButton, 'Stop reading'),
      );
      expect(action.isDestructive, isNot(true));
      expect(action.backgroundColor, isNot(softRedColor));
    });
  });

  group('the sheet offers one text action, and which one is the status', () {
    // **`Set aside` used to be in this list, and taking it out is a reversal.** The sheet
    // offered nothing there on the reasoning that a set-aside book resumes by moving the
    // thumb, so a link would be a second affordance for a gesture already present. The
    // premise was wrong: the thumb resumes only by *changing the position*, so a reader who
    // set a book aside at 46% and wants to carry on from 46% had no move available at all.
    // The one status a position cannot imply is the one that needs a control of its own.
    for (final (status, word) in const [
      (0, 'Not started'),
      (bookStatusFinished, 'Finished'),
    ]) {
      testWidgets('Given $word, Then neither action is present', (
        tester,
      ) async {
        // Nothing has been started at Not started, and a finished book can be neither
        // given up on nor resumed.
        await _openSheet(
          tester,
          currentStatus: status,
          startDate: status == 0 ? null : DateTime(2024, 3, 14),
          finishDate: status == 0 ? null : DateTime(2024, 4, 1),
          progress: status == bookStatusFinished ? 1 : null,
        );

        expect(find.text('Stop reading this'), findsNothing);
        expect(find.text('Start reading again'), findsNothing);
      });
    }

    testWidgets('Given Reading, Then it offers Stop reading this', (
      tester,
    ) async {
      await _openSheet(
        tester,
        currentStatus: bookStatusReading,
        startDate: DateTime(2024, 3, 14),
        progress: 0.46,
      );

      expect(find.text('Stop reading this'), findsOneWidget);
      expect(find.text('Start reading again'), findsNothing);
    });

    testWidgets('Given Set aside, Then it offers Start reading again', (
      tester,
    ) async {
      await _openSheet(
        tester,
        currentStatus: bookStatusSetAside,
        startDate: DateTime(2024, 3, 14),
        finishDate: DateTime(2024, 4, 1),
        progress: 0.46,
      );

      expect(find.text('Start reading again'), findsOneWidget);
      expect(find.text('Stop reading this'), findsNothing);
    });

    testWidgets(
      'Given Start reading again is tapped, When saved, Then the book is reading at the same page',
      (tester) async {
        // The exact reverse of setting it aside, and it must move the position no more than
        // stopping did: a reader picking a book back up carries on from where they left off.
        final saved = <_Saved>[];
        final start = DateTime(2024, 3, 14);
        await _openSheet(
          tester,
          currentStatus: bookStatusSetAside,
          startDate: start,
          finishDate: DateTime(2024, 4, 1),
          progress: 0.46,
          pageCount: _kPageCount,
          saved: saved,
        );

        await tester.tap(find.text('Start reading again'));
        await tester.pumpAndSettle();

        expect(find.text('Reading'), findsOneWidget);
        expect(find.text('46%'), findsOneWidget);
        // The finish date belonged to the closing, so its row goes with the status.
        expect(find.text('Finish date'), findsNothing);

        await tester.tap(_save);
        await tester.pumpAndSettle();

        expect(saved.single.status, bookStatusReading);
        expect(saved.single.progress, 0.46);
        expect(saved.single.clearProgress, isFalse);
        expect(saved.single.startDate, start);
        // Filtered out by status rather than cleared in the form — see the round trip below.
        expect(saved.single.finishDate, isNull);
      },
    );

    testWidgets(
      'Given a round trip through Reading, Then the day the book was first closed survives',
      (tester) async {
        // `Start reading again` does **not** clear `finish`, deliberately: Save filters it
        // out for a reading book, so nothing wrong is written, and keeping it means a reader
        // who resumes and changes their mind does not silently restamp the closing with
        // today. Same rule the sheet already applies to `start` — fill in what the new
        // status needs, never clear what it does not.
        await _openSheet(
          tester,
          currentStatus: bookStatusSetAside,
          startDate: DateTime(2024, 3, 14),
          finishDate: DateTime(2024, 4, 1),
          progress: 0.46,
        );

        await tester.tap(find.text('Start reading again'));
        await tester.pumpAndSettle();
        await _stopReading(tester);

        expect(_dateRowText(tester, 'Finish date'), '2024.04.01');
      },
    );

    testWidgets('and Start reading again is not confirmed', (tester) async {
      // The asymmetry is the point. `showStopReadingBottomSheet` exists because a wide grey
      // band is easy to hit by accident, and an accidental *resume* costs a reader nothing.
      // Confirming both would make the pair read as a matched set of consequential acts,
      // which is what every string here is written to avoid.
      await _openSheet(
        tester,
        currentStatus: bookStatusSetAside,
        startDate: DateTime(2024, 3, 14),
        finishDate: DateTime(2024, 4, 1),
        progress: 0.46,
      );

      await tester.tap(find.text('Start reading again'));
      await tester.pumpAndSettle();

      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('Stop reading this?'), findsNothing);
    });

    testWidgets(
      'Given a tap nowhere near the words, Then the whole width is still the target',
      (tester) async {
        // **The action is centred and full-width now**, where it used to be an `Align` on the
        // left, and the hit box is the reason rather than the alignment: the label is short,
        // grey and the least important thing on the sheet, which is exactly the combination
        // that makes a text-sized target hard to land on. So the band is the target.
        //
        // Tapped 4pt inside the content's left edge, which is ~100pt clear of the glyphs —
        // a `Text`-sized box would miss it, and an `Align`ed one would have put the words
        // there instead and hidden the difference.
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          startDate: DateTime(2024, 3, 14),
          progress: 0.46,
        );

        final label = tester.getRect(find.text('Stop reading this'));
        // Full content width: 375 less the sheet's 24pt insets.
        expect(label.width, 327);

        await tester.tapAt(Offset(label.left + 4, label.center.dy));
        await tester.pumpAndSettle();

        // **What a tap on the band reaches is now the confirmation, not the status.** That
        // is the same finding read forwards: a target this wide is easy to hit from 100pt
        // away from the words, which is why it asks before it acts.
        expect(find.text('Stop reading this?'), findsOneWidget);
        await tester.tap(find.text('Stop reading'));
        await tester.pumpAndSettle();

        expect(find.text('Set aside'), findsOneWidget);
        expect(find.text('Stop reading this'), findsNothing);
      },
    );

    testWidgets(
      'Given it is tapped, When saved, Then the book is set aside at the page it was on',
      (tester) async {
        // **The whole point of the status existing.** Position cannot tell "at 46% and
        // still going" from "closed at 46%" — the number is identical — so this is the
        // second bit, and it must not move the number it is a second bit *of*.
        final saved = <_Saved>[];
        final start = DateTime(2024, 3, 14);
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          startDate: start,
          progress: 0.46,
          pageCount: _kPageCount,
          saved: saved,
        );

        await _stopReading(tester);

        // The read-out keeps saying 46%, and the action is replaced by its reverse — the
        // book is no longer open, so there is nothing left to stop and something to resume.
        expect(find.text('46%'), findsOneWidget);
        expect(find.text('Set aside'), findsOneWidget);
        expect(find.text('Stop reading this'), findsNothing);
        expect(find.text('Start reading again'), findsOneWidget);

        await tester.tap(_save);
        await tester.pumpAndSettle();

        expect(saved.single.status, bookStatusSetAside);
        expect(saved.single.progress, 0.46);
        expect(saved.single.clearProgress, isFalse);
        expect(saved.single.startDate, start);
        // The day the book was *closed* rather than completed, which is what keeps the
        // read view's month grouping and year rail working untouched: both read the date
        // and neither cares why the book ended.
        expect(saved.single.finishDate, isNotNull);
        expect(
          DateFormat('yyyy.MM.dd').format(saved.single.finishDate!),
          _today(),
        );
      },
    );

    testWidgets(
      'Given a set-aside book, When the thumb is moved, Then it is Reading again',
      (tester) async {
        // The resume gesture, and the reason there is no "Put back on the shelf". Set
        // aside is the one status a position cannot imply, so it is the one status a drag
        // has to be able to leave.
        final saved = <_Saved>[];
        await _openSheet(
          tester,
          currentStatus: bookStatusSetAside,
          startDate: DateTime(2024, 3, 14),
          finishDate: DateTime(2024, 4, 1),
          progress: 0.46,
          saved: saved,
        );
        expect(find.text('Set aside'), findsOneWidget);

        await _dragTrackTo(tester, 0.6);
        await tester.tap(_save);
        await tester.pumpAndSettle();

        expect(saved.single.status, bookStatusReading);
        // A book being read has no finish date, whatever it was holding while closed.
        expect(saved.single.finishDate, isNull);
      },
    );
  });

  // -------------------------------------------------------------------------
  // The three doors.
  //
  // The track is for coarse work; these are for exact answers. Each opens a different sheet,
  // and the page one is absent for about two books in three.

  group('the read-out has three doors', () {
    testWidgets(
      'Given the percent is tapped, Then the wheel opens on percent',
      (tester) async {
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          progress: 0.46,
          pageCount: _kPageCount,
        );

        await tester.tap(find.text('46%'));
        await tester.pumpAndSettle();

        expect(find.text('How far in?'), findsOneWidget);
        expect(_wheelValue(tester), '46');
      },
    );

    testWidgets(
      'Given the page is tapped, Then the wheel opens in Page mode on that page',
      (tester) async {
        // Tapping the page has already said "pages", so opening on Percent would make the
        // reader say it twice — and the title names the field rather than asking the open
        // question the percent wheel asks.
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          progress: 0.46,
          pageCount: _kPageCount,
        );

        await tester.tap(find.text('p.199'));
        await tester.pumpAndSettle();

        expect(find.text('Current page'), findsOneWidget);
        expect(find.text('How far in?'), findsNothing);
        // The wheel is spinning pages, not percents: 199 is a page and there is no 199th
        // percent.
        expect(_wheelValue(tester), '199');
      },
    );

    testWidgets('Given the total is tapped, Then the total-pages sheet opens', (
      tester,
    ) async {
      await _openSheet(
        tester,
        currentStatus: bookStatusReading,
        progress: 0.46,
        pageCount: _kPageCount,
      );

      await tester.tap(find.text('/ $_kPageCount'));
      await tester.pumpAndSettle();

      expect(find.text('Total pages'), findsOneWidget);
      // Keypad first and no wheel: a total is read off the back of the book and typed.
      expect(find.byType(CupertinoTextField), findsOneWidget);
      expect(find.byType(CupertinoPicker), findsNothing);
    });

    testWidgets(
      'Given a book with no page count, Then there is no page door, only the offer',
      (tester) async {
        // About two books in three, because Kakao supplies no count at all. There is no
        // page to edit until there is a total, and the offer to supply one is the largest
        // single thing this sheet adds.
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          progress: 0.46,
        );

        expect(find.textContaining('p.'), findsNothing);
        expect(find.text('Add total pages'), findsOneWidget);

        await tester.tap(find.text('Add total pages'));
        await tester.pumpAndSettle();

        expect(find.text('Total pages'), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------------
  // The total.

  group('the total leaves only when the reader changed it', () {
    testWidgets(
      'Given the total was not touched, When saved, Then totalPages is null',
      (tester) async {
        // Null is "no news" rather than "no pages". It rides out with the rest and is
        // written by a different method, so a total echoed back on every Save would put a
        // needless write on `page_count` every time a reader nudged a bookmark.
        final saved = <_Saved>[];
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          startDate: DateTime(2024, 3, 14),
          progress: 0.46,
          pageCount: _kPageCount,
          saved: saved,
        );

        await _dragTrackTo(tester, 0.6);
        await tester.tap(_save);
        await tester.pumpAndSettle();

        expect(saved.single.totalPages, isNull);
      },
    );

    testWidgets(
      'Given a new total, When saved, Then it is reported and the position is untouched',
      (tester) async {
        // The contract the total's own writer exists for: the fraction *is* the position,
        // so correcting a total re-derives the page and leaves the position alone. Here
        // that has to hold across a Save that carries both.
        final saved = <_Saved>[];
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          startDate: DateTime(2024, 3, 14),
          progress: 0.46,
          pageCount: 500,
          saved: saved,
        );

        await tester.tap(find.text('/ 500'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(CupertinoTextField), '432');
        await tester.pumpAndSettle();
        await _confirm(tester);

        // The read-out re-derives: 46% of 432 is p.199 where 46% of 500 was p.230.
        expect(find.text('p.199'), findsOneWidget);

        await tester.tap(_save);
        await tester.pumpAndSettle();

        expect(saved.single.totalPages, _kPageCount);
        expect(saved.single.progress, 0.46);
        expect(saved.single.progressPage, isNull);
        expect(saved.single.clearProgress, isFalse);
        // And a total is not a reading state: nothing about the status moved either.
        expect(saved.single.status, bookStatusReading);
      },
    );
  });

  // -------------------------------------------------------------------------
  // The dates.
  //
  // Every case in this group is carried over from the old file. What changed is the act that
  // implies a status: a drag on the track rather than a tap on a segment.

  group('the dates follow the status without being clobbered by it', () {
    testWidgets(
      'Given a drag off the origin, Then the start date it needs is filled in',
      (tester) async {
        // A form that reveals an empty required field has asked a question it could have
        // answered. The reader who drags a thumb has said they are reading it now.
        await _openSheet(tester, currentStatus: 0);
        expect(find.byType(DateFieldRow), findsNothing);

        await _dragTrackTo(tester, 0.5);

        expect(find.text('Start date'), findsOneWidget);
        expect(find.text('Select'), findsNothing);
        expect(_dateRowText(tester, 'Start date'), _today());
      },
    );

    testWidgets('Given a drag to the far end, Then both dates are filled in', (
      tester,
    ) async {
      await _openSheet(tester, currentStatus: 0);

      await _dragTrackTo(tester, 1.0);

      expect(find.byType(DateFieldRow), findsNWidgets(2));
      expect(find.text(_today()), findsNWidgets(2));
    });

    testWidgets(
      "Given a book's real dates, When a status that hides them is visited, Then they survive",
      (tester) async {
        // The rows come and go; the values do not. A stray drag must not throw away a date
        // the reader entered months ago — which is why the sheet fills in what a status
        // needs and never clears what it does not, and filters at Save instead.
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          startDate: DateTime(2024, 3, 14),
          progress: 0.46,
        );
        expect(find.text('2024.03.14'), findsOneWidget);

        await _dragTrackTo(tester, 0.0);
        expect(find.byType(DateFieldRow), findsNothing);
        await _dragTrackTo(tester, 0.5);

        expect(_dateRowText(tester, 'Start date'), '2024.03.14');
        expect(find.text(_today()), findsNothing);
      },
    );

    testWidgets('Given a set-aside book, Then it keeps a finish date row', (
      tester,
    ) async {
      // Its finish date is the day it was closed rather than the day it was completed,
      // and the read view reads that column without caring which.
      await _openSheet(
        tester,
        currentStatus: bookStatusSetAside,
        startDate: DateTime(2024, 3, 14),
        finishDate: DateTime(2024, 4, 1),
        progress: 0.46,
      );

      expect(find.byType(DateFieldRow), findsNWidgets(2));
      expect(_dateRowText(tester, 'Finish date'), '2024.04.01');
    });

    testWidgets(
      'Given a finished book, When dragged back to the origin, Then both dates are dropped on save',
      (tester) async {
        // A book put back to Not started does not keep the dates the form was holding for
        // its own benefit.
        final saved = <_Saved>[];
        await _openSheet(
          tester,
          currentStatus: bookStatusFinished,
          startDate: DateTime(2024, 3, 14),
          finishDate: DateTime(2024, 4, 1),
          progress: 1,
          saved: saved,
        );

        await _dragTrackTo(tester, 0.0);
        await tester.tap(_save);
        await tester.pumpAndSettle();

        expect(saved.single.status, 0);
        expect(saved.single.startDate, isNull);
        expect(saved.single.finishDate, isNull);
      },
    );

    testWidgets(
      'Given a finished book, When dragged back mid-track, Then only the finish date is dropped',
      (tester) async {
        final saved = <_Saved>[];
        final start = DateTime(2024, 3, 14);
        await _openSheet(
          tester,
          currentStatus: bookStatusFinished,
          startDate: start,
          finishDate: DateTime(2024, 4, 1),
          progress: 1,
          saved: saved,
        );

        await _dragTrackTo(tester, 0.5);
        await tester.tap(_save);
        await tester.pumpAndSettle();

        expect(saved.single.status, bookStatusReading);
        expect(saved.single.startDate, start);
        expect(saved.single.finishDate, isNull);
      },
    );

    testWidgets(
      'Given a finish date is picked, Then it cannot land before the start',
      (tester) async {
        // The guard is on the picker rather than on the value, so there is no invalid
        // state to report and no error message to write.
        await _openSheet(
          tester,
          currentStatus: bookStatusFinished,
          startDate: DateTime(2024, 3, 14),
          finishDate: DateTime(2024, 4, 1),
          progress: 1,
        );

        await tester.tap(find.text('Finish date'));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
              .minimumDate,
          DateTime(2024, 3, 14),
        );
      },
    );

    testWidgets(
      'Given a start date moved past the finish, Then the finish moves with it',
      (tester) async {
        // The other half of the same clamp, and the half a `minimumDate` cannot cover:
        // moving the *start* forward would otherwise leave the book finished before it was
        // started.
        await _openSheet(
          tester,
          currentStatus: bookStatusFinished,
          startDate: DateTime(2024, 3, 14),
          finishDate: DateTime(2024, 3, 15),
          progress: 1,
        );

        await tester.tap(find.text('Start date'));
        await tester.pumpAndSettle();
        // Column 1 is the day in `en_US`'s month-day-year order. Forward by ten days,
        // which is well clear of the one-day gap and still inside the picker's own
        // ceiling of today.
        await _scrollDateColumn(tester, 1, by: -340);
        await _confirm(tester);

        final start = _dateRowText(tester, 'Start date');
        final finish = _dateRowText(tester, 'Finish date');
        expect(start, isNot('2024.03.14'));
        expect(finish, isNot('2024.03.15'));
        expect(finish, start);
      },
    );
  });

  // -------------------------------------------------------------------------

  group('the sheet fits the phones this app supports', () {
    // Heights here are the content box — the [AnimatedSize] — and the sheet adds its own
    // 24pt of padding above and below, so a figure comparable with the design record's is
    // this plus 48.
    //
    // **The sheet is one height now, and most of this group used to measure four.** It was
    // sized to its content, and the figures below were windows rather than pins for a good
    // reason: each is a sum of text line boxes, so a pin is a promise about font metrics.
    // They are exact now because the number is a constant in the Dart rather than a
    // consequence of the content — which is the change, not a tightening of the assertions.
    //
    // Why it changed is in the case that used to close this group, `and it grows rather than
    // snapping when Save arrives`. It asserted the sheet grew mid-drag and defended an
    // `AnimatedSize` for smoothing it, on the grounds that *"both happen on the same
    // gesture, so without the animation the sheet would jump twice under the reader's
    // thumb."* That diagnosis was right and the remedy treated the symptom: a bottom sheet
    // is anchored to the bottom of the screen, so growing moves its top edge — and the track
    // with it, since both date rows sit below the track. 220ms of easing still slides the
    // control out from under the finger dragging it. The frame removes the resize instead.
    //
    // It is a *minimum* height, so the last case here is the valve: content that genuinely
    // needs more room still gets it.

    for (final phone in const [_kSurface, Size(393, 852)]) {
      testWidgets(
        'Given a ${phone.width.toInt()}×${phone.height.toInt()} surface, Then the tallest state fits',
        (tester) async {
          // **A `RenderFlex` overflow is reported as a test failure, so reaching the
          // assertions is most of this case** — and it is a real measurement rather than an
          // artifact, because [_loadAppFonts] has put the app's own faces in front of the
          // test font's square glyphs.
          //
          // The tallest state: a set-aside book, which draws the read-out, the track, *both*
          // date rows and a dirty Save at once.
          await _openSheet(
            tester,
            currentStatus: bookStatusReading,
            startDate: DateTime(2024, 3, 14),
            progress: 0.46,
            pageCount: _kPageCount,
            surface: phone,
          );

          await _stopReading(tester);

          expect(_save, findsOneWidget);
          expect(find.byType(DateFieldRow), findsNWidgets(2));
          // **This is the state the frame is sized to**, so it is also the guard that the
          // constant is still big enough: if a row were added here, the content would exceed
          // 336, the sheet would start resizing between states again, and this is where it
          // shows up.
          //
          // **287 → 336 when Save moved to the foot.** The title row gave back 11 — it no
          // longer holds a 32pt button next to a ~21pt heading — and the commit row costs 60,
          // 44 plus its gap. 336 + 48 = 384, which still clears the shortest phone by nearly
          // 300pt, and this sheet must never become one that needs scrolling.
          expect(tester.getSize(find.byType(AnimatedSize)).height, 336.0);
          expect(
            tester.getRect(find.byType(AnimatedSize)).bottom,
            lessThanOrEqualTo(phone.height),
          );
        },
      );
    }

    testWidgets(
      'Given the Reading state, Then the sheet is now taller than both it replaced',
      (tester) async {
        // **The merge's headline number, measured rather than estimated.** The design record
        // has 270pt clean from summing row heights in the Dart, against an exact 368 for the
        // percent wheel alone (`_sheetHeight` sums 64 + 48 + 220 + 36) and ~342 for the old
        // status sheet. Rendered, the clean Reading state is 227 + 48 = 275 — within 5pt of
        // the estimate, and comfortably under both of the sheets it stands in for.
        //
        // **Re-measured after the track became a platform slider and the action moved, and it
        // did not budge.** `ReadingTrack.height` is still 48: the slider's band is 28 with a
        // 4pt gap where the hand-drawn thumb row was 24 with 8, and the end labels are the
        // same 16pt line. Nothing in this group's figures moved by a point.
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          startDate: DateTime(2024, 3, 14),
          progress: 0.46,
          pageCount: _kPageCount,
        );

        // **384, and the merge's headline claim is now false** — this is the case that used
        // to assert `lessThan(342)` and `lessThan(368)`, the old status sheet and the percent
        // wheel, and it asserted 275 before the sheet was framed at all.
        //
        // Two deliberate decisions spent that margin, in order: framing the sheet to its
        // tallest state so the track stops moving under a drag (275 → 335), and moving Save
        // to the foot, which added a 60pt commit row to the tallest state and so to every
        // state (335 → 384). Neither is reversible by tightening a gap, and the second is
        // what crossed the line.
        //
        // Pinned against the two old figures anyway, as an upper bound rather than a lower
        // one, so the size is a number someone has to look at rather than a claim that
        // quietly stopped being true.
        final total = tester.getSize(find.byType(AnimatedSize)).height + 48;
        expect(total, 384.0);
        expect(total, greaterThan(342.0));
        expect(total, greaterThan(368.0));
      },
    );

    testWidgets('and the Not started state is no shorter, which is the cost', (
      tester,
    ) async {
      // **170 → 335 → 384, and this state's content is still 122**, so 214pt of it — over
      // half — is empty cream, on the state a reader meets first. At the origin the read-out
      // collapses to a single word, there is no date row, no text action and nothing to
      // commit.
      //
      // Pinned rather than merely tolerated, because it is the figure that decides whether
      // the frame is worth keeping. What it buys is a sheet that does not jump on the first
      // drag of every new book — and that jump grew from 115pt to 165 when the commit row
      // moved to the foot, so both sides of this trade got worse at once.
      await _openSheet(tester, currentStatus: 0);

      final total = tester.getSize(find.byType(AnimatedSize)).height + 48;
      expect(total, 384.0);
      expect(total - 48 - 122, 214.0, reason: 'the void, stated as a number');
      expect(find.byType(DateFieldRow), findsNothing);
    });

    testWidgets('and it does not move at all when Save and a date row arrive', (
      tester,
    ) async {
      // **The inversion of the case this replaced**, which asserted the sheet grew and
      // sampled the animation halfway to prove the growth was eased rather than snapped.
      //
      // Save arriving and the start-date row appearing still both happen on the one gesture.
      // What changed is that neither moves anything: the sheet is already the height it will
      // be, so the track the reader is dragging stays exactly where their finger found it.
      // Sampled mid-animation as well as at rest, because "eased to the same size" and
      // "never resized" are different claims and only the second one is true.
      await _openSheet(tester, currentStatus: 0);
      final collapsed = tester.getSize(find.byType(AnimatedSize)).height;
      final trackBefore = tester.getRect(find.byType(ReadingTrack));

      await _dragTrackTo(tester, 0.5, settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getSize(find.byType(AnimatedSize)).height, collapsed);

      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AnimatedSize)).height, collapsed);
      // The point of the whole exercise, stated directly rather than through the height.
      expect(tester.getRect(find.byType(ReadingTrack)), trackBefore);
      // And the drag did what it was for, so this is not passing because nothing happened.
      expect(_save, findsOneWidget);
      expect(find.byType(DateFieldRow), findsOneWidget);
    });

    testWidgets('and the frame is a floor rather than a cage', (tester) async {
      // The valve. `ConstrainedBox(minHeight:)` rather than a `SizedBox`, so a state that
      // genuinely needs more room than 336 — a large accessibility text size, or a locale
      // that wraps a row — grows instead of clipping. Driven here by the text scale, which
      // is the realistic cause.
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _openSheet(
        tester,
        currentStatus: bookStatusSetAside,
        startDate: DateTime(2024, 3, 14),
        finishDate: DateTime(2024, 4, 1),
        progress: 0.46,
        pageCount: _kPageCount,
        surface: const Size(393, 852),
      );

      expect(
        tester.getSize(find.byType(AnimatedSize)).height,
        greaterThan(336.0),
      );
    });
  });
}
