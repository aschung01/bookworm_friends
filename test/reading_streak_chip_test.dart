// The library bar's streak chip.
//
// **A pointer, not a second home for the number.** The Library Card owns the figure;
// this is the everyday glance on the screen the reader opens most, and tapping it goes
// to the Card. What makes two displays safe is that both read the same derived value
// and neither stores one.
//
// **Two of this file's original rules were reversed, and the reversals are the point
// of half these cases.** The chip used to omit itself at zero and to lead with a stamp
// (`▣`). Omitting at zero hid it from 136 of the 137 profiles in production — exactly
// one has any reading day — so the tasteful default was the feature failing to exist.
// And the stamp answered "what marks a day?" when the chip's job is "what kind of
// number is this?"; beside a shelf-count badge, `▣ 12` read as a third count. The
// flame then changed *family* as well: Material's rounded flame became
// `PhosphorIconsFill.fire`, off a dependency the app was already carrying and had
// never called.
//
// The state rule is the part worth pinning, because getting it wrong inverts the
// feature: the colour is keyed on whether **today** is recorded, never on the count.
// The count is intact all day and only the day's own status changes at the midnight
// rollover, so keying it on the number made the chip green at 9am on an unstamped day
// — the opposite of a nudge. And the cold state still reads the full count in grey,
// not red and not empty: the streak is intact until the day actually ends, and a chip
// that panics in the morning is one readers learn to resent.
//
// **Neither state has a box**, which took two reversals to arrive at. The chip first
// drew a grey-outlined pill every day the reader had not yet read — most days — making
// it a fourth control in a row of three real buttons (the density toggle, the shelves
// button, the avatar). That deleted the *cold* outline and kept a full-radius amber
// pill for the days there was something to mark, and this file's header said exactly
// that for a revision. The second pass deleted the warm one too, on instruction:
// Duolingo's bar draws its streak as a mark and a numeral on the bar's own ground, and
// the objection that removed the cold pill applies just as well to the warm one — a
// status readout is not a control, and the fix is to stop drawing it like one on *every*
// day rather than on most of them.
//
// What that costs is pinned in the group below: the pill was load-bearing, because the
// amber numeral is only 2.00:1 on `surface`, so the shape was carrying a state the ink
// could not. Hot against cold is now a 2.75:1 hue delta in light mode and 1.5:1 in dark.
//
// The third drawn state — amber when the evening is running out — is **not built**.
// See `docs/superpowers/plans/2026-09-16-reading-streaks-plan.md`, Task 12: the hour
// that counts as "late" is undecided, and the mockup draws that state as a dashed
// border rather than amber, so there are two open questions behind one pixel.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/reading_date.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/reading_days_provider.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/reading_streak_chip.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_flame_mark.dart';

/// Serves a fixture instead of hitting Supabase.
///
/// Takes a set even though the notifier holds a day→book map: every case here is about the
/// count and the day's status, not about what was read, so a null book keeps the fixtures
/// one line each. It is a real state too — a row written before the column existed.
class _FakeReadingDays extends ReadingDaysNotifier {
  _FakeReadingDays(this.days);

  final Set<DateTime> days;

  @override
  Future<Map<DateTime, String?>> build() async => {
    for (final day in days) day: null,
  };
}

/// Never resolves, so the chip can be caught mid-fetch.
class _PendingReadingDays extends ReadingDaysNotifier {
  @override
  Future<Map<DateTime, String?>> build() =>
      Completer<Map<DateTime, String?>>().future;
}

/// A run of [length] days ending on [endingOn], as reading dates.
Set<DateTime> _run(int length, {required DateTime endingOn}) => {
  for (var back = 0; back < length; back++)
    DateTime(endingOn.year, endingOn.month, endingOn.day - back),
};

/// Records what the chip asked the navigator for.
///
/// The chip's contract is a route *name*; the page behind it is tested in
/// `reading_streak_page_test.dart`. Asserting the name here is what keeps this file about
/// the chip — and it is what stops the chip's test from needing a library fixture to build
/// a screen it is not about.
class _RouteLog extends NavigatorObserver {
  final List<String?> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route.settings.name);
    super.didPush(route, previousRoute);
  }
}

