// Widget tests for the "Manage shelves" sheet.
//
// The sheet replaces the old `LibraryMode.editShelf` page-level mode: it is
// presented *over* the library's edit mode, reorders/renames/deletes persist
// immediately, and dismissing it returns the user where they were.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/manage_shelves_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';

/// Counts the overlapping cover previews a row drew. At preview size a cover is a
/// colour block with no text, so the keys are the only handle on it.
Finder _coverFinder() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith(kShelfCoverKeyPrefix);
});

/// Stands in for the Supabase-backed notifier: serves a fixture and records the
/// reorder calls the sheet makes.
class FakeLibraryNotifier extends LibraryNotifier {
  FakeLibraryNotifier(this.shelves);

  final List<Shelf> shelves;
  final List<List<String>> reorderCalls = [];

  @override
  Future<List<Shelf>> build() async => shelves;

  @override
  Future<void> reorderShelves(List<String> shelfIds) async {
    reorderCalls.add(shelfIds);
    final byId = {for (final s in shelves) s.id: s};
    state = AsyncData([for (final id in shelfIds) byId[id]!]);
  }
}

/// Records shelf mutations instead of hitting Supabase / EasyLoading.
class FakeLibraryActions extends LibraryActions {
  FakeLibraryActions(super.ref);

  @override
  Future<void> deleteShelf(String shelfId) async => deletedShelves.add(shelfId);

  @override
  Future<void> updateShelfName(String shelfId, String newName) async =>
      renamedShelves.add((shelfId, newName));
}

// Recorded outside the fake because Riverpod creates it lazily, on first read.
final deletedShelves = <String>[];
final renamedShelves = <(String, String)>[];

Shelf _shelf(String id, String name, int bookCount, {int status = 0}) => Shelf(
  id: id,
  userId: 'u',
  name: name,
  position: 0,
  createdAt: DateTime(2024),
  books: List.generate(
    bookCount,
    (i) => Book(
      id: '$id-$i',
      userId: 'u',
      shelfId: id,
      isbn: '$i',
      title: 'B$i',
      thumbnail: '',
      status: status,
      position: i,
      createdAt: DateTime(2024),
    ),
  ),
);

late FakeLibraryNotifier notifier;

