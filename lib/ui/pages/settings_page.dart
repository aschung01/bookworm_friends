import 'dart:math';

import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/providers/profile_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/compliment_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:flutter/cupertino.dart';
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

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  void _onEditProfilePressed() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.editProfile, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkPrimaryColor)),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.emoji_emotions_outlined),
                title: Text(l10n.changeEmoji),
                onTap: () {
                  Navigator.pop(context);
                  _onUpdateEmojiPressed();
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(l10n.changeNickname),
                onTap: () {
                  Navigator.pop(context);
                  _onUpdateUsernamePressed();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _onUpdateEmojiPressed() {
    showEmojiBottomSheet(context, onEmojiPressed: (emoji) async {
      Navigator.pop(context);
      await ref.read(updateProfileProvider).updateEmoji(emoji);
    });
  }

  void _onUpdateUsernamePressed() {
    final profile = ref.read(profileProvider).valueOrNull;
    _usernameController.text = profile?.username ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return Padding(
          padding: EdgeInsets.only(
            left: 30, right: 30, top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.changeNickname, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkPrimaryColor)),
              const SizedBox(height: 20),
              TextField(
                controller: _usernameController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.newNickname,
                  filled: true,
                  fillColor: lightGrayColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
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
                    await ref.read(updateProfileProvider).updateUsername(_usernameController.text.trim());
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
    showDialog(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.deleteAccount),
          content: Text(l10n.deleteAccountConfirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel, style: const TextStyle(color: grayColor)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                EasyLoading.show();
                final success = await ref.read(authProvider.notifier).deleteAccount();
                if (success) {
                  EasyLoading.showSuccess(l10n.deleteAccountDone);
                  if (mounted) {
                    Navigator.pushReplacementNamed(context, AppRoutes.auth);
                  }
                } else {
                  EasyLoading.showError(l10n.deleteAccountFailed);
                }
              },
              child: Text(l10n.deleteAccountShort, style: const TextStyle(color: cancelRedColor)),
            ),
          ],
        );
      },
    );
  }

  void _showFollowList(BuildContext context, WidgetRef ref, String userId, int initialTab) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
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

  static String _bookSourceLabel(AppLocalizations l10n, BookSourcePreference pref) {
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
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(l10n.bookSearchSource,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: darkPrimaryColor)),
                ),
                for (final pref in BookSourcePreference.values)
                  ListTile(
                    title: Text(_bookSourceLabel(l10n, pref)),
                    trailing: pref == current
                        ? const Icon(Icons.check, color: greenThemeColor)
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      ref.read(bookSourcePreferenceProvider.notifier).set(pref);
                    },
                  ),
              ],
            ),
          ),
        );
      },
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
    final followerCount = userId != null ? ref.watch(followerCountProvider(userId)) : null;
    final followingCount = userId != null ? ref.watch(followingCountProvider(userId)) : null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios, color: darkPrimaryColor, size: 22),
        ),
      ),
      body: SafeArea(
        child: ListView(
          physics: const ClampingScrollPhysics(),
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
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: lightGrayColor),
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
                            style: const TextStyle(color: darkPrimaryColor, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Row(
                            children: [
                              GestureDetector(
                                onTap: userId != null ? () => _showFollowList(context, ref, userId, 0) : null,
                                child: Row(
                                  children: [
                                    Text(l10n.followers, style: const TextStyle(color: darkPrimaryColor, fontSize: 14, fontWeight: FontWeight.bold)),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 12),
                                      child: Text(
                                        followerCount?.valueOrNull?.toString() ?? '-',
                                        style: const TextStyle(color: darkPrimaryColor, fontSize: 20),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              GestureDetector(
                                onTap: userId != null ? () => _showFollowList(context, ref, userId, 1) : null,
                                child: Row(
                                  children: [
                                    Text(l10n.following, style: const TextStyle(color: darkPrimaryColor, fontSize: 14, fontWeight: FontWeight.bold)),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 12),
                                      child: Text(
                                        followingCount?.valueOrNull?.toString() ?? '-',
                                        style: const TextStyle(color: darkPrimaryColor, fontSize: 20),
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
                    ? ElevatedActionButton(
                        width: min(MediaQuery.of(context).size.width - 60, 330),
                        height: 36,
                        backgroundColor: lightGrayColor,
                        textStyle: const TextStyle(color: darkPrimaryColor, fontSize: 14),
                        buttonText: l10n.editProfile,
                        onPressed: _onEditProfilePressed,
                      )
                    : ElevatedActionButton(
                        width: min(MediaQuery.of(context).size.width - 60, 330),
                        height: 36,
                        borderRadius: 50,
                        textStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        buttonText: l10n.login,
                        onPressed: () => Navigator.pushNamed(context, AppRoutes.auth),
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
                  Text(auth.user?.email ?? '', style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
            _SettingsMenuItem(
              labelText: l10n.allowProfileSearch,
              trailing: isAuthenticated
                  ? Transform.scale(
                      scale: 0.9,
                      child: CupertinoSwitch(
                        value: !(profile?.isPrivate ?? false),
                        onChanged: (value) {
                          ref.read(updateProfileProvider).updatePrivacy(!value);
                        },
                        activeTrackColor: greenThemeColor,
                      ),
                    )
                  : const Text('-', style: TextStyle(fontSize: 20, color: darkPrimaryColor)),
            ),
            const SizedBox(height: 12),
            _SettingsLabelItem(labelText: l10n.preferencesSection),
            _SettingsMenuItem(
              labelText: l10n.bookSearchSource,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _bookSourceLabel(l10n, ref.watch(bookSourcePreferenceProvider)),
                    style: const TextStyle(fontSize: 13, color: grayColor),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right,
                      color: darkPrimaryColor, size: 20),
                ],
              ),
              onTap: _showBookSourcePicker,
            ),
            const SizedBox(height: 12),
            _SettingsLabelItem(labelText: l10n.contactDevSection),
            _SettingsMenuItem(
              labelText: l10n.aboutDev,
              trailing: const Icon(Icons.chevron_right, color: darkPrimaryColor, size: 20),
              onTap: () => _launchUrl(_personalInfoUrl),
            ),
            _SettingsMenuItem(
              labelText: l10n.reportBug,
              trailing: const Icon(Icons.chevron_right, color: darkPrimaryColor, size: 20),
              onTap: () => _launchUrl(_bugReportUrl),
            ),
            _SettingsMenuItem(
              labelText: l10n.writeFeedback,
              trailing: const Icon(Icons.chevron_right, color: darkPrimaryColor, size: 20),
              onTap: () => _launchUrl(_feedbackUrl),
            ),
            _SettingsMenuItem(
              labelText: l10n.leaveReview,
              trailing: const Icon(Icons.chevron_right, color: darkPrimaryColor, size: 20),
              onTap: _onInAppReviewPressed,
            ),
            const SizedBox(height: 12),
            _SettingsLabelItem(labelText: l10n.infoSection),
            _SettingsMenuItem(labelText: l10n.notices, onTap: () => _launchUrl(_noticeUrl)),
            _SettingsMenuItem(labelText: l10n.userGuide, onTap: () => _launchUrl(_helpUrl)),
            _SettingsMenuItem(labelText: l10n.termsOfUse, onTap: () => _launchUrl(_termsOfUseUrl)),
            _SettingsMenuItem(labelText: l10n.privacyPolicy, onTap: () => _launchUrl(_privacyPolicyUrl)),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version = snapshot.data?.version ?? '';
                final buildNumber = snapshot.data?.buildNumber ?? '';
                return _SettingsMenuItem(
                  labelText: l10n.appVersion,
                  trailing: Text(
                    version.isNotEmpty ? 'v$version ($buildNumber)' : '',
                    style: const TextStyle(fontSize: 13, color: grayColor),
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
                trailing: const Icon(Icons.chevron_right, color: cancelRedColor, size: 20),
                onTap: () => _showDeleteAccountDialog(),
              ),
            ],
          ],
        ),
      ),
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
            style: const TextStyle(color: darkPrimaryColor, fontWeight: FontWeight.w600, fontSize: 16),
          ),
        ),
        const Divider(color: lightGrayColor, thickness: 1, height: 1),
      ],
    );
  }
}

