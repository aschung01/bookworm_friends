// Finding the card a `LibrarySheet` paints, as opposed to the box it occupies.
//
// The two are no longer the same rect, and the difference is the point: the sheet's
// box is pinned to the bottom of the screen at a height layout decides, and the card
// floats inside it, pulling in from the sides and the bottom by as much as the sheet
// falls short of covering the screen. Anything about the sheet's *edges* has to be
// measured against the card; anything about the space it takes from the library has
// to be measured against the box.
//
// Shared because two test files need it, and a duplicated widget predicate is a
// duplicated definition of what "the sheet" means.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/library_sheet.dart';

/// The floating card. Matched on the *shape* it is painted with — a
/// [RoundedSuperellipseBorder] inside a [ShapeDecoration] — rather than on
/// "the first DecoratedBox": the handle, the title and every tile a body draws use
/// [BoxDecoration], and the Card sheet's share button is a `ShapeDecoration` with a
/// [StadiumBorder], which made a looser predicate ambiguous the moment a test looked
/// at an *expanded* sheet. This does not depend on the depth of the chrome above it.
final sheetCard = find.descendant(
  of: find.byType(LibrarySheet),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.decoration is ShapeDecoration &&
        (widget.decoration as ShapeDecoration).shape
            is RoundedSuperellipseBorder,
  ),
);

Rect sheetCardRect(WidgetTester tester) => tester.getRect(sheetCard);

/// The card's corners, read off the shape it is painted with rather than inferred
/// from the pixels.
BorderRadius sheetCardRadius(WidgetTester tester) {
  final decoration =
      tester.widget<DecoratedBox>(sheetCard).decoration as ShapeDecoration;
  final shape = decoration.shape as RoundedSuperellipseBorder;
  return shape.borderRadius as BorderRadius;
}
