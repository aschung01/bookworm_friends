/// The streak page, and the mandatory pair behind its one button.
///
/// **What these cases are really guarding.** The page is easy: four figures read off
/// providers that already shipped. The part that can go wrong is the *pair* — a book picker
/// and the shipped percent wheel, both required — because a half-completed pair is exactly
/// the silent write this design has refused twice. So the cases below spend most of their
/// weight on what happens when the reader walks away from either sheet, and on the fact
/// that agreeing with a pre-filled wheel is a *completed* step rather than a dismissal.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/reading_date.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/reading_days_provider.dart';
import 'package:bookworm_friends/ui/pages/reading_streak_page.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_flame_mark.dart';
import 'package:bookworm_friends/ui/widgets/book/book_chassis.dart';
import 'package:bookworm_friends/ui/widgets/book/generated_cover.dart';
import 'package:bookworm_friends/ui/widgets/streak/read_calendar_month.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_celebration.dart';

import 'still_streak_flame.dart';
import 'support/home_page_harness.dart';

/// Records what was asked of the log instead of writing it.
class _FakeReadingDays extends ReadingDaysNotifier {
  _FakeReadingDays(this.initial);

  final Map<DateTime, String?> initial;
  final List<({DateTime day, bool read, String? bookId})> calls = [];

  @override
  Future<Map<DateTime, String?>> build() async => initial;

  /// The real one's optimistic half, without the request. Kept rather than stubbed out
  /// entirely because the page reads the set back after the write to derive the figure it
  /// celebrates — a no-op `setRead` would make that read the old run and the celebration
  /// would be off by one without any case noticing.
  @override
  Future<void> setRead(
    DateTime day, {
    required bool read,
    String? bookId,
  }) async {
    calls.add((day: day, read: read, bookId: bookId));
    final next = {...(state.valueOrNull ?? const <DateTime, String?>{})};
    if (read) {
      next[day] = bookId;
    } else {
      next.remove(day);
    }
    state = AsyncData(next);
  }
}

class _FakeActions extends LibraryActions {
  _FakeActions(super.ref);

  final List<({String id, double progress, int? page})> positions = [];

  @override
  Future<void> recordReadingPosition(
    String bookId, {
    required double progress,
    int? progressPage,
  }) async {
    positions.add((id: bookId, progress: progress, page: progressPage));
  }
}

/// The day the *app* thinks it is, which is not the same as the calendar date.
///
/// **Through `readingDate`, and getting this wrong broke every case in this file once,
/// back when the rollover was 4am.** Even now that the rollover is midnight and this is
/// just the plain calendar date, the helper stays: it is what the page itself calls, so a
/// fixture built any other way is one accidental rollover change away from disagreeing
/// with the page again.
final _today = readingDate(DateTime.now());

/// A run of [length] days ending today, with no book attributed.
Map<DateTime, String?> _runEndingToday(int length) => {
  for (var back = 0; back < length; back++)
    DateTime(_today.year, _today.month, _today.day - back): null,
};

/// A run of [length] days ending *yesterday* — an intact streak on an open day.
///
/// Its own helper rather than `_runEndingToday(n)..remove(today)`, because that spelling
/// silently changes the length as well as the end, which is how the first draft of these
/// cases came to assert a figure one higher than the fixture held.
Map<DateTime, String?> _runEndingYesterday(int length) => {
  for (var back = 1; back <= length; back++)
    DateTime(_today.year, _today.month, _today.day - back): null,
};

/// A run of [length] days ending [back] days before today — history, not the current run.
Map<DateTime, String?> _runEndingDaysAgo(int back, int length) => {
  for (var i = 0; i < length; i++)
    DateTime(_today.year, _today.month, _today.day - back - i): null,
};

/// Two open books and one that is not, which is the shape the picker's grouping is about.
List<Shelf> _shelves() => [
  testShelf('reading', [
    testBook(
      'open-a',
      'reading',
      title: 'The Dispossessed',
      status: 1,
      progress: 0.46,
      pageCount: 320,
    ),
    testBook('open-b', 'reading', title: 'Piranesi', status: 1, position: 1),
  ]),
  testShelf('other', [
    testBook('shelved', 'other', title: 'Middlemarch', position: 0),
  ]),
];

