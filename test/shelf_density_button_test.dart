// The one control added back to the library bar. It earns its width by changing what
// every shelf on screen is — nothing else can reach the density — and the alternative
// was a three-glyph segmented pill costing 110-130pt of the row.
//
// The assertions worth understanding: the button names the state you are IN rather
// than the one you would get, and it is absent while editing, where density does not
// apply.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/shelf_density_provider.dart';

import 'support/home_page_harness.dart';
import 'support/prefs.dart';

Future<void> _pump(
  WidgetTester tester, {
  ShelfDensity density = ShelfDensity.covers,
  List<Shelf>? shelves,
}) async => pumpHome(
  tester,
  shelves: shelves,
  extraOverrides: [
    await sharedPreferencesOverride({'shelf_density': density.name}),
  ],
);

/// The density button, found by the glyph of the state it is in.
///
/// By icon rather than by semantics label: on the Material fallback the label is an
/// `IconButton` tooltip, and `library_bar_test` finds this row's controls the same
/// way. It also pins the glyph mapping, which is the thing a reader actually sees.
Finder _button(IconData icon) =>
    find.descendant(of: find.byType(AppBar), matching: find.byIcon(icon));

/// The Material fallbacks, which are what the tests see: `find.bySemanticsLabel` does
/// not reach an `AdaptiveIconButton` on this path, because the label becomes an
/// `IconButton` tooltip.
///
/// `Icons.book` for covers — a book, matching the `book.closed` SF Symbol the native
/// path draws.
const _covers = Icons.book;
const _spines = Icons.view_week;

void main() {
  testWidgets(
    'Given the covers density, When the bar is drawn, Then the button shows the '
    'covers glyph',
    (tester) async {
      await _pump(tester);

      // Shows the current state, not the next one: this is a mode indicator, and "what
      // am I looking at" is the more useful question for one to answer.
      expect(_button(_covers), findsOne);
      expect(_button(_spines), findsNothing);
    },
  );

  testWidgets(
    'Given the spines density, When the bar is drawn, Then the button shows the '
    'spines glyph',
    (tester) async {
      await _pump(tester, density: ShelfDensity.spines);

      expect(_button(_spines), findsOne);
    },
  );

  testWidgets(
    'Given the button, When it is tapped twice, Then the cycle returns to covers',
    (tester) async {
      await _pump(tester);

      await tester.tap(_button(_covers));
      await tester.pumpAndSettle();
      expect(_button(_spines), findsOne);

      await tester.tap(_button(_spines));
      await tester.pumpAndSettle();
      expect(_button(_covers), findsOne);
    },
  );

  testWidgets(
    'Given the button, When it is tapped, Then it carries the label of the state it '
    'moved to',
    (tester) async {
      await _pump(tester);
      await tester.tap(_button(_covers));
      await tester.pumpAndSettle();

      // The label names the state you are in, so the change is announced rather than
      // silent.
      expect(find.byTooltip('Shelf view: spines'), findsOne);
    },
  );

  testWidgets(
    'Given edit mode, When the bar is drawn, Then the density button is gone',
    (tester) async {
      // A book in progress, because `enterEditMode` holds a `BookWidget` and in
      // `spines` a book that is not in progress has no cover to hold. The gesture
      // itself works on a spine — the draggable wraps whatever the density drew — but
      // the helper looks for a cover.
      await _pump(
        tester,
        density: ShelfDensity.spines,
        shelves: [
          testShelf('s1', [
            testBook(
              'r',
              's1',
              title: 'In Progress',
              status: bookStatusReading,
            ),
            testBook('p', 's1', position: 1, title: 'Plain'),
          ]),
        ],
      );
      await enterEditMode(tester);

      // Density does not apply while rearranging: `spines` is edited as spines, so
      // there is nothing to choose here.
      expect(_button(_spines), findsNothing);
      expect(_button(_covers), findsNothing);
    },
  );
}
