// Tests for the read view's year filter.
//
// One piece of state, four renderings. The sheet has two sizes, so the control
// has two shapes — capsules under the header when expanded, a popover select in
// the header when collapsed — and each of those is the platform's own control on
// iOS 26 and a Flutter one everywhere else.
//
// Two things this file is careful about:
//
//  1. **The native controls are only ever asserted behind `useNativeGlass`.**
//     `flutter test` reports Android, so the fallback is what actually runs here;
//     a test that pumped `CNSegmentedControl` directly would be asserting nothing.
//     `debugDefaultTargetPlatformOverride` picks the rendering and has to be
//     cleared inside the test body, because flutter_test asserts that no
//     foundation debug variable outlives a test. Same shape as
//     `status_selector_test.dart` and `shelf_selector_test.dart`.
//  2. **The native callbacks are non-nullable**, so `enabled: false` cannot be
//     expressed by passing null the way the Flutter widgets allow. It is gated
//     *inside* the callback instead, and that gate is easy to drop — hence a test
//     for it on both paths.
//
// `readFilterYears` gets its own group because it is where the decision to fetch
// every finished book landed: a year-filtered query can only ever report the year
// you asked for, so the year list has to be derived from the books themselves.

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';
import 'package:bookworm_friends/ui/widgets/read_filter.dart';

const _years = [0, 2026, 2025];

Book _read(String id, DateTime? finished) => Book(
  id: id,
  userId: 'u',
  shelfId: 's',
  isbn: id,
  title: 'Book $id',
  thumbnail: '',
  // 2 is `bookStatusFinished`; inlined so this stays clear of the provider
  // library that declares it.
  status: 2,
  position: 0,
  finishDate: finished,
  createdAt: DateTime(2024),
);

Widget _wrap({
  List<int> years = _years,
  int selected = 0,
  required ValueChanged<int> onChanged,
  required bool expanded,
  bool enabled = true,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ReadFilter(
          years: years,
          selected: selected,
          onChanged: onChanged,
          expanded: expanded,
          enabled: enabled,
        ),
      ),
    ),
  );
}

