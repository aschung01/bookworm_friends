import 'package:awesome_emoji_picker/awesome_emoji_picker.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The emoji praise the app used to offer, now only a starting point.
///
/// These sixteen were the whole vocabulary until the picker replaced them. They
/// survive as the seed for an empty Recents row, so a first-time user meets a
/// sensible handful instead of a blank shelf above three and a half thousand
/// emoji. Nothing restricts praise to this list.
const List<String> seedEmojis = [
  '👏',
  '🎉',
  '❤️',
  '🔥',
  '⭐',
  '💪',
  '😍',
  '🥰',
  '👍',
  '✨',
  '🎊',
  '💯',
  '🙌',
  '😎',
  '🤩',
  '💐',
];

/// Fills an untouched Recents row with [seedEmojis].
///
/// [EmojiRepository] loads its recents from `SharedPreferences` asynchronously,
/// so the load has to be awaited before "is it empty?" means anything --
/// checking too early would overwrite a real history with the seed.
///
/// The repository is a process-wide singleton whose `prefsKey` is fixed by
/// whoever constructs it first, and [EmojiPicker] constructs it itself without
/// one. So praise and the profile emoji necessarily share one Recents store.
/// That is a small cost -- both are lists of friendly emoji, and the profile
/// emoji is changed once in a while, not constantly -- and the alternative was
/// resetting the singleton around every sheet.
Future<void> seedRecentEmojis() async {
  final repository = EmojiRepository();
  await repository.loadRecentEmoji();
  if (repository.getRecents().isEmpty) {
    await repository.setRecentEmojis(
      seedEmojis.map(EmojiModel.fromString).toList(),
    );
  }
}

/// Presents the emoji picker in a sheet.
///
/// [selected] is the emoji the viewer already holds. It is marked in the grid
/// and repeated in a strip above it, because praise is one-per-person: the same
/// emoji withdraws it and any other replaces it, and neither reads correctly if
/// the sheet cannot say where you stand. [onRemove], when given, is the strip's
/// explicit way out -- the grid alone cannot express "take it back" to someone
/// whose praise is a legacy emoji sitting hundreds of rows down.
Future<void> showEmojiBottomSheet(
  BuildContext context, {
  required void Function(String emoji) onEmojiPressed,
  String? selected,
  VoidCallback? onRemove,
  String? title,
}) async {
  final l10n = AppLocalizations.of(context);
  await seedRecentEmojis();
  if (!context.mounted) return;

  return CNBottomSheet.show(
    context: context,
    // The picker is a tall widget with its own scrolling grid, so the sheet has
    // to be told it may exceed the 9/16 of the screen `showModalBottomSheet`
    // otherwise caps it at.
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title ?? l10n.selectComplimentEmoji,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (selected != null)
            CurrentPraiseStrip(emoji: selected, onRemove: onRemove),
          const SizedBox(height: 12),
          SizedBox(
            height: (MediaQuery.sizeOf(context).height * 0.55).clamp(320, 460),
            child: PraiseEmojiPicker(
              selected: selected,
              onEmojiSelected: onEmojiPressed,
            ),
          ),
        ],
      ),
    ),
  );
}

/// The picker, wired to the app's strings and marking [selected].
///
/// Split out from the sheet so the grid can be pumped in a test without a modal
/// route, the way [CurrentPraiseStrip] can. Note the widget class is
/// `AwesomeEmojiPicker`, not the `EmojiPicker` the package's README shows.
class PraiseEmojiPicker extends StatelessWidget {
  const PraiseEmojiPicker({
    super.key,
    required this.onEmojiSelected,
    this.selected,
  });

  final String? selected;
  final void Function(String emoji) onEmojiSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    return AwesomeEmojiPicker(
      onEmojiSelected: (EmojiModel emoji) => onEmojiSelected(emoji.char),
      searchHintText: l10n.emojiSearchHint,
      searchResultsText: l10n.emojiSearchResults,
      skinToneLabel: l10n.emojiSkinTone,
      // Untranslated English categories in a Korean app read as unfinished. The
      // keys are the package's own category names, which is how it matches them.
      categoryTranslations: {
        'Recents': l10n.emojiCategoryRecents,
        'Smileys & People': l10n.emojiCategorySmileysAndPeople,
        'Animals & Nature': l10n.emojiCategoryAnimalsAndNature,
        'Food & Drink': l10n.emojiCategoryFoodAndDrink,
        'Activities': l10n.emojiCategoryActivities,
        'Travel & Places': l10n.emojiCategoryTravelAndPlaces,
        'Objects': l10n.emojiCategoryObjects,
        'Symbols': l10n.emojiCategorySymbols,
        'Flags': l10n.emojiCategoryFlags,
      },
      categoryIconColor: colors.secondaryText,
      categoryIconSelectedColor: colors.brandText,
      // The package's own cell renderer is a bare `EmojiWidget`, so overriding it
      // costs nothing and buys the one thing the picker has no concept of: which
      // emoji is already yours. Usually visible without hunting, since your
      // praise is in Recents.
      emojiRenderer: (EmojiModel emoji) {
        final isMine = emoji.char == selected;
        return Container(
          key: ValueKey('praise-cell-${emoji.char}'),
          decoration: isMine
              ? BoxDecoration(
                  color: colors.brand.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.brandFill, width: 2),
                )
              : null,
          alignment: Alignment.center,
          child: Text(emoji.char, style: const TextStyle(fontSize: 24)),
        );
      },
    );
  }
}

/// "Here is your praise, and here is how to take it back."
///
/// Absent entirely when the viewer holds no praise, so it never offers a
/// withdrawal that cannot happen.
class CurrentPraiseStrip extends StatelessWidget {
  const CurrentPraiseStrip({super.key, required this.emoji, this.onRemove});

  final String emoji;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            l10n.yourPraise,
            style: TextStyle(fontSize: 13, color: colors.secondaryText),
          ),
          const SizedBox(width: 8),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.pageBackground,
              border: Border.all(color: colors.brand.withValues(alpha: 0.3)),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 14)),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            TextButton(
              onPressed: onRemove,
              style: TextButton.styleFrom(
                foregroundColor: colors.brandText,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(l10n.removePraise),
            ),
          ],
        ],
      ),
    );
  }
}
