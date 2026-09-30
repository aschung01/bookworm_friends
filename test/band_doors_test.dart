// The band's door, and what the card under the cover says.
//
// The band prints a book's reading facts and, since the app bar's pencil was
// retired, it is also how you change them: the period card opens the sheet that
// edits status, dates and position — exactly what the card and the band's own
// bottom edge display between them.
//
// **It had two doors and now has one, which is what most of this file is about.**
// `BandProgressRow` — the `46% p.213/320` read-out, and the `How far in? ›` prompt
// before there was a value — is deleted, and with it the second door straight to
// the percent wheel. The position is read and set *inside* the one sheet now:
// `ReadingStateLine` prints it and `ReadingTrack` moves it. In the band itself the
// position survives only as `BandProgressEdge`, the bottom edge inked to the
// reader's place. So every claim here about the percent, the derived page and the
// prompt-versus-value swap has been retargeted one level in — at the sheet the card
// opens — rather than dropped, and the claims that were *about there being two
// rows* are void and marked as such where they stood.
//
// **A door only where it can be opened.** On a friend's book the card still reads,
// and it draws no handle: no chevron, no tap target, no press state. A chevron on a
// row that does nothing is a lie about what the row does.
//
// **And the band does not get taller for any of this.** The card's status-0 line
// reaches 14pt below its own ink, and those 14 come out of the band's 16pt bottom
// padding. The band sits above a pinned tab strip on the one screen whose last
// redesign was about lifting content up, so height here is not free. There is one
// claimant on that padding now, which is why the arbitration this file used to
// assert is gone — see `kStatusVerbSpill`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart' show bookProgressPage;
import 'package:bookworm_friends/providers/reading_days_provider.dart';
import 'package:bookworm_friends/ui/widgets/band_progress_edge.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_state_line.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_track.dart';
import 'package:bookworm_friends/ui/widgets/book_status_badge.dart';
import 'package:bookworm_friends/ui/widgets/reading_period_row.dart';

import 'support/book_details_harness.dart';

/// The chevron inside a given row, whichever row that is.
Finder _chevronIn(Type row) => find.descendant(
  of: find.byType(row),
  matching: find.byIcon(Icons.chevron_right),
);

/// Text inside the sheet's one-line read-out, which is where the position's numerals
/// live now that the band prints none of them.
Finder _inReadOut(Finder matching) =>
    find.descendant(of: find.byType(ReadingStateLine), matching: matching);

/// A reading-day set that never resolves, which is what a stalled fetch looks like.
class _PendingReadingDays extends ReadingDaysNotifier {
  /// Whether anything ever asked for the set.
  ///
  /// **The case below asserts an absence of waiting, so it would pass on a page that
  /// never asked at all** — including one where the override silently did not apply.
  /// This is how it says the set really was in flight.
  static bool built = false;

  @override
  Future<Map<DateTime, String?>> build() {
    built = true;
    return Completer<Map<DateTime, String?>>().future;
  }
}

/// Opens the band's one door and waits for the sheet.
Future<void> _openTheDoor(WidgetTester tester) async {
  await tester.tap(find.byType(ReadingPeriodRow));
  await tester.pumpAndSettle();
}

