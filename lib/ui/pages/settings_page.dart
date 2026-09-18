import 'package:bookworm_friends/ui/widgets/native_glass.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_back_button.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/menu_bottom_sheet.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'dart:math';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/handle.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/providers/libby_library_provider.dart';
import 'package:bookworm_friends/providers/profile_provider.dart';
import 'package:bookworm_friends/providers/theme_provider.dart';
import 'package:bookworm_friends/services/store_links_service.dart'
    show StoreId, storesForLocale;

import 'package:bookworm_friends/ui/widgets/avatar_circle.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/compliment_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/libby_library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/dialogs/adaptive_dialog_action.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// The handle field, so a test types into a control rather than into the only `TextField`
/// that happens to be on screen.
const Key kHandleFieldKey = Key('settings-handle-field');

/// The handle sheet's `Save`, which is inert until the value could be accepted.
const Key kHandleSaveKey = Key('settings-handle-save');

const String _termsOfUseUrl =
    'https://bookwormfriends.notion.site/ed87960f6f9b4db8addfd36cc906bc92';
const String _privacyPolicyUrl =
    'https://bookwormfriends.notion.site/a4ffdbd423cd47cca55eac821283f728';
const String _personalInfoUrl = 'https://www.instagram.com/andrewchung01/';
const String _bugReportUrl = 'https://www.instagram.com/p/Ciea-GHJzra/';
const String _feedbackUrl = 'https://www.instagram.com/p/Ciebbsypkso/';
const String _noticeUrl =
    'https://bookwormfriends.notion.site/485dd45c334a42149f2cbb4c8c1a7239';
