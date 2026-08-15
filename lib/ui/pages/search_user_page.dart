import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/headers/search_header.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _searchUserQueryProvider = StateProvider.autoDispose<String>((ref) => '');

final _searchUserResultsProvider = FutureProvider.autoDispose<List<Profile>>((
  ref,
) async {
  final query = ref.watch(_searchUserQueryProvider);
  if (query.isEmpty) return [];
  return ref.watch(searchUsersProvider(query).future);
});

class SearchUserPage extends ConsumerStatefulWidget {
  const SearchUserPage({super.key});

  @override
  ConsumerState<SearchUserPage> createState() => _SearchUserPageState();
}

class _SearchUserPageState extends ConsumerState<SearchUserPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSearchSubmitted(String val) {
    ref.read(_searchUserQueryProvider.notifier).state = val.trim();
  }

  void _onUserTap(Profile user) {
    Navigator.pushNamed(
      context,
      AppRoutes.userLibrary,
      arguments: {'user_id': user.id, 'username': user.username ?? '?'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final resultsAsync = ref.watch(_searchUserResultsProvider);

    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: SearchHeader(
        controller: _controller,
        hintText: l10n.searchUserPrompt,
        elevate: false,
        onFieldSubmitted: _onSearchSubmitted,
        onBackPressed: () => Navigator.pop(context),
      ),
      body: SafeArea(
        child: resultsAsync.when(
          data: (results) {
            if (results.isEmpty) {
              return Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).size.height * 0.25,
                ),
                child: Center(
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 15),
                        child: SmileBookwormIcon(width: 80),
                      ),
                      Text(
                        l10n.searchUserHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.colors.secondaryText,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(30, 10, 30, 15),
              itemCount: results.length,
              itemBuilder: (context, index) {
                final user = results[index];
                return SizedBox(
                  height: 56,
                  child: InkWell(
                    onTap: () => _onUserTap(user),
                    borderRadius: BorderRadius.circular(10),
                    splashColor: Colors.transparent,
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: context.colors.surfaceVariant,
                          ),
                          child: Center(
                            child: Text(
                              user.emoji ?? '📚',
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                        Text(
                          user.username ?? '?',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          loading: () =>
              const Center(child: CircularProgressIndicator.adaptive()),
          error: (e, _) =>
              Center(child: Text(l10n.searchErrorWithMessage(e.toString()))),
        ),
      ),
    );
  }
}
