// Tests for the read view's year filter.
//
// One piece of state, three renderings. The sheet has two sizes, so the control
// has two shapes — capsules under the header when expanded, a popover select in
// the header when collapsed — and the popover has a native form as well as a
// Flutter one. The capsule row does not: Flutter lays it out and draws every
// label on every platform, and iOS 26 only lends the glass *behind* the selected
// one. So most of this group is parameterised over both platforms.
//
// Three things this file is careful about:
//
//  1. **No native control may own a label.** `CNSegmentedControl` was the first
//     shape (full width, equal segments, grey track) and per-option `CNButton`s
//     with their own titles were the second — those wrapped the label onto two
//     lines for half a second on every selection change, because swapping a
//     button's style resets its title's font and the 13pt is only re-applied
//     several channel hops later. The glass button that survived is empty: it is
//     the pill's material, sitting behind a Flutter label.
//  2. **The native glass is only asserted behind `useNativeGlass`.**
//     `flutter test` reports Android, so the painted path is what runs by
//     default. `debugDefaultTargetPlatformOverride` picks the rendering and has
//     to be cleared inside the test body, because flutter_test asserts that no
//     foundation debug variable outlives a test. Same shape as
//     `status_selector_test.dart` and `shelf_selector_test.dart`.
//  3. **The native menu's callback is non-nullable**, so `enabled: false` cannot
//     be expressed by passing null the way the Flutter widgets allow. It is gated
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