Future<ProviderContainer> _pumpChip(
  WidgetTester tester, {
  required Set<DateTime> days,
  List<NavigatorObserver> observers = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      readingDaysProvider.overrideWith(() => _FakeReadingDays(days)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: observers,
        // A stub for whatever the chip pushes. The real table sends this name to a
        // full-screen cover holding the streak page; standing in for it here keeps this
        // file from building that page, which wants a library fixture this one has no use
        // for.
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const SizedBox(),
        ),
        home: const Scaffold(body: Center(child: ReadingStreakChip())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Whether the chip paints no box at all — no fill, no border, in either state.
///
/// **This inverts a helper that used to fetch the pill and assert its colours.**
/// The chip drew a `circular(20)` stadium — [kCandleFlame] at 12% behind a 1.5pt
/// border of the same hue at 55% — once today was recorded, and kept the identical
/// decoration with both colours transparent when cold, so the old question was "is
/// the box invisible?". Both states are now bare and the question is "is there a
/// box?".
///
/// **It looks for `DecoratedBox` rather than for `Container`, and that is the whole
/// reason it has teeth.** A `Container` carrying only padding is still a
/// `Container`, so a type check would pass on a chip that had quietly grown a fill
/// back; and a decoration could return as a bare `DecoratedBox` without a
/// `Container` anywhere. `Container` builds one of these whenever `decoration` is
/// non-null, so walking the rendered subtree for it catches both spellings. An
/// earlier draft of this helper also inspected `Container.decoration` — via
/// `find.byType(ReadingStreakChip)`, which yields the chip widget and never a
/// `Container`, so that clause was dead and passed unconditionally.
bool _chipHasNoBox(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(ReadingStreakChip),
        matching: find.byType(DecoratedBox),
      ),
    )
    .isEmpty;

/// The chip's tint, asserted through the flame rather than the numeral.
///
/// Reads both and requires them to agree: the mark and the digits are separate widgets, so
/// "the chip is flame-coloured" is only true if neither was left behind.
Color? _tint(WidgetTester tester) {
  final mark = tester.widget<StreakFlameMark>(find.byType(StreakFlameMark));
  final text = tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(ReadingStreakChip),
          matching: find.byType(Text),
        ),
      )
      .first;
  expect(
    mark.color,
    text.style?.color,
    reason: 'the flame and the numeral must carry the same tint',
  );
  return mark.color;
}

