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
// number is this?"; beside a shelf-count badge, `▣ 12` read as a third count.
//
// The state rule is the part worth pinning, because getting it wrong inverts the
// feature: the colour is keyed on whether **today** is recorded, never on the count.
// The count is intact all day and only the day's own status changes at the 4am
// rollover, so keying it on the number made the chip green at 9am on an unstamped day
// — the opposite of a nudge. And the cold state still reads the full count in grey,
// not red and not empty: the streak is intact until the day actually ends, and a chip
// that panics in the morning is one readers learn to resent.
//
// **The cold state has no box at all**, which is a third reversal. It used to draw a
// grey-outlined pill every day the reader had not yet read — most days — making this a
// fourth control in a row of three real buttons (the density toggle, the shelves
// button, the avatar). A bare flame and a grey numeral read as ambient status instead;
// the pill returns, full-radius, only once there is something to mark. And it is a
// drawn pill rather than native glass either way — glass exposes one tint per control
// with no separate fill/label knob, which cannot express this chip's two-tone system,
// and the bar underneath is opaque, so there would be nothing for glass to refract.
//
// The third drawn state — amber when the evening is running out — is **not built**.
// See `docs/superpowers/plans/2026-09-16-reading-streaks-plan.md`, Task 12: the hour
// that counts as "late" is undecided, and the mockup draws that state as a dashed
// border rather than amber, so there are two open questions behind one pixel.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/reading_date.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/providers/reading_days_provider.dart';
import 'package:bookworm_friends/ui/widgets/reading_streak_chip.dart';

/// Serves a fixture instead of hitting Supabase.
class _FakeReadingDays extends ReadingDaysNotifier {
  _FakeReadingDays(this.days);

  final Set<DateTime> days;

  @override
  Future<Set<DateTime>> build() async => days;
}

/// Never resolves, so the chip can be caught mid-fetch.
class _PendingReadingDays extends ReadingDaysNotifier {
  @override
  Future<Set<DateTime>> build() => Completer<Set<DateTime>>().future;
}

/// A run of [length] days ending on [endingOn], as reading dates.
Set<DateTime> _run(int length, {required DateTime endingOn}) => {
  for (var back = 0; back < length; back++)
    DateTime(endingOn.year, endingOn.month, endingOn.day - back),
};

