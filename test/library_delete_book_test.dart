// Tests for deleting a book from the library's edit mode.
//
// Two layers:
//   1. The badge-only confirmation gate. In edit mode the red X badge is the
//      sole delete target, and accepting its confirmation is the only action
//      that may commit the irreversible delete.
//   2. The local remove/restore pair underneath, which makes the delete feel
//      instant and rolls back if the database call fails.

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';

import 'support/home_page_harness.dart';

/// Records the commit instead of hitting Supabase. [succeeds] flips it to the
/// failure path so the rollback can be exercised.
class FakeLibraryActions extends LibraryActions {
  FakeLibraryActions(super.ref);

  @override
  Future<bool> deleteBookSilently(String bookId) async {
    committedDeletes.add(bookId);
    return deleteSucceeds;
  }
}

// Held outside the fake because Riverpod builds it lazily, on first read.
final committedDeletes = <String>[];
bool deleteSucceeds = true;

Future<void> _pumpLibraryInEditMode(WidgetTester tester) async {
  committedDeletes.clear();
  deleteSucceeds = true;
  await pumpHome(
    tester,
    extraOverrides: [
      libraryActionsProvider.overrideWith(FakeLibraryActions.new),
    ],
  );
  await enterEditMode(tester);
}

Finder _cover() => find.byType(BookWidget);
Finder _deleteBadge() => find.byKey(const ValueKey('delete_book_b1'));

Future<void> _tapDeleteBadge(WidgetTester tester) =>
    tester.tapAt(tester.getCenter(_deleteBadge()) + const Offset(6, 6));

/// Ids of the books on [shelfId], in order.
List<String> _idsOn(ProviderContainer container, String shelfId) => container
    .read(libraryProvider)
    .value!
    .firstWhere((s) => s.id == shelfId)
    .books
    .map((b) => b.id)
    .toList();

Future<ProviderContainer> _container() async {
  final container = ProviderContainer(
    overrides: [
      libraryProvider.overrideWith(
        () => FakeLibraryNotifier([
          testShelf('s1', [
            testBook('b0', 's1', position: 0),
            testBook('b1', 's1', position: 1),
            testBook('b2', 's1', position: 2),
          ]),
          testShelf('s2', [testBook('b3', 's2')]),
        ]),
      ),
    ],
  );
  await container.read(libraryProvider.future);
  return container;
}

