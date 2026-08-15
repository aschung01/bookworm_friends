import 'package:bookworm_friends/ui/widgets/native_glass.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_back_button.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/menu_bottom_sheet.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'dart:math';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/providers/profile_provider.dart';
import 'package:bookworm_friends/providers/theme_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/compliment_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/dialogs/adaptive_dialog_action.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const String _termsOfUseUrl =
    'https://bookwormfriends.notion.site/ed87960f6f9b4db8addfd36cc906bc92';
const String _privacyPolicyUrl =
    'https://bookwormfriends.notion.site/a4ffdbd423cd47cca55eac821283f728';
const String _personalInfoUrl = 'https://www.instagram.com/asounhoo1/';
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
  bool _isFollowListVisible = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  void _onEditProfilePressed() {
    final l10n = AppLocalizations.of(context);
    showMenuBottomSheet(
      context: context,
      title: l10n.editProfile,
      actions: [
        MenuAction(
          label: l10n.changeEmoji,
          icon: Icons.emoji_emotions_outlined,
          onPressed: _onUpdateEmojiPressed,
        ),
        MenuAction(
          label: l10n.changeNickname,
          icon: Icons.person_outline,
          onPressed: _onUpdateUsernamePressed,
        ),
      ],
    );
  }

  void _onUpdateEmojiPressed() {
    showEmojiBottomSheet(
      context,
      onEmojiPressed: (emoji) async {
        Navigator.pop(context);
        await ref.read(updateProfileProvider).updateEmoji(emoji);
      },
    );
  }

  void _onUpdateUsernamePressed() {
    final profile = ref.read(profileProvider).valueOrNull;
    _usernameController.text = profile?.username ?? '';
    CNBottomSheet.show(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
              Text(
                l10n.changeNickname,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _usernameController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.newNickname,
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

  void _showDeleteAccountDialog() {
    showAdaptiveDialog(
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

  Future<void> _showFollowList(
    BuildContext context,
    WidgetRef ref,
    String userId,
    int initialTab,
  ) async {
    setState(() => _isFollowListVisible = true);
    try {
      await CNBottomSheet.show<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.4,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) => _FollowListSheet(
            userId: userId,
            initialTab: initialTab,
            scrollController: scrollController,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isFollowListVisible = false);
      }
    }
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
    final userId = auth.user?.id;
    final followerCount = userId != null
        ? ref.watch(followerCountProvider(userId))
        : null;
    final followingCount = userId != null
        ? ref.watch(followingCountProvider(userId))
        : null;

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
              child: SizedBox(
                height: 60,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 20),
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: context.colors.surfaceVariant,
                        ),
                        child: Center(
                          child: Text(
                            profile?.emoji ?? '📚',
                            style: const TextStyle(fontSize: 26),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            profile?.username ?? '???',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Row(
                            children: [
                              GestureDetector(
                                onTap: userId != null
                                    ? () => _showFollowList(
                                        context,
                                        ref,
                                        userId,
                                        0,
                                      )
                                    : null,
                                child: Row(
                                  children: [
                                    Text(
                                      l10n.followers,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 12),
                                      child: Text(
                                        followerCount?.valueOrNull
                                                ?.toString() ??
                                            '-',
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              GestureDetector(
                                onTap: userId != null
                                    ? () => _showFollowList(
                                        context,
                                        ref,
                                        userId,
                                        1,
                                      )
                                    : null,
                                child: Row(
                                  children: [
                                    Text(
                                      l10n.following,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 12),
                                      child: Text(
                                        followingCount?.valueOrNull
                                                ?.toString() ??
                                            '-',
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 24),
              child: Center(
                child: isAuthenticated
                    ? _isFollowListVisible
                          ? SizedBox(
                              width: min(
                                MediaQuery.of(context).size.width - 60,
                                330,
                              ),
                              height: 36,
                            )
                          : _EditProfileButton(
                              width: min(
                                MediaQuery.of(context).size.width - 60,
                                330,
                              ),
                              label: l10n.editProfile,
                              emojiLabel: l10n.changeEmoji,
                              nicknameLabel: l10n.changeNickname,
                              onEmojiPressed: _onUpdateEmojiPressed,
                              onNicknamePressed: _onUpdateUsernamePressed,
                              onFallbackPressed: _onEditProfilePressed,
                            )
                    : ElevatedActionButton(
                        width: min(MediaQuery.of(context).size.width - 60, 330),
                        height: 36,
                        borderRadius: 50,
                        textStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
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
                  Text(
                    auth.user?.email ?? '',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            _SettingsMenuItem(
              labelText: l10n.allowProfileSearch,
              trailing: isAuthenticated
                  ? Transform.scale(
                      scale: 0.9,
                      child: Switch.adaptive(
                        value: !(profile?.isPrivate ?? false),
                        onChanged: (value) {
                          ref.read(updateProfileProvider).updatePrivacy(!value);
                        },
                        activeTrackColor: context.colors.brandFill,
                      ),
                    )
                  : const Text('-', style: TextStyle(fontSize: 20)),
            ),
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
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.secondaryText,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              onTap: _showBookSourcePicker,
            ),
            _SettingsMenuItem(
              labelText: l10n.appearance,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _appearanceLabel(l10n, ref.watch(themeModeProvider)),
                    style: TextStyle(
                      fontSize: 13,
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
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version = snapshot.data?.version ?? '';
                final buildNumber = snapshot.data?.buildNumber ?? '';
                return _SettingsMenuItem(
                  labelText: l10n.appVersion,
                  trailing: Text(
                    version.isNotEmpty ? 'v$version ($buildNumber)' : '',
                    style: TextStyle(
                      fontSize: 13,
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
  final String emojiLabel;
  final String nicknameLabel;
  final VoidCallback onEmojiPressed;
  final VoidCallback onNicknamePressed;
  final VoidCallback onFallbackPressed;

  const _EditProfileButton({
    required this.width,
    required this.label,
    required this.emojiLabel,
    required this.nicknameLabel,
    required this.onEmojiPressed,
    required this.onNicknamePressed,
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
            CNPopupMenuItem(label: emojiLabel, icon: CNSymbol('face.smiling')),
            CNPopupMenuItem(label: nicknameLabel, icon: CNSymbol('person')),
          ],
          onSelected: (index) {
            if (index == 0) {
              onEmojiPressed();
            } else {
              onNicknamePressed();
            }
          },
        ),
      );
    }

    return ElevatedActionButton(
      width: width,
      height: 36,
      backgroundColor: context.colors.surfaceVariant,
      textStyle: TextStyle(color: context.colors.primaryText, fontSize: 14),
      buttonText: label,
      onPressed: onFallbackPressed,
    );
  }
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
          child: Text(
            labelText,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
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
              Text(labelText, style: const TextStyle(fontSize: 14)),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _FollowListSheet extends ConsumerStatefulWidget {
  final String userId;
  final int initialTab;
  final ScrollController scrollController;

  const _FollowListSheet({
    required this.userId,
    required this.initialTab,
    required this.scrollController,
  });

  @override
  ConsumerState<_FollowListSheet> createState() => _FollowListSheetState();
}

class _FollowListSheetState extends ConsumerState<_FollowListSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final followersAsync = ref.watch(followerListProvider(widget.userId));
    final followingAsync = ref.watch(followingListProvider);

    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: context.colors.secondaryText,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        TabBar(
          controller: _tabController,
          labelColor: context.colors.primaryText,
          unselectedLabelColor: context.colors.secondaryText,
          indicatorColor: context.colors.brandText,
          tabs: [
            Tab(text: l10n.followers),
            Tab(text: l10n.following),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildUserList(followersAsync),
              _buildUserList(followingAsync),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserList(AsyncValue<List<Profile>> asyncProfiles) {
    final l10n = AppLocalizations.of(context);
    return asyncProfiles.when(
      data: (profiles) {
        if (profiles.isEmpty) {
          return Center(
            child: Text(
              l10n.emptyList,
              style: TextStyle(color: context.colors.secondaryText),
            ),
          );
        }
        return ListView.builder(
          controller: widget.scrollController,
          itemCount: profiles.length,
          itemBuilder: (context, index) {
            final p = profiles[index];
            return ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.surfaceVariant,
                ),
                alignment: Alignment.center,
                child: Text(
                  p.emoji ?? '📖',
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              title: Text(
                p.username ?? '',
                style: const TextStyle(fontSize: 15),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(
                  context,
                  AppRoutes.userLibrary,
                  arguments: {'user_id': p.id, 'username': p.username},
                );
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (_, __) => Center(child: Text(l10n.errorOccurred)),
    );
  }
}
