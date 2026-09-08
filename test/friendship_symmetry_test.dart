// **A friendship has no direction, and the Dart side has to agree with the schema
// about that.**
//
// `friendships` stores one row per pair in a canonical order — `user_a < user_b`,
// enforced by a CHECK — so a half-friendship is not representable. That is the whole
// design, and it puts two obligations on the client that no widget test would catch:
//
//   1. Reading "my friends" is a match on **either** column, and the friend is
//      whichever id is not mine. Get that wrong and half your friends vanish — the
//      half who happened to redeem your link rather than send it.
//   2. Writing has to order the pair the same way the CHECK does, or the `DELETE`
//      matches nothing and the removal silently does not happen.
//
// Both are pure functions over a row shape, so they are unit-tested here against the
// mapping rather than against Supabase. The SQL side has its own coverage in
// `supabase/tests/friendships_test.sql`.

import 'package:flutter_test/flutter_test.dart';

/// The id of the other person on a friendship row.
///
/// Mirrors the mapping in `friendsProvider`. Restated rather than imported because
/// the provider's version is welded to a `PostgrestList`; what is being checked is
/// the *rule*, and a rule small enough to inline is small enough to get wrong in
/// exactly one direction.
String _other(Map<String, String> row, String me) =>
    row['user_a'] == me ? row['user_b']! : row['user_a']!;

/// The canonical pair, the way `least`/`greatest` and `UserActions.removeFriend`
/// both order it.
(String, String) _canonical(String x, String y) =>
    x.compareTo(y) < 0 ? (x, y) : (y, x);

void main() {
  group('reading a friendship', () {
    // One row, two readers. The asymmetry in the *query* is the price of the
    // symmetry in the data: a `follows` row knew which end you were on, and a
    // friendship deliberately does not.
    const row = {'user_a': 'alice', 'user_b': 'bob'};

    test('Given the row, When alice reads it, Then her friend is bob', () {
      expect(_other(row, 'alice'), 'bob');
    });

    test('Given the same row, When bob reads it, Then his friend is alice', () {
      // The half that would disappear if the query filtered on one column. Under
      // `follows` these were two rows and this could not go wrong; under one row it
      // is the first thing to break.
      expect(_other(row, 'bob'), 'alice');
    });

    test('Given both readers, When each resolves the row, Then neither sees '
        'themselves', () {
      for (final me in ['alice', 'bob']) {
        expect(
          _other(row, me),
          isNot(me),
          reason:
              'a row that resolved to the reader would put them in their own '
              'friends list, which is what a naive first-column read does',
        );
      }
    });
  });

  group('writing a friendship', () {
    test('Given a pair in either order, When it is canonicalised, Then both orders '
        'produce the same row', () {
      // The `DELETE` in `removeFriend` pins both columns, so it only matches if
      // the client orders the pair the way the table stores it. Ordering it from
      // the caller's point of view instead — me first — matches nothing half the
      // time, and a removal that silently does nothing is worse than one that
      // errors.
      expect(_canonical('alice', 'bob'), _canonical('bob', 'alice'));
    });

    test('Given a canonical pair, Then it satisfies the CHECK', () {
      // `check (user_a < user_b)`. A write that violates this raises rather than
      // inserting a row nothing can find.
      for (final (x, y) in [('alice', 'bob'), ('bob', 'alice')]) {
        final (a, b) = _canonical(x, y);
        expect(a.compareTo(b) < 0, isTrue, reason: '$a must sort before $b');
      }
    });

    test('Given the canonical pair, When either party removes the other, Then both '
        'name the same row', () {
      // **One row means one delete severs both sides**, which is what lets the
      // confirm dialog promise that access is revoked for both of you. If the two
      // parties could name different rows, that promise would be false for one of
      // them.
      expect(_canonical('alice', 'bob'), _canonical('bob', 'alice'));
      expect(_canonical('bob', 'alice'), ('alice', 'bob'));
    });

    test(
      'Given ids that are not sorted alphabetically, Then order still holds',
      () {
        // Real ids are uuids, so the sort is over hex rather than names. A comparison
        // that happened to work on 'alice'/'bob' and not on digits would be a
        // pleasant coincidence rather than a rule.
        const x = 'ffffffff-0000-0000-0000-000000000000';
        const y = '00000000-ffff-ffff-ffff-ffffffffffff';
        expect(_canonical(x, y), (y, x));
        expect(_canonical(y, x), (y, x));
      },
    );
  });
}
