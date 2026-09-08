import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the one-time invite-code screen has already been offered.
///
/// Persisted, because "once" has to survive a relaunch — and because the screen is
/// **optional by design**. Someone who continued past it with an empty field has
/// declined; showing it again on the next launch would turn a skip into nagging.
const String kInviteCodePromptPrefKey = 'invite_code_prompt_shown';

/// Offers `InviteCodePage` exactly once, after a sign-in.
///
/// **This exists because the clipboard handoff needs somewhere to land.** The landing
/// page copies the token inside the tap that leaves for the App Store; the app then has
/// to read it back on first launch, and `InviteCodePage` is the screen that does
/// (`_prefillFromClipboard`). Without a route into it the deferred tier is a copy into
/// a void — the page was registered in `AppRoutes` and reachable from nowhere.
///
/// **Not shown when a token already arrived by link.** A tapped Universal Link routes
/// straight to consent, and following that with "have you got a code?" would ask for
/// something the reader has just used. The link path still burns the one chance.
///
/// **Reads `SharedPreferences` directly rather than through
/// `sharedPreferencesProvider`.** That provider throws unless overridden, and this is
/// reached from `AuthPage` — a screen whose own tests have no reason to know invites
/// exist. Making sign-in depend on an override broke three of them, which was the
/// design telling me the coupling was wrong rather than the tests being wrong. The
/// async instance is already a singleton, so there is no second read cost.
class InviteCodePrompt {
  const InviteCodePrompt();

  /// Whether the screen has been offered before now.
  Future<bool> get wasShown async =>
      (await SharedPreferences.getInstance()).getBool(
        kInviteCodePromptPrefKey,
      ) ??
      false;

  /// Whether to show it now, consuming the one chance as a side effect.
  ///
  /// The write happens before the caller navigates, so two paths racing on the same
  /// sign-in cannot both push the screen.
  Future<bool> takeChance() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(kInviteCodePromptPrefKey) ?? false) return false;
    await prefs.setBool(kInviteCodePromptPrefKey, true);
    return true;
  }
}

final inviteCodePromptProvider = Provider<InviteCodePrompt>(
  (ref) => const InviteCodePrompt(),
);