const String _helpUrl =
    'https://bookwormfriends.notion.site/503f3818b90949008cdcf9b8913d1053';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _usernameController = TextEditingController();
  final _handleController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _handleController.dispose();
    super.dispose();
  }

  /// The one definition of the edit-profile menu.
  ///
  /// Both presentations are built from this: the native `CNPopupMenuButton` and
  /// the `showMenuBottomSheet` fallback. They used to list the same actions
  /// twice, with the native one dispatching on a hard-coded index — which would
  /// have silently mis-routed every entry the moment a new one was inserted
  /// anywhere but the end.
  ///
  /// Photo and emoji are mutually exclusive avatar modes, so the menu offers one
  /// or the other rather than both. In photo mode the stored emoji is untouched
  /// and simply not editable — removing the photo hands it straight back, which is
  /// why "Remove photo" needs no confirmation.
  List<_ProfileEditAction> _profileEditActions(AppLocalizations l10n) {
    final hasPhoto = ref.read(profileProvider).valueOrNull?.avatarPath != null;
    return [
      _ProfileEditAction(
        // "Set" when there is nothing there yet, "Change" when there is. The
        // label is the only thing telling you which of the two modes you are in.
        label: hasPhoto ? l10n.changePhoto : l10n.setPhoto,
        symbol: 'photo',
        icon: Icons.photo_camera_back_outlined,
        onPressed: _onUpdatePhotoPressed,
      ),
      if (hasPhoto)
        _ProfileEditAction(
          label: l10n.removePhoto,
          // `trash` rather than something photo-specific like
          // `photo.badge.exclamationmark`: an SF Symbol name that does not exist
          // is discarded silently by the native menu, leaving the row with no
          // icon at all (see `native_glass.dart`). `trash` and `photo` have both
          // existed since SF Symbols 1.
          symbol: 'trash',
          icon: Icons.delete_outline,
          onPressed: _onRemovePhotoPressed,
        )
      else
        _ProfileEditAction(
          label: l10n.changeEmoji,
          symbol: 'face.smiling',
          icon: Icons.emoji_emotions_outlined,
          onPressed: _onUpdateEmojiPressed,
        ),
      _ProfileEditAction(
        label: l10n.changeUsername,
        symbol: 'person',
        icon: Icons.person_outline,
        onPressed: _onUpdateUsernamePressed,
      ),
      _ProfileEditAction(
        label: l10n.changeHandle,
        // `at` is the SF Symbol for `@`, which is the shape the handle is printed in
        // on the card's strip. See `native_glass.dart` on why a symbol name that does
        // not exist is silently dropped, leaving a row with no icon: `at` has existed
        // since SF Symbols 1.
        symbol: 'at',
        icon: Icons.alternate_email,
        onPressed: _onUpdateHandlePressed,
      ),
    ];
  }

  void _onEditProfilePressed() {
    final l10n = AppLocalizations.of(context);
    showMenuBottomSheet(
      context: context,
      title: l10n.editProfile,
      actions: [
        for (final action in _profileEditActions(l10n))
          MenuAction(
            label: action.label,
            icon: action.icon,
            onPressed: action.onPressed,
          ),
      ],
    );
  }

  /// Picks a photo, resized and re-encoded by the plugin before it ever reaches
  /// Dart.
  ///
  /// 512px and quality 80 lands around 40–70KB, which is why there is no
  /// separate compression package. There is no cropper either: the avatar draws
  /// at 40pt (60pt in this page's header), and `BoxFit.cover` inside a circle is
  /// the crop. Resizing here also keeps us off Supabase's on-the-fly image
  /// transformations, which are a paid-plan feature.
  Future<void> _onUpdatePhotoPressed() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    await ref
        .read(updateProfileProvider)
        .updateAvatar(bytes, avatarExtensionFor(picked.name));
  }

  Future<void> _onRemovePhotoPressed() =>
      ref.read(updateProfileProvider).removeAvatar();

  void _onUpdateEmojiPressed() {
    showEmojiBottomSheet(
      context,
      // Same picker, different job: this one names an avatar rather than praising
      // a book, so it carries its own title. The grid marks the emoji you
      // currently wear.
      title: AppLocalizations.of(context).changeEmoji,
      selected: ref.read(profileProvider).valueOrNull?.emoji,
      onEmojiPressed: (emoji) async {
        Navigator.pop(context);
        await ref.read(updateProfileProvider).updateEmoji(emoji);
      },
    );
  }

  void _onUpdateUsernamePressed() {
    final profile = ref.read(profileProvider).valueOrNull;
    _usernameController.text = profile?.username ?? '';
    CNBottomSheet.show<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return Padding(
          padding: EdgeInsets.only(
            left: 30,
            right: 30,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.changeUsername, style: AppTextStyles.subtitle),
              const SizedBox(height: 20),
              TextField(
                controller: _usernameController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.newUsername,
                  filled: true,
                  fillColor: context.colors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedActionButton(
                  height: 44,
                  buttonText: l10n.save,
                  onPressed: () async {
                    Navigator.pop(context);
                    await ref
                        .read(updateProfileProvider)
                        .updateUsername(_usernameController.text.trim());
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The handle editor.
  ///
  /// **Deliberately not modelled on the username sheet above it**, in one respect: the
  /// username sheet saves on tap and reports failure with a toast, which is fine for a
  /// field with no format. A handle has four separate ways to be wrong and a uniqueness
  /// constraint, so the sheet validates live and keeps `Save` inert until the value could
  /// possibly be accepted — the uniqueness check still happens at the database, because it
  /// is the only place that can answer it.
  ///
  /// The field normalises as the reader types and **drops** what it cannot use rather than
  /// transliterating it. That is the same refusal `cardStripToken` makes, for the same
  /// reason: a Korean name run through a converter comes out as a remnant that reads as a
  /// fault, and an empty field at least says "choose something".
  void _onUpdateHandlePressed() {
    final profile = ref.read(profileProvider).valueOrNull;
    _handleController.text = profile?.handle ?? '';
    CNBottomSheet.show<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return Padding(
          padding: EdgeInsets.only(
            left: 30,
            right: 30,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _handleController,
            builder: (context, value, _) {
              final problem = handleProblem(value.text);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.changeHandle,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.subtitle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.handleExplainer,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(
                      color: context.colors.primaryText.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: kHandleFieldKey,
                    controller: _handleController,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    onChanged: (raw) {
                      final cleaned = normaliseHandleInput(raw);
                      if (cleaned == raw) return;
                      // Selection pinned to the end rather than preserved: the
                      // normalisation can remove characters anywhere in the string, so
                      // any restored offset would land somewhere the reader did not put
                      // it.
                      _handleController.value = TextEditingValue(
                        text: cleaned,
                        selection: TextSelection.collapsed(
                          offset: cleaned.length,
                        ),
                      );
                    },
                    decoration: InputDecoration(
                      prefixText: '@',
                      hintText: l10n.handleHint,
                      // Empty is not an error — it is where the reader starts.
                      errorText: switch (problem) {
                        HandleProblem.none || HandleProblem.empty => null,
                        _ => l10n.handleInvalid,
                      },
                      filled: true,
                      fillColor: context.colors.surfaceVariant,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedActionButton(
                      key: kHandleSaveKey,
                      height: 44,
                      buttonText: l10n.save,
                      onPressed: problem == HandleProblem.none
                          ? () async {
                              Navigator.pop(context);
                              await ref
                                  .read(updateProfileProvider)
                                  .updateHandle(_handleController.text);
                            }
                          : null,
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showDeleteAccountDialog() {
    showAdaptiveDialog<void>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog.adaptive(
          title: Text(l10n.deleteAccount),
          content: Text(l10n.deleteAccountConfirmMessage),
          actions: [
            AdaptiveDialogAction(
              label: l10n.cancel,
              textColor: context.colors.secondaryText,
              onPressed: () => Navigator.pop(context),
            ),
            AdaptiveDialogAction(
              label: l10n.deleteAccountShort,
              isDestructive: true,
              onPressed: () async {
                Navigator.pop(context);
                EasyLoading.show();
                final success = await ref
                    .read(authProvider.notifier)
                    .deleteAccount();
                if (success) {
                  EasyLoading.showSuccess(l10n.deleteAccountDone);
                  if (mounted) {
                    Navigator.pushReplacementNamed(context, AppRoutes.auth);
                  }
                } else {
                  EasyLoading.showError(l10n.deleteAccountFailed);
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _onInAppReviewPressed() async {
    final inAppReview = InAppReview.instance;
    if (await inAppReview.isAvailable()) {
      inAppReview.requestReview();
    } else {
      inAppReview.openStoreListing();
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  }

  /// Credits, over Flutter's aggregated licence page.
  ///
  /// `awesome_emoji_picker` is MIT with an attribution requirement -- visible
  /// credit to its authors -- which pub.dev does not surface, since it reports
  /// the licence as unknown. The licence page alone would technically carry it,
  /// buried among every transitive dependency, so the names are stated in the
  /// page's own header where someone might actually read them. The app had no
  /// licence screen at all before this, which it owed regardless.
  ///
  /// The store marks are here for the same reason and one stronger: Libby's mark
  /// comes from Arcticons under **CC BY-SA 4.0**, which requires attribution as a
  /// licence condition rather than as a courtesy. Bundled SVG assets never appear
  /// in Flutter's aggregated page at all, since that only collects `LICENSE`
  /// files from packages -- so if this line is removed, nothing else carries it.
  void _onAcknowledgementsPressed() {
    final l10n = AppLocalizations.of(context);
    showLicensePage(
      context: context,
      applicationName: l10n.appTitle,
      applicationLegalese:
          '${l10n.emojiPickerCredit}\n\n${l10n.storeMarksCredit}',
    );
  }

  static String _bookSourceLabel(
    AppLocalizations l10n,
    BookSourcePreference pref,
  ) {
    switch (pref) {
      case BookSourcePreference.auto:
        return l10n.bookSourceAuto;
      case BookSourcePreference.kakao:
        return l10n.bookSourceKakao;
      case BookSourcePreference.googleBooks:
        return l10n.bookSourceGoogle;
    }
  }

  void _showBookSourcePicker() {
    final current = ref.read(bookSourcePreferenceProvider);
    final l10n = AppLocalizations.of(context);
    showMenuBottomSheet(
      context: context,
      title: l10n.bookSearchSource,
      actions: [
        for (final pref in BookSourcePreference.values)
          MenuAction(
            label: _bookSourceLabel(l10n, pref),
            isSelected: pref == current,
            onPressed: () =>
                ref.read(bookSourcePreferenceProvider.notifier).set(pref),
          ),
      ],
    );
  }

  /// Opens the same picker the book sheet opens on a first Libby tap.
  ///
  /// **The same sheet, deliberately.** A stored answer needs a way back — people
  /// move, join a second system, or mistype — and a second, Settings-shaped library
  /// chooser would be a second thing to keep in step with Libby's endpoint.
  ///
  /// Dismissing here changes nothing, which is the difference from the first-run
  /// ask: there the dismissal is an answer ("do not ask me again"), here it is just
  /// a cancel, and clearing is a separate deliberate action.
  Future<void> _showLibbyLibraryPicker() async {
    final chosen = await showLibbyLibrarySheet(context);
    if (chosen == null || !mounted) return;
    await ref
        .read(libbyLibraryProvider.notifier)
        .choose(chosen.key, chosen.name);
  }

  static String _appearanceLabel(AppLocalizations l10n, ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return l10n.appearanceSystem;
      case ThemeMode.light:
        return l10n.appearanceLight;
      case ThemeMode.dark:
        return l10n.appearanceDark;
    }
  }

  void _showAppearancePicker() {
    final current = ref.read(themeModeProvider);
    final l10n = AppLocalizations.of(context);
    showMenuBottomSheet(
      context: context,
      title: l10n.appearance,
      actions: [
        for (final mode in ThemeMode.values)
          MenuAction(
            label: _appearanceLabel(l10n, mode),
            isSelected: mode == current,
            onPressed: () => ref.read(themeModeProvider.notifier).set(mode),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authProvider);
    final profileAsync = ref.watch(profileProvider);
    final isAuthenticated = auth.status == AuthStatus.authenticated;

    final profile = profileAsync.valueOrNull;
    // Hoisted so the null check below promotes it; `profile?.handle` in the widget tree
    // would not.
    final handle = profile?.handle;

    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        elevation: 0,
        leading: const AdaptiveBackButton(),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              // Not a fixed 60 (the avatar's height) any more: the handle line below
              // the username is conditional, so the block has two legitimate heights and
              // a fixed box would clip the taller one.
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: AvatarCircle(
                      emoji: profile?.emoji,
                      avatarPath: profile?.avatarPath,
                      diameter: 60,
                      // 26, not half the diameter: this is the size the
                      // header has always drawn its glyph at.
                      emojiSize: 26,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          profile?.username ?? '???',
                          style: AppTextStyles.subtitle,
                        ),
                        // The one place a reader can *see* the handle they are told to
                        // pick. `Change handle` in the Edit profile menu opens a field
                        // seeded with the current value, but that is behind two taps, so
                        // until now the identity printed on an exported card was
                        // invisible from the app.
                        //
                        // Omitted rather than shown as a bare `@` when absent: `handle`
                        // is `NOT NULL` and generated at signup, so the only way here is
                        // a row read before the migration — a state where a lone `@`
                        // would read as a bug rather than as "unset". The `@` is added
                        // here and never stored, so it cannot end up inside the value.
                        if (handle != null && handle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '@$handle',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.label.copyWith(
                                color: context.colors.secondaryText,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 24),
              child: Center(
                // No longer swapped for a blank box while a sheet is open. That
                // branch existed because `_EditProfileButton` can be a *native*
                // `CNPopupMenuButton`, which is a platform view and therefore paints
                // above anything Flutter puts over it — including the follow-list
                // sheet, which is now gone along with the only thing that covered
                // this row.
                child: isAuthenticated
                    ? _EditProfileButton(
                        width: min(MediaQuery.of(context).size.width - 60, 330),
                        label: l10n.editProfile,
                        actions: _profileEditActions(l10n),
                        onFallbackPressed: _onEditProfilePressed,
                      )
                    : ElevatedActionButton(
                        width: min(MediaQuery.of(context).size.width - 60, 330),
                        height: 36,
                        borderRadius: 50,
                        textStyle: AppTextStyles.label.copyWith(
                          color: Colors.white,
                        ),
                        buttonText: l10n.login,
                        onPressed: () =>
                            Navigator.pushNamed(context, AppRoutes.auth),
                      ),
              ),
            ),
            _SettingsLabelItem(labelText: l10n.accountSection),
            _SettingsMenuItem(
              labelText: l10n.email,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (auth.user?.appMetadata['provider'] == 'apple')
                    const AppleBlackIcon(width: 18, height: 18)
                  else
                    const GoogleIcon(width: 18, height: 18),
                  const SizedBox(width: 10),
                  Text(auth.user?.email ?? '', style: AppTextStyles.label),
                ],
              ),
            ),
            // The "Allow profile search" switch stood here and is gone.
            //
            // It wrote `profiles.is_private`, and it gated handle search. Both are gone
            // with mutual friendship: visibility is friendship, and with no search there
            // is no directory to be absent from. Renaming it to something honest — "Let
            // anyone view my library" — was considered and rejected, because that is the
            // `public-profiles` design and it is the branch we did not take.
            const SizedBox(height: 12),
            _SettingsLabelItem(labelText: l10n.preferencesSection),
            _SettingsMenuItem(
              labelText: l10n.bookSearchSource,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _bookSourceLabel(
                      l10n,
                      ref.watch(bookSourcePreferenceProvider),
                    ),
                    style: AppTextStyles.label.copyWith(
                      color: context.colors.secondaryText,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              onTap: _showBookSourcePicker,
            ),
            // Sits beside the book-source picker because that row is already "which
            // catalogue does this app talk to", so this needs no new section and
            // nothing has to be explained twice.
            //
            // Shown only where a Libby row is offered at all: `storesForLocale('ko')`
            // is `[play, kindle]`, and a setting for a shop the reader never sees
            // would be a puzzle rather than a control.
            if (storesForLocale(
              Localizations.localeOf(context).languageCode,
            ).contains(StoreId.libby))
              _SettingsMenuItem(
                labelText: l10n.libbyLibrary,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ref.watch(libbyLibraryProvider).name ??
                          l10n.libbyLibraryNotSet,
                      style: AppTextStyles.label.copyWith(
                        color: context.colors.secondaryText,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
                onTap: _showLibbyLibraryPicker,
              ),
            _SettingsMenuItem(
              labelText: l10n.appearance,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _appearanceLabel(l10n, ref.watch(themeModeProvider)),
                    style: AppTextStyles.label.copyWith(
                      color: context.colors.secondaryText,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              onTap: _showAppearancePicker,
            ),
            const SizedBox(height: 12),
            _SettingsLabelItem(labelText: l10n.contactDevSection),
            _SettingsMenuItem(
              labelText: l10n.aboutDev,
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => _launchUrl(_personalInfoUrl),
            ),
            _SettingsMenuItem(
              labelText: l10n.reportBug,
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => _launchUrl(_bugReportUrl),
            ),
            _SettingsMenuItem(
              labelText: l10n.writeFeedback,
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => _launchUrl(_feedbackUrl),
            ),
            _SettingsMenuItem(
              labelText: l10n.leaveReview,
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: _onInAppReviewPressed,
            ),
            const SizedBox(height: 12),
            _SettingsLabelItem(labelText: l10n.infoSection),
            _SettingsMenuItem(
              labelText: l10n.notices,
              onTap: () => _launchUrl(_noticeUrl),
            ),
            _SettingsMenuItem(
              labelText: l10n.userGuide,
              onTap: () => _launchUrl(_helpUrl),
            ),
            _SettingsMenuItem(
              labelText: l10n.termsOfUse,
              onTap: () => _launchUrl(_termsOfUseUrl),
            ),
            _SettingsMenuItem(
              labelText: l10n.privacyPolicy,
              onTap: () => _launchUrl(_privacyPolicyUrl),
            ),
            _SettingsMenuItem(
              labelText: l10n.acknowledgements,
              onTap: _onAcknowledgementsPressed,
            ),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version = snapshot.data?.version ?? '';
                final buildNumber = snapshot.data?.buildNumber ?? '';
                return _SettingsMenuItem(
                  labelText: l10n.appVersion,
                  trailing: Text(
                    version.isNotEmpty ? 'v$version ($buildNumber)' : '',
                    style: AppTextStyles.label.copyWith(
                      color: context.colors.secondaryText,
                    ),
                  ),
                );
              },
            ),
            if (isAuthenticated) ...[
              _SettingsMenuItem(
                labelText: l10n.logout,
                onTap: () async {
                  await ref.read(authProvider.notifier).signOut();
                  if (mounted) {
                    Navigator.pushReplacementNamed(context, AppRoutes.auth);
                  }
                },
              ),
              _SettingsMenuItem(
                labelText: l10n.deleteAccount,
                trailing: const Icon(
                  Icons.chevron_right,
                  color: cancelRedColor,
                  size: 20,
                ),
                onTap: () => _showDeleteAccountDialog(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Edit profile" trigger.
///
/// On iOS 26+ this is a native [CNPopupMenuButton] with a native `UIMenu`.
/// Other platforms use the themed button and menu bottom sheet fallback.
class _EditProfileButton extends StatelessWidget {
  final double width;
  final String label;
  final List<_ProfileEditAction> actions;
  final VoidCallback onFallbackPressed;

  const _EditProfileButton({
    required this.width,
    required this.label,
    required this.actions,
    required this.onFallbackPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (useNativeGlass) {
      return SizedBox(
        width: width,
        height: 36,
        child: CNPopupMenuButton(
          buttonLabel: label,
          buttonStyle: CNButtonStyle.glass,
          height: 36,
          items: [
            for (final action in actions)
              CNPopupMenuItem(
                label: action.label,
                icon: CNSymbol(action.symbol),
              ),
          ],
          // Indexes into the same list the items came from, so the two can
          // never disagree about what position means.
          onSelected: (index) => actions[index].onPressed(),
        ),
      );
    }

    return ElevatedActionButton(
      width: width,
      height: 36,
      backgroundColor: context.colors.surfaceVariant,
      textStyle: AppTextStyles.label.copyWith(
        color: context.colors.primaryText,
      ),
      buttonText: label,
      onPressed: onFallbackPressed,
    );
  }
}

/// One entry in the edit-profile menu, in both of its presentations.
///
/// Carries a SF Symbol name for the native popup and a Material icon for the
/// bottom-sheet fallback, because the two menus draw from different icon sets
/// but must offer the same actions in the same order.
class _ProfileEditAction {
  final String label;
  final String symbol;
  final IconData icon;
  final VoidCallback onPressed;

  const _ProfileEditAction({
    required this.label,
    required this.symbol,
    required this.icon,
    required this.onPressed,
  });
}

class _SettingsLabelItem extends StatelessWidget {
  final String labelText;

  const _SettingsLabelItem({required this.labelText});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20, bottom: 16, top: 12),
          child: Text(labelText, style: AppTextStyles.subtitle),
        ),
        Divider(color: context.colors.divider, thickness: 1, height: 1),
      ],
    );
  }
}

class _SettingsMenuItem extends StatelessWidget {
  final VoidCallback? onTap;
  final String labelText;
  final Widget trailing;
  const _SettingsMenuItem({
    this.onTap,
    required this.labelText,
    this.trailing = const SizedBox(),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 30, right: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(labelText, style: AppTextStyles.body),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