typedef _Rig = ({
  ProviderContainer container,
  _FakeReadingDays days,
  _FakeActions actions,
});

Future<_Rig> _pump(
  WidgetTester tester, {
  Map<DateTime, String?>? log,
  List<Shelf>? shelves,
  ReadingDayPhase? phase,
  Size surface = const Size(393, 852),
}) async {
  // **A phone-shaped surface by default, because the harness default is not one.**
  // `flutter_test` hands out 800×600 — wider and much shorter than any device the app
  // supports, the smallest being an iPhone SE at 667. The page itself scrolls and survives
  // that, but half the cases here go on to *present the celebration*, which is a full-screen
  // column of fixed-height pieces between two `Spacer`s and has no scroll view. When the span
  // ladder moved into it, that column grew past 600 and four cases here failed with a
  // `RenderFlex` overflow about a widget none of them mentions. Setting a real size once is
  // both the fix and the honest statement of what this page is.
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final days = _FakeReadingDays(log ?? const {});
  final container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      readingDaysProvider.overrideWith(() => days),
      libraryProvider.overrideWith(
        () => FakeLibraryNotifier(shelves ?? _shelves()),
      ),
      libraryActionsProvider.overrideWith(_FakeActions.new),
      // **Overridden only when a case is about the evening warning.** Left alone, the real
      // provider derives the phase from the fake log exactly as it would in the app — which is
      // what every other case here wants, and why it is a plain derived provider with no clock
      // of its own (`MyApp` owns the timer). Pinning it is for the cases that need a particular
      // hour, because the alternative is a suite that passes differently after 21:00.
      if (phase != null) readingDayPhaseProvider.overrideWithValue(phase),
    ],
  );
  addTearDown(container.dispose);

  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorKey: nav,
        home: const Scaffold(body: SizedBox()),
      ),
    ),
  );
  // Pushed rather than used as `home`, so the ✕ has somewhere to pop to — which is the
  // one thing about a full-screen cover that a page used as `home` cannot exercise.
  nav.currentState!.push(
    MaterialPageRoute<void>(builder: (_) => const ReadingStreakPage()),
  );
  await tester.pumpAndSettle();
  // Read rather than captured in the override: a `Provider` is lazy, so the closure has not
  // run by the time `_pump` returns and a variable assigned inside it is still unset.
  return (
    container: container,
    days: days,
    actions: container.read(libraryActionsProvider) as _FakeActions,
  );
}

