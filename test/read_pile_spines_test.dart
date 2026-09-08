// Tests for the read pile's spines: their sizes, their tones, and turning one out.
//
// The pile is the only place in the app that draws every book at once, which is why
// it is also the only place the books were all the same size. Three things are
// asserted here and each has a failure mode that is invisible in a green test suite:
//
//   1. **No book exceeds the row.** The base height is derived from the row's space
//      *divided* by the tallest jitter factor, so the tallest book is exactly the
//      124pt every spine used to be. Get that backwards and the tallest book is
//      clipped at the head, which is where the eye is — and `ReadPile.extent`, which
//      LibrarySheet snaps to, silently stops being honest.
//   2. **The turned book is exactly as thick as the spine that was tapped.** The
//      spine and the chassis are two drawings of one book, and the swap between them
//      is instant. A thickness computed twice is a thickness that can differ.
//   3. **The tone comes from the book, and never from a decode.** A spine that had
//      to wait for an image would paint grey and colour itself in, on a row of a
//      dozen books, in a tab that loads no images at all today.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book/book_chassis.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart'
    show kBookTurnAngle;
import 'package:bookworm_friends/ui/widgets/book/generated_cover.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/read_pile.dart';

Book _book(String id, {String? isbn, int? pageCount, Color? coverColor}) =>
    Book(
      id: id,
      userId: 'u',
      shelfId: 's1',
      isbn: isbn ?? '978893643412$id',
      title: 'Book $id',
      thumbnail: '',
      status: 2,
      position: 0,
      createdAt: DateTime(2024),
      authors: const [],
      finishDate: DateTime(2024, 3, 1),
      pageCount: pageCount,
      coverColor: coverColor,
    );

