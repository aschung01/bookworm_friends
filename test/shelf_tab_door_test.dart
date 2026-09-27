// The shelf name tab as a door, and the shelf picker it opens.
//
// Before this, `moveBookToShelf` had exactly one caller in the app: a
// long-press-then-drag across `ShelfRow`. That is workable on a twelve-book library
// and not on the 473-book one in production, where the target shelf is usually off
// screen. The tab is the right place for the second door under the rule that retired
// the app bar's pencil — the thing you tap to change a fact is the fact itself.
//
// Three properties are worth holding down, and one of them is invisible except in
// motion:
//
//   1. **The tab is only a door where it can be one.** Your book, a resolved shelf,
//      and somewhere else to go. Each missing condition would otherwise produce a
//      chevron that leads nowhere, and the last one is the easy one to forget: with a
//      single shelf the picker opens on one row that is already ticked.
//   2. **The count gives way to the chevron, but not while the tab is flying.**
//      `ShelfLabel`'s box is squeezed onto its text and Flutter's default flight
//      shuttle is the *destination* hero's child, so a details tab that shows its
//      chevron on the first frame hands the flight a box of the wrong width and the
//      shelf name ellipsizes in mid-air. `ShelfLabelDoor` is the wait for the route to
//      land, and the last group here is where that wait is asserted rather than
//      assumed.
//   3. **The move goes through `moveBookToShelf`**, the same write the drag calls,
//      with the book appended to the target shelf's visible row.
//
// **Everything here exercises the app-drawn popover, and that is not a gap.** On iOS 26
// the tab opens a real `UIMenu` — a chrome-free `CNPopupMenuButton` stacked over the
// Flutter-drawn tab, the same control the settings page's *Edit profile* button is — and
// a `UIMenu` has no Flutter widgets to find, no rows to tap and no barrier to dismiss.
// `flutter test` reports Android, so `useNativeGlass` is false and every case below
// takes the fallback, which is also what runs on every non-iOS-26 device. What the
// native path is asserted on is the one thing it shares with the other: the tab
// underneath, whose width contract the last group holds down.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';

import 'support/book_details_harness.dart';
import 'support/home_page_harness.dart' show FakeLibraryNotifier;

/// Records the move instead of reaching Supabase for it.
///
/// The real `moveBookToShelf` writes two tables and shows its own failure toast, none
/// of which a widget test has a client for — and the thing under test here is *what*
/// this page asks for, not what the provider does with it.
class RecordingLibraryNotifier extends FakeLibraryNotifier {
  RecordingLibraryNotifier(super.shelves);

  final List<({String bookId, String shelfId, List<String> ordered})> moves =
      [];

  @override
  Future<void> moveBookToShelf(
    String bookId,
    String targetShelfId,
    List<String> orderedBookIds,
  ) async {
    moves.add((
      bookId: bookId,
      shelfId: targetShelfId,
      ordered: orderedBookIds,
    ));
  }
}

/// A book standing on some other shelf, to give the target a row to be appended to.
Book shelvedBook(String id, String onShelf, {int status = 0}) => Book(
  id: id,
  userId: meId,
  shelfId: onShelf,
  isbn: id,
  title: id,
  thumbnail: '',
  status: status,
  position: 0,
  createdAt: DateTime(2023),
);

Finder _chevronInTab() => find.descendant(
  of: find.byType(ShelfLabel),
  matching: find.byIcon(Icons.chevron_right),
);

Finder _textInTab(String text) =>
    find.descendant(of: find.byType(ShelfLabel), matching: find.text(text));

