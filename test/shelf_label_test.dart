// Tests for the shelf "tab" shown on a book cover.
//
// Two things it has to get right, both of which showed up on the book-details
// page for a book from a friend's library:
//   1. An unresolvable shelf (empty name) must not paint an empty tab.
//   2. A long shelf name must stay inside its bounds instead of running off
//      the edge of the screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';

Widget _wrap(Widget child, {double width = 320}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SizedBox(
        width: width,
        height: 200,
        // Mirrors the book cover: the tab is positioned in a stack, so it is
        // free to size itself rather than being stretched to the full width.
        child: Stack(children: [Positioned(bottom: 0, right: 0, child: child)]),
      ),
    ),
  );
}

void main() {
  testWidgets('Given a shelf name, Then the tab hugs its label', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const ShelfLabel(label: 'Novels')));

    expect(find.text('Novels'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The tab shrink-wraps its label (plus 9pt of padding per side) instead of
    // stretching across the space it is offered, which is what made it look
    // oversized on the book-details page.
    final labelWidth = tester.getSize(find.text('Novels')).width;
    expect(
      tester.getSize(find.byType(ShelfLabel)).width,
      closeTo(labelWidth + 18, 0.5),
    );
  });

  testWidgets(
    "Given a book whose shelf can't be resolved, Then no tab is painted",
    (tester) async {
      await tester.pumpWidget(_wrap(const ShelfLabel(label: '')));

      expect(find.byType(SizedBox), findsWidgets);
      expect(find.text(''), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Given a long shelf name, Then the tab stays within its maximum width',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ShelfLabel(
            label: 'Books I started but have not finished yet',
            maxWidth: 140,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(ShelfLabel)).width,
        lessThanOrEqualTo(140),
      );
    },
  );
}