/// Pumps [filter] and lets the platform-view side settle.
///
/// `CNButton` finishes wiring itself up in a short `Future.delayed` after the
/// view is created; left un-elapsed it is still pending when the tree is disposed
/// and flutter_test fails the test for leaking a timer. Pumped through a helper so
/// no single test ends up carrying the file.
Future<void> _pumpSettled(WidgetTester tester, Widget filter) async {
  await tester.pumpWidget(filter);
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  group('readFilterYears', () {
    test(
      'Given books read across three consecutive years, When derived, Then all '
      'time leads and the years follow newest first',
      () {
        expect(
          readFilterYears([
            _read('a', DateTime(2025, 11, 2)),
            _read('b', DateTime(2026, 3, 4)),
            _read('c', DateTime(2024, 1, 9)),
          ], now: DateTime(2026, 8, 19)),
          [0, 2026, 2025, 2024],
        );
      },
    );

    test('Given a gap year with no books in it, When derived, Then the gap is '
        'filled rather than skipped', () {
      expect(
        readFilterYears([
          _read('a', DateTime(2024, 1, 9)),
          _read('b', DateTime(2022, 6, 1)),
        ], now: DateTime(2024, 8, 19)),
        [0, 2024, 2023, 2022],
        reason:
            '2023 has no book in it, but it sits between two years that do, '
            'and hiding it would make the row depend on reading history '
            'rather than on the calendar',
      );
    });

    test('Given the last finish is older than the current year, When derived, '
        'Then the range still reaches the current year', () {
      expect(
        readFilterYears([
          _read('a', DateTime(2024, 3, 4)),
        ], now: DateTime(2026, 8, 19)),
        [0, 2026, 2025, 2024],
        reason:
            'nobody finished a book in 2025 or 2026 yet, but both years exist '
            'and are worth offering, which is the whole point of the range',
      );
    });

    test('Given a finish dated after the current year, When derived, Then the '
        'range still reaches it rather than truncating', () {
      expect(
        readFilterYears([
          _read('a', DateTime(2027, 1, 1)),
          _read('b', DateTime(2026, 3, 4)),
        ], now: DateTime(2026, 8, 19)),
        [0, 2027, 2026],
        reason:
            'a clock skew or a mistyped date should look odd for one year, '
            'not silently drop the book from every filter besides all time',
      );
    });

    test('Given several books in one year that is also the current year, When '
        'derived, Then all time and that year are both offered', () {
      expect(
        readFilterYears([
          _read('a', DateTime(2026, 3, 4)),
          _read('b', DateTime(2026, 8, 19)),
        ], now: DateTime(2026, 8, 19)),
        [0, 2026],
        reason:
            'the two options do select the same books, which used to be the '
            "argument for offering neither — but the rail's presence must not "
            'depend on how many years a reader happens to have read across, '
            'and 2026 is the year the next finish lands in',
      );
    });

    test(
      'Given one year plus an undated book, When derived, Then the year is worth '
      'offering even with no gap to fill',
      () {
        expect(
          readFilterYears([
            _read('a', DateTime(2026, 3, 4)),
            _read('b', null),
          ], now: DateTime(2026, 8, 19)),
          [0, 2026],
          reason:
              'all time includes the undated book and 2026 does not, so the two '
              'options differ and the filter can do something',
        );
      },
    );

    test(
      'Given only undated books, When derived, Then the current year is still '
      'offered beside all time',
      () {
        expect(
          readFilterYears([_read('a', null)], now: DateTime(2026, 8, 19)),
          [0, 2026],
          reason:
              'all time is the only option that shows the book, so the rail is '
              'the one place that says so — it cannot say it while absent',
        );
      },
    );

    test('Given no books at all, When derived, Then all time and the current year '
        'are offered anyway', () {
      expect(
        readFilterYears(const [], now: DateTime(2026, 8, 19)),
        [0, 2026],
        reason:
            'an empty library was the one read view with no control in it, and '
            'the current year is the one year we know exists without a finish '
            'to anchor it',
      );
    });
  });

  group('nothing to choose between', () {
    testWidgets(
      'Given a single option, When built either way, Then no control is drawn',
      (tester) async {
        for (final expanded in [true, false]) {
          await _pumpSettled(
            tester,
            _wrap(years: const [0], onChanged: (_) {}, expanded: expanded),
          );

          expect(find.byType(CNSegmentedControl), findsNothing);
          expect(find.byType(CNButton), findsNothing);
          expect(find.byType(CNPopupMenuButton), findsNothing);
          expect(find.text('All time'), findsNothing);
        }
      },
    );
  });

  group('the capsule row', () {
    // Parameterised over both platforms, because the row and every label in it
    // are Flutter's on all of them — the platform only lends the glass behind the
    // selected capsule.
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      final on = platform.name;

      testWidgets(
        'Given the sheet is expanded on $on, Then every year is offered at once '
        'and no native control owns the labels',
        (tester) async {
          await _asPlatform(platform, () async {
            await _pumpSettled(
              tester,
              _wrap(onChanged: (_) {}, expanded: true),
            );

            expect(
              find.byType(CNSegmentedControl),
              findsNothing,
              reason:
                  'a segmented control spreads the years across the full width '
                  'inside a track — the drawing is a short row of pills hugging '
                  'their labels',
            );
            expect(
              tester
                  .widgetList<CNButton>(find.byType(CNButton))
                  .every((b) => b.label!.isEmpty),
              isTrue,
              reason:
                  'a native control owning the text is what wrapped the label '
                  'onto two lines for half a second on every selection change; '
                  'the glass button is empty and sits behind a Flutter label',
            );
            for (final label in ['All time', '2026', '2025']) {
              expect(find.text(label), findsOneWidget);
            }
          });
        },
      );

      testWidgets(
        'When a capsule is tapped on $on, Then its year is reported',
        (tester) async {
          await _asPlatform(platform, () async {
            final chosen = <int>[];
            await _pumpSettled(
              tester,
              _wrap(onChanged: chosen.add, expanded: true),
            );

            await tester.tap(find.text('2025'));
            await tester.pump();

            expect(chosen, [2025]);
          });
        },
      );

      testWidgets(
        'Given the library is being edited on $on, When a capsule is tapped, '
        'Then nothing happens',
        (tester) async {
          await _asPlatform(platform, () async {
            final chosen = <int>[];
            await _pumpSettled(
              tester,
              _wrap(onChanged: chosen.add, expanded: true, enabled: false),
            );

            await tester.tap(find.text('2025'));
            await tester.pump();

            expect(chosen, isEmpty);
          });
        },
      );

      testWidgets(
        'When the padding beside a label is tapped on $on, Then the whole pill '
        'answers',
        (tester) async {
          await _asPlatform(platform, () async {
            final chosen = <int>[];
            await _pumpSettled(
              tester,
              _wrap(onChanged: chosen.add, expanded: true),
            );

            // An unselected capsule has no fill, so its padding only responds if
            // the gesture detector is opaque. Without that, most of a short
            // label's pill is a dead zone — 12pt of it either side of "2025".
            final label = tester.getRect(find.text('2025'));
            await tester.tapAt(
              Offset(label.right + 6, label.top + label.height / 2),
            );
            await tester.pump();

            expect(chosen, [2025]);
          });
        },
      );
    }

    testWidgets('Given iOS 26, Then only the selected capsule is backed by glass', (
      tester,
    ) async {
      await _asPlatform(TargetPlatform.iOS, () async {
        // Only meaningful on a host that reports glass support.
        if (!useNativeGlass) return;

        await _pumpSettled(
          tester,
          _wrap(selected: 2026, onChanged: (_) {}, expanded: true),
        );

        expect(
          find.byType(CNButton),
          findsOneWidget,
          reason: 'the glass is the selection, so there is exactly one',
        );
        final glass = tester.widget<CNButton>(find.byType(CNButton));
        expect(glass.config.style, CNButtonStyle.glass);
        expect(
          glass.label,
          isEmpty,
          reason: 'material only — the text above it is Flutter\'s',
        );
        expect(
          glass.config.interaction,
          isTrue,
          reason:
              'interaction is what makes it feel like glass: `CNButton` pushes '
              '`isHighlighted` to UIKit on pointer down, and inert glass is a '
              'picture of a button',
        );
        expect(
          glass.onPressed,
          isNotNull,
          reason:
              'an interactive button joins the gesture arena and usually beats '
              'the row\'s recognizer, so it has to be able to report the year '
              'itself',
        );

        // Geometry rather than tree shape: what matters is that the material
        // lands under the chosen year and not under its neighbours.
        final pill = tester.getRect(find.byType(CNButton));
        expect(pill.contains(tester.getRect(find.text('2026')).center), isTrue);
        expect(
          pill.contains(tester.getRect(find.text('2025')).center),
          isFalse,
        );
      });
    });

    testWidgets(
      'Given a platform with no glass to lend, Then the pill is painted instead',
      (tester) async {
        await _asPlatform(TargetPlatform.android, () async {
          await _pumpSettled(
            tester,
            _wrap(selected: 2026, onChanged: (_) {}, expanded: true),
          );

          expect(
            find.byType(CNButton),
            findsNothing,
            reason:
                'off iOS 26 a CNButton degrades to a CupertinoButton, which is '
                'not a pill — hence the painted fallback',
          );
        });
      },
    );

    testWidgets(
      'When the native glass button wins the tap, Then the year is still reported',
      (tester) async {
        await _asPlatform(TargetPlatform.iOS, () async {
          if (!useNativeGlass) return;

          final chosen = <int>[];
          await _pumpSettled(
            tester,
            _wrap(selected: 2026, onChanged: chosen.add, expanded: true),
          );

          // Driving the callback directly is the point: it stands in for the
          // platform view beating the row's recognizer to the tap.
          tester.widget<CNButton>(find.byType(CNButton)).onPressed!();

          expect(chosen, [2026]);
        });
      },
    );

    testWidgets(
      'Given the library is being edited, When the native glass button fires '
      'anyway, Then the change is swallowed',
      (tester) async {
        await _asPlatform(TargetPlatform.iOS, () async {
          if (!useNativeGlass) return;

          final chosen = <int>[];
          await _pumpSettled(
            tester,
            _wrap(
              selected: 2026,
              onChanged: chosen.add,
              expanded: true,
              enabled: false,
            ),
          );

          tester.widget<CNButton>(find.byType(CNButton)).onPressed!();

          expect(chosen, isEmpty);
        });
      },
    );

    testWidgets('Then every capsule shares the label weight, selected or not', (
      tester,
    ) async {
      await _asPlatform(TargetPlatform.android, () async {
        await _pumpSettled(
          tester,
          _wrap(selected: 2026, onChanged: (_) {}, expanded: true),
        );

        FontWeight? weightOf(String label) =>
            tester.widget<Text>(find.text(label)).style?.fontWeight;

        expect(
          weightOf('2026'),
          weightOf('2025'),
          reason:
              'Flighty\'s tab pills are one weight throughout — the pill and '
              'the label colour carry the selection between them, and bolding '
              'the chosen one as well reads as two type sizes in one row',
        );
        expect(weightOf('All time'), weightOf('2026'));
      });
    });

    testWidgets('When a capsule is pressed, Then it shrinks and springs back', (
      tester,
    ) async {
      await _asPlatform(TargetPlatform.android, () async {
        await _pumpSettled(tester, _wrap(onChanged: (_) {}, expanded: true));

        double scaleOf(String label) => tester
            .widget<AnimatedScale>(
              find.ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedScale),
              ),
            )
            .scale;

        expect(scaleOf('2025'), 1);

        // An unselected capsule has no platform view to give it a press
        // response, so this is the only feedback it gets.
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('2025')),
        );
        await tester.pump();
        expect(scaleOf('2025'), lessThan(1));
        expect(scaleOf('All time'), 1, reason: 'only the pressed one responds');

        await gesture.up();
        await tester.pumpAndSettle();
        expect(scaleOf('2025'), 1);
      });
    });

    testWidgets(
      'Given the library is being edited, When a capsule is pressed, Then it does '
      'not even shrink',
      (tester) async {
        await _asPlatform(TargetPlatform.android, () async {
          await _pumpSettled(
            tester,
            _wrap(onChanged: (_) {}, expanded: true, enabled: false),
          );

          final gesture = await tester.startGesture(
            tester.getCenter(find.text('2025')),
          );
          await tester.pump();

          expect(
            tester
                .widget<AnimatedScale>(
                  find.ancestor(
                    of: find.text('2025'),
                    matching: find.byType(AnimatedScale),
                  ),
                )
                .scale,
            1,
            reason:
                'a pill that cannot answer should not look like it is about to',
          );

          await gesture.up();
        });
      },
    );

    testWidgets(
      'Given the selected capsule is native, Then Flutter does not scale it too',
      (tester) async {
        await _asPlatform(TargetPlatform.iOS, () async {
          if (!useNativeGlass) return;

          await _pumpSettled(
            tester,
            _wrap(selected: 2026, onChanged: (_) {}, expanded: true),
          );

          expect(
            find.ancestor(
              of: find.text('2026'),
              matching: find.byType(AnimatedScale),
            ),
            findsNothing,
            reason:
                'UIKit gives the glass its own press response, and transforming a '
                'platform view in hybrid composition is unreliable',
          );
          expect(
            find.ancestor(
              of: find.text('2025'),
              matching: find.byType(AnimatedScale),
            ),
            findsOneWidget,
            reason: 'the ones Flutter draws still shrink',
          );
        });
      },
    );

    testWidgets(
      'Given a year is selected, Then it is announced as a selected button',
      (tester) async {
        await _asPlatform(TargetPlatform.android, () async {
          final handle = tester.ensureSemantics();
          await _pumpSettled(
            tester,
            _wrap(selected: 2026, onChanged: (_) {}, expanded: true),
          );

          // `isSemantics` rather than reading flags off the node: the flags are
          // tri-state now, and only these three properties are the point.
          expect(
            tester.getSemantics(find.text('2026')),
            isSemantics(label: '2026', isButton: true, isSelected: true),
          );
          expect(
            tester.getSemantics(find.text('2025')),
            isSemantics(isButton: true, isSelected: false),
          );

          handle.dispose();
        });
      },
    );
  });

  group('the collapsed popover, native glass', () {
    testWidgets(
      'Given the sheet is collapsed, Then a glass popover shows the selection and '
      'checks it in the menu',
      (tester) async {
        await _asPlatform(TargetPlatform.iOS, () async {
          // Only meaningful on a host that reports glass support.
          if (!useNativeGlass) return;

          await _pumpSettled(
            tester,
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
        await _pumpSettled(
          tester,
          _wrap(onChanged: chosen.add, expanded: false),
        );

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
          await _pumpSettled(
            tester,
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

  group('the collapsed popover, Flutter fallback', () {
    testWidgets(
      'Given the sheet is collapsed, Then only the selection is shown until the '
      'menu is opened',
      (tester) async {
        await _asPlatform(TargetPlatform.android, () async {
          await _pumpSettled(tester, _wrap(onChanged: (_) {}, expanded: false));

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
        await _pumpSettled(
          tester,
          _wrap(onChanged: chosen.add, expanded: false),
        );

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
          await _pumpSettled(
            tester,
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