Future<void> _pump(
  WidgetTester tester,
  List<Book> books, {
  int filterYear = 0,
  bool isEditMode = false,
}) async {
  await tester.pumpWidget(
    // The pile reports the open book's decoded cover colour back to
    // `books.cover_color`, so it reads `libraryActionsProvider` and needs a scope.
    // Nothing here overrides it: no cover in these tests decodes, so the callback
    // is never reached. The scope is present anyway, because "passes only because
    // the provider is never touched" is a test that breaks the day someone adds a
    // decoding one.
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 402,
            child: ReadPile(
              books: books,
              filterYear: filterYear,
              isEditMode: isEditMode,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

BookVertical _spine(WidgetTester tester, String title) =>
    tester.widget<BookVertical>(
      find.ancestor(of: find.text(title), matching: find.byType(BookVertical)),
    );

/// A pile on a route, so pushes can be observed. Every route builds the same pile,
/// which is enough: what is being asserted is *that* a push happened and with what
/// name, not what it landed on.
Future<void> _pumpRouted(
  WidgetTester tester,
  Book book,
  List<String> pushed,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        onGenerateRoute: (settings) {
          if (settings.name != null && settings.name != '/') {
            pushed.add(settings.name!);
          }
          return MaterialPageRoute(
            builder: (_) => Scaffold(
              body: SizedBox(width: 402, child: ReadPile(books: [book])),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('readSpineMetrics', () {
    test(
      'Given any ISBN, When a spine is sized, Then it fits the row it stands in',
      () {
        // The whole reason the base is written as a division. Swept rather than
        // sampled, because the tallest hash is the one that breaks and there is no
        // way to know which ISBN that is.
        var tallest = 0.0;
        for (var i = 0; i < 3000; i++) {
          final m = readSpineMetrics(_book('x', isbn: '97889364$i')).metrics;
          expect(
            m.height,
            lessThanOrEqualTo(ReadPile.rowExtent),
            reason: 'a spine outgrew the row it stands in',
          );
          tallest = math.max(tallest, m.height);
        }
        // And the tallest is exactly the flat height every spine used to have, so
        // `ReadPile.extent` is unchanged by construction rather than by luck.
        expect(tallest, closeTo(124, 0.01));
      },
    );

    test(
      'Given the pile\'s parts, When they are summed, Then the collapsed extent '
      'is still 169',
      () {
        // LibrarySheet snaps to this while the *grid* is the body on screen, so it
        // cannot measure it. Variable spine heights had to leave it untouched.
        expect(ReadPile.extent, 169);
      },
    );

    test('Given a book with a page count, When it is sized, Then the count sets its '
        'thickness rather than the hash', () {
      // The same rule the shelves follow. Worth pinning here because the pile is
      // the first place thickness is load-bearing for *layout* and not only for
      // a few pixels of fore-edge.
      final thin = readSpineMetrics(_book('a', pageCount: 90)).metrics;
      final thick = readSpineMetrics(_book('a', pageCount: 900)).metrics;
      expect(thin.thickness, lessThan(thick.thickness));
    });

    test(
      'Given the same book twice, When it is sized twice, Then both answers are '
      'identical',
      () {
        // It is called once per frame per book, and a spine that changed width
        // between frames would shimmer.
        final book = _book('a');
        expect(
          readSpineMetrics(book).metrics.thickness,
          readSpineMetrics(book).metrics.thickness,
        );
      },
    );
  });

  group('the resting row', () {
    testWidgets(
      'Given books of different ISBNs, When the pile is drawn, Then no two '
      'spines are the same width',
      (tester) async {
        // The point of the change. Before it, every book in the app was drawn at a
        // hashed size except here.
        final books = [
          _book('1', isbn: '9788934972464'),
          _book('2', isbn: '9788937834158'),
          _book('3', isbn: '9788954633767'),
        ];
        await _pump(tester, books);

        final widths = books.map((b) => _spine(tester, b.title).width).toSet();
        expect(widths, hasLength(3));
      },
    );

    testWidgets(
      'Given a book with a stored cover colour, When its spine is drawn, Then it '
      'is toned from that colour',
      (tester) async {
        const cover = Color(0xFF3D5A80);
        final book = _book('1', coverColor: cover);
        await _pump(tester, [book]);

        final tone = spineToneFor(cover);
        final spine = _spine(tester, book.title);
        expect(spine.fill, tone.fill);
        // Asserted alongside the fill, because the two are one decision: the fill is
        // walked away from whichever ink was chosen, so a spine that took the fill
        // and re-derived the ink could disagree with the walk that produced it.
        expect(spine.titleColor, tone.title);
      },
    );

    testWidgets(
      'Given a book with no stored colour, When its spine is drawn, Then it '
      'falls back to the swatch its ISBN already picks',
      (tester) async {
        // Not grey, and not a decode: the same colour `GeneratedCover` would use
        // for this book, so the spine and its own cover are the same family
        // whichever state the backfill is in.
        final book = _book('1', isbn: '9788901219943');
        await _pump(tester, [book]);

        expect(
          _spine(tester, book.title).fill,
          spineToneFor(generatedCoverColor(book.isbn)).fill,
        );
      },
    );

    testWidgets(
      'Given a resting pile, When it is drawn, Then it loads no covers at all',
      (tester) async {
        // The cost that keeps the pile cheap. One BookWidget appears when a book is
        // tapped and not before; a row of chassis would mean an ImageStream per
        // book in the collapsed Library tab.
        await _pump(tester, [_book('1'), _book('2'), _book('3')]);

        expect(find.byType(BookWidget), findsNothing);
      },
    );

    testWidgets('Given a spine, When it is drawn, Then it carries a separator', (
      tester,
    ) async {
      // Unnecessary while every spine was one green at three opacities. Once each
      // takes its own book's tone, two similar covers stand side by side as one
      // wide block without it.
      await _pump(tester, [_book('1')]);

      expect(_spine(tester, 'Book 1').separator, isTrue);
    });
  });

  group('turning one out', () {
    testWidgets(
      'Given a resting pile, When a spine is tapped, Then that book turns out '
      'from spine-on to cover-on',
      (tester) async {
        final book = _book('1');
        await _pump(tester, [book]);

        await tester.tap(find.text(book.title));
        await tester.pump();
        expect(
          tester.widget<BookChassis>(find.byType(BookChassis)).turn,
          closeTo(kReadSpinePose, 1e-9),
          reason: 'the book did not start from the pose the spine was drawn at',
        );

        await tester.pumpAndSettle();
        expect(
          tester.widget<BookChassis>(find.byType(BookChassis)).turn,
          closeTo(0, 1e-9),
          reason: 'the book did not finish cover-on',
        );
      },
    );

    testWidgets(
      'Given a book turning out, When it is drawn, Then it is exactly as thick '
      'as the spine that was tapped',
      (tester) async {
        // Failure mode: the chassis re-derives the jitter from the ISBN, gets the
        // same answer, and everything looks fine — until a book has a page count,
        // or the base height changes on one side only. The two must be one number.
        final book = _book('1', isbn: '9788937834158', pageCount: 512);
        await _pump(tester, [book]);
        final spineWidth = _spine(tester, book.title).width;

        await tester.tap(find.text(book.title));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<BookChassis>(find.byType(BookChassis))
              .metrics
              .thickness,
          closeTo(spineWidth, 1e-9),
        );
      },
    );

    testWidgets(
      'Given a book turned out, When it is drawn, Then it hinges on its spine '
      'and carries a spine face',
      (tester) async {
        final book = _book('1');
        await _pump(tester, [book]);
        await tester.tap(find.text(book.title));
        await tester.pumpAndSettle();

        final chassis = tester.widget<BookChassis>(find.byType(BookChassis));
        expect(chassis.pivot, Alignment.centerLeft);
        expect(chassis.spine, isNotNull);
      },
    );

    testWidgets(
      'Given one book open, When a second spine is tapped, Then both are in '
      'flight and only one is left open',
      (tester) async {
        final books = [
          _book('1', isbn: '9788934972464'),
          _book('2', isbn: '9788937834158'),
        ];
        await _pump(tester, books);

        await tester.tap(find.text('Book 1'));
        await tester.pumpAndSettle();
        expect(find.byType(BookChassis), findsOneWidget);

        await tester.tap(find.text('Book 2'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(
          find.byType(BookChassis),
          findsNWidgets(2),
          reason: 'the outgoing book snapped flat instead of turning back',
        );

        await tester.pumpAndSettle();
        expect(find.byType(BookChassis), findsOneWidget);
      },
    );

    testWidgets(
      'Given a book open, When the year filter changes, Then it closes',
      (tester) async {
        // The list under it is no longer the list that was tapped.
        final book = _book('1');
        await _pump(tester, [book]);
        await tester.tap(find.text(book.title));
        await tester.pumpAndSettle();
        expect(find.byType(BookChassis), findsOneWidget);

        await _pump(tester, [book], filterYear: 2024);
        expect(find.byType(BookChassis), findsNothing);
      },
    );

    testWidgets('Given a book open, When edit mode starts, Then it closes', (
      tester,
    ) async {
      // The sheet springs shut, and a book left turned out would reopen turned
      // out.
      final book = _book('1');
      await _pump(tester, [book]);
      await tester.tap(find.text(book.title));
      await tester.pumpAndSettle();

      await _pump(tester, [book], isEditMode: true);
      expect(find.byType(BookChassis), findsNothing);
    });

    testWidgets(
      'Given a book open, When it leaves the list, Then nothing is left open',
      (tester) async {
        final books = [
          _book('1', isbn: '9788934972464'),
          _book('2', isbn: '9788937834158'),
        ];
        await _pump(tester, books);
        await tester.tap(find.text('Book 1'));
        await tester.pumpAndSettle();

        await _pump(tester, [books[1]]);
        expect(find.byType(BookChassis), findsNothing);
      },
    );
  });

  group('the Hero, and why it is now safe', () {
    testWidgets(
      'Given a resting pile, When it is drawn, Then no book carries a hero tag',
      (tester) async {
        // The old objection, and it was a good one: thirteen books on one route
        // under `book_<isbn>` is thirteen sources for one tag, which is a Flutter
        // assertion rather than a design problem. It does not arise because a
        // resting spine is not a Hero at all.
        await _pump(tester, [
          _book('1', isbn: '9788934972464'),
          _book('2', isbn: '9788937834158'),
          _book('3', isbn: '9788954633767'),
        ]);

        expect(find.byType(Hero), findsNothing);
      },
    );

    testWidgets(
      'Given a pile of books, When one is turned out, Then exactly one hero tag '
      'exists',
      (tester) async {
        // What makes the flight legal: one book open at a time, and the tag lives
        // on the open book only.
        await _pump(tester, [
          _book('1', isbn: '9788934972464'),
          _book('2', isbn: '9788937834158'),
          _book('3', isbn: '9788954633767'),
        ]);

        await tester.tap(find.text('Book 2'));
        await tester.pumpAndSettle();

        expect(find.byType(Hero), findsOneWidget);
        expect(
          tester.widget<Hero>(find.byType(Hero)).tag,
          'book_9788937834158',
        );
      },
    );

    testWidgets(
      'Given every book in the pile has no ISBN, When one is turned out, Then '
      'nothing collides',
      (tester) async {
        // A book with no ISBN tags as `book_`, so a pile of them would be a pile of
        // identical tags if a resting spine were a Hero. It is not, so the only tag
        // on the route belongs to the book that was tapped.
        final books = [
          _book('1', isbn: ''),
          _book('2', isbn: ''),
          _book('3', isbn: ''),
        ];
        await _pump(tester, books);

        await tester.tap(find.text('Book 1'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(Hero), findsOneWidget);
      },
    );

    testWidgets(
      'Given a book turned out, When its cover is tapped, Then the details route '
      'is pushed',
      (tester) async {
        // Two taps to the details page where there was one, and this is the second.
        // A resting spine turns out; only a book already out navigates.
        final book = _book('1');
        final pushed = <String>[];
        await _pumpRouted(tester, book, pushed);

        // First tap: turns out, does not navigate.
        await tester.tap(find.text(book.title));
        await tester.pumpAndSettle();
        expect(pushed, isEmpty, reason: 'the first tap navigated');

        // Second tap, on the cover this time.
        await tester.tap(find.byType(BookWidget));
        await tester.pumpAndSettle();
        expect(pushed, [AppRoutes.details]);
      },
    );
  });

  group('a book that is out behaves like one on a shelf', () {
    testWidgets('Given a book turned out, When it is held, Then it turns a further '
        'kBookTurnAngle', (tester) async {
      // The reason the pose composes with the hold instead of replacing it. The
      // book is at 0 and the hold takes it to +16° on the shelves' own timings,
      // through the shelves' own code path.
      final book = _book('1');
      await _pump(tester, [book]);
      await tester.tap(find.text(book.title));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BookWidget)),
      );
      await tester.pump(kBookHoldDelay);
      await tester.pump(kBookTurnDuration);
      expect(
        tester.widget<BookChassis>(find.byType(BookChassis)).turn,
        closeTo(kBookTurnAngle, 1e-9),
      );

      // Cancelled rather than released, because releasing *navigates* — which is
      // the very next test. Cancelling runs the same `_endHold` path without
      // pushing a route on top of the book being measured.
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(
        tester.widget<BookChassis>(find.byType(BookChassis)).turn,
        closeTo(0, 1e-6),
        reason: 'releasing did not return the book to cover-on',
      );
    });

    testWidgets('Given a book held past the shelves\' stage-two delay, When it is '
        'released, Then it still navigates', (tester) async {
      // On the shelves a long hold enters edit mode and *suppresses* the tap that
      // follows. The pile has no edit mode and passes no `onLongPress`, so there
      // is no stage two to suppress anything — which means a hold of any length
      // ends in navigation. Worth pinning, because "nothing happens on a long
      // press" and "a long press swallows the tap" look identical until you hold
      // a book for two seconds and it does nothing at all.
      final book = _book('1');
      final pushed = <String>[];
      await _pumpRouted(tester, book, pushed);
      await tester.tap(find.text(book.title));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BookWidget)),
      );
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(pushed, [AppRoutes.details]);
    });
  });
}