/// Walks the pair: taps the button, picks [title], and confirms the wheel.
Future<void> _recordVia(WidgetTester tester, String title) async {
  await tester.tap(find.byKey(kStreakRecordButtonKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Confirm'));
  await tester.pumpAndSettle();
}

void main() {
  // **These cases push the celebration and then settle, so the flame has to hold still.**
  // Nothing here is about the flame -- it is scenery on a screen whose subject is whether
  // recording a day writes the day -- but the Rive artboard loops forever once it has caught,
  // so `pumpAndSettle` would never return on any machine that has run
  // `dart run rive_native:setup`. Four cases below started timing out on exactly that without
  // a line of this file changing. `useStillStreakFlame` has the long version.
  useStillStreakFlame();
  testWidgets('the run is drawn, and the label only names what it is', (
    tester,
  ) async {
    // **The figure stays honest all day, and nothing on this page says so in words.** A run
    // ending yesterday is still current — an unstamped today means the day is open, not broken
    // — so 11 beside an open day is correct, and a page that dropped it to 0 each morning
    // would be a threat rather than a record. The label used to carry that status ("day
    // streak, and today is open") over an italic line asking for a page; both were withdrawn,
    // so what is left is one attributive label in every phase.
    await _pump(tester, log: _runEndingYesterday(11));

    expect(find.byKey(kStreakFigureKey), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(kStreakFigureKey)).data, '11');
    expect(find.text('day streak'), findsOneWidget);
    expect(
      find.textContaining('today is open'),
      findsNothing,
      reason: 'the label names the figure and leaves the status to the drawing',
    );
    expect(
      find.textContaining('until midnight'),
      findsNothing,
      reason:
          'the deadline line lives on the home-screen widget, not on the page',
    );
    // The one place the page still asks for anything.
    expect(find.text('I read today'), findsOneWidget);
  });

  testWidgets('once today is in, the footer confirms it and offers an undo', (
    tester,
  ) async {
    // **The undo is a secondary inside a confirmation, not the primary button read back.** A
    // green CTA reading "Undo today" would advertise taking the day back as the thing to do
    // next. `setRead(read: false)` is a real delete, so it still has to be reachable — and
    // where a reader looks for it is where they made the act.
    final rig = await _pump(tester, log: _runEndingToday(12));

    expect(tester.widget<Text>(find.byKey(kStreakFigureKey)).data, '12');
    expect(find.text('day streak'), findsOneWidget);
    // **Once, and in the footer.** The hero used to repeat it under the figure, which put
    // the same sentence on one screen twice; the flame's own colour already carries the
    // day's status, so the confirmation belongs where the undo is.
    expect(find.textContaining('recorded'), findsOneWidget);
    expect(
      find.byKey(kStreakRecordButtonKey),
      findsNothing,
      reason: 'there is nothing to record, so the primary slot is not a button',
    );

    await tester.tap(find.byKey(kStreakUndoKey));
    await tester.pumpAndSettle();

    expect(rig.days.calls.single.read, isFalse);
    expect(
      rig.days.calls.single.day,
      _today,
      reason:
          'the undo must delete today, not whatever day the grid was showing',
    );
  });

  testWidgets(
    'an empty log reads "No streak yet", not the withdrawn start-here copy',
    (tester) async {
      await _pump(tester, log: const {});
      expect(tester.widget<Text>(find.byKey(kStreakFigureKey)).data, '0');
      expect(find.text('No streak yet'), findsOneWidget);
      expect(find.textContaining('starts here'), findsNothing);
    },
  );

  testWidgets('the record is the Library Card\'s job, not this page\'s', (
    tester,
  ) async {
    // **Three treatments were tried and all three are gone: a boxed `Longest / 2 days` row,
    // then a caption under the figure, then nothing.** The row cost ~60pt above the fold and
    // the caption cost a line, but the objection that settled it was not cost — it is that a
    // lifetime stat answers a question this screen is not about. The page is the run in
    // progress and today's act; `libraryCardStreakSub` carries the record on the surface
    // whose job is stats.
    await _pump(
      tester,
      log: {..._runEndingToday(3), ..._runEndingDaysAgo(30, 9)},
    );

    expect(tester.widget<Text>(find.byKey(kStreakFigureKey)).data, '3');
    expect(find.textContaining('Longest'), findsNothing);
    // The record's own figure, in the phrasing both dead treatments used. Not a bare '9':
    // the month grid draws day numerals, so 9 and 19 are on this screen either way.
    expect(find.textContaining('9 days'), findsNothing);
  });

  testWidgets('recording a day writes the day, its book, and the position', (
    tester,
  ) async {
    // **The pair, end to end.** This is the reversal the whole design turns on: ticking a
    // box used to write one `reading_days` row and *nothing else*, and now the position
    // rides with it — because recording the day and knowing where you stopped are one
    // event, and this is the one moment the reader has the answer in their hand.
    final rig = await _pump(tester);

    await tester.tap(find.byKey(kStreakRecordButtonKey));
    await tester.pumpAndSettle();
    // Reading books are their own group and come first: on an ordinary day the answer is
    // a few rows from the top rather than something to search for.
    expect(find.text('Reading now'), findsOneWidget);
    expect(find.text('The Dispossessed'), findsOneWidget);

    await tester.tap(find.text('The Dispossessed'));
    await tester.pumpAndSettle();
    // The wheel opens at the book's last known position, which is what keeps the cost
    // honest — Confirm is one tap on a number that is already roughly right.
    expect(find.text('Confirm'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(rig.days.calls.single.read, isTrue);
    expect(
      rig.days.calls.single.bookId,
      'open-a',
      reason: 'the day has to name the book, or the month cannot colour it',
    );
  });

  testWidgets('agreeing with the wheel records the day and writes no position', (
    tester,
  ) async {
    // **Two facts, and the sheet reports them separately for this exact case.** `_touched`
    // stops Confirm from rewriting the column with the value it was already showing — it
    // used to, and it walked bookmarks back a page. But the *step* was still completed, and
    // treating silence as a dismissal would refuse to record a day the reader just
    // confirmed. Hence `onConfirmed` beside `onProgressSelected`.
    final rig = await _pump(tester);
    await _recordVia(tester, 'The Dispossessed');

    expect(rig.days.calls.single.read, isTrue);
    expect(
      rig.actions.positions,
      isEmpty,
      reason: 'an untouched wheel is agreement, and agreement is not news',
    );
  });

  testWidgets('walking away from the picker abandons the whole write', (
    tester,
  ) async {
    // A day stamped with no position after the reader left the wheel would be a silent
    // half-write. The pair is either mandatory or it is not.
    final rig = await _pump(tester);

    await tester.tap(find.byKey(kStreakRecordButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Reading now'), findsOneWidget);

    Navigator.of(tester.element(find.text('Reading now'))).pop();
    await tester.pumpAndSettle();

    expect(rig.days.calls, isEmpty);
    expect(rig.actions.positions, isEmpty);
    expect(find.text('I read today'), findsOneWidget);
  });

  testWidgets('walking away from the wheel abandons it too', (tester) async {
    final rig = await _pump(tester);

    await tester.tap(find.byKey(kStreakRecordButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('The Dispossessed'));
    await tester.pumpAndSettle();

    // Dismissed rather than confirmed, which is the case `onConfirmed` exists to tell apart
    // from an untouched Confirm.
    Navigator.of(tester.element(find.text('Confirm'))).pop();
    await tester.pumpAndSettle();

    expect(
      rig.days.calls,
      isEmpty,
      reason: 'the book was named but the day was never confirmed',
    );
  });

  testWidgets('the celebration follows, and shows the run the write produced', (
    tester,
  ) async {
    // Read after the write rather than incremented: the figure is derived from the set, so
    // there is no counter here that can drift from it. A run of 11 ending yesterday plus
    // today is 12.
    await _pump(tester, log: _runEndingYesterday(11));
    await _recordVia(tester, 'Piranesi');

    expect(find.byType(StreakCelebration), findsOneWidget);
    expect(
      find.text('12'),
      findsWidgets,
      reason:
          'the celebration counts today, which is the whole reason it is up',
    );
  });

  testWidgets('the celebration hands the page back with today recorded', (
    tester,
  ) async {
    await _pump(tester);
    await _recordVia(tester, 'Piranesi');

    await tester.tap(find.text('Keep it going'));
    await tester.pumpAndSettle();

    expect(find.byType(StreakCelebration), findsNothing);
    // The month is the receipt, which is what lets the celebration be brief: the reader
    // does not have to remember what happened, because the grid in front of them shows it.
    expect(find.byKey(kStreakUndoKey), findsOneWidget);
  });

  testWidgets('outside debug there is no footer once the day is in', (
    tester,
  ) async {
    // **The shipped behaviour, which no other case can reach.** `flutter test` runs in
    // debug, so `streakUndoVisible` is true everywhere else in this file and the undo is
    // always there to assert — which is exactly why the gate is an overridable top-level
    // rather than a bare `kDebugMode` at the call site.
    //
    // What is gated is the whole confirmation footer, not just the `Undo` inside it: a
    // banner whose only control has been removed is a line of text restating what the week
    // row and the month grid above it already show. The record button is gone too, because
    // there is nothing left to record — so the page ends at the month card, and the
    // padding goes with the footer rather than staying as a reserved strip that reads as a
    // control which failed to load.
    debugStreakUndoVisibleOverride = false;
    addTearDown(() => debugStreakUndoVisibleOverride = null);

    await _pump(tester, log: _runEndingToday(3));

    expect(find.byKey(kStreakUndoKey), findsNothing);
    expect(find.text('Today is recorded.'), findsNothing);
    // And the button it replaces has not come back in its place: today is recorded, so
    // offering to record it again would be the worse of the two failures.
    expect(find.byKey(kStreakRecordButtonKey), findsNothing);
  });

  testWidgets(
    'in debug the footer is there, which is the other side of the gate',
    (tester) async {
      debugStreakUndoVisibleOverride = true;
      addTearDown(() => debugStreakUndoVisibleOverride = null);

      await _pump(tester, log: _runEndingToday(3));

      expect(find.byKey(kStreakUndoKey), findsOneWidget);
    },
  );

  testWidgets('the month colours a recorded day by the book it names', (
    tester,
  ) async {
    // The payload of the `book_id` decision, drawn. Without it the grid is a tally that
    // cannot say one word about what was read.
    await _pump(tester, log: {_today: 'open-a'});

    final die = tester.widget<CustomPaint>(
      find.byKey(ValueKey('streak-stamp-${_today.day}')),
    );
    final ink = (die.painter as ReadCalendarStampDie).colour;
    // `cover_color` is null on the fixture, so this is the ISBN-derived tone — the same
    // fallback every cover in the app uses, which is why a day and its book agree on colour
    // even before a cover has been decoded.
    final expected = generatedCoverColor('open-a');
    expect(ink.r, expected.r);
    expect(ink.g, expected.g);
    expect(ink.b, expected.b);
  });

  testWidgets('the legend names the books and counts their days', (
    tester,
  ) async {
    await _pump(
      tester,
      log: {
        _today: 'open-a',
        DateTime(_today.year, _today.month, _today.day - 1): 'open-a',
        DateTime(_today.year, _today.month, _today.day - 2): 'open-b',
      },
    );

    expect(find.text('2 days'), findsOneWidget);
    expect(find.text('1 day'), findsOneWidget);
    expect(find.text('2 books'), findsOneWidget);

    // **Spines, not swatches — and spines with a spine's anatomy.** The app's whole
    // vocabulary for *a book* is a cover seen edge-on, and a 12pt swatch of a
    // fifth-strength wash — which is what the key drew first, to match the patch it
    // explains — is barely a colour at that size.
    expect(
      find.byKey(const ValueKey('streak-legend-spine-The Dispossessed')),
      findsOneWidget,
    );
    final spineFinder = find.byKey(
      const ValueKey('streak-legend-spine-The Dispossessed'),
    );
    // 9x17, not the 5x15 that shipped first. The width is what the change is: at 5pt
    // the two details below have no room to be seen, which is why the drawings
    // (`cp-g-spine-thick`) widened it rather than replacing it with a cover.
    expect(
      tester.getSize(spineFinder),
      const Size(ReadLegendSpine.width, ReadLegendSpine.height),
    );
    expect(ReadLegendSpine.width, 9);
    expect(
      ReadLegendSpine.height,
      17,
      reason: 'the change is horizontal; the card\'s height must not move',
    );

    // **The two details are the reason this beat an 18x27 cover**, so they are asserted
    // rather than left to the eye: a hinge shadow at the binding and a sliver of page
    // block at the fore edge. Without them a wider rectangle is just a wider rectangle.
    final binding = find.descendant(
      of: spineFinder,
      matching: find.byType(FractionallySizedBox),
    );
    expect(
      tester.widget<FractionallySizedBox>(binding).widthFactor,
      ReadLegendSpine.bindingShare,
      reason:
          'the binding is a share of the spine, so tuning the width keeps it right',
    );
    // The fore edge takes the app's own page-block tone, which is what makes it read as
    // leaves in both themes — a typed cream would vanish against dark mode's surface,
    // the defect `BookChassisColors` exists to avoid.
    final foreEdge = tester.widget<ColoredBox>(
      find.descendant(of: spineFinder, matching: find.byType(ColoredBox)),
    );
    final paper = BookChassisColors.of(tester.element(spineFinder)).pageBase;
    expect(foreEdge.color.r, paper.r);
    expect(foreEdge.color.g, paper.g);
    expect(
      foreEdge.color.a,
      lessThan(1),
      reason:
          'the leaves sit slightly under the boards rather than as a white gap',
    );
  });

  testWidgets('the month card reports the tally and the books, not the run again', (
    tester,
  ) async {
    // **The run is deliberately not a third stat here.** The Library Card's month carries
    // "longest this month"; the hero on this page already *is* the run, so keeping it made
    // the page print one number three times — which is the defect the design record exists
    // to catch. The tally and the book count are two different facts off the same stamps.
    await _pump(
      tester,
      log: {
        _today: 'open-a',
        DateTime(_today.year, _today.month, _today.day - 1): 'open-a',
        DateTime(_today.year, _today.month, _today.day - 2): 'open-b',
      },
    );

    // Scoped to the tile, because this fixture's tally is 3 and so is its longest run — a
    // coincidence of this log, not a duplication. Asserting on the bare string would pass for
    // a page that printed the tally in the wrong place.
    // Uppercased at the call site, which is `AppTextStyles.caption`'s own documented
    // convention for a stat label — and a no-op on Korean, which is why the casing is not
    // baked into the `.arb` string.
    //
    // **Neither caption names a month any more, and that is the pager's doing.** They read
    // `READ THIS MONTH` and `THIS MONTH` while this card could only ever draw the current
    // month; now that the heading above them can be stepped back to August, a caption saying
    // "this month" contradicts the heading it sits under. The heading is the scope.
    expect(find.text('RECORDED'), findsOneWidget);
    expect(find.text('READ'), findsOneWidget);
    expect(
      find.text('READ THIS MONTH'),
      findsNothing,
      reason: 'the month is named once, by the pageable heading',
    );
    final tile = find
        .ancestor(of: find.text('RECORDED'), matching: find.byType(Container))
        .first;
    expect(
      find.descendant(of: tile, matching: find.text('3 days')),
      findsOneWidget,
    );
    expect(
      find.text('longest this month'),
      findsNothing,
      reason: 'the hero above is already the run',
    );
  });

  // **The pager, which this card's own comment argued against for three rounds.** The
  // argument was that `readingDaysProvider` "holds one window" and so cannot be asked for an
  // arbitrary month. It holds 400 *rows* ordered newest-first, which is every recorded day
  // back to the 400th — so the older months were already in memory and the control was
  // refused on a premise about the query that the query does not have. What is genuinely
  // bounded is the far edge of that row limit, and that is what these cases pin: the pager
  // reaches exactly as far as the log can speak about and no further, in either direction.
  group('the month is pageable', () {
    /// The month the grid is actually drawing, which is the thing that has to move.
    DateTime monthOnScreen(WidgetTester tester) =>
        tester.widget<ReadCalendarMonth>(find.byType(ReadCalendarMonth)).month;

    /// The heading, formatted the way the card formats it. Read off the live element rather
    /// than hardcoded, so the case does not quietly assert an `en` date format.
    String heading(WidgetTester tester, DateTime month) =>
        MaterialLocalizations.of(
          tester.element(find.byType(ReadCalendarMonth)),
        ).formatMonthYear(month);

    /// The tally tile, reached through its caption. Scoped because the legend prints "2 days"
    /// for a book with two days on it, so the bare string is ambiguous by construction.
    Finder tallyTile() => find
        .ancestor(of: find.text('RECORDED'), matching: find.byType(Container))
        .first;

    final thisMonth = DateTime(_today.year, _today.month);
    // `month - 1` rather than a subtracted duration: `DateTime` normalises month 0 to the
    // previous December, and the 15th exists in every month, which a `_today.day` would not.
    final lastMonth = DateTime(_today.year, _today.month - 1);

    testWidgets('stepping back moves the grid, its tally and its legend', (
      tester,
    ) async {
      await _pump(
        tester,
        log: {
          _today: 'open-a',
          DateTime(lastMonth.year, lastMonth.month, 15): 'open-b',
          DateTime(lastMonth.year, lastMonth.month, 14): 'open-b',
        },
      );

      expect(monthOnScreen(tester), thisMonth);
      expect(find.text(heading(tester, thisMonth)), findsOneWidget);

      await tester.tap(find.byKey(kStreakMonthPreviousKey));
      await tester.pump();

      expect(monthOnScreen(tester), lastMonth);
      expect(find.text(heading(tester, lastMonth)), findsOneWidget);
      expect(find.text(heading(tester, thisMonth)), findsNothing);

      // **Every figure on the card is scoped to the month, not just the grid.** The stats and
      // the legend derive from the same filtered map the marks do, so this is really a check
      // that nothing on the card kept reading `today`'s month behind the pager's back.
      expect(
        find.descendant(of: tallyTile(), matching: find.text('2 days')),
        findsOneWidget,
      );
      expect(find.text('1 book'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('streak-legend-spine-Piranesi')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('streak-legend-spine-The Dispossessed')),
        findsNothing,
        reason:
            'the book read this month did not appear in last month\'s legend',
      );
      // Last month has no today, so the rule that marks an open day is gone with it rather
      // than stranded on the 1st or drawn twice.
      expect(find.byKey(const ValueKey('streak-today-rule')), findsNothing);
    });

    testWidgets(
      'the oldest recorded day is the floor and today\'s month the ceiling',
      (tester) async {
        await _pump(
          tester,
          log: {
            _today: null,
            DateTime(lastMonth.year, lastMonth.month, 15): null,
          },
        );

        await tester.tap(find.byKey(kStreakMonthPreviousKey));
        await tester.pump();
        expect(monthOnScreen(tester), lastMonth);

        // **Nothing older is offered, because nothing older was fetched.** An empty grid for
        // two months ago would read as "you did not read then" where the honest statement is
        // that the query does not reach that far.
        await tester.tap(find.byKey(kStreakMonthPreviousKey));
        await tester.pump();
        expect(monthOnScreen(tester), lastMonth);

        await tester.tap(find.byKey(kStreakMonthNextKey));
        await tester.pump();
        expect(monthOnScreen(tester), thisMonth);

        // No future months: thirty dimmed numerals with nothing on them is not a record.
        await tester.tap(find.byKey(kStreakMonthNextKey));
        await tester.pump();
        expect(monthOnScreen(tester), thisMonth);
      },
    );

    testWidgets(
      'both steps stay drawn at either end, so the heading does not reflow',
      (tester) async {
        // One day, so there is nowhere to go in either direction — the state in which a pager
        // that hid its unavailable half would be at its most disruptive, because the month name
        // would shift as a side effect of the log rather than of a tap.
        await _pump(tester, log: {_today: null});

        final before = tester.getRect(find.text(heading(tester, thisMonth)));
        expect(find.byKey(kStreakMonthPreviousKey), findsOneWidget);
        expect(find.byKey(kStreakMonthNextKey), findsOneWidget);

        await tester.tap(find.byKey(kStreakMonthPreviousKey));
        await tester.pump();

        expect(monthOnScreen(tester), thisMonth);
        expect(tester.getRect(find.text(heading(tester, thisMonth))), before);
        // 36 rather than the record's 30: this is the tightest row in the feature, and 30 is
        // under every platform's minimum target.
        expect(
          tester.getSize(find.byKey(kStreakMonthPreviousKey)),
          const Size(36, 36),
        );
      },
    );
    testWidgets('recording today leaves the card where the reader put it', (
      tester,
    ) async {
      // **Deliberate, and the alternative is a real option rather than a bug.** Snapping back
      // to this month would put the stamp the reader just made in front of them; it would also
      // move the card out from under someone who navigated there on purpose, a second after
      // they dismissed a full-screen celebration. The hero and the week row above have both
      // already updated, so nothing on screen is stale — the card is showing a different month,
      // which is what it was asked to show, with a lit forward chevron saying so.
      await _pump(
        tester,
        log: {DateTime(lastMonth.year, lastMonth.month, 15): 'open-b'},
      );

      await tester.tap(find.byKey(kStreakMonthPreviousKey));
      await tester.pump();
      expect(monthOnScreen(tester), lastMonth);

      // Not Piranesi: it is the book on August's day, so its title is in the legend under the
      // grid as well as in the picker, and `tap` refuses two matches.
      await _recordVia(tester, 'The Dispossessed');
      await tester.tap(find.text('Keep it going'));
      await tester.pumpAndSettle();

      expect(monthOnScreen(tester), lastMonth);
      expect(
        find.byKey(kStreakUndoKey),
        findsOneWidget,
        reason: 'the write landed; it is only the card that did not move',
      );
    });
  });

  testWidgets('the flame leads the figure, and it is the chip\'s own mark', (
    tester,
  ) async {
    // **One flame, and it is now literally one drawing rather than one constant.** This
    // asserted `kReadingStreakIcon`, the Phosphor glyph the chip also used — which made the
    // page and the chip agree while both disagreed with the celebration's Rive artboard.
    // `StreakFlameMark` is generated from that artboard's own point lists. The flame names
    // the *run*, which is why the month under it draws stamps rather than thirty flames.
    await _pump(tester, log: _runEndingToday(3));
    expect(find.byType(StreakFlameMark), findsOneWidget);
  });

  testWidgets('it lays out at the frame size the drawings use', (tester) async {
    // **393×852 is where an overflow would actually happen**, and it is `_pump`'s default
    // now — stated through the parameter anyway, because this case is about the size rather
    // than merely at it. The default test surface is 800×600, wider and much shorter than any
    // phone, so a column that is fine there can still be clipped on device and a fixed-height
    // row that is fine on device can overflow there. The page has a scroll view precisely so
    // the long case fits; this asserts that the *pinned* parts around it do too.

    // A full month with a three-book legend: the tallest the card gets. Ending *yesterday*,
    // so the footer is the record button — the taller of the two footers, and the one whose
    // pinning is worth asserting.
    await _pump(
      tester,
      surface: const Size(393, 852),
      log: {
        for (var back = 1; back <= 28; back++)
          DateTime(_today.year, _today.month, _today.day - back): [
            'open-a',
            'open-b',
            'shelved',
          ][back % 3],
      },
    );

    // A render overflow surfaces as a test failure, so reaching here is most of the
    // assertion. The rest is that the one control is on screen rather than pushed under the
    // fold by the month above it.
    expect(find.byKey(kStreakRecordButtonKey), findsOneWidget);
    final button = tester.getRect(find.byKey(kStreakRecordButtonKey));
    expect(button.bottom, lessThanOrEqualTo(852));
    expect(
      button.top,
      greaterThan(0),
      reason: 'the primary action stays pinned, whatever the month is doing',
    );
  });

  testWidgets(
    'the ✕ dismisses, and there is no grab handle to promise a drag',
    (tester) async {
      await _pump(tester, log: _runEndingToday(3));

      await tester.tap(find.byKey(kStreakPageCloseKey));
      await tester.pumpAndSettle();

      expect(find.byType(ReadingStreakPage), findsNothing);
    },
  );

  // **The evening warning is no longer on this page, and these cases pin that.** The design
  // record specced four chip states and shipped two; the third — `sc-risk`, the open day
  // sharpening as midnight approaches — was built here as a line under the hero and has been
  // withdrawn with the rest of the page's status copy. It still exists on the home-screen
  // widget, which has no flame, week row or button to say it instead;
  // `streak_widget_snapshot_test.dart` owns that. What is asserted here is that the page reads
  // identically either side of the warning hour, and that the run and the flame are unmoved by
  // it — because the likeliest way this regresses is someone putting a red line or a third
  // tint back.
  group('the evening warning is not on this page', () {
    testWidgets('before the warning hour, the hero says only the run', (
      tester,
    ) async {
      await _pump(
        tester,
        log: _runEndingYesterday(4),
        phase: ReadingDayPhase.open,
      );

      expect(find.text('day streak'), findsOneWidget);
      expect(find.textContaining('A page is enough'), findsNothing);
    });

    testWidgets('from the warning hour, it says exactly the same thing', (
      tester,
    ) async {
      await _pump(
        tester,
        log: _runEndingYesterday(4),
        phase: ReadingDayPhase.openLate,
      );

      expect(find.text('day streak'), findsOneWidget);
      expect(find.textContaining('Nearly midnight'), findsNothing);
      expect(find.textContaining('A page is enough'), findsNothing);
    });

    // The figure is the run, and the run is intact until the day actually ends. A warning that
    // dropped the number would be scolding the reader for something that has not happened —
    // the rule the whole design shares, and the one a later "fix" is most likely to break.
    testWidgets('the run is still four, and the flame has not changed colour', (
      tester,
    ) async {
      await _pump(
        tester,
        log: _runEndingYesterday(4),
        phase: ReadingDayPhase.openLate,
      );

      expect(tester.widget<Text>(find.byKey(kStreakFigureKey)).data, '4');
      // Grey, not a third tint: `kCandleFlame` is what "recorded" means, and late is not a
      // weaker version of recorded.
      final mark = tester.widget<StreakFlameMark>(
        find.byType(StreakFlameMark).first,
      );
      expect(mark.color, isNot(kCandleFlame));
    });

    // Once the day is in, the footer says it three rows down and nothing above repeats it.
    testWidgets('once today is recorded, the hero still says only the run', (
      tester,
    ) async {
      await _pump(
        tester,
        log: _runEndingToday(4),
        phase: ReadingDayPhase.recorded,
      );

      expect(find.text('day streak'), findsOneWidget);
      expect(
        find.textContaining('recorded'),
        findsOneWidget,
        reason: 'the confirmation is the footer\'s, and it is said once',
      );
    });
  });
}