class _SettingsMenuItem extends StatelessWidget {
  final VoidCallback? onTap;
  final String labelText;
  final Widget trailing;
  const _SettingsMenuItem({this.onTap, required this.labelText, this.trailing = const SizedBox()});

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
              Text(labelText, style: const TextStyle(fontSize: 14, color: darkPrimaryColor)),
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
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
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
          width: 40, height: 4,
          decoration: BoxDecoration(color: grayColor, borderRadius: BorderRadius.circular(2)),
        ),
        TabBar(
          controller: _tabController,
          labelColor: darkPrimaryColor,
          unselectedLabelColor: grayColor,
          indicatorColor: greenThemeColor,
          tabs: [Tab(text: l10n.followers), Tab(text: l10n.following)],
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
          return Center(child: Text(l10n.emptyList, style: const TextStyle(color: grayColor)));
        }
        return ListView.builder(
          controller: widget.scrollController,
          itemCount: profiles.length,
          itemBuilder: (context, index) {
            final p = profiles[index];
            return ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: lightGrayColor),
                alignment: Alignment.center,
                child: Text(p.emoji ?? '📖', style: const TextStyle(fontSize: 20)),
              ),
              title: Text(p.username ?? '', style: const TextStyle(fontSize: 15, color: darkPrimaryColor)),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.userLibrary, arguments: {'user_id': p.id, 'username': p.username});
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(child: Text(l10n.errorOccurred)),
    );
  }
}
