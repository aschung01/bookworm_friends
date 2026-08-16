// The floating tab bar and what a tab switch actually changes.
//
// Two things are being pinned here, and the second is the one that matters.
//
// 1. The bar renders three tabs and a detached Add Book button, and selecting a
//    tab swaps the sheet's contents.
// 2. It swaps *only* the sheet. The library behind it is the same widget in the
//    same place — asserted through the `State` object of a `ShelfRow`, which a
//    rebuilt-from-scratch library would replace. "One persistent background,
//    never drawn twice" is the axiom the whole shell design rests on, and it is
//    the kind of thing that silently stops being true.
//
// Everything here exercises the **Flutter fallback**, because `useNativeGlass` is
// false under `flutter test` (the test binding reports Android). The native
// `CNTabBar` path cannot be pumped, so it is asserted only through the gate — its
// absence here — never by claiming it was rendered.

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/finished_books_sheet.dart';
import 'package:bookworm_friends/ui/widgets/friend_rail.dart';
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

List<Book> _readBooks() => [
  testBook('r1', 's1', position: 1, title: 'Dune', status: bookStatusFinished),
  testBook('r2', 's1', position: 2, title: 'Circe', status: bookStatusFinished),
];

Future<void> _pumpShell(WidgetTester tester) => pumpHome(
  tester,
  extraOverrides: [
    finishedBooksProvider.overrideWith((ref) async => _readBooks()),
    followingListProvider.overrideWith(
      (ref) async => [
        _friend('f1', 'jisoo', '🦊'),
        _friend('f2', 'minho', '🐣'),
      ],
    ),
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
      'Given the shell, When first laid out, Then three tabs and Add Book are '
      'shown with Library selected',
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
          find.descendant(of: bar, matching: find.byIcon(Icons.search)),
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

    testWidgets(
      'Given the bar floats over the sheet, When laid out, Then it covers none of '
      "the sheet's contents",
      (tester) async {
        await _pumpShell(tester);

        final bar = tester.getRect(find.byType(ShellTabBar));
        final screen = tester.getRect(find.byType(Scaffold));

        // Floating: inset from the sides and clear of the bottom edge.
        expect(bar.left, closeTo(ShellTabBar.sideInset, 0.5));
        expect(bar.right, closeTo(screen.right - ShellTabBar.sideInset, 0.5));
        expect(bar.bottom, closeTo(screen.bottom - ShellTabBar.gap, 0.5));
        expect(bar.height, closeTo(ShellTabBar.visualHeight, 0.5));

        // The sheet reserves room for it, so the last thing the sheet draws --
        // the shelf the read pile stands on -- stops above the bar.
        for (final content in [find.text('Books read'), find.text('Dune')]) {
          expect(
            tester.getRect(content).bottom,
            lessThanOrEqualTo(bar.top),
            reason: '$content is covered by the floating tab bar',
          );
        }
      },
    );

    testWidgets(
      'Given the Friends sheet, When a friend is tapped, Then a visit begins: rail '
      'in, tab bar out',
      (tester) async {
        await _pumpShell(tester);

        expect(
          find.byType(FriendRail),
          findsNothing,
          reason: 'the rail exists only inside a visit',
        );

        await _selectTab(tester, 'Friends');
        await tester.tap(find.text('jisoo'));
        await tester.pumpAndSettle();

        final rail = tester.widget<FriendRail>(find.byType(FriendRail));
        expect(rail.selectedFriend?.username, 'jisoo');
        expect(
          rail.following.map((f) => f.username),
          ['jisoo', 'minho'],
          reason: 'friends only — you are not in your own visit rail',
        );
        expect(
          find.byType(ShellTabBar),
          findsNothing,
          reason: 'a visit is a focused context and drops the tab bar',
        );
        expect(find.text('Poke'), findsOneWidget);
      },
    );

    testWidgets(
      'Given a visit, When the rail\'s ✕ is tapped, Then it ends and the tab bar '
      'comes back on Friends',
      (tester) async {
        await _pumpShell(tester);
        await enterVisit(tester, 'jisoo');

        await tester.tap(
          find.descendant(
            of: find.byType(FriendRail),
            matching: find.byIcon(Icons.close),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FriendRail), findsNothing);
        expect(find.byType(ShellTabBar), findsOneWidget);
        expect(find.text('My Library'), findsOneWidget);
        expect(
          find.byType(FriendsSheet),
          findsOneWidget,
          reason:
              'leaving a visit should land you back on the tab you left from',
        );
      },
    );
    // Card is the sharp case: its sheet has no reason of its own to move, so
    // before this it sat at full height while the covers wiggled, taking room the
    // library needed to be rearranged in. One test per tab rather than a loop:
    // edit mode's wiggle repeats forever, so a second `pumpHome` in the same test
    // never settles.
    for (final tab in ['Library', 'Friends', 'Card']) {
      testWidgets(
        'Given the $tab tab, When the library enters edit mode, Then the bar is '
        'hidden and the sheet springs shut',
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
            lessThan(sheetBefore.height),
            reason: 'the sheet should give the library room to edit in',
          );
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

        await tester.tap(find.text('Done'));
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
      'Given the shell, When Add Book is tapped, Then it opens as a modal at 95% '
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
            matching: find.byIcon(Icons.search),
          ),
        );
        await tester.pumpAndSettle();

        final sheet = find.byType(SearchTextField);
        expect(
          sheet,
          findsOneWidget,
          reason: 'the search field should be in it',
        );
        expect(find.text('Add book'), findsOneWidget);

        // 95%, not full screen: the barrier stays visible at the top so it reads
        // as covering the library rather than replacing it. Tight tolerance on
        // purpose — Material's own drag handle silently pushed this to ~98% and a
        // loose bound did not notice.
        final screen = tester.getSize(find.byType(MaterialApp)).height;
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
          closeTo(screen * 0.05, 2),
          reason: 'the sheet should start 5% down, leaving the barrier visible',
        );

        // The library is still there underneath, not popped.
        expect(find.byType(ShelfRow), findsWidgets);
      },
    );
  });
}