Future<ProviderContainer> _pumpChip(
  WidgetTester tester, {
  required Set<DateTime> days,
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
        home: const Scaffold(body: Center(child: ReadingStreakChip())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The chip's own decorated box, present only while today is recorded. Excludes the
/// transparent padding that widens its target.
BoxDecoration _chipDecoration(WidgetTester tester) => tester
    .widgetList<Container>(find.byType(Container))
    .map((container) => container.decoration)
    .whereType<BoxDecoration>()
    .firstWhere((decoration) => decoration.borderRadius != null);

/// Whether the cold chip's box is fully invisible — both its fill and its border
/// transparent — rather than the grey outline it used to keep.
///
/// **Not a null decoration.** That was the first cut, and a footprint test below
/// caught what it actually did: `Container` folds a border's width into its own
/// padding only when a border exists, so removing the decoration outright shrank
/// the box by 2 × 1.5pt between states. The border stays, at the same width, and
/// only its colour disappears.
bool _chipHasNoBox(WidgetTester tester) {
  final decoration = _chipDecoration(tester);
  final border = decoration.border as Border;
  return decoration.color == Colors.transparent &&
      border.top.color == Colors.transparent;
}

/// The chip's tint, asserted through the icon rather than the numeral.
///
/// Reads both and requires them to agree: the glyph and the digits are separate widgets
/// now, so "the chip is brand" is only true if neither was left behind.
Color? _tint(WidgetTester tester) {
  final icon = tester.widget<Icon>(find.byIcon(kReadingStreakIcon));
  final text = tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(ReadingStreakChip),
          matching: find.byType(Text),
        ),
      )
      .first;
  expect(
    icon.color,
    text.style?.color,
    reason: 'the flame and the numeral must carry the same tint',
  );
  return icon.color;
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

    expect(find.byIcon(kReadingStreakIcon), findsNothing);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('Given no run, Then it still draws, reading zero', (
    tester,
  ) async {
    // The reversal. Omitting here is what hid the chip from 136 of 137 accounts, and a
    // reader cannot start a run they have never been shown.
    await _pumpChip(tester, days: const {});

    expect(find.byIcon(kReadingStreakIcon), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('Given a run, Then it reads the flame and the count', (
    tester,
  ) async {
    await _pumpChip(tester, days: _run(12, endingOn: today));

    expect(find.byIcon(kReadingStreakIcon), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('a flame rather than a stamp', (tester) async {
    // Pinned as an identity, not a lookalike: `Icons.local_fire_department` and its
    // `_outlined` sibling are both flames and only one is filled, and a filled glyph is
    // what carries at the 13pt the `label` token sets.
    expect(kReadingStreakIcon, Icons.local_fire_department_rounded);
  });

  testWidgets(
    'the glyph is derived from the token the numeral uses, not equal to it',
    (tester) async {
      // 1:1 with the numeral read as too small to register as a flame at all — a filled
      // glyph at 13pt is mostly antialiasing. It is 1.5× that instead, so the two still
      // cannot drift apart if the token changes, without pinning the ratio at 1.
      await _pumpChip(tester, days: _run(12, endingOn: today));

      final icon = tester.widget<Icon>(find.byIcon(kReadingStreakIcon));
      expect(icon.size, AppTextStyles.label.fontSize! * 1.5);
    },
  );

  group('the colour is keyed on today, never on the count', () {
    testWidgets('Given today is recorded, Then the chip is flame-coloured', (
      tester,
    ) async {
      await _pumpChip(tester, days: _run(12, endingOn: today));

      final colors = AppColors.light;
      expect(_tint(tester), colors.flame);
      expect(_chipDecoration(tester).color, isNot(Colors.transparent));
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

  group('the box only exists while there is something to mark', () {
    testWidgets('Given today is recorded, Then the pill is a full stadium', (
      tester,
    ) async {
      // Not a new number: `_SegmentChip`'s own radius, so this chip's shape matches
      // the app's other pill rather than inventing its own. And the chip's own height
      // is well under 40, so this clamps to a true stadium, not a rounded rectangle.
      await _pumpChip(tester, days: _run(12, endingOn: today));

      expect(_chipDecoration(tester).borderRadius, BorderRadius.circular(20));
    });

    testWidgets(
      'Given either state, Then the border reserves the same width regardless of colour',
      (tester) async {
        // The mechanism behind the footprint staying put, asserted directly rather
        // than as a derived pixel diff: pumping two fixtures into one test to compare
        // sizes raced a pending `autoDispose` timer between them and made this flaky
        // to run, not just to write. `Container` only folds a border's width into its
        // own padding when a border exists at all — the bug this guards against set
        // the whole decoration to `null` when cold, which took the border's width out
        // of the layout along with its colour.
        final yesterday = DateTime(today.year, today.month, today.day - 1);
        await _pumpChip(tester, days: _run(12, endingOn: yesterday));

        final cold = _chipDecoration(tester).border as Border;
        expect(cold.top.width, 1.5);
        expect(cold.top.color, Colors.transparent);
      },
    );

    testWidgets('...and the same is true once there is something to mark', (
      tester,
    ) async {
      await _pumpChip(tester, days: _run(12, endingOn: today));

      final hot = _chipDecoration(tester).border as Border;
      expect(hot.top.width, 1.5);
      expect(hot.top.color, isNot(Colors.transparent));
    });

    testWidgets(
      'Given either state, Then the padded footprint keeps the same fixed inset',
      (tester) async {
        // The outer padding never changes, which is the other half of the invariant:
        // nothing here is computed from whether today is recorded.
        await _pumpChip(tester, days: _run(12, endingOn: today));

        final padding = tester
            .widget<Padding>(
              find.byKey(const ValueKey('reading-streak-chip-footprint')),
            )
            .padding;
        expect(
          padding,
          const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
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

    final ink = tester.getSize(
      find.ancestor(
        of: find.byIcon(kReadingStreakIcon),
        matching: find.byType(Container),
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

  testWidgets('tapping it goes to the Card, which is the number\'s home', (
    tester,
  ) async {
    final container = await _pumpChip(tester, days: _run(12, endingOn: today));
    // Subscribed, not just read. These are `autoDispose`, so a bare `read` is disposed
    // the instant it returns — the tap would then set state on a fresh instance that
    // this test never sees, and the assertion would read the default back.
    addTearDown(container.listen(libraryTabProvider, (_, _) {}).close);
    addTearDown(container.listen(selectedFriendProvider, (_, _) {}).close);
    addTearDown(container.listen(friendsSheetLevelProvider, (_, _) {}).close);

    expect(container.read(libraryTabProvider), LibraryTab.library);

    await tester.tap(find.byIcon(kReadingStreakIcon));
    await tester.pumpAndSettle();

    expect(container.read(libraryTabProvider), LibraryTab.card);
    // A tab switch also ends any visit, the way `ShellChrome._selectTab` does — all
    // three tabs always mean *yours*.
    expect(container.read(selectedFriendProvider), isNull);
    expect(container.read(friendsSheetLevelProvider), FriendsSheetLevel.list);
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
