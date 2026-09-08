// Tests for the Library Card's body: the hero tile and whatever tiles have
// something true to say.
//
// **These assert geometry, not presence.** That is a direct lesson from Phase 2:
// `GeneratedCover`'s colour block was laid out 0pt wide from the day it was written,
// so every generated cover rendered as a plain white card, and four colour tests
// passed on it the whole time because all four tested the *function* that picked the
// colour rather than the widget that drew it. A gradient tile is at risk of exactly
// the same failure — a decorated box in a `Column` with the default cross-axis
// alignment sizes to `constraints.smallest` — so the tiles' widths are measured here.
//
// The other thing under test is absence. The real data is thin: the median reader has
// finished two books, 57% of finished books were logged same-day and so have no
// reading span, and 40 of 53 readers with author data have a top author who wrote one
// book. A card that fills those gaps with zeroes would be confidently wrong about most
// readers, so every tile has a case proving it is *not in the tree* when its sample is
// empty.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/library_card_stats.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_furniture.dart';
import 'package:bookworm_friends/ui/widgets/library_card/library_card_body.dart';
import 'package:bookworm_friends/ui/widgets/library_card/stat_tile.dart';

const _surface = Size(390, 900);

/// The width the body is given, so a tile's measured width can be compared to the
/// space it was offered rather than to a magic number.
const double _bodyWidth = 340;

Book _book({
  required String id,
  DateTime? start,
  DateTime? finish,
  List<String> authors = const [],
}) => Book(
  id: id,
  userId: 'u',
  shelfId: 's',
  isbn: id,
  title: 'Book $id',
  thumbnail: '',
  status: 2,
  position: 0,
  startDate: start,
  finishDate: finish,
  createdAt: DateTime(2024),
  authors: authors,
);

Book _spanned(
  String id,
  int days,
  DateTime finish, {
  List<String> authors = const [],
}) => _book(
  id: id,
  start: finish.subtract(Duration(days: days)),
  finish: finish,
  authors: authors,
);