void main() {
  group('when the tab is a door', () {
    testWidgets(
      'Given a second shelf, Then the tab trades its count for a chevron',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: interestedBook(ownerId: meId),
          signedInAs: meId,
          otherShelves: [otherShelf(ownerId: meId)],
        );

        expect(find.text(shelfName), findsOneWidget);
        expect(_chevronInTab(), findsOneWidget);
        // The count is gone from the tab, and is not lost — the picker prints one per
        // shelf, where several side by side is a comparison rather than a lone number.
        expect(_textInTab('0'), findsNothing);
      },
    );

    testWidgets(
      'Given one shelf, Then the tab keeps its count and does nothing',
      (tester) async {
        // The state every other case in this suite runs in, which is why adding the
        // door changed none of them.
        await pumpBookDetails(
          tester,
          book: interestedBook(ownerId: meId),
          signedInAs: meId,
        );

        expect(_chevronInTab(), findsNothing);
        expect(find.byType(ShelfLabelDoor), findsNothing);
      },
    );

    testWidgets("Given a friend's book, Then the tab is not a door", (
      tester,
    ) async {
      // Their shelves are not ours to file a book into, however many they have.
      await pumpBookDetails(
        tester,
        book: interestedBook(ownerId: friendId),
        signedInAs: meId,
        otherShelves: [otherShelf(ownerId: friendId)],
      );

      expect(_chevronInTab(), findsNothing);
      expect(find.byType(ShelfLabelDoor), findsNothing);
    });
  });

  group('the picker', () {
    testWidgets('lists every shelf with its count and checks the current one', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: interestedBook(ownerId: meId),
        signedInAs: meId,
        otherShelves: [
          otherShelf(
            ownerId: meId,
            books: [
              shelvedBook('keep-1', 's2'),
              // Finished, so it is drawn in the read pile rather than on the plank.
              // `shelvedBookCount` excludes it, and the picker has to agree with the
              // tab that opened it about what a shelf holds.
              shelvedBook('done-1', 's2', status: 2),
            ],
          ),
        ],
      );

      await tester.tap(find.byType(ShelfLabel));
      await tester.pumpAndSettle();

      expect(find.text('Move to shelf'), findsOneWidget);
      expect(find.text('Essays'), findsOneWidget);
      // Two books on Essays, one of them finished, so the count reads 1.
      expect(find.text('1'), findsOneWidget);
      // And exactly one row is ticked: the one the book is on.
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('dismissing it moves nothing', (tester) async {
      late RecordingLibraryNotifier notifier;
      await pumpBookDetails(
        tester,
        book: interestedBook(ownerId: meId),
        signedInAs: meId,
        otherShelves: [otherShelf(ownerId: meId)],
        libraryNotifier: (shelves) =>
            notifier = RecordingLibraryNotifier(shelves),
      );

      await tester.tap(find.byType(ShelfLabel));
      await tester.pumpAndSettle();
      expect(find.text('Move to shelf'), findsOneWidget);

      // The barrier. A popover anchored to the thing that opened it has to dismiss on
      // one, because there is no Cancel button to reach for — which is the half of
      // being a `PopupRoute` that is not about the halo counter.
      await tester.tapAt(const Offset(20, 800));
      await tester.pumpAndSettle();

      expect(find.text('Move to shelf'), findsNothing);
      expect(notifier.moves, isEmpty);
    });

    testWidgets('choosing the shelf it is already on moves nothing either', (
      tester,
    ) async {
      late RecordingLibraryNotifier notifier;
      await pumpBookDetails(
        tester,
        book: interestedBook(ownerId: meId),
        signedInAs: meId,
        otherShelves: [otherShelf(ownerId: meId)],
        libraryNotifier: (shelves) =>
            notifier = RecordingLibraryNotifier(shelves),
      );

      await tester.tap(find.byType(ShelfLabel));
      await tester.pumpAndSettle();
      // The ticked row is a legal choice — a menu that refuses the row it has ticked
      // reads as broken — it simply has nothing to do. `.last` because the tab behind
      // the popover carries the same name.
      await tester.tap(find.text(shelfName).last);
      await tester.pumpAndSettle();

      expect(find.text('Move to shelf'), findsNothing);
      expect(notifier.moves, isEmpty);
    });

    testWidgets('choosing another shelf appends the book to its row', (
      tester,
    ) async {
      late RecordingLibraryNotifier notifier;
      await pumpBookDetails(
        tester,
        book: interestedBook(ownerId: meId),
        signedInAs: meId,
        otherShelves: [
          otherShelf(
            ownerId: meId,
            books: [
              shelvedBook('keep-1', 's2'),
              // Hidden from the plank, so it is left out of the order this page sends
              // — `moveBookToShelf`'s own contract is that whatever it leaves out
              // keeps its stored position.
              shelvedBook('done-1', 's2', status: 2),
              shelvedBook('keep-2', 's2'),
            ],
          ),
        ],
        libraryNotifier: (shelves) =>
            notifier = RecordingLibraryNotifier(shelves),
      );

      await tester.tap(find.byType(ShelfLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Essays'));
      await tester.pumpAndSettle();

      expect(notifier.moves, hasLength(1));
      final move = notifier.moves.single;
      expect(move.bookId, 'b1');
      expect(move.shelfId, 's2');
      // Appended, which is where a drag released past the last cover would have put
      // it, and with the finished book left out.
      expect(move.ordered, ['keep-1', 'keep-2', 'b1']);
    });

    testWidgets('Given more shelves than fit, Then the card is capped and scrolls', (
      tester,
    ) async {
      // Not hypothetical: the library that prompted this feature has ten shelves,
      // which is 472pt of card at 44pt a row. Twenty asks for 912 on an 874pt screen,
      // and without a cap every row past the fold is simply unreachable.
      await pumpBookDetails(
        tester,
        book: interestedBook(ownerId: meId),
        signedInAs: meId,
        otherShelves: [
          for (var i = 0; i < 24; i++)
            otherShelf(ownerId: meId, id: 's$i', name: 'Shelf $i'),
        ],
      );

      await tester.tap(find.byType(ShelfLabel));
      await tester.pumpAndSettle();

      // Exactly one list on screen: the picker's. Inside the screen, rather than
      // 1100pt of card hanging off the bottom of it.
      expect(
        tester.getSize(find.byType(ListView)).height,
        lessThan(
          tester.view.physicalSize.height / tester.view.devicePixelRatio,
        ),
      );

      // And the rows past the fold are reachable, which is the half a cap alone does
      // not buy.
      expect(find.text('Shelf 23'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Shelf 23'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // The hero width contract.
  //
  // Asserted on `ShelfLabelDoor` directly rather than through the details page,
  // because the property is about a route *arriving* and `pumpBookDetails` settles —
  // which is the landed state, the one frame this cannot be checked in.

  group('the hero width contract', () {
    // Two shelves, so the door has somewhere to point. Neither menu is opened here:
    // these cases are about what the tab draws while it is in the air.
    final shelves = [
      otherShelf(ownerId: meId, id: shelfId, name: 'Novels'),
      otherShelf(ownerId: meId),
    ];

    Widget door() => ShelfLabelDoor(
      label: 'Novels',
      count: 2,
      shelves: shelves,
      currentShelfId: shelfId,
      onPicked: (_) {},
    );

    testWidgets(
      'Given a route still arriving, Then the tab shows its count and not the chevron',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(body: door()),
                      ),
                    ),
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('go'));
        // Part-way in. Long enough for the tab to be built and laid out, short of the
        // ~300ms the page transition takes.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));

        expect(_chevronInTab(), findsNothing);
        expect(_textInTab('2'), findsOneWidget);

        await tester.pumpAndSettle();

        // Landed. Now, and only now, the chevron.
        expect(_chevronInTab(), findsOneWidget);
        expect(_textInTab('2'), findsNothing);

        // And leaving takes it away again, because the same gate holds the platform
        // view back: a `UiKitView` must not be inside a hero that is flying home.
        // The status listener is what makes this true on the *first* frame of the pop
        // rather than the second.
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        navigator.pop();
        await tester.pump();

        expect(_chevronInTab(), findsNothing);

        await tester.pumpAndSettle();
      },
    );

    testWidgets('Given a settled route, Then the chevron arrives a frame later', (
      tester,
    ) async {
      // The other side of the deferral. `pumpWidget` runs one frame, and the
      // post-frame callback that reads the route's real status fires at the end of it
      // — so the swap lands on the next. One frame of count on a page that is not
      // moving is invisible; a chevron on the frame a hero flight measures from is not.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: door()),
        ),
      );

      expect(_chevronInTab(), findsNothing);

      await tester.pumpAndSettle();

      expect(_chevronInTab(), findsOneWidget);
      expect(_textInTab('2'), findsNothing);
    });
  });
}
