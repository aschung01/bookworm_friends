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

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/friend_reading.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/profile_provider.dart';
import 'package:bookworm_friends/providers/shell_chrome_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/shell_chrome.dart';

Book _book(
  String id,
  String shelfId,
  String title, {
  int status = 0,
  int pos = 0,
  DateTime? started,
  DateTime? finished,
  List<String> authors = const [],
}) => Book(
  id: id,
  userId: 'u',
  shelfId: shelfId,
  isbn: id,
  title: title,
  thumbnail: '',
  status: status,
  position: pos,
  startDate: started,
  finishDate: finished,
  createdAt: DateTime(2024),
  authors: authors,
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

/// Read books with **start dates and authors**, which the Library Card needs and
/// the read view does not.
///
/// Deliberately mixed rather than uniformly complete, because the real data is
/// mixed and the card's whole design is about which tiles it can honestly show:
///
///  * `r4` and `r7` are both Han Kang, so the most-read-author tile clears its floor
///    of two. Every other author has one book, which is what 40 of 53 real readers
///    look like.
///  * `r5` has `start == finish` — the shape 57% of real finished books have, from
///    flipping a book straight to finished — so it must be excluded from pace rather
///    than counted as a zero-day read.
///  * `r8` has no dates at all, so it counts toward books read and nothing else.
///  * Finish dates span 2026 and 2025, so the year capsules have something to do.
List<Book> _readBooks() => [
  _book(
    'r1',
    's1',
    'Dune',
    status: bookStatusFinished,
    pos: 0,
    started: DateTime(2026, 2, 18),
    finished: DateTime(2026, 3, 4),
    authors: const ['Frank Herbert'],
  ),
  _book(
    'r2',
    's1',
    'Circe',
    status: bookStatusFinished,
    pos: 1,
    started: DateTime(2026, 3, 10),
    finished: DateTime(2026, 3, 19),
    authors: const ['Madeline Miller'],
  ),
  _book(
    'r3',
    's1',
    'Beloved',
    status: bookStatusFinished,
    pos: 2,
    started: DateTime(2026, 1, 22),
    finished: DateTime(2026, 2, 8),
    authors: const ['Toni Morrison'],
  ),
  _book(
    'r4',
    's1',
    'Human Acts',
    status: bookStatusFinished,
    pos: 3,
    started: DateTime(2026, 1, 19),
    finished: DateTime(2026, 1, 30),
    authors: const ['한강'],
  ),
  _book(
    'r5',
    's1',
    'Snow',
    status: bookStatusFinished,
    pos: 4,
    started: DateTime(2025, 12, 2),
    finished: DateTime(2025, 12, 2),
    authors: const ['Orhan Pamuk'],
  ),
  _book(
    'r6',
    's1',
    'Kafka on the Shore',
    status: bookStatusFinished,
    pos: 5,
    started: DateTime(2025, 10, 24),
    finished: DateTime(2025, 11, 11),
    authors: const ['무라카미 하루키'],
  ),
  _book(
    'r7',
    's1',
    'The Vegetarian',
    status: bookStatusFinished,
    pos: 6,
    started: DateTime(2025, 10, 20),
    finished: DateTime(2025, 11, 1),
    authors: const ['한강'],
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

/// `ShellChrome` sits above the navigator, so it needs a key to reach one.
final _previewNavigatorKey = GlobalKey<NavigatorState>();

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
        friendsProvider.overrideWith(
          (ref) async => [
            _profile('f1', 'jisoo', '🦊'),
            _profile('f2', 'minho', '🐣'),
            _profile('f3', 'hana', '🐨'),
          ],
        ),
        // The four states the `EVERYONE` fixture draws, minus one: jisoo is reading
        // one book, minho two at once, hana nothing. The fourth — a friend absent
        // from the map, i.e. still loading or invisible to us — cannot be shown in a
        // fixture that resolves instantly, so it is covered in
        // `test/friend_reading_test.dart` instead.
        friendsReadingProvider.overrideWith(
          (ref) async => {
            'f1': FriendReading(
              inProgress: [
                _book('p1', 's1', 'The Vegetarian', status: bookStatusReading),
              ],
              finishedCount: 24,
            ),
            'f2': FriendReading(
              inProgress: [
                _book('p2', 's1', 'Snow', status: bookStatusReading),
                _book('p3', 's1', 'Circe', status: bookStatusReading),
              ],
              finishedCount: 9,
            ),
            'f3': const FriendReading(finishedCount: 31),
          },
        ),
      ],
      child: const _PreviewApp(),
    ),
  );
}

class _PreviewApp extends ConsumerWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      navigatorKey: _previewNavigatorKey,
      // Wired exactly as `main.dart` does. `CNTabBarRouteObserver` is deliberately
      // gone: it destroys `CNTabBar` for sheet routes, and the floating bar is
      // meant to stay in front of Add Book. `ShellRouteObserver` keeps the
      // halo-containment half that `CNButton` needs.
      navigatorObservers: [ref.watch(shellRouteObserverProvider)],
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
      // Hosts the floating tab bar above the navigator, which is what lets it
      // float over the Add Book sheet.
      builder: (context, child) =>
          ShellChrome(navigatorKey: _previewNavigatorKey, child: child!),
      // The real route table, so Add Book and Add Friend push the pages they
      // push in production. `initialRoute` rather than `home:` because the table
      // already owns '/'.
      routes: AppRoutes.routes,
      // The preview pushes the real routes, so it needs the real fall-through too —
      // without this, `View and share` is an unknown route here and throws.
      onGenerateRoute: AppRoutes.onGenerateRoute,
      initialRoute: AppRoutes.home,
    );
  }
}