void main() {
  group('delete confirmation', () {
    testWidgets(
      'Given edit mode, When the cover is tapped, Then editing remains active and deletion is not requested',
      (tester) async {
        await _pumpLibraryInEditMode(tester);

        await tester.tap(_cover());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Delete this?'), findsNothing);
        expect(committedDeletes, isEmpty);
        expect(_cover(), findsOneWidget);
        expect(isEditing(), isTrue);
      },
    );

    testWidgets(
      'Given edit mode, When the delete badge is tapped, Then confirmation is required before committing',
      (tester) async {
        await _pumpLibraryInEditMode(tester);

        await _tapDeleteBadge(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Delete this?'), findsOneWidget);
        expect(committedDeletes, isEmpty);
        expect(_cover(), findsOneWidget);
      },
    );

    testWidgets(
      'Given the confirmation is showing, Then delete is visually destructive and cancel is neutral',
      (tester) async {
        await _pumpLibraryInEditMode(tester);

        await _tapDeleteBadge(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        final cancelFinder = find.byWidgetPredicate(
          (widget) =>
              widget is ElevatedActionButton && widget.buttonText == 'Cancel',
        );
        final deleteFinder = find.byWidgetPredicate(
          (widget) =>
              widget is ElevatedActionButton && widget.buttonText == 'Delete',
        );
        final cancel = tester.widget<ElevatedActionButton>(cancelFinder);
        final delete = tester.widget<ElevatedActionButton>(deleteFinder);

        expect(cancel.isDestructive, isFalse);
        expect(delete.isDestructive, isTrue);

        // Buttons inside a bottom sheet deliberately stay Material on *every*
        // platform, so there is no PlatformVersion branch here: Liquid Glass
        // needs content behind it to refract, and a sheet's backdrop is an
        // opaque surface, so glass would degrade into a flat pill. Scoped to
        // these two buttons rather than the whole tree, because the library
        // page behind the sheet may legitimately render glass buttons.
        expect(
          find.descendant(of: cancelFinder, matching: find.byType(CNButton)),
          findsNothing,
        );
        expect(
          find.descendant(of: deleteFinder, matching: find.byType(CNButton)),
          findsNothing,
        );

        final cancelMaterial = tester.widget<ElevatedButton>(
          find.descendant(
            of: cancelFinder,
            matching: find.byType(ElevatedButton),
          ),
        );
        final deleteMaterial = tester.widget<ElevatedButton>(
          find.descendant(
            of: deleteFinder,
            matching: find.byType(ElevatedButton),
          ),
        );

        expect(
          cancelMaterial.style?.backgroundColor?.resolve({}),
          isNot(softRedColor),
        );
        expect(
          deleteMaterial.style?.backgroundColor?.resolve({}),
          softRedColor,
        );
        expect(
          deleteMaterial.style?.foregroundColor?.resolve({}),
          Colors.white,
        );
      },
    );

    testWidgets(
      'Given edit mode, Then the delete badge has an accessible 44 point target',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await _pumpLibraryInEditMode(tester);

          expect(tester.getSize(_deleteBadge()), const Size(44, 44));

          final coverTopLeft = tester.getTopLeft(_cover());
          final targetCenter = tester.getCenter(_deleteBadge());
          // The disc, not the minus drawn inside it — the badge is two
          // `DecoratedBox`es. Matched on the shape rather than taken by position in
          // the subtree, so this keeps meaning "the thing the reader can see" if the
          // badge is ever put together differently.
          final disc = find.descendant(
            of: _deleteBadge(),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).shape == BoxShape.circle,
            ),
          );
          expect(disc, findsOneWidget);
          // The badge is pinned to the cover's top-left corner, but edit mode
          // wiggles the cover (see [Wiggle]) with a per-instance random phase
          // and amplitude, so global positions drift a pixel or two between
          // runs. Assert with tolerance rather than exact equality, otherwise
          // this flakes. Sizes are transform-independent, so those stay exact.
          expect(
            targetCenter,
            offsetMoreOrLessEquals(coverTopLeft, epsilon: 3),
          );
          expect(
            tester.getCenter(disc),
            offsetMoreOrLessEquals(coverTopLeft, epsilon: 3),
          );

          expect(
            tester.getSemantics(_deleteBadge()),
            matchesSemantics(
              label: 'Delete Clean Code',
              isButton: true,
              hasTapAction: true,
            ),
          );
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'Given the confirmation is showing, When it is cancelled, Then the book survives',
      (tester) async {
        await _pumpLibraryInEditMode(tester);

        await _tapDeleteBadge(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Delete this?'), findsNothing);
        expect(committedDeletes, isEmpty);
        expect(_cover(), findsOneWidget);
      },
    );

    testWidgets(
      'Given the confirmation is showing, When delete is accepted, Then the book is removed and the delete is committed',
      (tester) async {
        await _pumpLibraryInEditMode(tester);

        await _tapDeleteBadge(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Delete').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(committedDeletes, ['b1']);
        expect(_cover(), findsNothing);
      },
    );

    testWidgets(
      'Given the database delete fails, When it is accepted, Then the book comes back',
      (tester) async {
        await _pumpLibraryInEditMode(tester);
        deleteSucceeds = false;

        await _tapDeleteBadge(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Delete').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(committedDeletes, ['b1']);
        expect(_cover(), findsOneWidget);
      },
    );
  });

  group('local removal and rollback', () {
    test(
      'Given a book in the middle of a shelf, When removed and restored, Then it returns to the same position',
      () async {
        final container = await _container();
        addTearDown(container.dispose);
        final notifier = container.read(libraryProvider.notifier);

        final pending = notifier.removeBookLocally('b1');

        expect(pending, isNotNull);
        expect(pending!.shelfId, 's1');
        expect(pending.index, 1);
        expect(_idsOn(container, 's1'), ['b0', 'b2']);

        notifier.restoreBookLocally(pending);

        expect(_idsOn(container, 's1'), ['b0', 'b1', 'b2']);
      },
    );

    test(
      'Given a removal was already restored, When restored again, Then the book is not duplicated',
      () async {
        final container = await _container();
        addTearDown(container.dispose);
        final notifier = container.read(libraryProvider.notifier);

        final pending = notifier.removeBookLocally('b0')!;
        notifier.restoreBookLocally(pending);
        notifier.restoreBookLocally(pending);

        expect(_idsOn(container, 's1'), ['b0', 'b1', 'b2']);
      },
    );

    test(
      'Given other books were deleted in the meantime, When restoring, Then it clamps instead of throwing',
      () async {
        final container = await _container();
        addTearDown(container.dispose);
        final notifier = container.read(libraryProvider.notifier);

        final pending = notifier.removeBookLocally('b2')!;
        // Position 2 no longer exists once b0 and b1 are gone too.
        notifier.removeBookLocally('b0');
        notifier.removeBookLocally('b1');
        notifier.restoreBookLocally(pending);

        expect(_idsOn(container, 's1'), ['b2']);
      },
    );

    test(
      'Given an unknown book id, When removing, Then nothing happens',
      () async {
        final container = await _container();
        addTearDown(container.dispose);
        final notifier = container.read(libraryProvider.notifier);

        expect(notifier.removeBookLocally('nope'), isNull);
        expect(_idsOn(container, 's1'), ['b0', 'b1', 'b2']);
        expect(_idsOn(container, 's2'), ['b3']);
      },
    );

    test(
      'Given a book on a second shelf, When removed, Then only that shelf changes',
      () async {
        final container = await _container();
        addTearDown(container.dispose);
        final notifier = container.read(libraryProvider.notifier);

        final pending = notifier.removeBookLocally('b3')!;

        expect(pending.shelfId, 's2');
        expect(_idsOn(container, 's2'), isEmpty);
        expect(_idsOn(container, 's1'), ['b0', 'b1', 'b2']);
      },
    );
  });
}
