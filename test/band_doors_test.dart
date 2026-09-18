// The band's two doors, and the column their chevrons share.
//
// The band prints two reading facts and, since the app bar's pencil was retired,
// both of them are how you change them: the period card opens the change-status
// sheet (status, start, finish — exactly what it displays), and the progress row
// opens the percent wheel. This file is about the properties that made that
// survivable rather than confusing.
//
// **The chevrons are column-aligned, and that is asserted numerically here** because
// it is the one thing about this layout that looks like a mistake when it is wrong
// rather than looking wrong. The card is inset 10pt inside the band, so its chevron
// naturally lands 10pt short of the row's; the *card's* glyph is pulled out to meet
// the row, never the other way round — the row was settled first.
//
// **A door only where it can be opened.** On a friend's book both rows still read,
// and neither draws a handle: no chevron, no tap target, no press state. A chevron on
// a row that does nothing is a lie about what the row does.
//
// **And the band does not get taller for any of this.** The progress row's 44pt tap
// target is 14pt deeper than its ink, and those 14 come out of the band's 16pt bottom
// padding. The band sits above a pinned tab strip on the one screen whose last
// redesign was about lifting content up, so height here is not free.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/band_progress_edge.dart';
import 'package:bookworm_friends/ui/widgets/band_progress_row.dart';
import 'package:bookworm_friends/ui/widgets/book_status_badge.dart';
import 'package:bookworm_friends/ui/widgets/reading_period_row.dart';

import 'support/book_details_harness.dart';

/// The chevron inside a given row, whichever row that is.
Finder _chevronIn(Type row) => find.descendant(
  of: find.byType(row),
  matching: find.byIcon(Icons.chevron_right),
);

