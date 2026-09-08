// Tests for `profiles.handle`: the Latin identity the exported card's strip prints.
//
// **The most valuable test in this file reads a SQL file off disk.** The handle's format
// is stated in three places — the database's `CHECK`, `handleProblem` in Dart, and
// `cardStripToken` on the artifact — and three copies of one rule is exactly the shape
// that drifts. `supabase/tests/handle_test.sql` holds the SQL side against a real
// database; nothing until now held the two against *each other*.
//
// Everything else here is about the editor's rules rather than the column's: what the
// field does with a name it cannot use, and why it drops rather than transliterates.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/handle.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/ui/widgets/library_card/shareable_library_card.dart';

/// Handles the database would accept.
const _valid = [
  'abc',
  'a_1',
  'paper_fox_412',
  'reader_4f2c1204ab',
  '___',
  'abcdefghij0123456789',
];

/// Handles it would refuse, each one a real shape rather than an invented edge.
const _invalid = {
  'ab': HandleProblem.tooShort,
  'abcdefghij01234567890': HandleProblem.tooLong,
  'PaperFox': HandleProblem.charset,
  'paper fox': HandleProblem.charset,
  'paper-fox': HandleProblem.charset,
  'paper.fox': HandleProblem.charset,
  '독서하는_사람': HandleProblem.charset,
  '': HandleProblem.empty,
};

void main() {
  group('the rule', () {
    test(
      'Given a handle the database would take, When it is checked, Then nothing is wrong '
      'with it',
      () {
        for (final handle in _valid) {
          expect(handleProblem(handle), HandleProblem.none, reason: handle);
        }
      },
    );

    test(
      'Given a handle the database would refuse, When it is checked, Then the reason is '
      'named',
      () {
        // Named rather than a bool, because "invalid" is not an actionable message on a
        // field with four separate ways to be wrong.
        _invalid.forEach((handle, problem) {
          expect(handleProblem(handle), problem, reason: handle);
        });
      },
    );
  });

  group('the three copies of the rule agree', () {
    test('Given the migration, When its check is read, Then it is the same pattern Dart '
        'holds', () {
      // Read off disk rather than trusted to a comment. The SQL is the constraint that
      // binds; if these ever diverge, the client accepts a handle the database refuses
      // and the reader gets "couldn't save" with nothing to fix.
      final migration = File(
        'supabase/migrations/20260821100303_add_profile_handle.sql',
      ).readAsStringSync();

      expect(
        migration,
        contains("CHECK (handle ~ '$kHandlePattern')"),
        reason:
            'the migration and lib/models/handle.dart must state one rule, not two',
      );
    });

    test('Given a handle the database would accept, When the strip prints it, Then it is '
        'never rejected', () {
      // `cardStripToken` is deliberately *looser* — case-insensitive, because it
      // uppercases for the strip — so the relationship to assert is containment rather
      // than equality: everything the column can hold, the artifact can print. The
      // reverse is not required and is not true.
      for (final handle in _valid) {
        expect(
          cardStripToken(handle),
          handle.toUpperCase(),
          reason:
              'the strip refused a handle the database would store: $handle',
        );
      }
    });

    test('Given a display name, When the strip is asked to print it, Then it refuses rather '
        'than mangling it', () {
      // The whole reason this column exists, restated as a test: measured against the
      // live database, 126 of 136 display names are non-ASCII and exactly **two** are
      // already strip-safe. Sanitising `독서하는 08269f2d` would print `08269F2D`, which
      // reads as a rendering fault.
      for (final name in [
        '독서하는 사람',
        '독서하는 08269f2d',
        'paper fox',
        'paper-fox',
        'ab',
        '',
      ]) {
        expect(cardStripToken(name), isEmpty, reason: name);
      }
    });

    test('Given anything the strip will print, When it is lower-cased, Then it is a '
        'handle the database would store', () {
      // The containment in the other direction, and the one case where the two rules
      // genuinely differ: `cardStripToken` accepts `PaperFox` because it uppercases for
      // the strip, while the column refuses it because one canonical representation is
      // what makes a plain unique index case-insensitive. That looseness is safe exactly
      // as long as *case* is the only thing it is loose about -- which is what this
      // asserts.
      for (final candidate in [
        ..._valid,
        ..._invalid.keys,
        'PaperFox',
        'PAPER_FOX_412',
      ]) {
        if (cardStripToken(candidate).isEmpty) continue;
        expect(
          isValidHandle(candidate.toLowerCase()),
          isTrue,
          reason:
              'the strip would print \$candidate, which the column could not store',
        );
      }
    });
  });

  group('what the editor does as you type', () {
    test(
      'Given a name with spaces, When it is normalised, Then they become underscores',
      () {
        expect(normaliseHandleInput('Paper Fox'), 'paper_fox');
        expect(normaliseHandleInput('paper   fox'), 'paper_fox');
      },
    );

    test('Given a Korean name, When it is normalised, Then it is dropped rather than '
        'transliterated', () {
      // The same refusal `cardStripToken` makes, and for the same reason: a converter's
      // output is a remnant that reads as a fault, while an empty field at least says
      // "choose something".
      expect(normaliseHandleInput('독서하는 사람'), '_');
      expect(normaliseHandleInput('독서하는'), isEmpty);
    });

    test(
      'Given a name that is too long, When it is normalised, Then it is not truncated',
      () {
        // A field that silently stops accepting characters is indistinguishable from a
        // broken keyboard, so length is reported rather than enforced in the field.
        final long = 'a' * 40;
        expect(normaliseHandleInput(long), long);
        expect(handleProblem(long), HandleProblem.tooLong);
      },
    );

    test('Given anything the field produces, When it is valid, Then the database would take '
        'it unchanged', () {
      // No trimming and no lower-casing at save time: one canonical representation is
      // what makes a plain unique index case-insensitive, which is why the migration
      // dropped `citext`.
      for (final raw in ['Paper Fox 412', 'PAPER_FOX', 'p a p e r']) {
        final cleaned = normaliseHandleInput(raw);
        if (!isValidHandle(cleaned)) continue;
        expect(cleaned, cleaned.toLowerCase());
        expect(cleaned.trim(), cleaned);
      }
    });
  });

  group('the model', () {
    test(
      'Given a row with a handle, When it is parsed, Then the handle survives',
      () {
        final profile = Profile.fromJson({
          'id': 'u',
          'username': '독서하는 사람',
          'handle': 'paper_fox_412',
          'created_at': '2026-06-26T00:00:00Z',
          'updated_at': '2026-06-26T00:00:00Z',
        });

        // Two identities, two jobs — and the display name is not demoted by the handle
        // existing.
        expect(profile.handle, 'paper_fox_412');
        expect(profile.username, '독서하는 사람');
      },
    );

    test('Given a row from a database without the migration, When it is parsed, Then the '
        'handle is null rather than an error', () {
      // `NOT NULL` in the schema and generated at signup, so this state does not exist
      // once the migration is applied. It exists before it is, and a client that threw
      // on the old shape could not be deployed ahead of the migration.
      final profile = Profile.fromJson({
        'id': 'u',
        'created_at': '2026-06-26T00:00:00Z',
        'updated_at': '2026-06-26T00:00:00Z',
      });

      expect(profile.handle, isNull);
      expect(cardStripToken(profile.handle), isEmpty);
    });
  });
}