Future<void> _pumpPendingChip(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      readingDaysProvider.overrideWith(_PendingReadingDays.new),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: Center(child: ReadingStreakChip())),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  final today = readingDate(DateTime.now());

  testWidgets('Given the days are still loading, Then it draws nothing at all', (
    tester,
  ) async {
    // The regression that showing zero introduced. `currentStreakProvider` answers 0
    // while the fetch is in flight, so an ungated chip reads a cold `0` on every cold
    // open and then flips to the real run — a reader with twelve days watches the app
    // appear to lose them. Not knowing is not zero.
    await _pumpPendingChip(tester);

    expect(find.byType(StreakFlameMark), findsNothing);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('Given no run, Then it still draws, reading zero', (
    tester,
  ) async {
    // The reversal. Omitting here is what hid the chip from 136 of 137 accounts, and a
    // reader cannot start a run they have never been shown.
    await _pumpChip(tester, days: const {});

    expect(find.byType(StreakFlameMark), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('Given a run, Then it reads the flame and the count', (
    tester,
  ) async {
    await _pumpChip(tester, days: _run(12, endingOn: today));

    expect(find.byType(StreakFlameMark), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('a drawn flame, and not a font glyph of any family', (
    tester,
  ) async {
    // **This case used to pin a codepoint and it no longer can.** It asserted
    // `kReadingStreakIcon.codePoint == 0xe242`, `fontFamily == 'PhosphorFill'` and
    // `fontPackage == 'phosphor_flutter'` — three assertions, because each could rot on its
    // own — and none of them is expressible now: the constant is deleted and the dependency
    // is out of `pubspec.yaml`. It was a Phosphor glyph because `PhosphorIconsFill.fire`
    // cannot be referenced at all (the package declares `PhosphorIconData extends IconData`
    // and `IconData` is final on this SDK), and before that it was Material's
    // `local_fire_department_rounded`, whose hollow base closes into a blob at 19pt.
    //
    // What replaced all of that is `StreakFlameMark`, generated from the Rive artboard's own
    // point lists — so the assertion worth having is not *which* font but *no* font: the chip
    // and the celebration must draw one silhouette, which is the defect the glyph caused and
    // the reason it went.
    await _pumpChip(tester, days: _run(12, endingOn: today));

    expect(find.byType(StreakFlameMark), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ReadingStreakChip),
        matching: find.byType(Icon),
      ),
      findsNothing,
      reason: 'no icon font anywhere in the chip',
    );
  });

  testWidgets('the flame is derived from the token the numeral uses, not equal to it', (
    tester,
  ) async {
    // 1:1 with the numeral read as too small to register as a flame at all — a filled
    // glyph at 13pt is mostly antialiasing. It is 1.5× that instead, so the two still
    // cannot drift apart if the token changes, without pinning the ratio at 1.
    //
    // **And the box is square, which is what made the swap off the glyph invisible.** The
    // mark fills its `size` on the tall axis and centres the narrow one, exactly as `Icon`
    // laid out, so the chip's height and the row's centring did not move.
    await _pumpChip(tester, days: _run(12, endingOn: today));

    final mark = tester.widget<StreakFlameMark>(find.byType(StreakFlameMark));
    expect(mark.size, AppTextStyles.label.fontSize! * 1.5);
    expect(
      tester.getSize(find.byType(StreakFlameMark)),
      Size.square(AppTextStyles.label.fontSize! * 1.5),
    );
  });

  group('the colour is keyed on today, never on the count', () {
    testWidgets('Given today is recorded, Then the chip is flame-coloured', (
      tester,
    ) async {
      await _pumpChip(tester, days: _run(12, endingOn: today));

      // `kCandleFlame`, not `AppColors.light.flame`: the chip moved to the artboard's
      // amber so it and the streak page draw one orange. See `reading_streak_chip.dart`,
      // which records what that costs in contrast — and note the mark and the numeral are
      // now all there is to move, where this comment used to say "the whole capsule".
      expect(_tint(tester), kCandleFlame);
      // And the hue is the *whole* readout now — see the group below.
      expect(_chipHasNoBox(tester), isTrue);
    });

    testWidgets(
      'Given today is open, Then the chip has no box at all, and still reads the full count',
      (tester) async {
        // The state that decides whether this is a nudge or a scold. The run ended
        // yesterday, so it is intact — the reader has not lost anything, they simply
        // have not read yet, and it is not tomorrow.
        //
        // And the receding rule: cold is not a quieter pill, it is no pill. A bare
        // flame and a grey numeral, so this is not a fourth chrome control every day
        // the reader has not yet read — which is most days.
        final yesterday = DateTime(today.year, today.month, today.day - 1);
        await _pumpChip(tester, days: _run(12, endingOn: yesterday));

        final colors = AppColors.light;
        expect(_tint(tester), colors.secondaryText);
        expect(_chipHasNoBox(tester), isTrue);
      },
    );

    testWidgets('Given a broken run, Then it reads a cold zero', (
      tester,
    ) async {
      // Two days ago is over, so the run really is zero. The record is not lost with
      // it — that lives on the Library Card's tile — and the chip is now the door back
      // rather than an absence where a door used to be.
      final twoDaysAgo = DateTime(today.year, today.month, today.day - 2);
      await _pumpChip(tester, days: _run(12, endingOn: twoDaysAgo));

      expect(find.text('0'), findsOneWidget);
      expect(_tint(tester), AppColors.light.secondaryText);
    });

    testWidgets('a zero is always the cold chip, so zero needs no state', (
      tester,
    ) async {
      // The invariant the design leans on: a run of zero cannot contain today, so
      // `readTodayProvider` is already false and the empty chip *is* the cold chip.
      // If this ever fails, zero has become a third state and needs its own drawing.
      await _pumpChip(tester, days: const {});

      expect(_tint(tester), AppColors.light.secondaryText);
      expect(_chipHasNoBox(tester), isTrue);
    });
  });

  // **There is no box in either state, and this group used to assert the opposite.**
  // It held four cases about a pill: that hot drew a `circular(20)` stadium, that the
  // border reserved 1.5pt whether or not it was visible, and that the footprint
  // therefore never moved. The pill is gone on instruction — Duolingo's own bar draws
  // the streak as a mark and a numeral on the bar's ground, with the hue carrying the
  // state — so what is left to pin is that nothing paints and that the footprint still
  // did not move.
  //
  // The reasoning that lost is in `reading_streak_chip.dart` and is not repeated here,
  // but the short version is that the pill was load-bearing: the amber numeral is
  // 2.00:1 on `surface`, so the shape was saying "recorded" where the ink could not.
  // Removing it leaves a 2.75:1 light-mode / 1.5:1 dark-mode hue delta as the entire
  // visual readout, which is why `Semantics` carrying the run in words is no longer a
  // nicety.
  group('there is no box, in either state', () {
    testWidgets('Given today is recorded, Then nothing is painted behind it', (
      tester,
    ) async {
      await _pumpChip(tester, days: _run(12, endingOn: today));

      expect(_chipHasNoBox(tester), isTrue);
    });

    testWidgets('...and the same is true before today is recorded', (
      tester,
    ) async {
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      await _pumpChip(tester, days: _run(12, endingOn: yesterday));

      expect(_chipHasNoBox(tester), isTrue);
    });

    testWidgets(
      'Given either state, Then the padded footprint keeps the same fixed inset',
      (tester) async {
        // The outer padding never changes, which is half the invariant: nothing here
        // is computed from whether today is recorded.
        //
        // **16.5 × 14.5, and the halves are the point.** They are the three old insets
        // summed — 8 + 7 + 1.5 and 11 + 2 + 1.5 — two of which belonged to the pill (an
        // inner inset holding the ink off its edge, and a border width). Preserved
        // rather than rounded so that dropping the pill moved nothing else: the bar's
        // row of controls lays out to the same pixel and the target is the same 48.5pt
        // tall. The border term is the one that would have been easy to lose, because
        // `Container` folds a border's width into its own effective padding only when a
        // border is present — the same mechanism that, one revision earlier, made a
        // `null` cold decoration shrink the target by 3pt on the days the reader had not
        // read yet.
        await _pumpChip(tester, days: _run(12, endingOn: today));

        final padding = tester
            .widget<Padding>(
              find.byKey(const ValueKey('reading-streak-chip-footprint')),
            )
            .padding;
        expect(
          padding,
          const EdgeInsets.symmetric(horizontal: 16.5, vertical: 14.5),
        );
      },
    );
  });

  testWidgets('the target is widened, and the chip is not grown to fill it', (
    tester,
  ) async {
    // A 44pt ring drawn around a 22pt chip is a failure this design has rejected
    // twice: it makes the control look like it is floating inside a button. So the
    // padding is transparent — the ink stays chip-sized and the touch area does not.
    await _pumpChip(tester, days: _run(12, endingOn: today));

    // The ink is the `Row` now rather than the pill that used to wrap it, which is
    // also the reason this case still means something: with no box, "the chip was not
    // inflated to meet the touch floor" is a claim about the mark and the numeral
    // alone, and they are 19.5pt tall against a 48.5pt target.
    final ink = tester.getSize(
      find.descendant(
        of: find.byKey(const ValueKey('reading-streak-chip-footprint')),
        matching: find.byType(Row),
      ),
    );
    final target = tester.getSize(find.byType(GestureDetector));

    expect(target.height, greaterThanOrEqualTo(44));
    expect(
      ink.height,
      lessThan(target.height),
      reason: 'the chip must not have been inflated to meet the touch floor',
    );
  });

  testWidgets('tapping it opens the streak page, which is the number\'s home', (
    tester,
  ) async {
    // **This assertion used to say the opposite, and the reversal is the record.** It read
    // `tapping it goes to the Card`: the chip switched the library's tab to the Library
    // Card, because the streak had no surface of its own and the Card was the nearest thing
    // that showed the figure. The Card was always the wrong home — it is year-scoped and
    // says so in its own label, so the month grid could not live inside it. The streak page
    // is year-agnostic and holds the month, so the home moved there and the Card's streak
    // tile becomes a second pointer.
    final log = _RouteLog();
    await _pumpChip(
      tester,
      days: _run(12, endingOn: today),
      observers: [log],
    );

    await tester.tap(find.byType(StreakFlameMark));
    await tester.pumpAndSettle();

    expect(log.pushed, contains(AppRoutes.readingStreak));
  });

  testWidgets('carries a spoken label, since it draws a glyph and a numeral', (
    tester,
  ) async {
    await _pumpChip(tester, days: _run(12, endingOn: today));

    expect(
      tester.getSemantics(find.byType(ReadingStreakChip)).label,
      contains('12'),
    );
  });
}
