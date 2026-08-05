import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

const List<String> _emojis = [
  '👏', '🎉', '❤️', '🔥', '⭐', '💪', '😍', '🥰',
  '👍', '✨', '🎊', '💯', '🙌', '😎', '🤩', '💐',
];

Future<void> showEmojiBottomSheet(
  BuildContext context, {
  required void Function(String emoji) onEmojiPressed,
}) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.selectComplimentEmoji,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkPrimaryColor),
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: _emojis.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => onEmojiPressed(_emojis[i]),
              child: Container(
                decoration: BoxDecoration(
                  color: lightGrayColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(_emojis[i], style: const TextStyle(fontSize: 24)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
