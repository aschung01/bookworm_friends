// A device preview of the **book details page**, for the two doors added to it:
// the `Change status` verb on a status-0 line, and the shelf name tab.
//
// Same reason `main_shell_preview.dart` exists — reaching this page in the real app
// means signing in with Apple or Google — and one reason of its own: both of those
// doors are decided by measurements that `flutter test` cannot take. The test
// environment draws every glyph as a square of the font size, so `Interested` plus
// `Change status` measures about 340pt there against roughly 200 on device, which is
// the difference between the line wrapping and not. This entrypoint is where that is
// looked at rather than assumed.
//
//   flutter build ios --simulator --debug -t lib/main_details_preview.dart \
//     --dart-define-from-file=env.json

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/book_compliment.dart';
import 'package:bookworm_friends/models/book_memo.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/book_details_provider.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/ui/views/book_details_tab_view.dart';

const _me = 'u';

/// Where to synthesize a tap once the page has settled, or null to leave it alone.
///
/// **This exists because there is no Simulator GUI in this Xcode install** — only a
/// headless booted device and `xcrun simctl io ... screenshot` — so a state that lives
/// behind a tap cannot be photographed by hand. `(351, 301)` is the centre of the
/// shelf name tab at 402x874, read off `_shot_device.png`.
///
/// Synthesized through `GestureBinding.handlePointerEvent`, which takes logical
/// coordinates and enters the same arena a real touch does.
///
/// **On iOS 26 it is now a negative check, and that is the most this machine can
/// offer.** The tab's gesture belongs to a chrome-free `CNPopupMenuButton` stacked over
/// it, and UIKit's menu opens from a real `UITouch` that a synthesized Flutter pointer
/// is not — Flutter forwards actual touches to a platform view, never fabricated ones.
/// So what this proves is that the tap opens **nothing in Flutter**: if the app-drawn
/// popover shows up in the screenshot, the native and fallback paths have been wired at
/// the same time, which is the one mistake `ShelfLabel.onTap`'s doc is about.
///
/// The popover itself was photographed before the menu became native, and those shots
/// are kept in `docs/mockups/book-details-edit/`. There is no pre-26 runtime installed
/// to take a new one on.
const Offset? _autoTapAt = Offset(351, 301);

class _NoBookInfo implements BookSearchProvider {
  @override
  Future<List<BookSearchResult>> search(
    String query, {
    int page = 1,
    int size = 10,
  }) async => const [];

  @override
  Future<BookSearchResult?> getByIsbn(String isbn) async => null;
}

class _FixedLibrary extends LibraryNotifier {
  _FixedLibrary(this.shelves);
  final List<Shelf> shelves;

  @override
  Future<List<Shelf>> build() async => shelves;

  /// The write, locally only. Enough to see the tab's name and count change and the
  /// picker's check move, which is what this preview is for.
  @override
  Future<void> moveBookToShelf(
    String bookId,
    String targetShelfId,
    List<String> orderedBookIds,
  ) async {
    final current = state.valueOrNull;
    if (current == null) return;
    Book? found;
    for (final s in current) {
      for (final b in s.books) {
        if (b.id == bookId) found = b;
      }
    }
    if (found == null) return;
    state = AsyncData([
      for (final s in current)
        if (s.id == found.shelfId)
          s.copyWith(books: s.books.where((b) => b.id != bookId).toList())
        else if (s.id == targetShelfId)
          s.copyWith(
            books: [
              ...s.books,
              found.copyWith(shelfId: targetShelfId),
            ],
          )
        else
          s,
    ]);
  }
}

Book _book(
  String id,
  String shelfId,
  String title, {
  int status = 0,
  List<String> authors = const [],
}) => Book(
  id: id,
  userId: _me,
  shelfId: shelfId,
  isbn: id,
  title: title,
  thumbnail: '',
  status: status,
  position: 0,
  authors: authors,
  createdAt: DateTime(2024),
);

/// The book from the report: status 0, so no dates, so no card — the state that had
/// no door anywhere in the app.
final _subject = _book(
  'b1',
  's1',
  '경제기사 궁금증 300문 300답(2022)',
  authors: const ['곽해선'],
);

Shelf _shelf(String id, String name, List<Book> books) => Shelf(
  id: id,
  userId: _me,
  name: name,
  position: 0,
  createdAt: DateTime(2024),
  books: books,
);

/// Ten shelves, matching the library that prompted the feature. The number is what
/// decides whether the card is capped and its list scrolls, and it is also the picker's
/// whole argument: one name with one count is what the tab used to show on its own,
/// where ten side by side is a comparison.
List<Shelf> _library() => [
  _shelf('s1', '리더십', [
    _subject,
    for (var i = 0; i < 6; i++) _book('l$i', 's1', 'Leadership $i'),
  ]),
  _shelf('s2', '사회', [
    for (var i = 0; i < 3; i++) _book('so$i', 's2', 'Society $i'),
  ]),
  _shelf('s3', '금융', [
    for (var i = 0; i < 3; i++) _book('f$i', 's3', 'Finance $i'),
  ]),
  _shelf('s4', '의사결정', [
    for (var i = 0; i < 6; i++) _book('d$i', 's4', 'Decision $i'),
  ]),
  _shelf('s5', '자기계발', [
    for (var i = 0; i < 7; i++) _book('g$i', 's5', 'Growth $i'),
  ]),
  _shelf('s6', '브랜딩, 마케팅', [
    for (var i = 0; i < 5; i++) _book('br$i', 's6', 'Brand $i'),
  ]),
  _shelf('s7', 'IT', [
    for (var i = 0; i < 7; i++) _book('it$i', 's7', 'IT $i'),
  ]),
  _shelf('s8', '소설', const []),
  _shelf('s9', 'Studies', const []),
  _shelf('s10', '스타트업', [
    for (var i = 0; i < 7; i++) _book('st$i', 's10', 'Startup $i'),
  ]),
];

/// Fires [_autoTapAt] once the first frame is up and the page has settled.
void _scheduleAutoTap() {
  const at = _autoTapAt;
  if (at == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // Long enough for the catalogue lookup to resolve and the header to stop
    // resizing under the tap.
    await Future<void>.delayed(const Duration(seconds: 2));
    const id = 7;
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: id, position: at),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(pointer: id, position: at),
    );
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  _scheduleAutoTap();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUserIdProvider.overrideWithValue(_me),
        bookSearchProvider.overrideWithValue(_NoBookInfo()),
        bookMemosProvider(
          _subject.id,
        ).overrideWith((ref) async => <BookMemo>[]),
        bookComplimentsProvider(
          _subject.id,
        ).overrideWith((ref) async => <BookCompliment>[]),
        userLibraryProvider(_me).overrideWith((ref) async => _library()),
        libraryProvider.overrideWith(() => _FixedLibrary(_library())),
      ],
      child: MaterialApp(
        title: 'Details preview',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        onGenerateRoute: (settings) => MaterialPageRoute(
          builder: (_) => const BookDetailsTabView(),
          settings: RouteSettings(name: settings.name, arguments: _subject),
        ),
      ),
    ),
  );
}
