import 'package:awesome_emoji_picker/awesome_emoji_picker.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/headers/search_header.dart'
    show kSearchPillRadius;
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

/// How tall the emoji grid should be, given the screen and the keyboard.
///
/// Pulled out of the sheet so it can be tested without a modal route, and so the
/// reasoning is somewhere other than a widget tree.
///
/// [keyboardInset] is subtracted rather than ignored. Focusing the search field
/// used to leave two visible rows: the sheet neither lifted nor shrank, so the
/// keyboard covered the grid in the one flow where you most need to see results.
/// The inset is spent once — taken off the grid here, and added to the sheet's
/// bottom padding so nothing hides behind the keyboard either.
///
/// The 240 floor is about four rows. Below that the grid stops being worth
/// shrinking, and on a small phone with a tall keyboard the sheet is better off
/// overflowing into its own scroll than collapsing to a sliver.
double emojiGridHeight({
  required double screenHeight,
  required double keyboardInset,
}) {
  return ((screenHeight * 0.55) - keyboardInset).clamp(240.0, 460.0);
}

/// Presents the emoji picker in a sheet.
///
/// [selected] is the emoji the viewer already holds. It is marked in the grid,
/// which matters because praise is one-per-person: the same emoji withdraws it
/// and any other replaces it, so the sheet has to be able to say where you stand.
///
/// There used to be a strip above the grid repeating [selected] with an explicit
/// "Remove" button. It is gone. The marked cell already says which emoji is
/// yours, and tapping it already withdraws — `praiseTapFor` reads a tap on what
/// you hold as removal — so the strip restated one thing and duplicated the
/// other. It also cost: shared between praise and the profile-emoji picker, it
/// captioned avatar emoji as "Your praise" until the label was parameterised, and
/// a label that has to be threaded through two callers to stay correct is a lot
/// of surface for a caption.
Future<void> showEmojiBottomSheet(
  BuildContext context, {
  required void Function(String emoji) onEmojiPressed,
  String? selected,
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
    builder: (context) {
      // The inset is spent once: taken off the grid by [emojiGridHeight], and
      // added to the padding below so nothing hides behind the keyboard either.
      final keyboard = MediaQuery.viewInsetsOf(context).bottom;
      final gridHeight = emojiGridHeight(
        screenHeight: MediaQuery.sizeOf(context).height,
        keyboardInset: keyboard,
      );

      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: 24 + keyboard,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title ?? l10n.selectComplimentEmoji,
              style: AppTextStyles.subtitle,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: gridHeight,
              child: PraiseEmojiPicker(
                selected: selected,
                onEmojiSelected: onEmojiPressed,
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// The picker, wired to the app's strings and marking [selected].
///
/// Split out from the sheet so the grid can be pumped in a test without a modal
/// route. That mark is now the only thing telling you which emoji is already
/// yours, since the strip that used to repeat it above the grid is gone — so the
/// marked cell is load-bearing rather than decorative. Note the widget class is
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

    // The package's search field is a plain `TextField` that sets only its hint,
    // its two icons, `filled: true` and a content padding — no border, no fill
    // colour, no hint style. Everything else came from Material's defaults, and
    // since `AppTheme` defines no `inputDecorationTheme`, that meant a grey slab
    // with a hard underline that turned brand-green on focus: the one search
    // field in the app that did not look like the other two.
    //
    // Restyled from here rather than by forking the package, which works
    // precisely because those properties are left unset — the field even reads
    // `prefixIconColor` and `suffixIconColor` off the theme. This keeps the
    // package's controller sync, clear button and results wiring untouched.
    final pill = OutlineInputBorder(
      borderRadius: BorderRadius.circular(kSearchPillRadius),
      borderSide: BorderSide.none,
    );

    return Theme(
      data: Theme.of(context).copyWith(
        // The picker wraps itself in `ColoredBox(scaffoldBackgroundColor)` and
        // paints its sticky category headers the same, which is the wrong token
        // inside a sheet: `scaffoldBackgroundColor` is `pageBackground`
        // (#F8F9FA), while the sheet is `sheetBackground` (#EFF5EF, the
        // deliberate mint tint pinned by `sheet_theme_test.dart`). The two are
        // close enough to look like a rendering artefact and far enough apart to
        // be a visible seam under the search field. Pointing the token at the
        // sheet fixes the grid and the headers together.
        scaffoldBackgroundColor: colors.sheetBackground,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colors.surfaceVariant,
          // All three, not just `border`: the enabled and focused states are
          // where the underline and its green focus variant actually come from.
          border: pill,
          enabledBorder: pill,
          focusedBorder: pill,
          hintStyle: AppTextStyles.body.copyWith(color: colors.secondaryText),
          prefixIconColor: colors.secondaryText,
          suffixIconColor: colors.secondaryText,
          // Material reserves a 48x48 box for `prefixIcon`. The package's
          // magnifier is 24px centred in it, which is the dead space that had the
          // icon floating away from the placeholder.
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 36,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
        ),
      ),
      child: _picker(l10n, colors),
    );
  }

  Widget _picker(AppLocalizations l10n, AppColors colors) {
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
          child: Text(
            emoji.char,
            style: const TextStyle(fontSize: kEmojiGlyphSize),
          ),
        );
      },
    );
  }
}
