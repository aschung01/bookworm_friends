// Whose library is on screen, how you change it, and what may not change it.
//
// This file is the regression guard for a deletion. The shell used to hold a
// horizontal `PageView` — your library at index 0, each followed friend at an index
// after it — with a `FriendRail` of avatars above it as the map. Two reported
// defects came out of that arrangement rather than out of any bug in it:
//
//   1. A sideways drag on your own library opened somebody else's. The pager's
//      `physics` were gated on the edit mode alone, and `shouldAcceptUserOffset` is
//      `pixels != 0 || min != max` — so a shelf whose books fit, a read pile that
//      does not overflow, and the whole Card tab all *declined* the drag and handed
//      it down to the pager.
//   2. Tapping the fourth friend in the list animated through the two in between,
//      building and dropping each one's `userLibraryProvider` and
//      `userFinishedBooksProvider` on the way: 2(k−1) queries thrown away to show
//      one reader.
//
// Both are gone because the axis is gone. What replaced them is one rule, and most
// of the tests below are that rule stated as behaviour: **all three tabs always mean
// yours, and everything about a friend lives one level down the Friends tab.**

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/friends_sheet.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/loading_blocks.dart';
import 'package:bookworm_friends/ui/widgets/read_filter.dart';
import 'package:bookworm_friends/ui/widgets/shelf_row.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:bookworm_friends/ui/widgets/shell_tab_bar.dart';

import 'support/home_page_harness.dart';

