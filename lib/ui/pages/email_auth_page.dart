import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/email_auth_error.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';

/// Supabase's own default minimum, matched here so the reader is not sent on a round trip
/// to be told. The server still enforces it and answers `weak_password`.
const int kMinPasswordLength = 6;

@visibleForTesting
const Key kEmailFieldKey = Key('emailAuthEmailField');

@visibleForTesting
const Key kPasswordFieldKey = Key('emailAuthPasswordField');

@visibleForTesting
const Key kEmailAuthSubmitKey = Key('emailAuthSubmit');

/// Which of the three errands the page is on.
///
/// **`reset` is a mode rather than a fourth route.** It is one field and one button, and a
/// page of its own would duplicate the email field, its validation and its error mapping --
/// three things that would then be free to drift.
enum _Mode { signIn, signUp, reset }

/// Email and password, for signing in, signing up, and asking for a reset link.
///
/// **A page rather than fields on `AuthPage`, and the reason is layout.** That screen is a
/// centred `Column` with no scroll view, and two fields plus a submit, a mode toggle and a
/// "Forgot password?" link is around 230pt of new content with a keyboard raised -- the
/// `RenderFlex` overflow the streak celebration is recorded hitting on a 375x667 phone.
/// Inline would also put form state, submission and error state into the file that already
/// owns `_leaveIfSignedIn` and `_spendPendingInvite`.
///
/// So this page owns the scroll view and the view insets, which is the thing the inline
/// placement could not afford and the whole reason it exists.
///
/// **It does not navigate on success.** A session reaches `AuthPage` underneath, whose
/// `_leaveIfSignedIn` clears the stack -- this page included. Popping here as well would
/// race that, and the loser would leave the reader on a dead screen.
class EmailAuthPage extends ConsumerStatefulWidget {
  const EmailAuthPage({super.key});

  @override
  ConsumerState<EmailAuthPage> createState() => _EmailAuthPageState();
}

