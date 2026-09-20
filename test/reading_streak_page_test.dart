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
import 'package:bookworm_friends/ui/widgets/book/book_chassis.dart';
import 'package:bookworm_friends/ui/widgets/book/generated_cover.dart';
import 'package:bookworm_friends/ui/widgets/reading_streak_chip.dart';
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
/// **Through `readingDate`, and getting this wrong broke every case in this file once.** The
/// 4am rollover means that between midnight and 03:59 the app's today is the previous
/// calendar day, so a fixture built from `DateTime.now()`'s raw date disagreed with the page
/// by one day — and only for anyone running the suite after midnight. Read it the way the
/// page reads it and the hour stops mattering.
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
}) async {
  final days = _FakeReadingDays(log ?? const {});
  final container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      readingDaysProvider.overrideWith(() => days),
      libraryProvider.overrideWith(
        () => FakeLibraryNotifier(shelves ?? _shelves()),
      ),
      libraryActionsProvider.overrideWith(_FakeActions.new),
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
  // recording a night writes the day -- but the Rive artboard loops forever once it has caught,
  // so `pumpAndSettle` would never return on any machine that has run
  // `dart run rive_native:setup`. Four cases below started timing out on exactly that without
  // a line of this file changing. `useStillStreakFlame` has the long version.
  useStillStreakFlame();
  testWidgets('the run is drawn, and the label carries the day\'s status', (
    tester,
  ) async {
    // **The figure stays honest all day and the label does the worrying.** A run ending
    // yesterday is still current — an unstamped today means the day is open, not broken —
    // so 11 beside an open day is correct, and a page that dropped it to 0 each morning
    // would be a threat rather than a record.
    await _pump(tester, log: _runEndingYesterday(11));

    expect(find.byKey(kStreakFigureKey), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(kStreakFigureKey)).data, '11');
    // Two lines, and they say different things: the label names what the figure is and
    // carries the day's status, the line under it is the only place the page asks for
    // anything.
    expect(find.text('days, and today is open'), findsOneWidget);
    expect(find.textContaining('until 4am'), findsOneWidget);
    expect(find.text('I read today'), findsOneWidget);
  });

  testWidgets('once today is in, the footer confirms it and offers an undo', (
    tester,
  ) async {
    // **The undo is a secondary inside a confirmation, not the primary button read back.** A
    // green CTA reading "Undo today" would advertise taking the night back as the thing to do
    // next. `setRead(read: false)` is a real delete, so it still has to be reachable — and
    // where a reader looks for it is where they made the act.
    final rig = await _pump(tester, log: _runEndingToday(12));

    expect(tester.widget<Text>(find.byKey(kStreakFigureKey)).data, '12');
    expect(find.text('days in a row'), findsOneWidget);
    expect(find.textContaining('recorded'), findsWidgets);
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
    'an empty log says where a streak would start, not that it is zero',
    (tester) async {
      await _pump(tester, log: const {});
      expect(tester.widget<Text>(find.byKey(kStreakFigureKey)).data, '0');
      expect(find.textContaining('starts here'), findsOneWidget);
    },
  );

  testWidgets('recording a night writes the day, its book, and the position', (
    tester,
  ) async {
    // **The pair, end to end.** This is the reversal the whole design turns on: ticking a
    // box used to write one `reading_days` row and *nothing else*, and now the position
    // rides with it — because recording the night and knowing where you stopped are one
    // event, and this is the one moment the reader has the answer in their hand.
    final rig = await _pump(tester);

    await tester.tap(find.byKey(kStreakRecordButtonKey));
    await tester.pumpAndSettle();
    // Reading books are their own group and come first: on an ordinary night the answer is
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

  testWidgets('agreeing with the wheel records the night and writes no position', (
    tester,
  ) async {
    // **Two facts, and the sheet reports them separately for this exact case.** `_touched`
    // stops Confirm from rewriting the column with the value it was already showing — it
    // used to, and it walked bookmarks back a page. But the *step* was still completed, and
    // treating silence as a dismissal would refuse to record a night the reader just
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
      reason: 'the book was named but the night was never confirmed',
    );
  });

  testWidgets('the celebration follows, and shows the run the write produced', (
    tester,
  ) async {
    // Read after the write rather than incremented: the figure is derived from the set, so
    // there is no counter here that can drift from it. A run of 11 ending yesterday plus
    // tonight is 12.
    await _pump(tester, log: _runEndingYesterday(11));
    await _recordVia(tester, 'Piranesi');

    expect(find.byType(StreakCelebration), findsOneWidget);
    expect(
      find.text('12'),
      findsWidgets,
      reason:
          'the celebration counts tonight, which is the whole reason it is up',
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

  testWidgets('the month colours a recorded night by the book it names', (
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

  testWidgets('the legend names the books and counts their nights', (
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

    expect(find.text('2 nights'), findsOneWidget);
    expect(find.text('1 night'), findsOneWidget);
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

    // Scoped to the tile, because the fixture's longest run is also 3 and `_RecordRow`
    // prints "3 days" too — a coincidence of this log, not a duplication. Asserting on the
    // bare string would pass for a page that printed the tally in the wrong place.
    // Uppercased at the call site, which is `AppTextStyles.caption`'s own documented
    // convention for a stat label — and a no-op on Korean, which is why the casing is not
    // baked into the `.arb` string.
    expect(find.text('READ THIS MONTH'), findsOneWidget);
    expect(find.text('THIS MONTH'), findsOneWidget);
    final tile = find
        .ancestor(
          of: find.text('READ THIS MONTH'),
          matching: find.byType(Container),
        )
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

  testWidgets('the flame leads the figure, and it is the chip\'s own glyph', (
    tester,
  ) async {
    // One flame constant, not two that happen to look alike. The flame names the *run*,
    // which is why the month under it draws stamps rather than thirty flames.
    await _pump(tester, log: _runEndingToday(3));
    expect(find.byIcon(kReadingStreakIcon), findsOneWidget);
  });

  testWidgets('it lays out at the frame size the drawings use', (tester) async {
    // **Pumped at 393×852 because that is where an overflow would actually happen.** The
    // default test surface is 800×600 — wider and much shorter than any phone — so a column
    // that is fine there can still be clipped on device, and a fixed-height row that is fine
    // on device can overflow there. The page has a scroll view precisely so the long case
    // fits; this asserts that the *pinned* parts around it do too.
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // A full month with a three-book legend: the tallest the card gets. Ending *yesterday*,
    // so the footer is the record button — the taller of the two footers, and the one whose
    // pinning is worth asserting.
    await _pump(
      tester,
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
}
