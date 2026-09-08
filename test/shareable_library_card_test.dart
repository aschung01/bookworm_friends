// Tests for the exported Library Card artifact.
//
// The card on screen and the card in the shared image are two different widget trees,
// and the exported one renders in a place with different ambient inheritance: the
// capture hosts it in the app's `Overlay`, which has **no ancestor `Material`**. So
// every test here pumps it as `MaterialApp(home: ...)` with no `Scaffold`, which
// reproduces that condition exactly. Wrapping it in a `Scaffold` for convenience would
// make this file pass while the real export stayed broken.
//
// That is not hypothetical. The first exported PNG had a yellow double underline under
// every glyph, because `MaterialApp` installs a fallback `DefaultTextStyle` for text
// outside a `Material` — its `debugLabel` reads "fallback style; consider putting your
// text in a Material" — and the card's `Text` widgets set size, weight and colour but
// not `decoration`. It was invisible on screen, invisible to the body's own widget
// tests, and obvious the moment the exported file was opened.
//
// **The artifact no longer reuses `LibraryCardBody`.** It is a library checkout card
// now — cover well, perforation, issue block, stat row, strip — so what is asserted
// here is that structure, the absences in it, and the strip's string rules. The strip
// is deliberately tested as text rather than as pixels: under the test font every
// glyph is one em wide, so any geometry assertion about a 44-column monospace line
// would measure the test font rather than the card.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/library_card_stats.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_furniture.dart';
import 'package:bookworm_friends/ui/widgets/library_card/shareable_library_card.dart';

/// Fixed so `Date of issue` is not the day the suite happens to run.
final _issued = DateTime(2026, 8, 20);
final _memberSince = DateTime(2026, 6, 26);

Book _read(
  String id,
  DateTime finish, {
  List<String> authors = const [],
  String shelf = 's',
  int spanDays = 7,
}) => Book(
  id: id,
  userId: 'u',
  shelfId: shelf,
  isbn: id,
  title: 'Book $id',
  thumbnail: '',
  status: 2,
  position: 0,
  startDate: finish.subtract(Duration(days: spanDays)),
  finishDate: finish,
  createdAt: DateTime(2024),
  authors: authors,
);

Book _sameDay(String id, DateTime on, {String shelf = 's'}) =>
    _read(id, on, shelf: shelf, spanDays: 0);

