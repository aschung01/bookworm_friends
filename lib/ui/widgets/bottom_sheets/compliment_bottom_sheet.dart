import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/praise_palette.dart';
import 'package:flutter/material.dart';

/// Presents [PraisePalette] in a sheet.
///
/// [selected] marks the caller's current emoji, so re-opening the sheet shows
/// where they stand rather than offering sixteen equally-fresh choices.
Future<void> showEmojiBottomSheet(
  BuildContext context, {
  required void Function(String emoji) onEmojiPressed,
  String? selected,
}) {
  final l10n = AppLocalizations.of(context);
  return CNBottomSheet.show(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.selectComplimentEmoji,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          PraisePalette(selected: selected, onPick: onEmojiPressed),
        ],
      ),
    ),
  );
}