void main() {
  group('the position the band carries', () {
    testWidgets('Given a position, When the band is drawn, Then the card prints it '
        'instead of the dates and the edge is inked', (tester) async {
      // **The band says the position once, in the card, plus the inked edge.**
      //
      // This case was written the other way round first — asserting the band printed
      // *no* numeral — and it was right about the code and wrong about the design. The
      // merge deleted the second row, `BandProgressRow`, which carried both the numerals
      // and a second door; deleting it took the numerals with it, so the band went silent
      // about the fact that changes most often. The drawing has the card carrying
      // `46% · p.213`, so the numerals came back into this card and only the door was
      // removed. Printed *once*, which is what the original absence was really guarding.
      //
      // **This used to say "beside the dates", and the spec used to say the card carries
      // "status, dates *and* position".** Both were true for one round and the result
      // wrapped onto two lines; the card has two slots now and the position takes the one
      // the start date had. See `reading_period_row_test.dart` for the rule — this case
      // only cares that the band states the position exactly once.
      //
      // **And the position on the card is now a bare percent**, so the page numeral this
      // case used to require is asserted absent instead. That is not the numerals leaving
      // the band the way they did when `BandProgressRow` was deleted: the case below opens
      // the door and finds `p.147` in the sheet's read-out, where it is tappable. The band
      // is a glance; the page belongs where it can be edited.
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: meId, progress: 0.46, pageCount: 320),
        signedInAs: meId,
      );

      expect(find.byType(ReadingPeriodRow), findsOneWidget);
      expect(find.byType(BandProgressEdge), findsOneWidget);
      // The owner's half of "a door only where it can be opened": one handle, on the
      // one row that has one. Every friend's-book case below is the other half.
      expect(_chevronIn(ReadingPeriodRow), findsOneWidget);
      // One rounding site, shared with the wheel's rider and the sheet's read-out, so
      // none of the three can disagree about which page 46% of 320 is. Read through the
      // free function rather than restated as a literal, which is what makes it the
      // *same* rounding rather than a second opinion that agrees today.
      expect(bookProgressPage(0.46, 320), 147);
      expect(
        find.textContaining('46%', findRichText: true),
        findsOneWidget,
        reason: 'the percent, printed once in the band',
      );
      expect(
        find.textContaining('147', findRichText: true),
        findsNothing,
        reason: 'the derived page is not on the card, only behind its door',
      );
      expect(
        find.textContaining('320', findRichText: true),
        findsNothing,
        reason: 'and neither is the total',
      );
      // The prompt is gone, which is the deleted row seen from its other state — see
      // the group below for where the first set is reached from now.
      expect(find.text('How far in?'), findsNothing);
    });

    testWidgets(
      'Given a position, When the door is opened, Then the read-out prints the '
      'page and percent',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: readingBook(ownerId: meId, progress: 0.46, pageCount: 320),
          signedInAs: meId,
        );

        await _openTheDoor(tester);

        expect(_inReadOut(find.text('46%')), findsOneWidget);
        // One rounding site, shared with the wheel's rider — so these can never
        // disagree about which page 46% of 320 is. Read through the free function
        // rather than restated as a literal, which is what makes it the *same*
        // rounding rather than a second opinion that happens to agree today.
        expect(bookProgressPage(0.46, 320), 147);
        expect(_inReadOut(find.text('p.147')), findsOneWidget);
      },
    );

    testWidgets(
      'Given no page count, Then the percent reads alone and the total is an offer',
      (tester) async {
        // About two reading books in three. The percent is the stored fact and is
        // enough on its own.
        //
        // **This reverses half of what the deleted row claimed, deliberately.** That
        // row printed the percent with *no substitute* — there was no apology in the
        // page's place, because the row had no way to fix the missing count. The
        // sheet does, so the page's slot is an invitation instead, and it is the
        // largest single thing the merge adds for those two books in three.
        await pumpBookDetails(
          tester,
          book: readingBook(ownerId: meId, progress: 0.46),
          signedInAs: meId,
        );

        await _openTheDoor(tester);

        expect(_inReadOut(find.text('46%')), findsOneWidget);
        expect(
          _inReadOut(find.textContaining('p.')),
          findsNothing,
          reason: 'no total, so there is no page to derive',
        );
        expect(_inReadOut(find.text('Add total pages')), findsOneWidget);
      },
    );

    testWidgets('Given a finished book, Then the band reads no position at all', (
      tester,
    ) async {
      // Folds the two cases that used to say this about the deleted row and about
      // its prompt. A finished book is at 100% by definition, so asking would be a
      // field with one legal answer — and the edge is gated on `bookStatusReading`,
      // so it is not inked either. The card stays: it is carrying the dates.
      await pumpBookDetails(
        tester,
        book: finishedBook(ownerId: meId),
        signedInAs: meId,
      );

      expect(find.byType(ReadingPeriodRow), findsOneWidget);
      expect(find.byType(BandProgressEdge), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });

    // Two cases stood here and are void, both for the same reason: **the band has
    // one door now.**
    //
    // `opens the percent wheel directly, not the status sheet` asserted the second
    // door went straight to the wheel, because the row already showed the value and
    // a form in between would ask the reader to find what they just tapped on. There
    // is no second door and no row that shows the value: the wheel is reached from
    // inside the sheet, behind the read-out's own numeral, which is the version of
    // that argument that survived — the numeral you tap *is* the value.
    //
    // `reaches 44pt of target out of 30pt of ink` asserted the row spent the band's
    // bottom padding to get a 44pt target out of 30pt of ink. No row, no 30pt of
    // ink. The padding accounting is now asserted once, in the period card's own
    // `and the band is no taller for having it` below, because there is one claimant
    // on that padding rather than two competing for it.
  });

  group('the period card', () {
    testWidgets('opens the sheet the retired pencil used to open', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: meId),
        signedInAs: meId,
      );

      await _openTheDoor(tester);

      // **The sheet is identified by its control, not by its title.** Its heading is
      // the book — `Eldest` here — which is also printed in the band behind it, so
      // matching the words would pass on a sheet that never opened. `ReadingTrack`
      // and `ReadingStateLine` exist nowhere else on this page.
      expect(find.byType(ReadingStateLine), findsOneWidget);
      expect(find.byType(ReadingTrack), findsOneWidget);
      // The title it replaced. Kept as an absence because the string is still in the
      // ARB, so nothing else would notice the sheet growing it back as a heading.
      expect(find.text('Change reading status'), findsNothing);
    });

    testWidgets(
      'Given the reading-day set is still in flight, Then the sheet still opens',
      (tester) async {
        // **The most valuable case in this file, and it is about a reversal.**
        // Awaiting `readingDaysProvider.future` before opening the sheet is the
        // airtight way to get the day-stamp and the celebration right, and it puts a
        // network read in front of the form: a fetch that stalls means the reader
        // cannot edit their dates at all. That trades a wrong celebration for an
        // unreachable form, which is the worse of the two, so the page *watches* the
        // set in `build` and the door reads `readTodayProvider` without waiting.
        //
        // The regression this caught was exactly that — the form became unreachable
        // — and nothing else in the suite would see it, because on device the library
        // bar's streak chip watches the same provider and the route below this one
        // stays in the tree, so the set is nearly always already cached.
        _PendingReadingDays.built = false;
        await pumpBookDetails(
          tester,
          book: readingBook(ownerId: meId, progress: 0.46, pageCount: 320),
          signedInAs: meId,
          extraOverrides: [
            readingDaysProvider.overrideWith(_PendingReadingDays.new),
          ],
        );

        expect(
          _PendingReadingDays.built,
          isTrue,
          reason: 'the set has to be unresolved for this case to mean anything',
        );

        await _openTheDoor(tester);

        expect(find.byType(ReadingStateLine), findsOneWidget);
        expect(find.byType(ReadingTrack), findsOneWidget);
      },
    );

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
      'Given a not-started book, Then there is no card and the verb is the door',
      (tester) async {
        // No dates means no card — and for a while it meant no door either, which was
        // not a missing shortcut but a dead end: `showBookStatusBottomSheet` has one
        // caller in the app and it is this widget, so a Not-started book could not
        // reach Reading or Finished from anywhere. The verb at the end of the line is
        // the repair.
        await pumpBookDetails(
          tester,
          book: interestedBook(ownerId: meId),
          signedInAs: meId,
        );

        expect(find.text('Not started'), findsOneWidget);
        expect(find.text('Change status'), findsOneWidget);
        // Still no card: the chip is not wrapped in a full-width white slab.
        expect(find.textContaining('~'), findsNothing);

        await tester.tap(find.text('Change status'));
        await tester.pumpAndSettle();

        // The same sheet the card opens, which is what makes one target enough for
        // all four states rather than one destination. **It is the track that makes
        // that true now, not a selector**: the three-segment `BookStatusSelector` is
        // gone, and the status is a read-out of where the thumb is — so the way out
        // of Not started is to move the thumb, and the way to Finished is to move it
        // all the way.
        expect(find.byType(ReadingTrack), findsOneWidget);
        expect(find.byType(ReadingStateLine), findsOneWidget);
      },
    );

    testWidgets('the whole line is the target, badge included', (tester) async {
      // Exactly as the card at status 1 and 2 is a target with the badge inside it.
      // The badge grows no chevron and no press state of its own, but it is not a
      // hole in the row either.
      await pumpBookDetails(
        tester,
        book: interestedBook(ownerId: meId),
        signedInAs: meId,
      );

      await tester.tap(find.byType(BookStatusBadge));
      await tester.pumpAndSettle();

      expect(find.byType(ReadingTrack), findsOneWidget);
    });

    testWidgets('and the band is no taller for having it', (tester) async {
      // The 14pt that gets the line past its own ink comes out of the band's 16pt
      // bottom padding, so the band's height is unchanged by making the line
      // tappable.
      //
      // **This used to be half of an arbitration and is now the whole accounting.**
      // Two rows below the cover could reach past their own ink — this line and the
      // deleted `BandProgressRow` — competing for one bottom padding, and
      // `spillsBelow` existed to prove only one of them ever spent it. There is one
      // row now, so there is one claimant, and the case that asserted the two could
      // not both spend it is void.
      //
      // Asserted as the accounting rather than by pumping the page twice and
      // comparing: the harness overrides providers per pump and cannot be re-pumped
      // with a different owner inside one test.
      await pumpBookDetails(
        tester,
        book: interestedBook(ownerId: meId),
        signedInAs: meId,
        // Wide enough that the line's [Wrap] stays on one run. It is not a device
        // width: `flutter_test` draws every glyph as a square of the font size, so
        // `Not started` and `Change status` measure about 340pt here against roughly
        // 200 on device. The wrap firing is the safety valve working, not a layout
        // bug — but the spill accounting is only visible while it does not.
        logicalSize: const Size(500, 900),
      );

      final line = tester.getSize(find.byType(ReadingPeriodRow)).height;
      final chip = tester.getSize(find.byType(BookStatusBadge)).height;
      expect(line, chip + kStatusVerbSpill);
      // And what it took is exactly what the band stopped padding with.
      expect(kStatusVerbSpill + kBandResidualPadding, 16);
    });

    testWidgets(
      "Given a friend's not-started book, Then the line offers nothing",
      (tester) async {
        // A handle on a door nobody can open is a lie, and this is the one state where
        // the badge would otherwise sit alone with a verb beside it that fails.
        await pumpBookDetails(
          tester,
          book: interestedBook(ownerId: friendId),
          signedInAs: meId,
        );

        expect(find.text('Not started'), findsOneWidget);
        expect(find.text('Change status'), findsNothing);
        expect(_chevronIn(ReadingPeriodRow), findsNothing);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Before there is a position.
  //
  // The band draws **no bar** with nothing recorded. The migration's rule is that
  // null draws no *bar*, because an empty track is a claim: it says the reader
  // started and got nowhere.
  //
  // The band used to answer the other half of that rule with a `How far in? ›`
  // prompt, on the grounds that a prompt claims nothing — and the defect that fixed
  // was not cosmetic: the band had **no door for the first set**, which is the one
  // moment every book passes through. That door still exists; it is the period card,
  // which is now present on every book in every state, so the first set is reachable
  // from the band without a row of its own for it.

  group('before there is a position', () {
    testWidgets('Given no position, Then no bar is painted', (tester) async {
      // An empty track would claim the reader started and got nowhere, on every book
      // in the library.
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

    testWidgets('Given no position, Then the read-out reads no 0% either', (
      tester,
    ) async {
      // The prompt's claim, retargeted at the read-out that replaced it. Null is
      // "never asked"; 0% is "at the very start". Only one of those is something the
      // reader said, and the line prints neither a percent nor a page until there is
      // one — just the status word.
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: meId, pageCount: 432),
        signedInAs: meId,
      );

      await _openTheDoor(tester);

      expect(_inReadOut(find.text('Reading')), findsOneWidget);
      expect(_inReadOut(find.text('0%')), findsNothing);
      expect(_inReadOut(find.textContaining('p.')), findsNothing);
      expect(_inReadOut(find.textContaining('%')), findsNothing);
    });

    testWidgets('the first set is reachable from the band', (tester) async {
      // The whole point of the state the prompt used to serve: the first set is
      // reachable from the band, in the thumb's arc, rather than only from inside a
      // form the reader has to find. The card is that door on every book now, and
      // what it opens onto is a track parked at its origin.
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: meId, pageCount: 432),
        signedInAs: meId,
      );

      await _openTheDoor(tester);

      final track = tester.widget<ReadingTrack>(find.byType(ReadingTrack));
      // Null rather than 0: the origin is *Not started*, and a track whose leftmost
      // pixel meant two things would have no way to express the difference.
      expect(track.progress, isNull);
    });

    // `is the same height as the answer that replaces it` stood here and is void.
    // It asserted the prompt and the value it is replaced by were the same height, so
    // the band would not resize under the reader at the moment they answered. The
    // band prints neither, so nothing in it changes size when a position arrives —
    // and the swap it was guarding happens inside the sheet, where
    // `reading_state_line_test.dart` owns it.

    testWidgets(
      "Given a friend's book with no position, Then the band reads and offers "
      'nothing',
      (tester) async {
        // Nothing to read, and not a door for anyone but the owner. The card itself
        // stays — it is carrying the status and the start date, which are a friend's
        // to read — but it grows no handle and the band inks no edge.
        await pumpBookDetails(
          tester,
          book: readingBook(ownerId: friendId, pageCount: 432),
          signedInAs: meId,
        );

        expect(find.byType(ReadingPeriodRow), findsOneWidget);
        expect(find.byType(BandProgressEdge), findsNothing);
        expect(_chevronIn(ReadingPeriodRow), findsNothing);
        expect(find.text('How far in?'), findsNothing);
      },
    );

    testWidgets("Given a friend's book with a position, Then it still reads", (
      tester,
    ) async {
      // The position still reads on a friend's book — as the inked edge, which is the
      // only read-out the band has left. What it does not grow is a handle.
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: friendId, progress: 0.46, pageCount: 432),
        signedInAs: meId,
      );

      expect(find.byType(ReadingPeriodRow), findsOneWidget);
      expect(find.byType(BandProgressEdge), findsOneWidget);
      expect(_chevronIn(ReadingPeriodRow), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Two groups stood here and are void, because **both were about the band having
  // two rows.**
  //
  // `the row's left edge` asserted that the progress row's text was indented to meet
  // the status chip in the card above it — the object above it, rather than the
  // letters inside the chip — and that the indent moved nothing on the right-hand
  // side. There is no second row to indent.
  //
  // `the two chevrons` asserted numerically that the card's chevron and the row's sat
  // in one column, the card's glyph pulled 10pt out of its inset to meet the row's,
  // and that the two were the same glyph at the same size and colour. It was asserted
  // numerically because it is the one thing about that layout that looks like a
  // mistake when it is wrong rather than looking wrong. With one chevron there is
  // nothing to stagger against; `_kChevronColumnPull` survives in
  // `reading_period_row.dart` and now aligns the card's glyph with the band's own
  // content edge instead.

  group("on a friend's book", () {
    testWidgets('the band reads and draws no handle', (tester) async {
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: friendId, progress: 0.46, pageCount: 320),
        signedInAs: meId,
      );

      expect(find.byType(ReadingPeriodRow), findsOneWidget);
      expect(find.text('Reading'), findsOneWidget);
      expect(find.byType(BandProgressEdge), findsOneWidget);

      expect(_chevronIn(ReadingPeriodRow), findsNothing);
    });

    testWidgets('tapping the period card opens nothing', (tester) async {
      await pumpBookDetails(
        tester,
        book: readingBook(ownerId: friendId),
        signedInAs: meId,
      );

      await _openTheDoor(tester);

      expect(find.byType(ReadingStateLine), findsNothing);
      expect(find.byType(ReadingTrack), findsNothing);
    });

    // `tapping the progress row opens nothing` stood here and is void with the row.
    // The case above is the whole of it now: the band has one door, and on a friend's
    // book it is not one.
  });
}
