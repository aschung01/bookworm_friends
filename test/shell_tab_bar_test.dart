// The floating tab bar and what a tab switch actually changes.
//
// Two things are being pinned here, and the second is the one that matters.
//
// 1. The bar renders four tabs -- Library, Friends, Card and Search -- and
//    selecting one of the first three swaps the sheet's contents. Search is the
//    odd one out: it opens a modal instead, and stays lit while that modal is up.
// 2. It swaps *only* the sheet. The library behind it is the same widget in the
//    same place — asserted through the `State` object of a `ShelfRow`, which a
//    rebuilt-from-scratch library would replace. "One persistent background,
//    never drawn twice" is the axiom the whole shell design rests on, and it is
//    the kind of thing that silently stops being true.
//
// Everything that *renders* here exercises the **Flutter fallback**, because
// `useNativeGlass` is false under `flutter test` (the test binding reports
// Android). The native `CNTabBar` path cannot be pumped, so it is asserted only
// through the gate — its absence here — never by claiming it was rendered.
//
// The exception is the `geometry` group at the bottom. `ShellTabBarGeometry` is a
// pure function of (path, home-indicator inset), so the native path's *layout*
// can be checked without rendering it — which matters, because the two numbers it
// gets wrong are invisible to every test above and were wrong on device for two
// rounds of verification.

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/book_info_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/finished_books_sheet.dart';
import 'package:bookworm_friends/ui/widgets/friends_sheet.dart';
import 'package:bookworm_friends/ui/widgets/headers/search_header.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/library_card_sheet.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';
import 'package:bookworm_friends/ui/widgets/shelf_row.dart';
import 'package:bookworm_friends/ui/widgets/shell_tab_bar.dart';

import 'support/home_page_harness.dart';