/// Pumps the artifact the way the capture does: no `Scaffold`, no `Material` above it,
/// and sized to its own fixed export size rather than the surface.
Future<void> _pump(
  WidgetTester tester, {
  required List<Book> books,
  int year = 0,
  String? displayName,
  String? handle,
  DateTime? memberSince,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Center(
        child: ShareableLibraryCard(
          stats: libraryCardStats(books, year: year),
          books: books,
          year: year,
          displayName: displayName,
          handle: handle,
          memberSince: memberSince,
          issuedOn: _issued,
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The style a `Text` actually paints with: its own, merged onto whatever it inherits.
TextStyle _effectiveStyle(WidgetTester tester, Text text) {
  final context = tester.element(find.byWidget(text));
  final inherited = DefaultTextStyle.of(context).style;
  return text.style == null ? inherited : inherited.merge(text.style);
}

void main() {
  _labelFitGuards();

  group('the artifact as an object', () {
    testWidgets(
      'Given the card is rendered with no Material above it, When its text is '
      'inspected, Then nothing inherits the fallback underline',
      (tester) async {
        // The regression this file exists for.
        await _pump(tester, books: [_read('a', DateTime(2026, 3, 1))]);

        final texts = tester.widgetList<Text>(find.byType(Text));
        expect(
          texts,
          isNotEmpty,
          reason: 'nothing to check means nothing was drawn',
        );

        for (final text in texts) {
          final style = _effectiveStyle(tester, text);
          expect(
            style.decoration ?? TextDecoration.none,
            TextDecoration.none,
            reason:
                '"${text.data}" would export with a yellow double underline. The '
                'card needs its own Material, because the overlay does not '
                'provide one',
          );
        }
      },
    );

    testWidgets('Given the card, When its text is inspected, Then only the strip '
        'is monospace', (tester) async {
      // The other half of the fallback style, which is monospace 48pt: the
      // underline was only its visible half. The strip *wants* a monospace family,
      // so it is the exception and every other line is checked against it.
      await _pump(tester, books: [_read('a', DateTime(2026, 3, 1))]);

      final monospace = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => _effectiveStyle(tester, t).fontFamily == 'monospace')
          .toList();

      expect(
        monospace,
        isNotEmpty,
        reason: 'the strip is monospace on purpose',
      );
      for (final text in monospace) {
        expect(
          text.data,
          contains('<'),
          reason:
              '"${text.data}" is monospace but is not a strip line, so it fell '
              'back to the error style',
        );
      }
    });

    testWidgets(
      'Given the card, When it renders, Then it is exactly the export size',
      (tester) async {
        await _pump(tester, books: [_read('a', DateTime(2026, 3, 1))]);

        expect(
          tester.getSize(find.byType(ShareableLibraryCard)),
          kShareableCardSize,
        );
      },
    );

    testWidgets('Given either theme, When the card renders, Then it is the same '
        'card stock both times', (tester) async {
      // Today's export takes `colors.pageBackground`, so a dark-mode reader ships a
      // dark card and the product has two looks in circulation. The stock is pinned
      // instead, which is why it is not a theme token.
      final grounds = <Color?>[];
      for (final theme in [ThemeData.light(), ThemeData.dark()]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Center(
              child: ShareableLibraryCard(
                stats: libraryCardStats([_read('a', DateTime(2026, 3, 1))]),
                books: [_read('a', DateTime(2026, 3, 1))],
                issuedOn: _issued,
              ),
            ),
          ),
        );
        await tester.pump();
        grounds.add(
          tester
              .widget<Material>(
                find
                    .descendant(
                      of: find.byType(ShareableLibraryCard),
                      matching: find.byType(Material),
                    )
                    .first,
              )
              .color,
        );
      }

      expect(grounds.first, kCardStock);
      expect(grounds.last, kCardStock);
    });

    testWidgets(
      'Given a Korean locale, When the card renders, Then its furniture '
      'is unchanged',
      (tester) async {
        // Fixed furniture, not l10n: an artifact that names itself differently
        // depending on who exported it is two products. The date is forced English
        // for the same reason — `8월` on one card and `AUG` on the next.
        await _pump(
          tester,
          books: [_read('a', DateTime(2026, 3, 1))],
          locale: const Locale('ko'),
          displayName: '독서하는 지수',
          handle: 'paper_fox_412',
        );

        expect(find.text('MY LIBRARY CARD'), findsOneWidget);
        expect(find.text(kCardStampLine), findsOneWidget);
        expect(find.text(kCardAuthority), findsOneWidget);
        expect(find.text('20 AUG 26'), findsOneWidget);
      },
    );
  });

  group('the issue block', () {
    testWidgets('Given a reader, When the card renders, Then the record names them '
        'in their own script', (tester) async {
      // The Holder row is set in the app's own type, so a Korean name belongs here
      // rather than in the Latin strip. That split is the whole division of labour
      // between the two.
      await _pump(
        tester,
        books: [_read('a', DateTime(2026, 3, 1))],
        displayName: '독서하는 지수',
        handle: 'paper_fox_412',
        memberSince: _memberSince,
      );

      expect(find.text('Holder'), findsOneWidget);
      expect(find.text('독서하는 지수'), findsOneWidget);
      expect(find.text('Member since'), findsOneWidget);
      expect(find.text('26 JUN 26'), findsOneWidget);
    });

    testWidgets('Given any reader, When the card renders, Then no card number is '
        'invented for them', (tester) async {
      // The first version derived one from the handle. Flighty prints no card number
      // either, and a derived one is the same class of fiction as the place of issue
      // this deliberately leaves out.
      await _pump(
        tester,
        books: [_read('a', DateTime(2026, 3, 1))],
        displayName: 'jisoo',
        handle: 'paper_fox_412',
      );

      expect(find.text('Card no.'), findsNothing);
      expect(find.textContaining('Place'), findsNothing);
      // Four rows, the count Flighty prints, and every one answerable.
      for (final row in [
        'Holder',
        'Authority',
        'Date of issue',
        'Member since',
      ]) {
        expect(
          find.text(row),
          row == 'Member since' ? findsNothing : findsOneWidget,
          reason: row,
        );
      }
    });

    testWidgets(
      'Given no display name, When the card renders, Then the Holder row '
      'is absent rather than filled in',
      (tester) async {
        await _pump(tester, books: [_read('a', DateTime(2026, 3, 1))]);

        expect(find.text('Holder'), findsNothing);
        // What is always true is still printed.
        expect(find.text('Authority'), findsOneWidget);
        expect(find.text('Date of issue'), findsOneWidget);
      },
    );

    testWidgets(
      'Given one book, When the figure renders, Then the unit is singular',
      (tester) async {
        await _pump(tester, books: [_read('a', DateTime(2026, 3, 1))]);

        expect(find.text('1'), findsOneWidget);
        expect(find.text('book'), findsOneWidget);
        expect(find.text('books'), findsNothing);
      },
    );
  });

  group('the stat row', () {
    testWidgets(
      'Given the median reader, When the card renders, Then there is no '
      'stat row at all',
      (tester) async {
        // Two books, both logged same-day, two authors, one shelf. Every figure fails
        // its floor, and this is the card the whole design has to survive.
        final on = DateTime(2026, 5, 1);
        await _pump(
          tester,
          books: [
            _sameDay('a', on),
            _sameDay('b', on.add(const Duration(days: 3))),
          ],
          displayName: 'jisoo',
          handle: 'paper_fox_412',
        );

        expect(find.text('Days reading'), findsNothing);
        expect(find.text('Pace'), findsNothing);
        expect(find.text('Authors'), findsNothing);
        expect(find.text('Shelves'), findsNothing);
        expect(
          find.text('2'),
          findsOneWidget,
          reason: 'the figure is still true',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Given a reader who clears every floor, When the card renders, '
        'Then all four cells are drawn', (tester) async {
      await _pump(
        tester,
        books: [
          _read('a', DateTime(2026, 1, 5), authors: ['한강'], shelf: 'x'),
          _read('b', DateTime(2026, 2, 5), authors: ['김영하'], shelf: 'x'),
          _read('c', DateTime(2026, 3, 5), authors: ['이문열'], shelf: 'y'),
        ],
        displayName: 'jisoo',
        handle: 'paper_fox_412',
      );

      expect(find.text('Days reading'), findsOneWidget);
      expect(find.text('Pace'), findsOneWidget);
      expect(find.text('Authors'), findsOneWidget);
      expect(find.text('3'), findsWidgets, reason: 'three authors');
      expect(find.text('Shelves'), findsOneWidget);
      expect(find.text('2'), findsOneWidget, reason: 'two shelves');
    });

    testWidgets('Given two authors over two books, When the card renders, '
        'Then no author count is claimed', (tester) async {
      // "2 authors" over two books restates the hero figure. The floor is 3.
      await _pump(
        tester,
        books: [
          _read('a', DateTime(2026, 1, 5), authors: ['한강']),
          _read('b', DateTime(2026, 2, 5), authors: ['김영하']),
        ],
      );

      expect(find.text('Authors'), findsNothing);
      expect(
        find.text('Shelves'),
        findsNothing,
        reason: 'one shelf says nothing',
      );
      expect(find.text('Days reading'), findsOneWidget, reason: 'real spans');
    });

    test('Given books, When the artifact counts them, Then it counts distinct '
        'authors and shelves', () {
      final books = [
        _read('a', DateTime(2026, 1, 5), authors: ['한강', '김영하'], shelf: 'x'),
        _read('b', DateTime(2026, 2, 5), authors: ['한강'], shelf: 'x'),
        _read('c', DateTime(2026, 3, 5), authors: const [], shelf: 'y'),
      ];

      expect(cardDistinctAuthors(books), 2);
      expect(cardDistinctShelves(books), 2);
      expect(cardDistinctAuthors(const []), 0);
    });
  });

  group('the strip', () {
    test('Given a handle, When the strip is composed, Then both lines are 44 '
        'columns and the return path hangs off the end', () {
      final lines = cardStripLines(
        handle: 'paper_fox_412',
        year: 0,
        issued: _issued,
        memberSince: _memberSince,
      );

      expect(lines.length, 2);
      expect(lines.first, startsWith('ALLTIME<<PAPER_FOX_412<<MEMBER26JUN26'));
      expect(lines.last, startsWith('ISSUED20AUG26<'));
      // Right-aligned, exactly where Flighty puts FLIGHTY.COM -- the most legible
      // slot on the strip, and printed once rather than twice, because our
      // Instagram handle and our domain are the same string.
      expect(lines.last, endsWith('@LIBSTACK.APP'));
      for (final line in lines) {
        expect(line.length, 44);
      }
    });

    test('Given the longest handle allowed, When the strip is composed, Then it '
        'still fits two lines', () {
      // There is no per-reader path in the return path any more, so its width is
      // fixed and no handle can push it onto a third line.
      final lines = cardStripLines(
        handle: 'twenty_characters_ok',
        year: 2026,
        issued: _issued,
        memberSince: _memberSince,
      );

      expect(lines.length, 2);
      expect(
        lines.first,
        startsWith('Y2026<<TWENTY_CHARACTERS_OK<<MEMBER26JUN26'),
      );
      expect(lines.last, endsWith('@LIBSTACK.APP'));
      for (final line in lines) {
        expect(line.length, 44);
      }
    });

    test('Given a Korean display name where a handle belongs, When the strip is '
        'composed, Then it is rejected rather than mangled', () {
      // 142 of the 153 migrated names are non-ASCII. Sanitising this one would
      // leave `08269F2D` on the card, which is worse than no identity: it reads as
      // a fault. This is the reason `profiles.handle` exists at all.
      final lines = cardStripLines(
        handle: '\ub3c5\uc11c\ud558\ub294 08269f2d',
        year: 0,
        issued: _issued,
        memberSince: _memberSince,
      );

      expect(lines.first, startsWith('ALLTIME<<MEMBER26JUN26'));
      expect(lines.first, isNot(contains('08269F2D')));
      expect(lines.last, endsWith('@LIBSTACK.APP'));
    });

    test('Given no handle at all, When the strip is composed, Then it still '
        'carries the return path', () {
      final lines = cardStripLines(handle: null, year: 0, issued: _issued);

      expect(lines.first, startsWith('ALLTIME<<<'));
      expect(lines.last, endsWith('@LIBSTACK.APP'));
    });

    test(
      'Given a selected year, When the strip is composed, Then it says which',
      () {
        expect(
          cardStripLines(handle: 'a_reader', year: 2026, issued: _issued).first,
          startsWith('Y2026<<A_READER'),
        );
      },
    );

    test('Given anything that is not a handle, When the token is taken, Then '
        'nothing survives', () {
      // A guard rather than a converter: Task 7's format check is
      // `^[a-z0-9_]{3,20}$`, so anything failing it is a display name that
      // wandered in, and this code cannot transliterate one.
      expect(cardStripToken('paper_fox_412'), 'PAPER_FOX_412');
      expect(cardStripToken('  paper_fox_412  '), 'PAPER_FOX_412');
      expect(cardStripToken('\ub3c5\uc11c\ud558\ub294 08269f2d'), isEmpty);
      expect(
        cardStripToken('alex smith'),
        isEmpty,
        reason: 'a space is illegal',
      );
      expect(cardStripToken('ab'), isEmpty, reason: 'under the floor');
      expect(
        cardStripToken('twenty_one_characters'),
        isEmpty,
        reason: 'too long',
      );
      expect(cardStripToken(''), isEmpty);
      expect(cardStripToken(null), isEmpty);
    });
  });

  group('the card at its fullest', () {
    testWidgets('Given every row, every cell and a three-line strip, When the card '
        'renders, Then nothing overflows its fixed height', (tester) async {
      // The worst case the layout has to hold: a three-digit figure, all five issue
      // rows, all four stat cells, and a handle long enough to push the return path
      // onto its own line. An overflow here is a clipped strip in a PNG that has
      // already left the phone.
      final books = [
        for (var i = 0; i < 120; i++)
          _read(
            'b$i',
            DateTime(2026, 1, 1).add(Duration(days: i)),
            authors: ['author ${i % 9}'],
            shelf: 'shelf ${i % 4}',
            spanDays: 3,
          ),
      ];

      await _pump(
        tester,
        books: books,
        displayName: 'jisoo',
        handle: 'twenty_characters_ok',
        memberSince: _memberSince,
      );

      expect(find.text('120'), findsOneWidget);
      expect(find.text('Days reading'), findsOneWidget);
      expect(find.text('Shelves'), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'the well and the body have to share 450pt exactly',
      );
      // Not just "it fits" but "it fits with room": the metrics here are the test
      // font's, and a real one differs slightly, so zero slack would be a card that
      // overflows on a device and passes in CI. This is also what Task 4's framing
      // and Task 5's Candlelight have to leave alone.
      expect(
        tester.getSize(find.byType(Spacer)).height,
        greaterThan(5),
        reason: 'the fullest card has no headroom left',
      );
    });
  });
}

/// Guards the two labels a device screenshot caught ellipsising.
///
/// **Neither can be asserted the obvious way, and that is the finding.** The first attempt
/// here checked `RenderParagraph.didExceedMaxLines`, which fails for *every* label in CI:
/// `flutter test` renders in a fixed-width font where every glyph is one em, so a 12-letter
/// label needs 126pt and no column this card can afford would pass. Measuring width in a
/// widget test measures the test font.
///
/// What is left is the two things that do mean the same thing on both: the *constant*, which
/// carries its device measurement in its own doc comment, and a character ceiling for the
/// stat row, where every label is short plain English at one size.
void _labelFitGuards() {
  group('labels that ellipsised on a device', () {
    test(
      'Given the record column, When it is sized, Then it keeps the width a device '
      'needed',
      () {
        // 21 shipped `Member sin\u2026`. 22 would just about clear it; this is the headroom.
        expect(kCardMetaLabelUnits, greaterThanOrEqualTo(26));
      },
    );

    testWidgets(
      'Given four stat cells, When they render, Then no label is longer than '
      'the widest one known to fit',
      (tester) async {
        // Four cells is the widest the row gets and therefore the narrowest each cell gets.
        // `Pace, per book` did not survive it; `Days reading` did, and is the ceiling.
        await _pump(
          tester,
          books: [
            _read(
              'a',
              DateTime(2026, 3, 1),
              authors: const ['One'],
              shelf: 's1',
            ),
            _read(
              'b',
              DateTime(2026, 3, 8),
              authors: const ['One'],
              shelf: 's1',
            ),
            _read(
              'c',
              DateTime(2026, 3, 15),
              authors: const ['Two'],
              shelf: 's2',
            ),
            _read(
              'd',
              DateTime(2026, 3, 22),
              authors: const ['Three'],
              shelf: 's3',
            ),
          ],
        );

        // Read off the rendered card rather than from a list repeated here, so a label added
        // to `_StatRow` is checked without anyone remembering to add it.
        final labels = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .whereType<String>()
            .where(
              (value) => const {
                'Days reading',
                'Pace',
                'Authors',
                'Shelves',
              }.contains(value),
            );

        expect(labels, isNotEmpty);
        for (final label in labels) {
          expect(
            label.length,
            lessThanOrEqualTo(kCardStatLabelMaxChars),
            reason: '$label is wider than a quarter of the card',
          );
        }
      },
    );
  });
}
