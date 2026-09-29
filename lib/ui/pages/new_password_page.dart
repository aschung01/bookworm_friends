import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/email_auth_error.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/ui/pages/email_auth_page.dart'
    show kMinPasswordLength;
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';

@visibleForTesting
const Key kNewPasswordFieldKey = Key('newPasswordField');

@visibleForTesting
const Key kNewPasswordSaveKey = Key('newPasswordSave');

/// Chooses a new password, after a reset link has been exchanged.
///
/// **Presented over whatever the reader landed on, not instead of it.** A recovery session
/// is a real session, so `AuthPage._leaveIfSignedIn` and `SplashPage` route normally and
/// `PasswordRecoveryListener` pushes this on top -- the same "push onto the destination
/// rather than replace it" rule `_spendPendingInvite` and `_pushConsentIfPending` follow, so
/// dismissing leaves the reader somewhere real.
///
/// **Dismissible, and that is a choice.** Backing out leaves them signed in with their old
/// password, which is precisely what the session is; a screen with no way out would be worse
/// for the reader who tapped the link by accident. Dismissing calls
/// [AuthNotifier.dismissRecovery] so the listener does not present it again.
class NewPasswordPage extends ConsumerStatefulWidget {
  const NewPasswordPage({super.key});

  @override
  ConsumerState<NewPasswordPage> createState() => _NewPasswordPageState();
}

class _NewPasswordPageState extends ConsumerState<NewPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  bool _busy = false;
  bool _obscured = true;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authProvider.notifier).updatePassword(_controller.text);
      if (!mounted) return;
      // Popped by this page rather than by the listener: the listener's job is presenting,
      // and a success that closed the screen from outside would also close it for a
      // failure it could not see.
      Navigator.pop(context);
      EasyLoading.showSuccess(l10n.newPasswordSaved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = emailAuthError(error, l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _dismiss() {
    ref.read(authProvider.notifier).dismissRecovery();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        backgroundColor: colors.pageBackground,
        surfaceTintColor: Colors.transparent,
        // An ✕ rather than a ⟨: a full-screen cover is not a level deeper into anything,
        // and it is not back-swipe dismissible either. Same reasoning as `ScanBookPage`.
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _busy ? null : _dismiss,
        ),
        title: Text(l10n.newPasswordTitle, style: AppTextStyles.subtitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 32,
            right: 32,
            top: 24,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: kNewPasswordFieldKey,
                  controller: _controller,
                  autofocus: true,
                  enabled: !_busy,
                  obscureText: _obscured,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.newPassword],
                  style: AppTextStyles.body,
                  decoration: InputDecoration(
                    hintText: l10n.newPasswordLabel,
                    hintStyle: TextStyle(color: colors.secondaryText),
                    filled: true,
                    fillColor: colors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colors.brand, width: 1.5),
                    ),
                    errorStyle: AppTextStyles.label.copyWith(
                      color: softRedColor,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscured ? Icons.visibility_off : Icons.visibility,
                        color: colors.secondaryText,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscured = !_obscured),
                    ),
                  ),
                  validator: (value) =>
                      (value ?? '').length < kMinPasswordLength
                      ? l10n.emailAuthPasswordTooShort
                      : null,
                  onFieldSubmitted: (_) => _save(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: AppTextStyles.body.copyWith(color: softRedColor),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedActionButton(
                  key: kNewPasswordSaveKey,
                  height: 44,
                  buttonText: l10n.newPasswordSave,
                  activated: !_busy,
                  onPressed: _busy ? null : _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
