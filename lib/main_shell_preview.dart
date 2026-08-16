// A device preview of the library shell — Task 7 verification only.
//
// `flutter test` reports Android, so `useNativeGlass` is false there and every
// widget test exercises the *fallback* chrome. The native `CNTabBar`, its Liquid
// Glass search orb, and how a native `UITabBar` z-orders against the Flutter
// sheet underneath it can only be seen on a real iOS 26 surface.
//
// Reaching `HomePage` in the real app means signing in with Apple or Google, so
// this entrypoint stands in for `main.dart`: same `MaterialApp`, same theme, same
// `CNTabBarRouteObserver`, same `HomePage` — with the Supabase-backed providers
// replaced by fixtures, and no Firebase, Supabase or push init. Nothing here is
// reachable from the shipped app; it is a viewer for the chrome.
//
//   flutter build ios --simulator --debug -t lib/main_shell_preview.dart \
//     --dart-define-from-file=env.json

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/profile_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';

Book _book(
  String id,
  String shelfId,
  String title, {
  int status = 0,
  int pos = 0,
  DateTime? finished,
}) => Book(
  id: id,
  userId: 'u',
  shelfId: shelfId,
  isbn: id,
  title: title,
  thumbnail: '',
  status: status,
  position: pos,
  finishDate: finished,
  createdAt: DateTime(2024),
);

Shelf _shelf(String id, String name, List<Book> books) => Shelf(
  id: id,
  userId: 'u',
  name: name,
  position: 0,
  createdAt: DateTime(2024),
  books: books,
);

/// Two full shelves plus a read pile, so the library has something behind the
/// sheet worth being covered by — an empty library would hide the very overlap
/// this preview exists to check.
List<Shelf> _library() => [
  _shelf('s1', 'Novels', [
    _book('b1', 's1', 'The Vegetarian', pos: 0),
    _book('b2', 's1', 'Pachinko', pos: 1),
    _book('b3', 's1', 'Snow', status: 1, pos: 2),
    _book('b4', 's1', 'Almond', pos: 3),
  ]),
  _shelf('s2', 'Non-fiction', [
    _book('b5', 's2', 'Sapiens', pos: 0),
    _book('b6', 's2', 'Thinking, Fast and Slow', pos: 1),
  ]),
];

List<Book> _readBooks() => [
  _book(
    'r1',
    's1',
    'Dune',
    status: bookStatusFinished,
    pos: 0,
    finished: DateTime(2026, 3, 4),
  ),
  _book(
    'r2',
    's1',
    'Circe',
    status: bookStatusFinished,
    pos: 1,
    finished: DateTime(2026, 3, 19),
  ),
  _book(
    'r3',
    's1',
    'Beloved',
    status: bookStatusFinished,
    pos: 2,
    finished: DateTime(2026, 2, 8),
  ),
  _book(
    'r4',
    's1',
    'Human Acts',
    status: bookStatusFinished,
    pos: 3,
    finished: DateTime(2026, 1, 30),
  ),
  _book(
    'r5',
    's1',
    'Snow',
    status: bookStatusFinished,
    pos: 4,
    finished: DateTime(2025, 12, 2),
  ),
  _book(
    'r6',
    's1',
    'Kafka on the Shore',
    status: bookStatusFinished,
    pos: 5,
    finished: DateTime(2025, 11, 11),
  ),
  _book(
    'r7',
    's1',
    'The Vegetarian',
    status: bookStatusFinished,
    pos: 6,
    finished: DateTime(2025, 11, 1),
  ),
  _book('r8', 's1', 'Almond', status: bookStatusFinished, pos: 7),
];

Profile _profile(String id, String name, String emoji) => Profile(
  id: id,
  username: name,
  emoji: emoji,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

class _FixtureLibrary extends LibraryNotifier {
  @override
  Future<List<Shelf>> build() async => _library();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUserIdProvider.overrideWithValue('u'),
        libraryProvider.overrideWith(_FixtureLibrary.new),
        finishedBooksProvider.overrideWith((ref) async => _readBooks()),
        // A visit reads a friend's library through its own providers, so without
        // these the visit renders a Supabase-not-initialised error instead of the
        // chrome this preview exists to show.
        userLibraryProvider.overrideWith((ref, userId) async => _library()),
        userFinishedBooksProvider.overrideWith(
          (ref, userId) async => _readBooks(),
        ),
        profileProvider.overrideWith(
          (ref) async => _profile('u', 'tester', '📚'),
        ),
        followingListProvider.overrideWith(
          (ref) async => [
            _profile('f1', 'jisoo', '🦊'),
            _profile('f2', 'minho', '🐣'),
            _profile('f3', 'hana', '🐨'),
          ],
        ),
      ],
      child: const _PreviewApp(),
    ),
  );
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Registered exactly as `main.dart` does: without it `CNTabBar` cannot
      // auto-hide behind a modal, which is one of the things worth looking at.
      navigatorObservers: [CNTabBarRouteObserver()],
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      // The real route table, so Add Book and Add Friend push the pages they
      // push in production. `initialRoute` rather than `home:` because the table
      // already owns '/'.
      routes: AppRoutes.routes,
      initialRoute: AppRoutes.home,
    );
  }
}
