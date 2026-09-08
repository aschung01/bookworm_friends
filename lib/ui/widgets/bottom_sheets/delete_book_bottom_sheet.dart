import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/material.dart';

Future<void> showDeleteBookBottomSheet(
  BuildContext context, {
  required VoidCallback onDeletePressed,
}) {
  final l10n = AppLocalizations.of(context);
  return CNBottomSheet.show(
    context: context,
    builder: (context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.deleteConfirmTitle, style: AppTextStyles.subtitle),
          const SizedBox(height: 8),
          Text(
            l10n.deleteBookWarning,
            style: AppTextStyles.body.copyWith(
              color: context.colors.secondaryText,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedActionButton(
                  height: 44,
                  buttonText: l10n.cancel,
                  backgroundColor: context.colors.surfaceVariant,
                  textStyle: AppTextStyles.label,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedActionButton(
                  height: 44,
                  buttonText: l10n.delete,
                  backgroundColor: softRedColor,
                  isDestructive: true,
                  onPressed: onDeletePressed,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
