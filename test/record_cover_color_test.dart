// Tests for `LibraryActions.recordCoverColor`, the backfill that fills
// `books.cover_color` in from a cover the app has just decoded.
//
// The rules are the whole substance of this method — who may write, when, and how
// often — while the UPDATE underneath is one line. So the seam under test is
// `writeCoverColor`, and every assertion here is about a decision the real method
// made rather than about a reimplementation of it.
//
// Why the rules are strict is worth restating, because a laxer version of this
// method would look harmless: it is called from a *render* path, once per decoded
// cover, on shelves that may belong to somebody else.

import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';

/// Records the write instead of hitting Supabase. [fails] exercises the offline
/// path, which must stay silent.
class _FakeLibraryActions extends LibraryActions {
  _FakeLibraryActions(super.ref);

  final List<String> writtenIds = <String>[];
  final List<Color> writtenColors = <Color>[];
  bool fails = false;

  @override
  Future<void> writeCoverColor(String bookId, Color color) async {
    writtenIds.add(bookId);
    writtenColors.add(color);
    if (fails) throw Exception('offline');
  }
}

Book _book({String id = 'b1', String userId = 'u', Color? coverColor}) => Book(
  id: id,
  userId: userId,
  shelfId: 's1',
  isbn: '9788936434120',
  title: '아몬드',
  thumbnail: 'https://example.com/cover.jpg',
  status: 0,
  position: 0,
  createdAt: DateTime(2024),
  authors: const [],
  coverColor: coverColor,
);

({ProviderContainer container, _FakeLibraryActions actions}) _harness({
  String? signedInAs = 'u',
}) {
  final container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue(signedInAs),
      libraryActionsProvider.overrideWith(_FakeLibraryActions.new),
    ],
  );
  addTearDown(container.dispose);
  return (
    container: container,
    actions: container.read(libraryActionsProvider) as _FakeLibraryActions,
  );
}

const Color _sampled = Color(0xFF3C6E71);

void main() {
  group('who may write', () {
    test('Given a book the reader owns with no stored colour, When a cover is '
        'sampled, Then the colour is written', () async {
      final h = _harness();

      await h.actions.recordCoverColor(_book(), _sampled);

      expect(h.actions.writtenIds, ['b1']);
      expect(h.actions.writtenColors, [_sampled]);
    });

    test(
      'Given a book belonging to somebody else, When a cover is sampled, Then '
      'nothing is written',
      () async {
        // A friend's library renders through the same BookWidget, so scrolling
        // their shelves samples their covers. RLS would reject the write anyway;
        // the right place to decline is before the request, not after it.
        final h = _harness();

        await h.actions.recordCoverColor(_book(userId: 'friend'), _sampled);

        expect(h.actions.writtenIds, isEmpty);
      },
    );

    test('Given nobody is signed in, When a cover is sampled, Then nothing is '
        'written', () async {
      final h = _harness(signedInAs: null);

      await h.actions.recordCoverColor(_book(), _sampled);

      expect(h.actions.writtenIds, isEmpty);
    });
  });

  group('how often', () {
    test('Given the book already has a stored colour, When a cover is sampled, '
        'Then nothing is written', () async {
      // The column is filled once and then left alone. Rewriting it on every
      // decode would also mean rewriting it on every *re*-decode, and a cover
      // re-fetched at a different size can average a shade or two differently
      // — a book that quietly changed tone for no reason the reader can see.
      final h = _harness();

      await h.actions.recordCoverColor(
        _book(coverColor: const Color(0xFF102030)),
        _sampled,
      );

      expect(h.actions.writtenIds, isEmpty);
    });

    test('Given the same book is sampled twice in a session, When the second '
        'sample lands, Then only one write happens', () async {
      // The reason a session-level set is needed at all: `recordCoverColor`
      // deliberately invalidates nothing, so the Book objects on screen keep
      // their null `coverColor` until the next fetch. Without the set, the check
      // above can never notice that the write already happened — and one book
      // can easily be on a shelf and in the read grid at the same time.
      final h = _harness();
      final book = _book();

      await h.actions.recordCoverColor(book, _sampled);
      await h.actions.recordCoverColor(book, _sampled);

      expect(h.actions.writtenIds, ['b1']);
    });

    test('Given two decodes land in the same frame, When both are recorded, Then '
        'each book is written once', () async {
      // Not awaited in turn: both calls are started before either finishes,
      // which is what a screenful of covers resolving together actually looks
      // like. The id is claimed *before* the await for exactly this reason — a
      // gap between the check and the mark is long enough for two calls on one
      // book to pass it.
      final h = _harness();
      final a = _book(id: 'b1');
      final b = _book(id: 'b2');

      await Future.wait([
        h.actions.recordCoverColor(a, _sampled),
        h.actions.recordCoverColor(a, _sampled),
        h.actions.recordCoverColor(b, _sampled),
      ]);

      expect(h.actions.writtenIds, ['b1', 'b2']);
    });
  });

  group('when it fails', () {
    test(
      'Given the device is offline, When a cover is sampled, Then the failure is '
      'swallowed',
      () async {
        // Nothing the reader did caused this write, so nothing they see may
        // depend on it. A book scrolling into view on a train must not raise a
        // failure toast over the shelf. This is the one write in LibraryActions
        // that swallows its error on purpose.
        final h = _harness();
        h.actions.fails = true;

        await expectLater(
          h.actions.recordCoverColor(_book(), _sampled),
          completes,
        );
        expect(h.actions.writtenIds, ['b1']);
      },
    );

    test(
      'Given a write that failed, When the same book is sampled again, Then it '
      'is not retried',
      () async {
        // Retrying would need a fresh decode to be worth anything, and the cost
        // of not retrying is a book that keeps deriving its tone from its ISBN —
        // which is exactly what every book did before this column existed.
        final h = _harness();
        h.actions.fails = true;
        final book = _book();

        await h.actions.recordCoverColor(book, _sampled);
        await h.actions.recordCoverColor(book, _sampled);

        expect(h.actions.writtenIds, ['b1']);
      },
    );
  });
}
