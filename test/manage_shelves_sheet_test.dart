// Widget tests for the "Manage shelves" sheet.
//
// The sheet replaces the old `LibraryMode.editShelf` page-level mode: it is
// presented *over* the library's edit mode, reorders/renames/deletes persist
// immediately, and dismissing it returns the user where they were.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/manage_shelves_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';

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

Shelf _shelf(String id, String name, int bookCount) => Shelf(
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
      status: 0,
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

        final grip = find.byIcon(Icons.drag_handle).at(1);
        final gesture = await tester.startGesture(tester.getCenter(grip));
        // The grip uses an immediate drag listener, so a nudge starts the drag.
        // Frames need a non-zero duration or the list never processes the move.
        await tester.pump(const Duration(milliseconds: 20));
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump(const Duration(milliseconds: 20));
        await gesture.moveBy(const Offset(0, -40));
        await tester.pump(const Duration(milliseconds: 20));
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
      'Given a shelf row, When the name or the pencil is tapped, Then the rename sheet opens',
      (tester) async {
        await _pumpAndOpenSheet(tester, [_shelf('a', 'Dev', 1)]);

        await tester.tap(find.text('Dev'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);

        // Dismiss by tapping the modal barrier above the sheet.
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);

        await tester.tap(find.byIcon(Icons.edit_outlined));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);
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
  });
}
