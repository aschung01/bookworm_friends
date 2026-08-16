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

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/finished_books_sheet.dart';
import 'package:bookworm_friends/ui/widgets/friend_rail.dart';
import 'package:bookworm_friends/ui/widgets/friends_sheet.dart';
import 'package:bookworm_friends/ui/widgets/library_card_sheet.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';
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
    finishedBooksProvider.overrideWith((ref, filter) async => _readBooks()),
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
      'Given the Friends sheet, When a friend is tapped, Then the shell moves to '
      'that friend',
      (tester) async {
        await _pumpShell(tester);
        await _selectTab(tester, 'Friends');

        Profile? selected() =>
            tester.widget<FriendRail>(find.byType(FriendRail)).selectedFriend;

        expect(selected(), isNull, reason: 'starts in your own library');

        await tester.tap(find.text('jisoo'));
        await tester.pumpAndSettle();

        expect(selected()?.username, 'jisoo');
        // The row is gone with it: the Everyone list belongs to your own page,
        // and tapping it pages to hers. Task 5 makes that a visit and hides the
        // bar; today it is the existing pager behaviour, reached from the sheet.
        expect(find.byType(FriendsSheet), findsNothing);
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
  });
}