/// Runs [body] with [platform] reported as the target platform.
Future<void> _asPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  group('readFilterYears', () {
    test(
      'Given books read across three years, When derived, Then all time leads '
      'and the years follow newest first',
      () {
        expect(
          readFilterYears([
            _read('a', DateTime(2025, 11, 2)),
            _read('b', DateTime(2026, 3, 4)),
            _read('c', DateTime(2024, 1, 9)),
          ]),
          [0, 2026, 2025, 2024],
        );
      },
    );

    test(
      'Given several books in one year, When derived, Then it appears once',
      () {
        expect(
          readFilterYears([
            _read('a', DateTime(2026, 3, 4)),
            _read('b', DateTime(2026, 8, 19)),
          ]),
          [0],
          reason:
              'one year and nothing undated means all time and that year select '
              'the same books — a control whose options are indistinguishable is '
              'noise, so there is nothing to offer',
        );
      },
    );

    test(
      'Given one year plus an undated book, When derived, Then the year is worth '
      'offering',
      () {
        expect(
          readFilterYears([_read('a', DateTime(2026, 3, 4)), _read('b', null)]),
          [0, 2026],
          reason:
              'all time includes the undated book and 2026 does not, so the two '
              'options differ and the filter can do something',
        );
      },
    );

    test(
      'Given only undated books, When derived, Then there is nothing to filter',
      () {
        expect(readFilterYears([_read('a', null)]), [0]);
      },
    );

    test(
      'Given no books at all, When derived, Then there is nothing to filter',
      () {
        expect(readFilterYears(const []), [0]);
      },
    );
  });

  group('nothing to choose between', () {
    testWidgets(
      'Given a single option, When built either way, Then no control is drawn',
      (tester) async {
        for (final expanded in [true, false]) {
          await tester.pumpWidget(
            _wrap(years: const [0], onChanged: (_) {}, expanded: expanded),
          );

          expect(find.byType(CNSegmentedControl), findsNothing);
          expect(find.byType(CNPopupMenuButton), findsNothing);
          expect(find.text('All time'), findsNothing);
        }
      },
    );
  });

  group('native glass rendering', () {
    testWidgets(
      'Given the sheet is expanded, Then a native segmented control offers every '
      'year with the current one selected',
      (tester) async {
        await _asPlatform(TargetPlatform.iOS, () async {
          // Only meaningful on a host that reports glass support.
          if (!useNativeGlass) return;

          await tester.pumpWidget(
            _wrap(selected: 2025, onChanged: (_) {}, expanded: true),
          );

          final control = tester.widget<CNSegmentedControl>(
            find.byType(CNSegmentedControl),
          );
          expect(control.labels, ['All time', '2026', '2025']);
          expect(control.selectedIndex, 2);
        });
      },
    );

    testWidgets(
      'When a segment is chosen, Then the year is reported rather than its index',
      (tester) async {
        await _asPlatform(TargetPlatform.iOS, () async {
          if (!useNativeGlass) return;

          final chosen = <int>[];
          await tester.pumpWidget(_wrap(onChanged: chosen.add, expanded: true));

          tester
              .widget<CNSegmentedControl>(find.byType(CNSegmentedControl))
              .onValueChanged(1);

          expect(chosen, [2026]);
        });
      },
    );

    testWidgets(
      'Given the library is being edited, When the native control fires anyway, '
      'Then the change is swallowed',
      (tester) async {
        await _asPlatform(TargetPlatform.iOS, () async {
          if (!useNativeGlass) return;

          final chosen = <int>[];
          await tester.pumpWidget(
            _wrap(onChanged: chosen.add, expanded: true, enabled: false),
          );

          // `onValueChanged` is non-nullable, so being inert has to be a gate
          // inside the callback rather than an absent one.
          tester
              .widget<CNSegmentedControl>(find.byType(CNSegmentedControl))
              .onValueChanged(1);

          expect(chosen, isEmpty);
        });
      },
    );

    testWidgets(
      'Given the sheet is collapsed, Then a glass popover shows the selection and '
      'checks it in the menu',
      (tester) async {
        await _asPlatform(TargetPlatform.iOS, () async {
          if (!useNativeGlass) return;

          await tester.pumpWidget(
            _wrap(selected: 2026, onChanged: (_) {}, expanded: false),
          );

          final button = tester.widget<CNPopupMenuButton>(
            find.byType(CNPopupMenuButton),
          );
          expect(button.buttonLabel, '2026');
          expect(button.buttonStyle, CNButtonStyle.glass);
          expect(button.items.length, _years.length);

          final checked = button.items
              .whereType<CNPopupMenuItem>()
              .where((item) => item.checked)
              .map((item) => item.label)
              .toList();
          expect(checked, ['2026']);
        });
      },
    );

    testWidgets('When a menu item is chosen, Then its year is reported', (
      tester,
    ) async {
      await _asPlatform(TargetPlatform.iOS, () async {
        if (!useNativeGlass) return;

        final chosen = <int>[];
        await tester.pumpWidget(_wrap(onChanged: chosen.add, expanded: false));

        // The menu itself is native, so drive the callback the platform invokes.
        tester
            .widget<CNPopupMenuButton>(find.byType(CNPopupMenuButton))
            .onSelected(2);

        expect(chosen, [2025]);
      });
    });

    testWidgets(
      'Given the library is being edited, When the native menu fires anyway, Then '
      'the change is swallowed',
      (tester) async {
        await _asPlatform(TargetPlatform.iOS, () async {
          if (!useNativeGlass) return;

          final chosen = <int>[];
          await tester.pumpWidget(
            _wrap(onChanged: chosen.add, expanded: false, enabled: false),
          );

          tester
              .widget<CNPopupMenuButton>(find.byType(CNPopupMenuButton))
              .onSelected(2);

          expect(chosen, isEmpty);
        });
      },
    );
  });

  group('Flutter fallback', () {
    testWidgets(
      'Given the sheet is expanded, Then every year is offered as a capsule at '
      'once',
      (tester) async {
        await _asPlatform(TargetPlatform.android, () async {
          await tester.pumpWidget(_wrap(onChanged: (_) {}, expanded: true));

          expect(find.byType(CNSegmentedControl), findsNothing);
          for (final label in ['All time', '2026', '2025']) {
            expect(find.text(label), findsOneWidget);
          }
        });
      },
    );

    testWidgets('When a capsule is tapped, Then its year is reported', (
      tester,
    ) async {
      await _asPlatform(TargetPlatform.android, () async {
        final chosen = <int>[];
        await tester.pumpWidget(_wrap(onChanged: chosen.add, expanded: true));

        await tester.tap(find.text('2025'));
        await tester.pump();

        expect(chosen, [2025]);
      });
    });

    testWidgets(
      'Given the library is being edited, When a capsule is tapped, Then nothing '
      'happens',
      (tester) async {
        await _asPlatform(TargetPlatform.android, () async {
          final chosen = <int>[];
          await tester.pumpWidget(
            _wrap(onChanged: chosen.add, expanded: true, enabled: false),
          );

          await tester.tap(find.text('2025'));
          await tester.pump();

          expect(chosen, isEmpty);
        });
      },
    );

    testWidgets(
      'Given the sheet is collapsed, Then only the selection is shown until the '
      'menu is opened',
      (tester) async {
        await _asPlatform(TargetPlatform.android, () async {
          await tester.pumpWidget(_wrap(onChanged: (_) {}, expanded: false));

          expect(find.byType(CNPopupMenuButton), findsNothing);
          expect(find.text('All time'), findsOneWidget);
          expect(
            find.text('2026'),
            findsNothing,
            reason:
                'the collapsed header has room for one label, not for the whole '
                'list — that is why this shape exists',
          );

          await tester.tap(find.text('All time'));
          await tester.pumpAndSettle();

          expect(find.text('2026'), findsOneWidget);
          expect(find.text('2025'), findsOneWidget);
        });
      },
    );

    testWidgets('When a menu entry is picked, Then its year is reported', (
      tester,
    ) async {
      await _asPlatform(TargetPlatform.android, () async {
        final chosen = <int>[];
        await tester.pumpWidget(_wrap(onChanged: chosen.add, expanded: false));

        await tester.tap(find.text('All time'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('2025'));
        await tester.pumpAndSettle();

        expect(chosen, [2025]);
      });
    });

    testWidgets(
      'Given the library is being edited, When the popover is tapped, Then it '
      'does not open',
      (tester) async {
        await _asPlatform(TargetPlatform.android, () async {
          await tester.pumpWidget(
            _wrap(onChanged: (_) {}, expanded: false, enabled: false),
          );

          await tester.tap(find.text('All time'));
          await tester.pumpAndSettle();

          expect(find.text('2026'), findsNothing);
        });
      },
    );
  });
}