Future<void> _pump(
  WidgetTester tester,
  List<Book> books, {
  int year = 0,
  double textScale = 1,
}) async {
  tester.view.physicalSize = _surface * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Center(
            child: SizedBox(
              width: _bodyWidth,
              child: LibraryCardBody(
                stats: libraryCardStats(books, year: year),
                books: books,
                year: year,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// All stat tiles in the tree, in layout order.
List<Element> _tiles(WidgetTester tester) =>
    find.byType(StatTile).evaluate().toList();

Rect _rectOf(WidgetTester tester, Element element) =>
    tester.getRect(find.byWidget(element.widget));

void main() {
  group('LibraryCardBody geometry', () {
    testWidgets('Given a reader with books, When the body renders, '
        'Then the hero fills the width it was given', (tester) async {
      // The `GeneratedCover` failure, guarded. A hero that shrink-wrapped its
      // longest word would still contain the right text and would still pass any
      // `findsOneWidget` assertion.
      await _pump(tester, [_spanned('a', 6, DateTime(2024, 3, 1))]);

      final hero = _tiles(tester).first;
      expect(
        _rectOf(tester, hero).width,
        _bodyWidth,
        reason: 'a shrink-wrapped tile is the bug this test exists for',
      );
    });

    testWidgets(
      'Given a hero tile, When it renders, Then its gradient covers the whole tile',
      (tester) async {
        await _pump(tester, [_spanned('a', 6, DateTime(2024, 3, 1))]);

        // The decoration is what could collapse, so it is measured rather than the
        // tile around it.
        final decorated = find
            .descendant(
              of: find.byType(StatTile).first,
              matching: find.byType(DecoratedBox),
            )
            .first;
        final box = tester.getRect(decorated);

        expect(box.width, _bodyWidth);
        expect(box.height, greaterThan(60), reason: 'a hero with no height');

        final decoration =
            tester.widget<DecoratedBox>(decorated).decoration as BoxDecoration;
        expect(decoration.gradient, isNotNull);
      },
    );

    testWidgets('Given a single tile below the hero, When it renders, '
        'Then it fills the width rather than sitting in a half-width box', (
      tester,
    ) async {
      // The common case: a reader with a pace but no repeat author. A fixed
      // half-width tile would leave a hole beside itself for most readers.
      await _pump(tester, [
        _spanned('a', 4, DateTime(2024, 3, 1)),
        _spanned('b', 8, DateTime(2024, 5, 1)),
      ]);

      final tiles = _tiles(tester);
      expect(tiles.length, 2, reason: 'hero plus pace');
      expect(_rectOf(tester, tiles[1]).width, _bodyWidth);
    });

    testWidgets('Given two tiles below the hero, When they render, '
        'Then they split the width evenly and sit side by side', (
      tester,
    ) async {
      await _pump(tester, [
        _spanned('a', 4, DateTime(2024, 3, 1), authors: ['한강']),
        _spanned('b', 8, DateTime(2024, 5, 1), authors: ['한강']),
      ]);

      final tiles = _tiles(tester);
      expect(tiles.length, 3, reason: 'hero, pace, author');

      final pace = _rectOf(tester, tiles[1]);
      final author = _rectOf(tester, tiles[2]);

      expect(pace.width, author.width);
      // 10pt gutter between them, so each is (340 - 10) / 2.
      expect(pace.width, (_bodyWidth - 10) / 2);
      expect(pace.top, author.top, reason: 'side by side, not stacked');
      expect(author.left, greaterThan(pace.right));
    });
  });

  group('LibraryCardBody absence', () {
    testWidgets(
      'Given nothing finished, When the body renders, Then no tile is drawn at all',
      (tester) async {
        await _pump(tester, []);

        expect(find.byType(StatTile), findsNothing);
        expect(find.text('Your reading stats will live here'), findsOneWidget);
      },
    );

    testWidgets(
      'Given books read in other years, When a year with none of them is selected, '
      'Then the card is still drawn, reading zero',
      (tester) async {
        // The rail offers every year back to the earliest finish, gaps included, so
        // this is a normal thing to be looking at rather than an edge case — and a
        // swipe across the card now lands on it. Replacing the card with a line of
        // copy both told a reader with a library that their stats had not started
        // yet, and took away the one object this tab exists to show.
        await _pump(tester, [
          _spanned('a', 4, DateTime(2024, 3, 1)),
        ], year: 2026);

        expect(find.text('2026 LIBRARY CARD'), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
        expect(
          find.text('books'),
          findsOneWidget,
          reason: 'the unit belongs with the figure however small it is',
        );
        expect(
          find.text('Your reading stats will live here'),
          findsNothing,
          reason: 'their stats do not live in the future, they live in 2024',
        );
      },
    );

    testWidgets(
      'Given an empty year, When the hero renders, Then it stands alone with no '
      'covers and no derived tiles',
      (tester) async {
        // Zero is fair for a *count*. A pace of 0d per book, or a most-read author
        // drawn from no books, would be the confidently-wrong kind of zero this class
        // omits tiles to avoid — so at 0 the hero is the whole card.
        await _pump(tester, [
          _spanned('a', 4, DateTime(2024, 3, 1), authors: ['한강']),
          _spanned('b', 8, DateTime(2024, 5, 1), authors: ['한강']),
        ], year: 2026);

        expect(_tiles(tester).length, 1, reason: 'the hero, and nothing else');
        expect(
          find.byKey(const ValueKey('cover-a')),
          findsNothing,
          reason: 'no cover may appear that the figure has not counted',
        );
        expect(find.text('한강'), findsNothing);
        expect(find.textContaining('0d'), findsNothing);
      },
    );

    testWidgets('Given an empty year, When the hero renders, Then it ends at its own padding '
        'rather than leaving a band where the covers would be', (tester) async {
      // `CardCoverRow` shrinks to nothing on an empty list, so handing it one *looks*
      // free — but `StatTile` pays for a non-null footer with 12pt above it, and the
      // card would end in a strip of blank gradient that reads as a row which failed
      // to load. The footer is withheld instead, and this is the 12pt that says so:
      // the gap below the sub-line is the tile's own bottom padding, not 18 + 12.
      await _pump(tester, [_spanned('a', 4, DateTime(2024, 3, 1))], year: 2026);

      final hero = _rectOf(tester, _tiles(tester).first);
      expect(
        hero.bottom - tester.getRect(find.text('books')).bottom,
        moreOrLessEquals(18, epsilon: 1),
        reason: "StatTile's hero bottom padding, with nothing added to it",
      );
    });

    testWidgets(
      'Given nothing finished at all, When a year is somehow selected, Then it is '
      'still the promise rather than a card reading zero',
      (tester) async {
        // The narrow case the message is actually for: no card to draw and no scope
        // to draw it at. Reachable through a stale filter — the rail clamps what it
        // *draws* to the years on offer, and the selected year is the shell's state.
        await _pump(tester, [], year: 2026);

        expect(find.text('Your reading stats will live here'), findsOneWidget);
        expect(find.byType(StatTile), findsNothing);
      },
    );

    testWidgets(
      'Given only undated finishes, When a year is selected, Then the card reads zero '
      'for that year while all time counts them',
      (tester) async {
        // All time counts a book with no finish date; a year cannot place it. So this
        // reader's card is full at all-time and reads 0 on every year, and the year
        // one has to say which year it is being 0 about.
        await _pump(tester, [_book(id: 'a')], year: 2026);

        expect(find.text('2026 LIBRARY CARD'), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
      },
    );

    testWidgets('Given every book was logged same-day, When the body renders, '
        'Then the hero stands alone and no pace is claimed', (tester) async {
      // 29 of 55 real readers are shaped like this. The hero is still true — they
      // did read the books — and everything derived from a span is not.
      final sameDay = DateTime(2024, 5, 1);
      await _pump(tester, [
        _book(id: 'a', start: sameDay, finish: sameDay),
        _book(id: 'b', start: sameDay, finish: sameDay),
      ]);

      expect(_tiles(tester).length, 1, reason: 'the hero, and nothing else');
      expect(find.textContaining('0d'), findsNothing);
      // The sub-line drops the days clause rather than printing "0 days".
      expect(find.textContaining('days reading'), findsNothing);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('Given every author has one book, When the body renders, '
        'Then no author is named', (tester) async {
      await _pump(tester, [
        _spanned('a', 4, DateTime(2024, 3, 1), authors: ['한강']),
        _spanned('b', 8, DateTime(2024, 5, 1), authors: ['김영하']),
      ]);

      expect(find.text('한강'), findsNothing);
      expect(find.text('김영하'), findsNothing);
      expect(_tiles(tester).length, 2, reason: 'hero and pace only');
    });

    testWidgets(
      'Given one book with a span, When the body renders, Then the card is still coherent',
      (tester) async {
        // n=1 is not an edge case here; 23 of 55 readers have exactly one finished
        // book.
        await _pump(tester, [_spanned('a', 9, DateTime(2024, 3, 1))]);

        expect(find.text('1'), findsOneWidget);
        expect(
          find.text('book'),
          findsNothing,
          reason: 'unit is in the sub-line',
        );
        expect(find.textContaining('book'), findsWidgets);
        expect(find.text('9d'), findsOneWidget);
        expect(find.textContaining('of 1 dated'), findsOneWidget);
      },
    );
  });

  group('LibraryCardBody labelling', () {
    testWidgets('Given all time, When the hero renders, Then it says so', (
      tester,
    ) async {
      await _pump(tester, [_spanned('a', 4, DateTime(2024, 3, 1))]);

      expect(find.text('ALL-TIME LIBRARY CARD'), findsOneWidget);
    });

    testWidgets('Given a year is selected, When the hero renders, '
        'Then the label is that year rather than all-time', (tester) async {
      // Without this the card claims to be all-time while showing one year's
      // figures, which is the one place the capsules could make the card lie.
      await _pump(tester, [
        _spanned('a', 4, DateTime(2024, 3, 1)),
        _spanned('b', 4, DateTime(2023, 3, 1)),
      ], year: 2024);

      expect(find.text('ALL-TIME LIBRARY CARD'), findsNothing);
      expect(find.text('2024 LIBRARY CARD'), findsOneWidget);
      expect(find.text('1'), findsOneWidget, reason: 'one book in 2024');
    });

    testWidgets(
      'Given accessibility text sizes, When the body renders, Then nothing overflows',
      (tester) async {
        // The test font makes every glyph one em wide, so this is a strict upper
        // bound on real text — a pass here is stronger than it looks, and a failure
        // would still be worth acting on.
        await _pump(tester, [
          _spanned('a', 4, DateTime(2024, 3, 1), authors: ['한강']),
          _spanned('b', 18, DateTime(2024, 5, 1), authors: ['한강']),
        ], textScale: 2);

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('LibraryCardBody as a preview of the export', () {
    // Before this the hero was a chart: a reader tapped share on a green rectangle
    // and got back an object they had never seen. The two things that make it a
    // preview are the card's own furniture and the covers.
    testWidgets('Given a reader with books, When the hero renders, '
        'Then it carries the card\'s printed furniture', (tester) async {
      await _pump(tester, [_spanned('a', 6, DateTime(2024, 3, 1))]);

      expect(find.text(kCardStampLine), findsOneWidget);
    });

    testWidgets('Given a reader with books, When the hero renders, '
        'Then a cover is drawn for each of them', (tester) async {
      await _pump(tester, [
        _spanned('a', 4, DateTime(2024, 3, 1)),
        _spanned('b', 8, DateTime(2024, 5, 1)),
      ]);

      expect(find.byKey(const ValueKey('cover-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('cover-b')), findsOneWidget);
    });

    testWidgets('Given a year is selected, When the hero renders, '
        'Then only that year\'s covers are drawn', (tester) async {
      // The covers and the hero figure come from one selection rule, so a cover
      // the figure has not counted cannot appear beside it.
      await _pump(tester, [
        _spanned('a', 4, DateTime(2024, 3, 1)),
        _spanned('b', 4, DateTime(2023, 3, 1)),
      ], year: 2024);

      expect(find.byKey(const ValueKey('cover-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('cover-b')), findsNothing);
    });

    testWidgets('Given nothing finished, When the body renders, '
        'Then there is no furniture and no cover row', (tester) async {
      await _pump(tester, []);

      expect(find.text(kCardStampLine), findsNothing);
      expect(find.byType(Row), findsNothing);
    });
  });
}