Profile _friend(String id, String name, String emoji) => Profile(
  id: id,
  username: name,
  emoji: emoji,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

// Two read books with real finish dates. The dates are not decoration: the read
// view opens filtered to the current year, so a dateless fixture leaves the pile
// empty and nothing below it can be measured.
List<Book> _readBooks() => [
  testBook(
    'r1',
    's1',
    position: 1,
    title: 'Dune',
    status: bookStatusFinished,
    finishDate: DateTime(DateTime.now().year, 3, 4),
  ),
  testBook(
    'r2',
    's1',
    position: 2,
    title: 'Circe',
    status: bookStatusFinished,
    finishDate: DateTime(DateTime.now().year - 1, 11, 2),
  ),
];

Future<void> _pumpShell(WidgetTester tester) => pumpHome(
  tester,
  extraOverrides: [
    finishedBooksProvider.overrideWith((ref) async => _readBooks()),
    friendsProvider.overrideWith(
      (ref) async => [
        _friend('f1', 'jisoo', '🦊'),
        _friend('f2', 'minho', '🐣'),
      ],
    ),
    // A visit reads these two, and it reads them in *this* page rather than in a
    // pager's child: one pane draws whoever `selectedFriendProvider` names. Left
    // unstubbed they resolve to an error and the pane never builds at all.
    userLibraryProvider.overrideWith(
      (ref, id) async => [
        testShelf('hers', [testBook('hb1', 'hers', title: 'Ficciones')]),
      ],
    ),
    userFinishedBooksProvider.overrideWith((ref, id) async => _readBooks()),
  ],
);

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(ShellTabBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ShellTabBar', () {
    testWidgets(
      'Given the test binding reports Android, When the bar builds, Then the '
      'Flutter fallback is used and no native tab bar is created',
      (tester) async {
        await _pumpShell(tester);

        expect(
          useNativeGlass,
          isFalse,
          reason:
              'if this ever becomes true under flutter test, every assertion '
              'below is about a different widget tree',
        );
        expect(find.byType(CNTabBar), findsNothing);
        expect(find.byType(ShellTabBar), findsOneWidget);
      },
    );

    testWidgets(
      'Given the shell, When first laid out, Then four tabs are shown with '
      'Library selected',
      (tester) async {
        await _pumpShell(tester);

        final bar = find.byType(ShellTabBar);
        expect(
          find.descendant(of: bar, matching: find.text('Library')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: bar, matching: find.text('Friends')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: bar, matching: find.text('Card')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: bar, matching: find.text('Search')),
          findsOneWidget,
        );

        // Library is the default tab, so its sheet is the one on screen.
        expect(find.byType(FinishedBooksSheet), findsOneWidget);
        expect(find.byType(FriendsSheet), findsNothing);
        expect(find.byType(LibraryCardSheet), findsNothing);
      },
    );

    testWidgets(
      'Given the Library tab, When Friends then Card then Library are selected, '
      'Then only the sheet changes',
      (tester) async {
        await _pumpShell(tester);

        await _selectTab(tester, 'Friends');
        expect(find.byType(FriendsSheet), findsOneWidget);
        expect(find.byType(FinishedBooksSheet), findsNothing);
        // The Everyone list is the sheet's body.
        expect(find.text('jisoo'), findsOneWidget);
        expect(find.text('minho'), findsOneWidget);

        await _selectTab(tester, 'Card');
        expect(find.byType(LibraryCardSheet), findsOneWidget);
        expect(find.byType(FriendsSheet), findsNothing);
        expect(find.text('Library Card'), findsOneWidget);

        await _selectTab(tester, 'Library');
        expect(find.byType(FinishedBooksSheet), findsOneWidget);
        expect(find.text('Books read'), findsOneWidget);
      },
    );

    testWidgets(
      'Given a library on screen, When the tab changes, Then the library behind '
      'it is the same widget, not a rebuilt one',
      (tester) async {
        await _pumpShell(tester);

        // A State object survives a rebuild but not a replacement, so holding on
        // to it is the sharpest available proof that the background persisted.
        final before = tester.state(find.byType(ShelfRow).first);
        final shelvesBefore = tester.getRect(find.byType(ShelfRow).first);

        await _selectTab(tester, 'Card');

        expect(tester.state(find.byType(ShelfRow).first), same(before));
        // Same shelves, same size: nothing scaled to make room for the sheet.
        expect(
          tester.getRect(find.byType(ShelfRow).first).size,
          shelvesBefore.size,
        );
      },
    );

    // The tab switch is a *move*, not a cut. Two tabs rest at different heights — the
    // read view on its pile, the Card at its middle detent — and the sheet used to
    // arrive at the new one on the frame of the tap, because each tab built its own
    // `LibrarySheet` and a new one has no idea where the last was. See
    // `LibrarySheet.contentId`.
    group('a tab switch springs the sheet rather than jumping it', () {
      double sheetHeight(WidgetTester tester) =>
          tester.getRect(find.byType(LibrarySheet)).height;

      Future<void> tapTab(WidgetTester tester, String label) => tester.tap(
        find.descendant(
          of: find.byType(ShellTabBar),
          matching: find.text(label),
        ),
      );

      testWidgets(
        'Given the Library tab on its pile, When Card is selected, Then the sheet '
        'travels to the Card\'s position over several frames',
        (tester) async {
          await _pumpShell(tester);
          final pile = sheetHeight(tester);

          // Pumped frame by frame rather than settled: the frames *between* the two
          // positions are the whole assertion, and `pumpAndSettle` is what hid this
          // being a jump cut in the first place.
          await tapTab(tester, 'Card');
          await tester.pump();
          expect(
            sheetHeight(tester),
            closeTo(pile, 1),
            reason:
                'the swap frame shows the Card in the box the read view was in — '
                'the contents change here, the height does not',
          );
          expect(find.byType(LibraryCardSheet), findsOneWidget);

          // One more frame before it moves, and that frame is not slack: the target
          // is measured from the header the *incoming* tab draws, so the sheet cannot
          // know where it is going until that has been laid out once.
          await tester.pump(const Duration(milliseconds: 16));
          expect(sheetHeight(tester), closeTo(pile, 1));

          await tester.pump(const Duration(milliseconds: 48));
          final moving = sheetHeight(tester);
          expect(moving, greaterThan(pile + 1), reason: 'it has left the pile');

          await tester.pumpAndSettle();
          final rested = sheetHeight(tester);
          expect(
            rested,
            greaterThan(pile + 50),
            reason: 'the Card rests far taller than the read view\'s pile',
          );
          expect(
            moving,
            lessThan(rested),
            reason: 'and part-way through it was still on its way there',
          );
        },
      );

      testWidgets(
        'Given the Card, When Library is selected, Then the sheet comes down from '
        'the height the Card was at',
        (tester) async {
          await _pumpShell(tester);
          await _selectTab(tester, 'Card');
          final card = sheetHeight(tester);

          await tapTab(tester, 'Library');
          await tester.pump();

          expect(
            sheetHeight(tester),
            closeTo(card, 1),
            reason: 'shrinking is the same rule as growing, from the other end',
          );
          await tester.pumpAndSettle();
          expect(sheetHeight(tester), lessThan(card - 50));
        },
      );

      testWidgets(
        'Given a tab switch, When it happens, Then it is one sheet being handed '
        'over rather than two sheets swapping',
        (tester) async {
          // The mechanism, stated as sharply as the persistent-library test states
          // its own: a `State` survives a re-parent and does not survive a
          // replacement, and a replacement is what makes the height a jump. Nothing
          // else here can tell the two apart — both draw the same frame at rest.
          await _pumpShell(tester);
          final sheet = tester.state(find.byType(LibrarySheet));

          await _selectTab(tester, 'Card');
          expect(tester.state(find.byType(LibrarySheet)), same(sheet));

          await _selectTab(tester, 'Friends');
          expect(tester.state(find.byType(LibrarySheet)), same(sheet));
        },
      );
    });

    testWidgets(
      'Given the bar floats over the sheet, When laid out, Then it covers none of '
      "the sheet's contents",
      (tester) async {
        await _pumpShell(tester);

        final bar = tester.getRect(find.byType(ShellTabBar));
        final screen = tester.getRect(find.byType(Scaffold));

        // Floating: inset from the sides and clear of the bottom edge. Literal
        // numbers on purpose -- asserting against `ShellTabBarGeometry`'s own
        // getters here would only prove they equal themselves. The test surface
        // has no home-indicator inset, so the bottom offset is just the gap.
        expect(bar.left, closeTo(14, 0.5));
        expect(bar.right, closeTo(screen.right - 14, 0.5));
        expect(bar.bottom, closeTo(screen.bottom - 8, 0.5));
        expect(bar.height, closeTo(50, 0.5));

        // The sheet reserves room for it, so the last thing the sheet draws --
        // the shelf the read pile stands on -- stops above the bar.
        //
        // "Reserves" means for its *chrome*, which is what both of these are: the
        // header, and the collapsed body the snap position is measured from. A
        // scrolling body is deliberately not in that class -- the expanded grid's
        // rows run under the bar and out the other side, because a strip of blank
        // card behind a translucent bar is what an iOS sheet does not look like.
        // What keeps such a body's last row reachable is its own scroll padding;
        // see `ReadMonthGrid.bottomPadding`.
        for (final content in [find.text('Books read'), find.text('Dune')]) {
          expect(
            tester.getRect(content).bottom,
            lessThanOrEqualTo(bar.top),
            reason: '$content is covered by the floating tab bar',
          );
        }
      },
    );

    testWidgets('Given the Friends sheet, When a friend is tapped, Then a visit begins '
        'and the tab bar stays', (tester) async {
      await _pumpShell(tester);

      await _selectTab(tester, 'Friends');
      await tester.tap(find.text('jisoo'));
      await tester.pumpAndSettle();

      // The provider is the sharpest evidence that the *background* changed: it is
      // now the only thing that decides whose library is on screen, and the bar's
      // title is drawn from it.
      expect(
        shellContainer(tester).read(selectedFriendProvider)?.username,
        'jisoo',
      );
      expect(find.text('My Library'), findsNothing);
      expect(find.text('Poke'), findsOneWidget);

      // The one decision this branch of the design reopened, and the reason the
      // rail could go: no tab changes meaning inside a visit, so the bar has
      // nothing to lie about and stays.
      expect(
        find.byType(ShellTabBar),
        findsOneWidget,
        reason:
            'the bar is hidden only for an edit now; every tab still means '
            'yours during a visit',
      );
      expect(
        tester.widget<ShellTabBar>(find.byType(ShellTabBar)).current,
        LibraryTab.friends,
        reason: 'a visit is a state of the Friends tab, not a place beside it',
      );

      // And the sheet drilled in: the list is gone and her read books are the level
      // below it. Nothing was added to the sheet to get back out — the Friends tab
      // itself is that control, which the next test exercises.
      expect(find.byType(FriendsSheet), findsNothing);
      expect(find.byType(FinishedBooksSheet), findsOneWidget);
    });

    testWidgets(
      'Given a friend\'s read books, When the already-selected Friends tab is '
      'tapped, Then the list returns and the visit does not end',
      (tester) async {
        await _pumpShell(tester);
        await enterVisit(tester, 'jisoo');

        // A reselect, not a switch. The whole friend switcher rests on the bar
        // reporting it — the fallback's segments call `onChanged` unconditionally and
        // `CNTabBar` forwards every native `valueChanged`; see
        // `ShellChrome._selectTab`.
        await backToFriendsList(tester);

        expect(find.byType(FriendsSheet), findsOneWidget);
        expect(
          find.text('minho'),
          findsOneWidget,
          reason: 'the switcher is back, so the next friend is one tap away',
        );
        expect(
          shellContainer(tester).read(selectedFriendProvider)?.username,
          'jisoo',
          reason:
              'coming up a level leaves her library behind the sheet — that is '
              'what makes the list a switcher rather than an exit',
        );
        expect(
          find.text('jisoo\'s Library'),
          findsOneWidget,
          reason: 'and the bar still says whose library you are in',
        );
      },
    );

    testWidgets(
      'Given a visit, When the bar\'s ✕ is tapped, Then it ends and the Friends '
      'list comes back',
      (tester) async {
        await _pumpShell(tester);
        await enterVisit(tester, 'jisoo');

        await endVisit(tester);

        expect(shellContainer(tester).read(selectedFriendProvider), isNull);
        expect(find.byType(ShellTabBar), findsOneWidget);
        expect(find.text('My Library'), findsOneWidget);
        expect(
          find.byType(FriendsSheet),
          findsOneWidget,
          reason:
              'leaving a visit should land you back on the tab you left from, at '
              'its first level',
        );
      },
    );
    // Card is the sharp case: its sheet has no reason of its own to move, so
    // before this it sat at full height while the covers wiggled, taking room the
    // library needed to be rearranged in. One test per tab rather than a loop:
    // edit mode's wiggle repeats forever, so a second `pumpHome` in the same test
    // never settles.
    //
    // Note what this can and cannot see. Only Friends launches open — the read view
    // rests on its pile and the Card opens to `card-down` — so Friends is the one tab
    // where the *spring* is observable from here at all. Opening the other two first is
    // not an option: an edit is started by long-pressing a cover, and an open sheet is
    // either covering the library or putting its own `BookWidget`s in front of it. The
    // spring itself is pinned by `finished_books_sheet_test.dart` and
    // `library_sheet_test.dart`; what this holds is that *every* tab drops its chrome
    // and none of them grow into the space the edit needs.
    for (final tab in ['Library', 'Friends', 'Card']) {
      testWidgets(
        'Given the $tab tab, When the library enters edit mode, Then the bar is '
        'hidden and the sheet is out of the way',
        (tester) async {
          await _pumpShell(tester);
          await _selectTab(tester, tab);
          final sheetBefore = tester.getRect(find.byType(LibrarySheet));

          await enterEditMode(tester);
          await tester.pump(const Duration(seconds: 2));

          expect(
            find.byType(ShellTabBar),
            findsNothing,
            reason: 'an edit is a focused context and drops its chrome',
          );
          expect(
            tester.getRect(find.byType(LibrarySheet)).height,
            lessThanOrEqualTo(sheetBefore.height + 0.5),
            reason: 'the sheet must leave the library room to edit in',
          );
          if (tab == 'Friends') {
            expect(
              tester.getRect(find.byType(LibrarySheet)).height,
              lessThan(sheetBefore.height),
              reason:
                  'the only tab that launches open, so the only one where the '
                  'spring shut is visible from here',
            );
          }
          expect(isEditing(), isTrue);
        },
      );
    }

    testWidgets(
      'Given an edit in progress, When it ends, Then the bar comes back on the '
      'same tab',
      (tester) async {
        await _pumpShell(tester);
        await _selectTab(tester, 'Card');

        await enterEditMode(tester);
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(ShellTabBar), findsNothing);

        await tester.tap(libraryDoneButton());
        await tester.pumpAndSettle();

        expect(find.byType(ShellTabBar), findsOneWidget);
        expect(
          find.byType(LibraryCardSheet),
          findsOneWidget,
          reason: 'an edit should not quietly move you to another tab',
        );
      },
    );
    testWidgets(
      'Given the shell, When Search is tapped, Then it opens as a modal at 95% '
      'height rather than replacing the library',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        await pumpHome(
          tester,
          extraOverrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            finishedBooksProvider.overrideWith((ref) async => <Book>[]),
          ],
        );

        await tester.tap(
          find.descendant(
            of: find.byType(ShellTabBar),
            matching: find.text('Search'),
          ),
        );
        await tester.pumpAndSettle();

        final sheet = find.byType(SearchTextField);
        expect(
          sheet,
          findsOneWidget,
          reason: 'the search field should be in it',
        );
        expect(
          find.text('Search books'),
          findsOneWidget,
          reason:
              'the sheet is titled Search books, not Add book: it searches the '
              "reader's own library as well as the catalogue, and adding is one "
              'of its two sections rather than the whole of it',
        );

        // Starts at the safe-area inset so the barrier stays visible and the
        // status bar reads against the library, not against sheet content.
        // Tight tolerance on purpose -- Material's own drag handle silently
        // pushed this to ~98% and a loose bound did not notice.
        //
        // 24 is the floor `_minAddBookTopInset` applies, because the test
        // surface reports no top inset; on a real phone this is the 62pt status
        // bar instead.
        // Scoped to the modal: the library's own sheet is still behind it, with a
        // handle of its own.
        final modal = find
            .ancestor(
              of: find.byType(SearchTextField),
              matching: find.byType(Column),
            )
            .last;
        final sheetBox = tester.getRect(
          find.descendant(of: modal, matching: find.byType(SheetGrabHandle)),
        );
        expect(
          sheetBox.top,
          closeTo(24, 2),
          reason: 'the sheet should leave a band of library above it',
        );

        // The library is still there underneath, not popped.
        expect(find.byType(ShelfRow), findsWidgets);
      },
    );

    testWidgets(
      'Given Add Book is open over the bar, When a tab is tapped, Then the sheet '
      'is dismissed and the tab actually changes',
      (tester) async {
        await _pumpShell(tester);

        await tester.tap(
          find.descendant(
            of: find.byType(ShellTabBar),
            matching: find.text('Search'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SearchTextField), findsOneWidget);
        expect(
          find.byType(ShellTabBar),
          findsOneWidget,
          reason:
              'the bar is hosted above the navigator so it stays in front of the '
              'sheet -- if this fails it is being auto-hidden again',
        );

        await _selectTab(tester, 'Friends');

        // Without the dismiss the tab would switch *behind* Add Book, and the bar
        // would look inert: visible, tappable, apparently doing nothing.
        expect(
          find.byType(SearchTextField),
          findsNothing,
          reason: 'tapping a tab should dismiss the sheet over the shell',
        );
        expect(find.byType(FriendsSheet), findsOneWidget);
      },
    );

    testWidgets(
      'Given Add Book is open with the bar over it, When a sheet opens from Add '
      'Book, Then the bar leaves until that sheet is closed',
      (tester) async {
        await _pumpShell(tester);

        await tester.tap(
          find.descendant(
            of: find.byType(ShellTabBar),
            matching: find.text('Search'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ShellTabBar), findsOneWidget);

        // Presented from a context *inside* Add Book, the way tapping a search
        // result does it. The results list is empty here, and the sheet under
        // test is the shell's reaction to it rather than the list.
        showBookInfoBottomSheet(
          tester.element(find.text('Search books')),
          book: const BookSearchResult(
            title: 'The Hard Thing About Hard Things',
            isbn: '9780062273208',
            thumbnail: '',
            authors: ['Ben Horowitz'],
          ),
          shelfNames: const ['자기계발'],
          onSavePressed: (_, __, {startDate, finishDate, coverColor}) {},
        );
        await tester.pumpAndSettle();
        // Twice: the sheet's heading, and the generated cover beside it, which
        // paints the title when there is no thumbnail.
        expect(find.text('The Hard Thing About Hard Things'), findsWidgets);

        expect(
          find.byType(ShellTabBar),
          findsNothing,
          reason:
              'the bar floats over Add Book, not over a stack of sheets: a tab '
              'tap only pops one route, and the native search bar bleeds its '
              'glass through the sheet drawn above it',
        );

        Navigator.of(tester.element(find.byType(ShelfRow).first)).pop();
        await tester.pumpAndSettle();

        expect(find.byType(ShellTabBar), findsOneWidget);
        expect(
          find.byType(SearchTextField),
          findsOneWidget,
          reason: 'closing the inner sheet should land you back on Add Book',
        );
      },
    );

    testWidgets(
      'Given a page is pushed over the shell, When it is on top, Then the bar is '
      'hidden, and it comes back on pop',
      (tester) async {
        await _pumpShell(tester);
        expect(find.byType(ShellTabBar), findsOneWidget);

        final navigator = Navigator.of(
          tester.element(find.byType(ShelfRow).first),
        );
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('a pushed page')),
          ),
        );
        await tester.pumpAndSettle();

        // This used to be free: the bar lived inside the page, so a push covered
        // it. Hosted above the navigator nothing is free -- without the
        // top-page-route rule the bar would float on top of every pushed page.
        expect(
          find.byType(ShellTabBar),
          findsNothing,
          reason: 'a pushed page should take the chrome with it',
        );

        navigator.pop();
        await tester.pumpAndSettle();
        expect(find.byType(ShellTabBar), findsOneWidget);
      },
    );
  });

  // The bar's position, for both paths.
  //
  // What these pin is the *shape* of the derivation, not the measured constants:
  // that the native bar is handed the frame a system tab bar gets, and that the
  // bar's position and the sheet's reservation come off the same edge. 83 and 62
  // still rest on a device reading; 0 and 0 do not — they follow from what a
  // `UITabBar` frame is.
  group('geometry', () {
    // iPhone in portrait with a home indicator.
    const indicator = 34.0;
    const gap = ShellTabBarGeometry.gap;
    const pillTopRoom = ShellTabBarGeometry.pillTopRoom;

    test('Given the native path, Then the bar is handed a system tab bar\'s '
        'frame: flush with the bottom and full-width', () {
      const geometry = ShellTabBarGeometry(
        native: true,
        bottomViewPadding: indicator,
      );

      // The regression this exists for. iOS insets its glass platter *within*
      // this frame -- 21pt at the bottom, some margin at each side -- so any
      // offset added here lands on top of the system's own and the bar comes out
      // floating high and narrow. A `UITabBar` gets the whole bottom of the
      // screen; matching one means giving it the whole bottom of the screen.
      expect(geometry.bottomOffset, 0);
      expect(geometry.sideInset, 0);

      // 83 is `49 + 34`: the bar, plus the home-indicator strip it owns itself.
      // So the indicator inset must *not* be added on top.
      expect(geometry.glassTop, 83);
      expect(geometry.reserve, 83 + gap - indicator);

      // The box is taller than the frame by the package's own top inset, and
      // *only* by that -- the bar still ends at the bottom of the screen. This is
      // what changed when the search item went away: `boxHeight` grew, and the
      // three numbers above did not move, which is why no sheet had to.
      expect(geometry.boxHeight, 83 + pillTopRoom);
    });

    test('Given the fallback path, Then it reserves the home-indicator strip '
        'itself, because nothing else will', () {
      const geometry = ShellTabBarGeometry(
        native: false,
        bottomViewPadding: indicator,
      );

      expect(geometry.bottomOffset, indicator + gap);
      expect(geometry.sideInset, 14);
      // Unchanged by the native fix, which is the point: the fallback draws its
      // own pill and always needed these.
      expect(geometry.reserve, gap + 50 + gap);
    });

    test('Given either path, Then the bar and the sheet are derived from one '
        'edge, so they cannot drift apart', () {
      for (final native in [true, false]) {
        final geometry = ShellTabBarGeometry(
          native: native,
          bottomViewPadding: indicator,
        );
        final label = native ? 'native' : 'fallback';

        expect(
          geometry.bottomOffset + geometry.boxHeight,
          geometry.glassTop + (native ? pillTopRoom : 0),
          reason:
              '$label: the glass\'s top edge is a fixed offset from the box\'s '
              'top edge -- the same edge on the fallback, and the package\'s own '
              '14pt of pill room above it on the native path. It is the only edge '
              'Flutter can place, since every other one involves an inset only '
              'native code can see',
        );
        expect(
          geometry.reserve + geometry.bottomViewPadding,
          geometry.glassTop + gap,
          reason:
              '$label: the sheet must stop a gap above the glass, and it adds '
              'the indicator inset itself',
        );
      }
    });
  });
}