Profile _friend(String id, String name) => Profile(
  id: id,
  username: name,
  emoji: '🦊',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

/// A shelf named after its owner, so which library is on screen can be read off
/// the shelves rather than inferred from the chrome.
List<Shelf> _shelfFor(String owner) => [
  testShelf(owner, [testBook('$owner-b1', owner, title: 'Ficciones')]),
];

/// Enough books on one shelf that the row cannot fit them, which is the case that
/// has to keep scrolling horizontally after the pager's deletion.
List<Shelf> _overflowingShelf() => [
  testShelf('wide', [
    for (var i = 0; i < 12; i++) testBook('b$i', 'wide', position: i),
  ]),
];

List<Book> _readBooks() => [
  testBook(
    'r1',
    's1',
    title: 'Dune',
    status: bookStatusFinished,
    finishDate: DateTime(DateTime.now().year, 3, 4),
  ),
  testBook(
    'r2',
    's1',
    title: 'Circe',
    status: bookStatusFinished,
    finishDate: DateTime(DateTime.now().year - 1, 11, 2),
  ),
];

/// A library that fails the first read and succeeds after it.
///
/// The counter is a list held by the *test* rather than a field, because
/// `ref.invalidate` builds a new notifier from the override's factory — a field
/// would reset with it, and the retry would fail forever.
class _FlakyLibraryNotifier extends LibraryNotifier {
  _FlakyLibraryNotifier(this.attempts, this.shelves);

  final List<int> attempts;
  final List<Shelf> shelves;

  @override
  Future<List<Shelf>> build() async {
    attempts.add(1);
    if (attempts.length == 1) throw Exception('offline');
    return shelves;
  }
}

/// The shell with two friends, each with a library of their own.
///
/// [friendShelves] and [friendReads] replace what *every* friend has, which is how
/// the empty-library case is set up. Pass [pendingFriend] with [pendingId] to hold
/// one friend's library in flight, which is how the switch's in-flight state is
/// exercised.
Future<void> _pumpShell(
  WidgetTester tester, {
  List<Shelf>? shelves,
  List<Book>? ownReads,
  Future<List<Book>>? pendingOwnReads,
  List<Shelf>? friendShelves,
  List<Book>? friendReads,
  Future<List<Shelf>>? pendingFriend,
  String? pendingId,
  List<Override> extra = const [],
  bool settle = true,
}) => pumpHome(
  tester,
  shelves: shelves,
  settle: settle,
  extraOverrides: [
    finishedBooksProvider.overrideWith(
      (ref) => pendingOwnReads ?? Future.value(ownReads ?? _readBooks()),
    ),
    friendsProvider.overrideWith(
      (ref) async => [_friend('f1', 'jisoo'), _friend('f2', 'minho')],
    ),
    userLibraryProvider.overrideWith((ref, id) {
      if (pendingFriend != null && id == pendingId) return pendingFriend;
      return Future.value(friendShelves ?? _shelfFor(id));
    }),
    userFinishedBooksProvider.overrideWith(
      (ref, id) async => friendReads ?? _readBooks(),
    ),
    ...extra,
  ],
);

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(ShellTabBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('no gesture changes whose library you are looking at', () {
    testWidgets(
      'Given your own library on the Library tab, When the shelves are dragged '
      'sideways, Then no visit begins and the library is untouched',
      (tester) async {
        await _pumpShell(tester);
        final container = shellContainer(tester);
        final shelfBefore = tester.state(find.byType(ShelfRow).first);

        // The exact gesture defect 1 was reported for: a horizontal drag starting on
        // a shelf row whose books fit, which used to be handed to the pager.
        await tester.drag(find.byType(ShelfRow).first, const Offset(-320, 0));
        await tester.pumpAndSettle();

        expect(
          container.read(selectedFriendProvider),
          isNull,
          reason: 'a sideways drag is not a request to go anywhere',
        );
        expect(
          tester.state(find.byType(ShelfRow).first),
          same(shelfBefore),
          reason:
              'and the library behind the sheet is the same element, not a '
              'rebuilt one',
        );
        expect(find.text('My Library'), findsOneWidget);
      },
    );

    testWidgets(
      'Given the Card tab, When it is dragged sideways, Then nothing happens',
      (tester) async {
        // The Card was the worst of the three leaks: the whole tab is a sheet with no
        // horizontal scrollable in it, so every horizontal drag anywhere on it
        // reached the pager.
        await _pumpShell(tester);
        await _selectTab(tester, 'Card');

        await tester.drag(find.text('Library Card'), const Offset(-320, 0));
        await tester.pumpAndSettle();

        expect(shellContainer(tester).read(selectedFriendProvider), isNull);
        expect(find.text('Library Card'), findsOneWidget);
      },
    );

    testWidgets(
      'Given a shelf whose books overflow the row, When it is dragged sideways, '
      'Then it still scrolls',
      (tester) async {
        // The other half of the deletion: horizontal drags must not become dead in
        // general. This row declined nothing before and must keep accepting.
        await _pumpShell(tester, shelves: _overflowingShelf());
        final firstBook = find.byType(BookWidget).first;
        final before = tester.getRect(firstBook).left;

        await tester.drag(firstBook, const Offset(-60, 0));
        await tester.pumpAndSettle();

        expect(
          tester.getRect(find.byType(BookWidget).first).left,
          lessThan(before - 30),
          reason: 'an overflowing shelf owns its own horizontal axis',
        );
        expect(shellContainer(tester).read(selectedFriendProvider), isNull);
      },
    );
  });

  group('the invariant: a visit is a state of the Friends tab', () {
    testWidgets(
      'Given a friend is selected, Then the Friends tab is the selected tab',
      (tester) async {
        await _pumpShell(tester);
        await enterVisit(tester, 'jisoo');
        final container = shellContainer(tester);

        expect(container.read(selectedFriendProvider), isNotNull);
        expect(
          container.read(libraryTabProvider),
          LibraryTab.friends,
          reason:
              'selectedFriend != null implies the Friends tab — the whole '
              'navigation design in one line',
        );
        expect(
          container.read(friendsSheetLevelProvider),
          FriendsSheetLevel.friend,
        );
      },
    );

    for (final tab in ['Library', 'Card']) {
      testWidgets(
        'Given a visit, When the $tab tab is selected, Then the visit ends',
        (tester) async {
          await _pumpShell(tester);
          await enterVisit(tester, 'jisoo');
          // The bar's title is a `Text.rich`, and `find.text` matches its plain text.
          expect(find.text('jisoo\'s Library'), findsOneWidget);

          await _selectTab(tester, tab);

          final container = shellContainer(tester);
          expect(
            container.read(selectedFriendProvider),
            isNull,
            reason:
                '$tab is about you, and the only reading of that which is not a '
                'lie is that the visit is over',
          );
          expect(
            container.read(friendsSheetLevelProvider),
            FriendsSheetLevel.list,
          );
          expect(find.text('My Library'), findsOneWidget);
          expect(
            find.text('Ficciones'),
            findsNothing,
            reason: 'her shelves went with her',
          );
        },
      );
    }
  });

  group('switching friends', () {
    testWidgets(
      'Given a visit, When the list is reopened and another friend tapped, Then '
      'her library replaces the first one',
      (tester) async {
        await _pumpShell(tester);
        await enterVisit(tester, 'jisoo');
        expect(find.text('f1'), findsOneWidget, reason: "jisoo's shelf");

        await backToFriendsList(tester);
        await tester.tap(find.text('minho'));
        await tester.pumpAndSettle();

        expect(find.text('f2'), findsOneWidget, reason: "minho's shelf");
        expect(find.text('f1'), findsNothing);
        expect(
          shellContainer(tester).read(selectedFriendProvider)?.username,
          'minho',
        );
      },
    );

    testWidgets(
      'Given the incoming library is still loading, When a friend is tapped, Then '
      'the outgoing shelves are held rather than blanked',
      (tester) async {
        // What `_FriendLibraryPage` used to do here was
        // `.when(loading: CircularProgressIndicator.adaptive())`, which wiped the
        // pane — and with the sheet as the switcher that blank is the *primary*
        // experience rather than an edge case, which is why the held pane and the
        // provider cache landed with the deletion rather than after it.
        final pending = Completer<List<Shelf>>();
        await _pumpShell(
          tester,
          pendingFriend: pending.future,
          pendingId: 'f2',
        );

        await enterVisit(tester, 'jisoo');
        await backToFriendsList(tester);
        await tester.tap(find.text('minho'));
        await tester.pumpAndSettle();

        expect(
          find.byType(LoadingLibrary),
          findsNothing,
          reason: 'a switch must not blank the library it is switching from',
        );
        expect(
          find.text('f1'),
          findsOneWidget,
          reason: "jisoo's shelves stay until minho's arrive",
        );
        expect(
          find.text('loading minho…'),
          findsOneWidget,
          reason:
              'and the one thing worth saying is whose library is arriving, '
              'which a spinner cannot',
        );

        pending.complete(_shelfFor('f2'));
        await tester.pumpAndSettle();

        expect(find.text('f2'), findsOneWidget);
        expect(find.text('loading minho…'), findsNothing);
      },
    );
  });

  group("the Friends sheet's second level", () {
    testWidgets(
      'Given a friend is tapped, Then the sheet shows her reads and looks exactly '
      'like your own read view',
      (tester) async {
        await _pumpShell(tester);
        await enterVisit(tester, 'jisoo');

        expect(find.byType(FriendsSheet), findsNothing);
        expect(find.text('Books read'), findsOneWidget);
        // Nothing was added to this header. An earlier round put a `‹ Friends`
        // control in the leading slot, which cost the year popover its place (three
        // controls in a 375pt row is what overflows at 2× text) and made her read
        // view a different shape from yours. The Friends tab is the way back up
        // instead, so the header is the read view's own, unchanged.
        //
        // By type rather than by label: collapsed, the control shows the year that is
        // *selected*, so asserting on "All time" would be asserting about the filter's
        // default instead of about the header's composition.
        expect(
          find.byType(ReadFilter),
          findsOneWidget,
          reason: 'the collapsed year popover is hers to use, as it is yours',
        );
      },
    );

    testWidgets(
      'Given her read books expanded, When the Friends tab is tapped, Then the '
      'list comes back over her library',
      (tester) async {
        // The level change has to work from any detent, since the sheet is where the
        // reader was last dragging.
        await _pumpShell(tester);
        await enterVisit(tester, 'jisoo');
        await tester.tap(find.byType(SheetGrabHandle));
        await tester.pumpAndSettle();

        await backToFriendsList(tester);

        expect(find.byType(FriendsSheet), findsOneWidget);
        expect(
          shellContainer(tester).read(selectedFriendProvider)?.username,
          'jisoo',
        );
        expect(
          find.text('f1'),
          findsOneWidget,
          reason: 'her shelves are still the background',
        );
      },
    );

    testWidgets(
      'Given a friend who has finished nothing this year, When her library is '
      'visited, Then her read view opens on all time rather than on an empty year',
      (tester) async {
        // The defect: both year providers defaulted to the current year, which is a
        // good guess about *your* library and a bad one about hers. A reader whose
        // last finish was last year had her entire library hidden behind a default
        // nobody chose — the visit opened on `Books read 0` over the empty-year
        // message, with the rail the only way to find out she had read anything at
        // all. See `friendReadsFilterYearProvider`.
        final thisYear = DateTime.now().year;
        await _pumpShell(
          tester,
          friendReads: [
            testBook(
              'h1',
              's1',
              title: 'Kindred',
              status: bookStatusFinished,
              finishDate: DateTime(thisYear - 1, 5, 6),
            ),
            testBook(
              'h2',
              's1',
              title: 'Beloved',
              status: bookStatusFinished,
              finishDate: DateTime(thisYear - 2, 8, 9),
            ),
          ],
        );
        final container = shellContainer(tester);

        await enterVisit(tester, 'jisoo');

        expect(container.read(friendReadsFilterYearProvider), 0);
        expect(
          tester.widget<ReadFilter>(find.byType(ReadFilter)).selected,
          0,
          reason: 'and the header says so, so all time is a state she can see',
        );
        expect(
          find.text('No books recorded for $thisYear'),
          findsNothing,
          reason: 'her books are what a visit opens on, not a year she skipped',
        );
        expect(
          container.read(readsFilterYearProvider),
          thisYear,
          reason:
              'yours is the library you have been adding to, so it is unchanged',
        );
      },
    );

    testWidgets(
      'Given the read filters, When switching between your library and a '
      "friend's, Then the two years are separate and every friend shares one",
      (tester) async {
        // Pinned deliberately rather than left to be rediscovered as a bug. Your
        // year and the friend year are different providers, which is right — but the
        // *friend* year is shared by every friend, so it follows you from jisoo to
        // minho. That is easier to notice now that a switch is a tap in a list, and
        // it is a decision, not an accident. See `friendReadsFilterYearProvider`.
        await _pumpShell(tester);
        final container = shellContainer(tester);
        final thisYear = DateTime.now().year;

        await enterVisit(tester, 'jisoo');
        container.read(friendReadsFilterYearProvider.notifier).state =
            thisYear - 1;

        await backToFriendsList(tester);
        await tester.tap(find.text('minho'));
        await tester.pumpAndSettle();

        expect(
          container.read(friendReadsFilterYearProvider),
          thisYear - 1,
          reason: 'one year for every friend, so it carries across a switch',
        );
        expect(
          container.read(readsFilterYearProvider),
          thisYear,
          reason: 'and yours is untouched by any of it',
        );
      },
    );
  });

  group('an empty library still has a sheet', () {
    // The sheet is the shell's one switcher, so "no books" must not mean "no
    // switcher". `LibraryPane` used to `return` its empty state before the `Stack`
    // that floats the sheet, which cost nothing while a visit hid the tab bar and
    // broke outright once the bar stayed: visiting a reader with empty shelves left
    // the Friends tab with nothing to open, so the bar looked dead.
    testWidgets(
      'Given a friend whose library is empty, When it is visited, Then her read '
      'sheet is still on screen over the empty state',
      (tester) async {
        await _pumpShell(
          tester,
          friendShelves: const [],
          friendReads: const [],
        );
        await enterVisit(tester, 'jisoo');

        expect(find.text('This library is empty'), findsOneWidget);
        expect(
          find.byType(LibrarySheet),
          findsOneWidget,
          reason: 'an empty library is a library with a sheet over it',
        );
        expect(find.text('Books read'), findsOneWidget);
      },
    );

    testWidgets(
      'Given an empty friend\'s library, When the Friends tab is tapped, Then the '
      'list opens over it and the visit survives',
      (tester) async {
        await _pumpShell(
          tester,
          friendShelves: const [],
          friendReads: const [],
        );
        await enterVisit(tester, 'jisoo');

        await backToFriendsList(tester);

        expect(find.byType(FriendsSheet), findsOneWidget);
        expect(find.text('minho'), findsOneWidget);
        expect(
          shellContainer(tester).read(selectedFriendProvider)?.username,
          'jisoo',
        );
        expect(
          find.text('This library is empty'),
          findsOneWidget,
          reason: 'her empty library is still the background',
        );
      },
    );

    testWidgets(
      'Given your own library is empty, When the shell opens, Then the read sheet '
      'and the add-a-book invitation are both there',
      (tester) async {
        await _pumpShell(
          tester,
          shelves: const [],
          ownReads: const [],
          friendShelves: const [],
          friendReads: const [],
        );

        // Your own empty state keeps its invitation, and the sheet no longer
        // suppresses it — the art is centred in the band above the collapsed card
        // rather than in the whole pane.
        expect(find.text('Your library is empty...'), findsOneWidget);
        expect(find.textContaining('to add a book'), findsOneWidget);
        expect(find.byType(LibrarySheet), findsOneWidget);
        expect(
          tester.getRect(find.byType(SadCharacter)).bottom,
          lessThanOrEqualTo(tester.getRect(find.byType(LibrarySheet)).top),
          reason:
              'the empty state has to sit clear of the sheet floating over it, '
              'which is what centring it in the whole pane would not do',
        );
      },
    );
  });

  group('every state carries the sheet', () {
    // The generalisation of the empty-library bug. `LibraryPane` was the only thing
    // that built a sheet, so every state that rendered something *else* — empty,
    // loading, failed — left the tab bar with nothing to switch. `LibraryPaneFrame`
    // is what makes "library content, sheet over it" one arrangement instead of a
    // habit, and these are the two states that had no test at all.
    testWidgets(
      'Given the library has not loaded yet, When the skeleton is on screen, Then '
      'the sheet is too and the tabs still work',
      (tester) async {
        final reads = Completer<List<Book>>();
        // Held on the *reads*, because the pane waits for shelves and reads as a
        // pair — see `_HomePageState._onScreen`.
        await _pumpShell(
          tester,
          pendingOwnReads: reads.future,
          // `LoadingLibrary` shimmers forever, so this must not settle.
          settle: false,
        );

        expect(find.byType(LoadingLibrary), findsOneWidget);
        expect(
          find.byType(LibrarySheet),
          findsOneWidget,
          reason: 'the chrome does not wait for the library',
        );
        expect(
          tester.getRect(find.byType(LoadingLibrary)).top,
          greaterThan(0),
          reason:
              'and the skeleton is below the bar rather than painted over the '
              'title, which is what an unpositioned loading state did',
        );

        await tester.tap(
          find.descendant(
            of: find.byType(ShellTabBar),
            matching: find.text('Friends'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.byType(FriendsSheet),
          findsOneWidget,
          reason: 'a tab tap during a cold start must not be a no-op',
        );

        reads.complete(const []);
        await tester.pumpAndSettle();
        expect(find.byType(LoadingLibrary), findsNothing);
      },
    );

    testWidgets(
      'Given the library query fails, When the error is shown, Then the sheet is '
      'there and Retry re-reads it',
      (tester) async {
        final attempts = <int>[];
        await _pumpShell(
          tester,
          extra: [
            libraryProvider.overrideWith(
              () => _FlakyLibraryNotifier(attempts, _shelfFor('mine')),
            ),
          ],
        );

        expect(attempts, hasLength(1));
        expect(find.textContaining('offline'), findsOneWidget);
        expect(
          find.byType(LibrarySheet),
          findsOneWidget,
          reason:
              'an error used to take the sheet with it, leaving a live tab bar '
              'that did nothing and no way to try again',
        );

        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();

        expect(
          attempts,
          hasLength(2),
          reason: 'Retry goes through the same path as the pull-to-refresh',
        );
        expect(find.textContaining('offline'), findsNothing);
        expect(find.text('mine'), findsOneWidget, reason: 'the shelf, at last');
      },
    );
  });

  group('a friend cannot be edited', () {
    testWidgets(
      'Given a visit, When a cover is long-pressed, Then edit mode does not open',
      (tester) async {
        await _pumpShell(tester);
        await enterVisit(tester, 'jisoo');

        await enterEditMode(tester);

        expect(
          isEditing(),
          isFalse,
          reason:
              'the pane draws her shelves now, and a long press on them must '
              'stay inert — it used to be a different widget that ignored it',
        );
      },
    );
  });
}