void main() {
  group('the progress row', () {
    testWidgets(
      'Given a position, When the band is drawn, Then the page and percent are printed',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: readingBook(ownerId: meId, progress: 0.46, pageCount: 320),
          signedInAs: meId,
        );

        expect(find.byType(BandProgressRow), findsOneWidget);
        expect(find.text('46%'), findsOneWidget);
        // One rounding site, shared with the wheel's rider — so these can never
        // disagree about which page 46% of 320 is.
        expect(
          find.descendant(
            of: find.byType(BandProgressRow),
            matching: find.textContaining('p.147', findRichText: true),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Given no page count, Then the percent stands alone with no substitute',
      (tester) async {
        // About two reading books in three. The percent is the stored fact and is
        // enough on its own; there is no apology in the row's place.
        await pumpBookDetails(
          tester,
          book: readingBook(ownerId: meId, progress: 0.46),
          signedInAs: meId,
        );

        expect(find.byType(BandProgressRow), findsOneWidget);
        expect(find.text('46%'), findsOneWidget);
        expect(find.textContaining('p.', findRichText: true), findsNothing);
      },
    );

    testWidgets('Given a finished book, Then there is no row', (tester) async {
      await pumpBookDetails(
        tester,
        book: finishedBook(ownerId: meId),
        signedInAs: meId,
      );

      expect(find.byType(BandProgressRow), findsNothing);
    });

    testWidgets('opens the percent wheel directly, not the status sheet', (
      tester,
    ) async {
      // Straight to the wheel: the row already shows the value, so a form in
      // between would ask the reader to find what they just tapped on.
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: meId, progress: 0.46, pageCount: 320),
        signedInAs: meId,
      );

      await tester.tap(find.byType(BandProgressRow));
      await tester.pumpAndSettle();

      expect(find.text('How far in?'), findsOneWidget);
      expect(find.text('Change reading status'), findsNothing);
    });

    testWidgets('reaches 44pt of target out of 30pt of ink', (tester) async {
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: meId, progress: 0.46, pageCount: 320),
        signedInAs: meId,
      );

      // 30pt of ink plus the 14 taken out of the band's bottom padding, which is
      // what keeps the band exactly as tall as it was before it had a door.
      expect(
        tester.getSize(find.byType(BandProgressRow)).height,
        30 + kBandProgressRowSpill,
      );
      expect(kBandProgressRowSpill + kBandProgressRowResidualPadding, 16);
    });
  });

  group('the period card', () {
    testWidgets('opens the sheet the retired pencil used to open', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: meId),
        signedInAs: meId,
        // The sheet's Material status-selector fallback needs the room — see the
        // harness. Nothing about this case is width-dependent.
        logicalSize: const Size(500, 900),
      );

      await tester.tap(find.byType(ReadingPeriodRow));
      await tester.pumpAndSettle();

      expect(find.text('Change reading status'), findsOneWidget);
    });

    testWidgets('takes the 44pt touch floor, which costs it 2pt', (
      tester,
    ) async {
      // The card draws 42. That figure is a correction of a remembered 46, which
      // was a different row — the grouped-section variant that was not chosen.
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: meId),
        signedInAs: meId,
      );

      expect(
        tester.getSize(find.byType(ReadingPeriodRow)).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets(
      'Given an interested book, Then there is no card and so no door',
      (tester) async {
        // No dates means no card, which means no shape for a chevron to end. The
        // bare badge is not a control.
        await pumpBookDetails(
          tester,
          book: interestedBook(ownerId: meId),
          signedInAs: meId,
        );

        expect(_chevronIn(ReadingPeriodRow), findsNothing);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // The prompt state.
  //
  // With no position recorded the row is `How far in? ›` — no numbers and **no bar**.
  // The migration's rule is that null draws no *bar*, because an empty track is a
  // claim: it says the reader started and got nowhere. A prompt claims nothing, so the
  // rule does not reach it.
  //
  // This row shipped gated on `progress != null` first, and the defect that fixed was
  // not cosmetic: the band had **no door for the first set**, which is the one moment
  // every book passes through, and the feature was invisible on a fresh install because
  // the streak chip hides at 0 as well.

  group('the prompt, before there is a position', () {
    testWidgets('Given no position, Then the row asks rather than reading 0%', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: meId, pageCount: 432),
        signedInAs: meId,
      );

      expect(find.byType(BandProgressRow), findsOneWidget);
      expect(find.text('How far in?'), findsOneWidget);
      // Null is "never asked"; 0% is "at the very start". Only one of those is
      // something the reader said.
      expect(find.text('0%'), findsNothing);
      expect(find.textContaining('p.', findRichText: true), findsNothing);
    });

    testWidgets('Given no position, Then no bar is painted', (tester) async {
      // The half of the rule that still holds. An empty track would claim the reader
      // started and got nowhere, on every book in the library.
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: meId, pageCount: 432),
        signedInAs: meId,
      );

      expect(find.byType(BandProgressEdge), findsNothing);
    });

    testWidgets('Given a position, Then the bar is painted', (tester) async {
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: meId, progress: 0.46, pageCount: 432),
        signedInAs: meId,
      );

      expect(find.byType(BandProgressEdge), findsOneWidget);
    });

    testWidgets('the prompt is a door, and opens the same wheel', (
      tester,
    ) async {
      // The whole point of the state: the first set is reachable from the band, in
      // the thumb's arc, rather than only from inside a sheet.
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: meId, pageCount: 432),
        signedInAs: meId,
      );

      await tester.tap(find.byType(BandProgressRow));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoPicker), findsOneWidget);
      // Opens at 0 rather than refusing, and the rider reads the page for it. The row
      // is a bare numeral now: the wheel wears its unit as a static label beside the
      // column, so both modes centre their digits the same way. Scoped to the picker,
      // because a bare `0` also appears in the shelf badge on the page behind.
      expect(
        find.descendant(
          of: find.byType(CupertinoPicker),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(find.text('≈ p.0'), findsOneWidget);
    });

    testWidgets('is the same height as the answer that replaces it', (
      tester,
    ) async {
      // So the band does not resize under the reader at the moment they answer.
      //
      // Asserted against the constant rather than by pumping both states and
      // comparing: `pumpBookDetails` twice in one test reuses the first route, so the
      // comparison would silently measure the prompt against itself and pass. The
      // value state is pinned to this same expression by 'reaches 44pt of target out
      // of 30pt of ink' above.
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: meId, pageCount: 432),
        signedInAs: meId,
      );

      expect(
        tester.getSize(find.byType(BandProgressRow)).height,
        30 + kBandProgressRowSpill,
      );
    });

    testWidgets(
      "Given a friend's book with no position, Then there is no row at all",
      (tester) async {
        // Nothing to read, and not a door for anyone but the owner — so the prompt
        // would be a bare chevron on an empty line.
        await pumpBookDetails(
          tester,
          book: readingBook(ownerId: friendId, pageCount: 432),
          signedInAs: meId,
        );

        expect(find.byType(BandProgressRow), findsNothing);
        expect(find.text('How far in?'), findsNothing);
      },
    );

    testWidgets("Given a friend's book with a position, Then it still reads", (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: friendId, progress: 0.46, pageCount: 432),
        signedInAs: meId,
      );

      expect(find.byType(BandProgressRow), findsOneWidget);
      expect(find.text('46%'), findsOneWidget);
      expect(_chevronIn(BandProgressRow), findsNothing);
    });

    testWidgets('Given a finished book, Then there is no prompt either', (
      tester,
    ) async {
      // A finished book is at 100% by definition; asking would be a field with one
      // legal answer.
      await pumpBookDetails(
        tester,
        book: finishedBook(ownerId: meId),
        signedInAs: meId,
      );

      expect(find.byType(BandProgressRow), findsNothing);
    });
  });

  group('the row\'s left edge', () {
    // The row sits on the band's own content edge at x30, while the period card is
    // inset 10pt inside the band and so puts its status chip at x40. The row's text is
    // indented to meet the chip's edge — the object above it — rather than the letters
    // inside the chip, which sit at x51 and read as over-indented.
    //
    // Asserted as a *relationship* rather than as coordinates, because the numbers
    // move with the device width and the thing that matters does not.

    testWidgets('the prompt lines up with the status chip above it', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: meId, pageCount: 432),
        signedInAs: meId,
      );

      expect(
        tester.getTopLeft(find.text('How far in?')).dx,
        closeTo(tester.getTopLeft(find.byType(BookStatusBadge)).dx, 0.5),
      );
    });

    testWidgets('and so does the answer that replaces it', (tester) async {
      // The half that makes the indent safe. Indenting only the prompt would slide
      // the text 10pt left at the instant the reader answers — the one moment they
      // are looking straight at it.
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: meId, progress: 0.46, pageCount: 432),
        signedInAs: meId,
      );

      final leading = find.descendant(
        of: find.byType(BandProgressRow),
        matching: find.byType(RichText),
      );
      expect(
        tester.getTopLeft(leading.first).dx,
        closeTo(tester.getTopLeft(find.byType(BookStatusBadge)).dx, 0.5),
      );
    });

    testWidgets('the trailing half is not moved by it', (tester) async {
      // The chevron column was settled by pulling the *card's* glyph out to meet this
      // row, so an indent on the left must not push the right-hand side anywhere.
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: meId, progress: 0.46, pageCount: 432),
        signedInAs: meId,
      );

      final card = tester.getRect(_chevronIn(ReadingPeriodRow));
      final row = tester.getRect(_chevronIn(BandProgressRow));
      expect(card.right, closeTo(row.right, 0.5));
    });
  });

  group('the two chevrons', () {
    testWidgets('are column-aligned, the card pulled out to meet the row', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: meId, progress: 0.46, pageCount: 320),
        signedInAs: meId,
      );

      final card = tester.getRect(_chevronIn(ReadingPeriodRow));
      final row = tester.getRect(_chevronIn(BandProgressRow));

      // Staggered, two identical glyphs 20pt apart vertically read as a
      // misalignment rather than as a pair.
      expect(card.right, closeTo(row.right, 0.5));
    });

    testWidgets('are the same glyph at the same size', (tester) async {
      // Or the rows do not read as peers.
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: meId, progress: 0.46, pageCount: 320),
        signedInAs: meId,
      );

      final card = tester.widget<Icon>(_chevronIn(ReadingPeriodRow));
      final row = tester.widget<Icon>(_chevronIn(BandProgressRow));
      expect(card.icon, row.icon);
      expect(card.size, row.size);
      expect(card.color, row.color);
    });
  });

  group("on a friend's book", () {
    testWidgets('both rows read and neither draws a handle', (tester) async {
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: friendId, progress: 0.46, pageCount: 320),
        signedInAs: meId,
      );

      expect(find.byType(ReadingPeriodRow), findsOneWidget);
      expect(find.byType(BandProgressRow), findsOneWidget);
      expect(find.text('46%'), findsOneWidget);

      expect(_chevronIn(ReadingPeriodRow), findsNothing);
      expect(_chevronIn(BandProgressRow), findsNothing);
    });

    testWidgets('tapping the period card opens nothing', (tester) async {
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: friendId),
        signedInAs: meId,
      );

      await tester.tap(find.byType(ReadingPeriodRow));
      await tester.pumpAndSettle();

      expect(find.text('Change reading status'), findsNothing);
    });

    testWidgets('tapping the progress row opens nothing', (tester) async {
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: friendId, progress: 0.46, pageCount: 320),
        signedInAs: meId,
      );

      await tester.tap(find.byType(BandProgressRow));
      await tester.pumpAndSettle();

      expect(find.text('How far in?'), findsNothing);
    });
  });
}
