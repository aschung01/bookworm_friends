import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/material.dart';

Future<void> showDeleteShelfBottomSheet(
  BuildContext context, {
  required VoidCallback onDeletePressed,
}) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.deleteShelfConfirmTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: darkPrimaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.deleteShelfWarning,
            style: const TextStyle(fontSize: 14, color: grayColor),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedActionButton(
                  height: 44,
                  buttonText: l10n.cancel,
                  backgroundColor: lightGrayColor,
                  textStyle: const TextStyle(color: darkPrimaryColor, fontSize: 14),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedActionButton(
                  height: 44,
                  buttonText: l10n.delete,
                  backgroundColor: softRedColor,
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