/// Pumps a host page whose only job is to open the sheet, mirroring how the
/// library's edit mode presents it.
Future<void> _pumpAndOpenSheet(WidgetTester tester, List<Shelf> shelves) async {
  deletedShelves.clear();
  renamedShelves.clear();
  notifier = FakeLibraryNotifier(shelves);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryProvider.overrideWith(() => notifier),
        libraryActionsProvider.overrideWith(FakeLibraryActions.new),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showManageShelvesBottomSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('Manage shelves sheet', () {
    testWidgets(
      'Given several shelves, When the sheet opens, Then each shelf is listed with its book count and a reorder hint',
      (tester) async {
        await _pumpAndOpenSheet(tester, [
          _shelf('a', 'Dev', 1),
          _shelf('b', 'Self-help', 2),
        ]);

        expect(find.text('Manage shelves'), findsOneWidget);
        expect(find.text('Drag to reorder'), findsOneWidget);
        expect(find.text('Dev'), findsOneWidget);
        expect(find.text('Self-help'), findsOneWidget);
        expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
        expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));
        expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
      },
    );

    testWidgets(
      'Given a single shelf, When the sheet opens, Then no grip or reorder hint is shown',
      (tester) async {
        await _pumpAndOpenSheet(tester, [_shelf('a', 'Dev', 1)]);

        expect(find.text('Dev'), findsOneWidget);
        expect(find.text('Drag to reorder'), findsNothing);
        expect(find.byIcon(Icons.drag_handle), findsNothing);
      },
    );

    testWidgets(
      'Given two shelves, When the second is dragged above the first by its grip, Then the new order is persisted',
      (tester) async {
        await _pumpAndOpenSheet(tester, [
          _shelf('a', 'Dev', 1),
          _shelf('b', 'Self-help', 2),
        ]);

        // Measured rather than hard-coded. This drag was two nudges totalling 70pt,
        // which silently stopped reordering the day the rows grew from 48pt to 66pt
        // to make room for the covers — a test failure that said nothing about the
        // widget under test. A drag expressed in rows cannot rot that way.
        final rowHeight = tester
            .getSize(find.byKey(const ValueKey('a')))
            .height;

        final grip = find.byIcon(Icons.drag_handle).at(1);
        final gesture = await tester.startGesture(tester.getCenter(grip));
        // The grip uses an immediate drag listener, so a nudge starts the drag.
        // Frames need a non-zero duration or the list never processes the move.
        await tester.pump(const Duration(milliseconds: 20));
        for (var i = 0; i < 3; i++) {
          await gesture.moveBy(Offset(0, -rowHeight / 2));
          await tester.pump(const Duration(milliseconds: 20));
        }
        await gesture.up();
        await tester.pumpAndSettle();

        expect(notifier.reorderCalls, [
          ['b', 'a'],
        ]);
      },
    );

    testWidgets(
      'Given a shelf row, When its delete button is tapped, Then a confirmation is required before deleting',
      (tester) async {
        await _pumpAndOpenSheet(tester, [
          _shelf('a', 'Dev', 1),
          _shelf('b', 'Self-help', 2),
        ]);

        await tester.tap(find.byIcon(Icons.delete_outline).first);
        await tester.pumpAndSettle();

        // Nothing deleted yet — the confirmation sheet is on top.
        expect(deletedShelves, isEmpty);
        expect(find.text('Delete'), findsWidgets);
        final deleteButton = tester.widget<ElevatedActionButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is ElevatedActionButton && widget.buttonText == 'Delete',
          ),
        );
        expect(deleteButton.isDestructive, isTrue);

        await tester.tap(find.text('Delete').last);
        await tester.pumpAndSettle();

        expect(deletedShelves, ['a']);
      },
    );

    testWidgets(
      'Given a shelf row, When the pencil is tapped, Then the rename sheet opens',
      (tester) async {
        await _pumpAndOpenSheet(tester, [_shelf('a', 'Dev', 1)]);

        await tester.tap(find.byIcon(Icons.edit_outlined));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);
      },
    );

    testWidgets(
      'Given a shelf row, When its name is tapped, Then nothing opens and the name is not wrapped in a press target',
      (tester) async {
        await _pumpAndOpenSheet(tester, [_shelf('a', 'Dev', 1)]);

        // The pencil is the only way to rename, so the name must not be a second
        // one: a tappable name meant a full-width InkWell, and the theme's press
        // tint lit the whole row grey — on a drag as much as on a tap.
        await tester.tap(find.text('Dev'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);

        expect(
          find.ancestor(of: find.text('Dev'), matching: find.byType(InkWell)),
          findsNothing,
        );
      },
    );
    testWidgets(
      'Given the sheet is open, When the close button is tapped, Then the sheet is dismissed',
      (tester) async {
        await _pumpAndOpenSheet(tester, [_shelf('a', 'Dev', 1)]);
        expect(find.text('Manage shelves'), findsOneWidget);

        // A close affordance, not "Done": the sheet commits as you go, so there
        // is nothing to confirm.
        expect(find.text('Done'), findsNothing);
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        expect(find.text('Manage shelves'), findsNothing);
      },
    );

    testWidgets(
      'Given the sheet is open, When the close button is inspected, Then it carries an accessible name and a 44pt target',
      (tester) async {
        await _pumpAndOpenSheet(tester, [_shelf('a', 'Dev', 1)]);

        final closeButton = find.ancestor(
          of: find.byIcon(Icons.close),
          matching: find.byType(AdaptiveIconButton),
        );
        expect(closeButton, findsOneWidget);
        expect(tester.getSize(closeButton), const Size(44, 44));
        // Icon-only, so the label is the only thing a screen reader can read.
        expect(
          tester
              .widget<IconButton>(
                find.descendant(
                  of: closeButton,
                  matching: find.byType(IconButton),
                ),
              )
              .tooltip,
          'Close',
        );
      },
    );

    testWidgets(
      'Given a shelf with more books than fit, When the sheet opens, Then the row previews the first few covers and states the full count',
      (tester) async {
        await _pumpAndOpenSheet(tester, [_shelf('a', 'Dev', 6)]);

        // Capped rather than one per book: the preview is for recognising the
        // shelf, and a fourth cover buys no recognition.
        expect(_coverFinder(), findsNWidgets(3));

        // The cap is only honest because the number is on the row: without it a
        // shelf of six and a shelf of three drew the same stack.
        expect(find.text('6'), findsOneWidget);

        // Overlapping, so the stack is narrower than three covers end to end.
        final coverWidth = tester.getSize(_coverFinder().first).width;
        final stackWidth = tester
            .getSize(
              find
                  .ancestor(
                    of: _coverFinder().first,
                    matching: find.byType(SizedBox),
                  )
                  .first,
            )
            .width;
        expect(stackWidth, lessThan(coverWidth * 3));

        // The leftmost cover is the unobstructed one, so it must paint last.
        final covers = tester.widgetList(_coverFinder()).toList();
        expect(
          (covers.last.key! as ValueKey<String>).value,
          '${kShelfCoverKeyPrefix}a-0',
        );
      },
    );

    testWidgets(
      'Given shelves with different book counts, When the sheet opens, Then every cover slot is the same width so the names line up',
      (tester) async {
        await _pumpAndOpenSheet(tester, [
          _shelf('a', 'Dev', 6),
          _shelf('b', 'Self-help', 1),
          _shelf('c', 'Empty', 0),
        ]);

        // The defect this replaces: the stack sized to its contents, so a
        // one-book shelf's cover sat marooned and no two rows agreed on where the
        // name began.
        final lefts = <double>{
          for (final name in ['Dev', 'Self-help', 'Empty'])
            tester.getTopLeft(find.text(name)).dx,
        };
        expect(lefts, hasLength(1));
      },
    );

    testWidgets(
      'Given an empty shelf, When the sheet opens, Then the row draws a placeholder instead of covers',
      (tester) async {
        await _pumpAndOpenSheet(tester, [_shelf('a', 'Dev', 0)]);

        expect(find.text('Dev'), findsOneWidget);
        expect(_coverFinder(), findsNothing);
        // Blank space read as a rendering fault, so the slot is outlined.
        expect(find.byKey(kShelfCoverEmptyKey), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
      },
    );

    testWidgets(
      'Given a shelf whose books are all read, When the sheet opens, Then neither its covers nor its count include them',
      (tester) async {
        // Read books are drawn in the library's pile rather than on the plank, so a
        // sheet built from the raw list advertised covers that were not on the
        // shelf — three of them, under a plank showing none.
        await _pumpAndOpenSheet(tester, [
          _shelf('a', 'Dev', 4, status: bookStatusFinished),
        ]);

        expect(_coverFinder(), findsNothing);
        expect(find.byKey(kShelfCoverEmptyKey), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
        expect(find.text('4'), findsNothing);
      },
    );

    testWidgets(
      'Given a shelf row, When its actions are inspected, Then the bin is not drawn in alarm red',
      (tester) async {
        await _pumpAndOpenSheet(tester, [_shelf('a', 'Dev', 1)]);

        // Eleven red bins outranked the shelf names they act on. The red belongs to
        // the confirmation, which is where the decision is taken.
        final bin = tester.widget<Icon>(find.byIcon(Icons.delete_outline));
        expect(bin.color, isNot(softRedColor));
        final pencil = tester.widget<Icon>(find.byIcon(Icons.edit_outlined));
        expect(pencil.color, bin.color);
      },
    );

    testWidgets(
      'Given more shelves than fit on screen, When the sheet opens, Then it may grow to 80% of the screen',
      (tester) async {
        final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
        await _pumpAndOpenSheet(tester, [
          for (var i = 0; i < 20; i++) _shelf('s$i', 'Shelf $i', 3),
        ]);

        final height = tester.getSize(find.byType(BottomSheet)).height;
        expect(height, closeTo(screen.height * 0.8, 0.5));
        // Regression guard for the real defect: without `isScrollControlled`,
        // `showModalBottomSheet` holds the sheet at 9/16 of the screen and the
        // cap above is unreachable however large it is set.
        expect(height, greaterThan(screen.height * 9 / 16));
      },
    );
  });
}
