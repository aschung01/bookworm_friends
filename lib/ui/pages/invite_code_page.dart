import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/invite.dart';
import 'package:bookworm_friends/providers/invite_provider.dart';
import 'package:bookworm_friends/ui/pages/invite_consent_page.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';

/// Characters an invite token can contain.
///
/// The server's alphabet, restated here so the field can refuse everything else as it
/// is typed: A–Z and 2–9, less `O`, `I`, `0` and `1`. See
/// `supabase/migrations/20260828120300_invite_rpcs.sql` for why those four are out —
/// they are the pairs that cost a redemption when a code is read down a phone.
///
/// **Filtering rather than validating.** A field that accepts `0` and then reports
/// "we couldn't find that code" has taught the reader nothing; one where the `0`
/// simply never appears makes the alphabet self-evident.
final _tokenFormatter = FilteringTextInputFormatter.allow(
  RegExp('[A-HJ-NP-Z2-9]'),
);

/// Length of a token. Eight, from the same migration.
const int kInviteTokenLength = 8;

/// Folds input to upper case as it is typed.
///
/// Named and public so the ordering constraint at the call site can point at
/// something — an anonymous `withFunction` in a list is exactly the kind of thing
/// that gets reordered by someone tidying imports.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue previous,
    TextEditingValue next,
  ) => next.copyWith(text: next.text.toUpperCase());
}

/// **The tier that makes the invite loop reliable, and the one no vendor sells.**
///
/// Pre-filled from the clipboard when it holds something that looks like a token,
/// typed when not. This is what works when the iOS paste prompt is declined, when an
/// in-app webview swallows a Universal Link, and when someone reads the code aloud.
///
/// **Continue with the field empty is the skip.** That is what "optional" means here,
/// and it is why there is no second action: a Skip button beside Continue would only
/// make it ambiguous which one declines. **It must never block signup** — every path
/// out of this screen leads onward.
///
/// Shown once, after signup. Reachable again is deliberately *not* offered: someone
/// who has a code later has a link, and someone who has neither has nothing to type.
class InviteCodePage extends ConsumerStatefulWidget {
  const InviteCodePage({super.key});

  @override
  ConsumerState<InviteCodePage> createState() => _InviteCodePageState();
}

class _InviteCodePageState extends ConsumerState<InviteCodePage> {
  final _controller = TextEditingController();
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _prefillFromClipboard();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Reads the clipboard once, and only accepts it if it is token-shaped.
  ///
  /// **Silent on failure, deliberately.** On iOS this raises the system paste prompt,
  /// and a reader who declines it must not then see an error — declining is a
  /// perfectly ordinary answer and the field is optional anyway. The shape check is
  /// what stops a URL, a sentence, or whatever was copied an hour ago from landing in
  /// the field and having to be cleared.
  Future<void> _prefillFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim().toUpperCase() ?? '';
      if (text.length != kInviteTokenLength) return;
      if (!RegExp('^[A-HJ-NP-Z2-9]{$kInviteTokenLength}\$').hasMatch(text)) {
        return;
      }
      if (mounted) _controller.text = text;
    } catch (_) {
      // No clipboard on this platform, or the read was refused. Neither is worth
      // saying anything about.
    }
  }

  /// The one action, and it has two meanings.
  ///
  /// Empty field: skip. Anything else: redeem. The button's label does not change
  /// between the two, because both are literally "continue" — the difference is
  /// whether a code came along.
  Future<void> _continue() async {
    final token = _controller.text.trim().toUpperCase();
    if (token.isEmpty) {
      _leave();
      return;
    }

    setState(() => _pending = true);
    late final InviteRedemption redemption;
    try {
      redemption = await ref.read(inviteActionsProvider).redeem(token);
    } catch (_) {
      redemption = const InviteRedemption(
        InviteRedemptionResult.notFound,
        null,
      );
    }
    if (!mounted) return;
    setState(() => _pending = false);

    if (redemption.result.isFriendNow) {
      // **Straight to the success screen, past consent.** Typing a code *is* the
      // consent: nobody types eight characters by accident, and the friendship is
      // already written by the time this returns. The consent screen exists for the
      // tapped-link path, where the reader arrived without deciding anything.
      Navigator.pushReplacementNamed(
        context,
        AppRoutesInvite.inviteDone,
        arguments: InviteDoneArgs(
          inviter: null,
          alreadyFriends:
              redemption.result == InviteRedemptionResult.alreadyFriends,
        ),
      );
      return;
    }

    Navigator.pushReplacementNamed(
      context,
      AppRoutesInvite.inviteDead,
      arguments: InviteDeadArgs(result: redemption.result, inviterName: ''),
    );
  }

  void _leave() => Navigator.of(context).popUntil((r) => r.isFirst);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.pageBackground,
      body: SafeArea(
        // **Not pinned to the floor.** It was, under 380px of white — and unlike the
        // three sheets before it this screen has no mark, so the pin framed the
        // emptiness rather than using it. Everything sits at the top instead.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.oneLastThing, style: AppTextStyles.hero),
              const SizedBox(height: 24),
              Text(
                l10n.haveInviteCode.toUpperCase(),
                style: AppTextStyles.caption.copyWith(
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                enabled: !_pending,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                maxLength: kInviteTokenLength,
                textAlign: TextAlign.center,
                // **Upper-case first, then filter, and the order is the bug this
                // pair had.** Formatters run in sequence, so filtering ahead of the
                // case fold tested lowercase input against an uppercase-only
                // alphabet and deleted every character as it was typed — a code read
                // aloud and typed in lowercase produced an empty field, silently.
                // `textCapitalization` does not save it: that is a hint to the soft
                // keyboard, not a guarantee, and it does nothing for a paste or a
                // hardware keyboard.
                inputFormatters: [UpperCaseTextFormatter(), _tokenFormatter],
                // `figure`'s metrics: this is eight characters read one at a time,
                // and tabular figures keep them from shifting as they are typed.
                style: AppTextStyles.figure.copyWith(letterSpacing: 4),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: colors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 18),
                ),
                onSubmitted: (_) => _continue(),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.inviteCodeOptional,
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(color: colors.secondaryText),
              ),
              const SizedBox(height: 20),
              // **One button, always enabled.** Disabling it on an empty field would
              // turn the skip into a dead end, which is exactly the thing this screen
              // must never do.
              ElevatedActionButton(
                width: double.infinity,
                height: 48,
                borderRadius: 24,
                buttonText: l10n.continueLabel,
                activated: !_pending,
                onPressed: _pending ? null : _continue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