class _EmailAuthPageState extends ConsumerState<EmailAuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _obscured = true;

  /// The address a link was just sent to, and the page's second phase.
  ///
  /// Non-null *is* the "check your inbox" state, rather than a separate enum: the phase and
  /// the address it needs to name are the same fact, so they cannot disagree.
  String? _sentTo;

  /// The last failure, already mapped to a sentence.
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _switchTo(_Mode mode) {
    setState(() {
      _mode = mode;
      // Cleared, because a message about the last errand is misleading on the next one --
      // "that email and password don't match" above a lone email field especially.
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final l10n = AppLocalizations.of(context);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      switch (_mode) {
        case _Mode.signIn:
          await ref
              .read(authProvider.notifier)
              .signInWithEmail(email: email, password: password);
        // Nothing follows: `AuthPage` sees the session and clears the stack.
        case _Mode.signUp:
          final outcome = await ref
              .read(authProvider.notifier)
              .signUpWithEmail(email: email, password: password);
          if (!mounted) return;
          // `signedIn` means confirmation is off on the project and a session already
          // arrived, so there is nothing to wait for and `AuthPage` is already leaving.
          if (outcome == EmailSignUpOutcome.confirmationSent) {
            setState(() => _sentTo = email);
          }
        case _Mode.reset:
          await ref.read(authProvider.notifier).sendPasswordReset(email);
          if (!mounted) return;
          setState(() => _sentTo = email);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = emailAuthError(error, l10n));
    } finally {
      // Guarded, because a successful sign-in disposes this page from underneath the
      // await -- `AuthPage` clears the stack the moment the session lands.
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validateEmail(String? value) {
    final l10n = AppLocalizations.of(context);
    final email = value?.trim() ?? '';
    // Deliberately shallow. The server is the authority on what it will accept, and a
    // clever local pattern can only ever be wrong in the direction of refusing a real
    // address -- which is unrecoverable from the reader's side.
    if (email.isEmpty || !email.contains('@')) {
      return l10n.emailAuthEmailRequired;
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final l10n = AppLocalizations.of(context);
    if ((value ?? '').length < kMinPasswordLength) {
      return l10n.emailAuthPasswordTooShort;
    }
    return null;
  }

  String _title(AppLocalizations l10n) => switch (_mode) {
    _Mode.signIn => l10n.emailAuthSignIn,
    _Mode.signUp => l10n.emailAuthSignUp,
    _Mode.reset => l10n.emailAuthResetTitle,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        backgroundColor: colors.pageBackground,
        surfaceTintColor: Colors.transparent,
        title: Text(_title(l10n), style: AppTextStyles.subtitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          // The keyboard is up for nearly the whole life of this page, so the insets are
          // added to the padding rather than left to `resizeToAvoidBottomInset` alone --
          // that resizes the viewport but does not stop the submit button sitting directly
          // against the keyboard's top edge.
          padding: EdgeInsets.only(
            left: 32,
            right: 32,
            top: 24,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: _sentTo == null ? _buildForm(l10n, colors) : _buildSent(l10n),
        ),
      ),
    );
  }

  Widget _buildSent(AppLocalizations l10n) {
    final address = _sentTo!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.emailAuthCheckInbox, style: AppTextStyles.title),
        const SizedBox(height: 12),
        Text(
          _mode == _Mode.reset
              ? l10n.emailAuthResetSent(address)
              : l10n.emailAuthConfirmSent(address),
          style: AppTextStyles.body,
        ),
      ],
    );
  }

  Widget _buildForm(AppLocalizations l10n, AppColors colors) {
    final isReset = _mode == _Mode.reset;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isReset) ...[
            Text(l10n.emailAuthResetBody, style: AppTextStyles.body),
            const SizedBox(height: 20),
          ],
          TextFormField(
            key: kEmailFieldKey,
            controller: _emailController,
            autofocus: true,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            textInputAction: isReset
                ? TextInputAction.done
                : TextInputAction.next,
            autocorrect: false,
            // So iOS Keychain offers to fill, and to save the pair after a sign-up.
            autofillHints: const [AutofillHints.email],
            style: AppTextStyles.body,
            decoration: _fieldDecoration(l10n.emailLabel, colors),
            validator: _validateEmail,
            onFieldSubmitted: isReset ? (_) => _submit() : null,
          ),
          if (!isReset) ...[
            const SizedBox(height: 12),
            TextFormField(
              key: kPasswordFieldKey,
              controller: _passwordController,
              enabled: !_busy,
              obscureText: _obscured,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              // `newPassword` on sign-up is what makes iOS offer to generate and save
              // one rather than autofill an existing credential into a new account.
              autofillHints: [
                _mode == _Mode.signUp
                    ? AutofillHints.newPassword
                    : AutofillHints.password,
              ],
              style: AppTextStyles.body,
              decoration: _fieldDecoration(l10n.passwordLabel, colors).copyWith(
                // **A reveal toggle instead of a confirm-password field.** It catches a
                // typo before submitting rather than after, in one field rather than two,
                // and password reset is the real backstop either way.
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscured ? Icons.visibility_off : Icons.visibility,
                    color: colors.secondaryText,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscured = !_obscured),
                ),
              ),
              validator: _validatePassword,
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: AppTextStyles.body.copyWith(color: softRedColor),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedActionButton(
            key: kEmailAuthSubmitKey,
            height: 44,
            buttonText: switch (_mode) {
              _Mode.signIn => l10n.emailAuthSignIn,
              _Mode.signUp => l10n.emailAuthSignUp,
              _Mode.reset => l10n.emailAuthSendReset,
            },
            activated: !_busy,
            onPressed: _busy ? null : _submit,
          ),
          const SizedBox(height: 8),
          // Reset is reached from sign-in and returns there, so it offers one way back
          // rather than the two-way toggle the other modes share.
          if (isReset)
            _LinkButton(
              label: l10n.emailAuthSignIn,
              onPressed: _busy ? null : () => _switchTo(_Mode.signIn),
            )
          else ...[
            if (_mode == _Mode.signIn)
              _LinkButton(
                label: l10n.emailAuthForgot,
                onPressed: _busy ? null : () => _switchTo(_Mode.reset),
              ),
            _LinkButton(
              label: _mode == _Mode.signIn
                  ? l10n.emailAuthToSignUp
                  : l10n.emailAuthToSignIn,
              onPressed: _busy
                  ? null
                  : () => _switchTo(
                      _mode == _Mode.signIn ? _Mode.signUp : _Mode.signIn,
                    ),
            ),
          ],
        ],
      ),
    );
  }

  /// The app's existing field treatment: filled, `surfaceVariant`, no visible border.
  /// Copied from the Settings sheets rather than invented, so a text field looks like a
  /// text field everywhere in the app.
  InputDecoration _fieldDecoration(String label, AppColors colors) {
    return InputDecoration(
      hintText: label,
      hintStyle: TextStyle(color: colors.secondaryText),
      filled: true,
      fillColor: colors.surfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      // Spelled out because `border` alone does not cover the focused and error states,
      // which fall back to the theme's underline and drew a stray line under the fill.
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.brand, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: softRedColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: softRedColor, width: 1.5),
      ),
      errorStyle: AppTextStyles.label.copyWith(color: softRedColor),
    );
  }
}

/// A text-only control for the page's three lateral moves.
///
/// `TextButton` rather than [ElevatedActionButton]: these change what the form is for, they
/// do not submit it, and a second filled button under the first would compete with it.
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: AppTextStyles.body.copyWith(color: context.colors.brandText),
      ),
    );
  }
}
