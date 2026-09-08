import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/material.dart';

Future<void> showUpdateShelfNameBottomSheet(
  BuildContext context, {
  required TextEditingController controller,
  required VoidCallback onSavePressed,
  bool update = true,
}) {
  final l10n = AppLocalizations.of(context);
  return CNBottomSheet.show(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        left: 30,
        right: 30,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            update ? l10n.editShelfName : l10n.newShelf,
            style: AppTextStyles.subtitle,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: l10n.shelfNameHint,
              hintStyle: TextStyle(color: context.colors.secondaryText),
              filled: true,
              fillColor: context.colors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedActionButton(
              height: 44,
              buttonText: l10n.save,
              onPressed: onSavePressed,
            ),
          ),
        ],
      ),
    ),
  );
}
