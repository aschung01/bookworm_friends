import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/material.dart';

Future<void> showWriteMemoBottomSheet(
  BuildContext context, {
  required TextEditingController controller,
  required VoidCallback onSavePressed,
}) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Padding(
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
            l10n.writeMemoTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: darkPrimaryColor,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: l10n.memoHint,
              hintStyle: const TextStyle(color: grayColor),
              filled: true,
              fillColor: lightGrayColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(16),
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
