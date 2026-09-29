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
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/library_provider.dart'
    show bookStatusFinished, bookStatusReading, bookStatusSetAside;
import 'package:bookworm_friends/ui/widgets/book/reading_state_line.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_track.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/book_status_bottom_sheet.dart';
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
      expect(find.text('~ p.199'), findsNothing);
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
        // **This case passed for a weaker reason before the fonts were loaded.** Under the
        // test font the sheet was tall enough that 160pt fell short of the dismissal
        // threshold, so it sprang back and the case only ever saw an unchanged read-out.
        final saved = <_Saved>[];
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          progress: 0.46,
          saved: saved,
        );

        await tester.dragFrom(_onThumb(tester), const Offset(0, 160));
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

        await tester.tap(find.text('Stop reading this'));
        await tester.pumpAndSettle();
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
        expect(find.text('~ p.199'), findsOneWidget);
        expect(find.text('/ $_kPageCount'), findsOneWidget);
      },
    );

    testWidgets(
      'Given the reader typed a page, Then the line prints that page and not the derived one',
      (tester) async {
        // The obvious "improvement" is to derive the page whenever the book has a count,
        // which would put `~ p.199` where the reader said p.200.
        await _openSheet(
          tester,
          currentStatus: bookStatusReading,
          progress: 200 / _kPageCount,
          progressPage: 200,
          pageCount: _kPageCount,
        );

        expect(find.text('p.200'), findsOneWidget);
        expect(find.text('~ p.199'), findsNothing);
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

        await tester.tap(find.text('Stop reading this'));
        await tester.pumpAndSettle();
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

  group('Stop reading this is offered only while the book is open', () {
    for (final (status, word) in const [
      (0, 'Not started'),
      (bookStatusFinished, 'Finished'),
      (bookStatusSetAside, 'Set aside'),
    ]) {
      testWidgets('Given $word, Then it is absent', (tester) async {
        // Nothing has been started at Not started; a finished book cannot be given up on;
        // and a set-aside book resumes by moving the thumb, so a resume link would be a
        // second affordance for a gesture the sheet already has.
        await _openSheet(
          tester,
          currentStatus: status,
          startDate: status == 0 ? null : DateTime(2024, 3, 14),
          finishDate: status == 0 ? null : DateTime(2024, 4, 1),
          progress: status == bookStatusFinished
              ? 1
              : (status == 0 ? null : 0.46),
        );

        expect(find.text('Stop reading this'), findsNothing);
      });
    }

    testWidgets('Given Reading, Then it is present', (tester) async {
      await _openSheet(
        tester,
        currentStatus: bookStatusReading,
        startDate: DateTime(2024, 3, 14),
        progress: 0.46,
      );

      expect(find.text('Stop reading this'), findsOneWidget);
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

        await tester.tap(find.text('Stop reading this'));
        await tester.pumpAndSettle();

        // The read-out keeps saying 46%, and the action withdraws itself — the book is no
        // longer open, so there is nothing left to stop.
        expect(find.text('46%'), findsOneWidget);
        expect(find.text('Set aside'), findsOneWidget);
        expect(find.text('Stop reading this'), findsNothing);

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

        await tester.tap(find.text('~ p.199'));
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
        expect(find.text('~ p.199'), findsOneWidget);

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
    // this plus 48. Asserted as windows rather than as exact pins because every one of them
    // is a sum of text line boxes: a pin would be a promise about font metrics, and the one
    // thing worth promising is the relationship to the sheets this replaced.

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

          await tester.tap(find.text('Stop reading this'));
          await tester.pumpAndSettle();

          expect(_save, findsOneWidget);
          expect(find.byType(DateFieldRow), findsNWidgets(2));
          // 239 + 48, so it clears the shortest phone by nearly 400pt. The margin is the
          // assertion: this sheet replaced two, and the one thing it must not have done is
          // become a sheet that needs scrolling.
          expect(
            tester.getSize(find.byType(AnimatedSize)).height,
            lessThan(320.0),
          );
          expect(
            tester.getRect(find.byType(AnimatedSize)).bottom,
            lessThanOrEqualTo(phone.height),
          );
        },
      );
    }

    testWidgets(
      'Given the Reading state, Then the sheet is shorter than either it replaced',
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

        final total = tester.getSize(find.byType(AnimatedSize)).height + 48;
        expect(total, closeTo(275, 6));
        expect(total, lessThan(342.0));
        expect(total, lessThan(368.0));
      },
    );

    testWidgets('and the Not started state is shorter still', (tester) async {
      // 122 + 48 = 170, where the record estimates 246 — the one figure in it that is not
      // close, and the reason is the read-out rather than an arithmetic slip: at the origin
      // the line collapses to a single word, with no percent, no page pair and no date row
      // under it. Worth pinning because the estimate is what a reader of the record would
      // budget against.
      await _openSheet(tester, currentStatus: 0);

      final total = tester.getSize(find.byType(AnimatedSize)).height + 48;
      expect(total, closeTo(170, 6));
      expect(find.byType(DateFieldRow), findsNothing);
    });

    testWidgets('and it grows rather than snapping when Save arrives', (
      tester,
    ) async {
      // Save arriving and the start-date row appearing both change the sheet's height, and
      // both happen on the same gesture — so without the animation the sheet would jump
      // twice under the reader's thumb.
      await _openSheet(tester, currentStatus: 0);
      final collapsed = tester.getSize(find.byType(AnimatedSize)).height;

      // **Unsettled**, which is the whole case: the helper's own `pumpAndSettle` would run
      // the animation to its end before anything could be sampled halfway through it.
      await _dragTrackTo(tester, 0.5, settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final midway = tester.getSize(find.byType(AnimatedSize)).height;

      await tester.pumpAndSettle();
      final expanded = tester.getSize(find.byType(AnimatedSize)).height;

      expect(expanded, greaterThan(collapsed));
      expect(midway, greaterThan(collapsed));
      expect(midway, lessThan(expanded));
    });
  });
}
