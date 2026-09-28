import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/models/sign_in_provider.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:flutter/material.dart';

/// The account's address, with one mark per sign-in door in front of it.
///
/// Its own widget rather than an inline `Row` in `settings_page.dart` so it can be
/// pumped on its own: the defect this replaced was in the row, and reaching the row
/// through `SettingsPage` means standing up the profile, theme, book-source and Libby
/// providers plus `package_info_plus` and `in_app_review` first.
///
/// Two things the `provider == 'apple' ? Apple : Google` this replaced got wrong:
///
/// - It drew **one** mark, off the field that records how the account was *opened*
///   rather than how it can be opened now, so a Google account with Apple linked showed
///   Google alone. See [linkedSignInProviders] for why that field never updates.
/// - Its `else` branch claimed *Google* for everything that was not Apple, so an
///   email-only account wore a Google mark it does not have. Anything unrecognised now
///   draws nothing, leaving the row as the address by itself, because a wrong mark is
///   worse than no mark -- it is a claim about which account this is.
class SignInIdentityRow extends StatelessWidget {
  /// `User.appMetadata`. Nullable because the row is built before the session is.
  final Map<String, dynamic>? appMetadata;
  final String email;

  const SignInIdentityRow({
    super.key,
    required this.appMetadata,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final mark in _marks(context)) ...[
          mark,
          const SizedBox(width: 10),
        ],
        Text(email, style: AppTextStyles.label),
      ],
    );
  }

  /// `AppleLogo` is tinted to the body ink beside it. It used to draw `AppleBlackIcon`,
  /// which carried an opaque *white* 44x44 plate behind a black glyph -- right-looking
  /// on the light theme's surface by accident, and a bright white square with a nearly
  /// invisible apple on the dark theme's #1E1E1E.
  List<Widget> _marks(BuildContext context) => [
    for (final provider in linkedSignInProviders(appMetadata))
      if (provider == 'apple')
        AppleLogo(height: 18, color: context.colors.primaryText)
      else if (provider == 'google')
        const GoogleIcon(width: 18, height: 18),
  ];
}
