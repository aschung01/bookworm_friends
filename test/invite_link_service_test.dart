// The URI filter, which is the security boundary of the link tier and the thing
// standing between Supabase's OAuth observer and a second `app_links` subscriber.
//
// **Why this file is mostly refusals.** `app_links` is a singleton that hands the one
// incoming URI to every listener. `Supabase.initialize` already runs one to exchange
// the OAuth code, and an unfiltered second listener raced it over a single-use PKCE
// code -- one of the two exchanges always failed. `main.dart` carried a comment saying
// there was deliberately no deep link listener here *because* of that.
//
// `inviteTokenFromUri` is what makes a second subscriber safe, so every case it must
// say no to is asserted individually. A regression here does not look like an invite
// bug; it looks like intermittent sign-in failure, which is far harder to trace.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/services/invite_link_service.dart';

void main() {
  group('accepting a real invite link', () {
    test(
      'Given a well-formed invite URL, When it is parsed, Then the token comes back',
      () {
        expect(
          inviteTokenFromUri(Uri.parse('https://libstack.app/i/K7M2QP4X')),
          'K7M2QP4X',
        );
      },
    );

    test(
      'Given a lowercased link, When it is parsed, Then the token is folded up',
      () {
        // Some proxies and mail clients lowercase URLs. The server alphabet is
        // uppercase, so folding here is the difference between a link that works and
        // one that reports "we couldn't find that code".
        expect(
          inviteTokenFromUri(Uri.parse('https://libstack.app/i/k7m2qp4x')),
          'K7M2QP4X',
        );
      },
    );

    test(
      'Given a link carrying campaign parameters, When it is parsed, Then the query '
      'is ignored',
      () {
        // The landing page redirect adds `pt`/`ct` for install attribution, and a
        // messenger may append its own tracking. Neither is part of the token.
        expect(
          inviteTokenFromUri(
            Uri.parse('https://libstack.app/i/K7M2QP4X?pt=123&ct=invite'),
          ),
          'K7M2QP4X',
        );
      },
    );
  });

  group('refusing everything else', () {
    // **The OAuth callback is the one that matters.** If this ever returns non-null,
    // two observers race a single-use PKCE code and sign-in breaks intermittently.
    test(
      'Given the OAuth callback on the custom scheme, When it is parsed, Then it is '
      'refused so Supabase keeps sole ownership of it',
      () {
        expect(
          inviteTokenFromUri(
            Uri.parse('bookworm-friends://login-callback?code=abc123'),
          ),
          isNull,
        );
      },
    );

    test(
      'Given the custom scheme carrying an invite-shaped path, When it is parsed, '
      'Then it is still refused',
      () {
        // Deliberate: the custom scheme belongs to auth. An invite must arrive over
        // https or not at all, so there is exactly one owner per scheme.
        expect(
          inviteTokenFromUri(Uri.parse('bookworm-friends://i/K7M2QP4X')),
          isNull,
        );
      },
    );

    test(
      'Given a lookalike host, When it is parsed, Then a suffix match does not let it '
      'through',
      () {
        // The check is equality, not `endsWith`. This is the case a sloppy filter
        // passes, and it would hand an attacker's page a working token path.
        expect(
          inviteTokenFromUri(Uri.parse('https://evil-libstack.app/i/K7M2QP4X')),
          isNull,
        );
        expect(
          inviteTokenFromUri(
            Uri.parse('https://libstack.app.evil.com/i/K7M2QP4X'),
          ),
          isNull,
        );
      },
    );

    test('Given plain http, When it is parsed, Then it is refused', () {
      expect(
        inviteTokenFromUri(Uri.parse('http://libstack.app/i/K7M2QP4X')),
        isNull,
      );
    });

    test(
      'Given another path on the right host, When it is parsed, Then only /i/ is '
      'claimed',
      () {
        // The app claims `/i/*` only. `/@handle` and the marketing pages are web
        // pages by design, and an app that swallowed them would break them.
        expect(
          inviteTokenFromUri(Uri.parse('https://libstack.app/@jisoo')),
          isNull,
        );
        expect(inviteTokenFromUri(Uri.parse('https://libstack.app/')), isNull);
      },
    );

    test(
      'Given a token of the wrong shape, When it is parsed, Then it is refused before '
      'it reaches the server',
      () {
        final bad = {
          'too short': 'K7M2QP4',
          'too long': 'K7M2QP4XY',
          'ambiguous O': 'K7M2QP4O',
          'ambiguous I': 'K7M2QP4I',
          'ambiguous zero': 'K7M2QP40',
          'ambiguous one': 'K7M2QP41',
          'punctuation': 'K7M2-P4X',
        };
        for (final entry in bad.entries) {
          expect(
            inviteTokenFromUri(
              Uri.parse('https://libstack.app/i/${entry.value}'),
            ),
            isNull,
            reason: entry.key,
          );
        }
      },
    );

    test(
      'Given extra path segments, When it is parsed, Then the deeper path is refused',
      () {
        expect(
          inviteTokenFromUri(
            Uri.parse('https://libstack.app/i/K7M2QP4X/extra'),
          ),
          isNull,
        );
        expect(
          inviteTokenFromUri(Uri.parse('https://libstack.app/i/')),
          isNull,
        );
      },
    );
  });
}
