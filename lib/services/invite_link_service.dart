import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// The host that owns invite links. Must match the `applinks:` entitlement and the
/// AASA served at that domain, or the OS never hands the URL over in the first place.
const String kInviteLinkHost = 'libstack.app';

/// The path prefix an invite lives under, matching `kInviteLinkBase`.
const String kInviteLinkPathPrefix = '/i/';

/// A token is 8 characters of the server's alphabet: A-Z and 2-9, less `O`, `I`, `0`
/// and `1`. Restated from `supabase/migrations/20260828120300_invite_rpcs.sql`.
///
/// **The only place this rule lives on the client now.** It used to be duplicated in
/// `invite_code_page.dart`, as an input filter for a typed code; that page and the whole
/// typed tier are gone, so a link is the only thing a token is ever read out of.
final RegExp kInviteTokenPattern = RegExp(r'^[A-HJ-NP-Z2-9]{8}$');

/// Pulls a token out of a URI, or returns null.
///
/// **Deliberately strict, because this is the security boundary of the link tier.** It
/// is the one function standing between "any URI the OS hands us" and "a token we send
/// to the server", so every check is a refusal rather than a normalisation:
///
///  * the scheme must be `https` -- the `bookworm-friends://` custom scheme is *not*
///    accepted here even though it is registered, because it is the OAuth callback and
///    must be left entirely to Supabase's observer;
///  * the host must be exactly [kInviteLinkHost] -- not a suffix match, which would
///    accept `evil-libstack.app`;
///  * the path must start with `/i/` and hold exactly one more segment;
///  * the segment must match the server's alphabet exactly.
///
/// Case is folded up before matching, so a link that survived a lowercasing proxy still
/// works. Nothing else is repaired: a token that fails any check is not a token.
String? inviteTokenFromUri(Uri uri) {
  if (uri.scheme != 'https') return null;
  if (uri.host != kInviteLinkHost) return null;
  if (!uri.path.startsWith(kInviteLinkPathPrefix)) return null;

  final segments = uri.pathSegments;
  if (segments.length != 2) return null;

  final token = segments[1].toUpperCase();
  return kInviteTokenPattern.hasMatch(token) ? token : null;
}

/// Watches for invite links and hands the token to whoever is listening.
///
/// **Why this is a filter and not just a listener.** `app_links` is a singleton that
/// delivers the one incoming URI to *every* subscriber, and `Supabase.initialize`
/// already runs one (`SupabaseAuth._startDeeplinkObserver`) to exchange the OAuth code.
/// A previous attempt at a second, unfiltered listener raced it over a single-use PKCE
/// code, so one of the two exchanges always failed and pushed an `AuthException` onto
/// `onAuthStateChange`. That is why `main.dart` carried a comment saying there was
/// deliberately no deep link listener here.
///
/// [inviteTokenFromUri] is what makes a second subscriber safe: this class reacts only
/// to `https://libstack.app/i/<token>` and is inert for every other URI, including the
/// OAuth callback. **Widening that filter re-opens the sign-in bug**, and it will
/// present as intermittent login failure rather than as anything to do with invites.
class InviteLinkService {
  InviteLinkService({AppLinks? appLinks}) : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;
  StreamSubscription<Uri>? _subscription;

  /// Tokens, in arrival order. Broadcast because both the cold-start read and the
  /// warm-resume stream feed it, and more than one thing may want to listen.
  final _tokens = StreamController<String>.broadcast();
  Stream<String> get tokens => _tokens.stream;

  /// The token a cold start arrived with, if any.
  ///
  /// Held rather than only streamed: the app is launched *by* the link, so the token
  /// exists before anything is listening. A stream-only design drops it.
  String? _pending;
  String? get pending => _pending;

  /// Takes the pending token, clearing it.
  ///
  /// Read-once, because a token that stayed set would be redeemed again on the next
  /// screen that asked -- and the reader would be walked through consent twice for one
  /// tap.
  String? takePending() {
    final token = _pending;
    _pending = null;
    return token;
  }

  /// Reads the launch URI and subscribes to later ones.
  ///
  /// Safe to call when the app was not launched from a link: `getInitialLink` simply
  /// returns null.
  Future<void> start() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (e) {
      // A missing platform implementation must not take the app down on startup. The
      // link tier degrades to the typed code, which is the whole reason that floor
      // exists.
      if (kDebugMode) debugPrint('invite: initial link read failed: $e');
    }

    _subscription = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e) {
        if (kDebugMode) debugPrint('invite: link stream error: $e');
      },
    );
  }

  void _handle(Uri uri) {
    final token = inviteTokenFromUri(uri);
    // Not an invite link. Almost certainly the OAuth callback, which belongs to
    // Supabase's observer -- returning here is what keeps the two from racing.
    if (token == null) return;

    _pending = token;
    _tokens.add(token);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _tokens.close();
  }
}
