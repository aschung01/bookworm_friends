import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bookworm_friends/services/book_search_service.dart';

/// User-facing preference for which book catalog to search.
/// [auto] resolves to a source based on the device locale.
enum BookSourcePreference { auto, kakao, googleBooks }

const String _prefKey = 'book_source_preference';

/// Overridden in `main()` with the loaded [SharedPreferences] instance so the
/// preference can be read/written synchronously throughout the app.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

class BookSourceNotifier extends Notifier<BookSourcePreference> {
  @override
  BookSourcePreference build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return _parse(prefs.getString(_prefKey));
  }

  Future<void> set(BookSourcePreference pref) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_prefKey, _serialize(pref));
    state = pref;
  }

  static BookSourcePreference _parse(String? value) {
    switch (value) {
      case 'kakao':
        return BookSourcePreference.kakao;
      case 'google':
        return BookSourcePreference.googleBooks;
      default:
        return BookSourcePreference.auto;
    }
  }

  static String _serialize(BookSourcePreference pref) {
    switch (pref) {
      case BookSourcePreference.kakao:
        return 'kakao';
      case BookSourcePreference.googleBooks:
        return 'google';
      case BookSourcePreference.auto:
        return 'auto';
    }
  }
}

final bookSourcePreferenceProvider =
    NotifierProvider<BookSourceNotifier, BookSourcePreference>(
  BookSourceNotifier.new,
);

/// Resolves the [BookSourcePreference] into a concrete [BookSearchSource],
/// falling back to the device locale when the preference is [auto].
final bookSearchSourceProvider = Provider<BookSearchSource>((ref) {
  final pref = ref.watch(bookSourcePreferenceProvider);
  switch (pref) {
    case BookSourcePreference.kakao:
      return BookSearchSource.kakao;
    case BookSourcePreference.googleBooks:
      return BookSearchSource.googleBooks;
    case BookSourcePreference.auto:
      final languageCode = PlatformDispatcher.instance.locale.languageCode;
      return languageCode == 'ko'
          ? BookSearchSource.kakao
          : BookSearchSource.googleBooks;
  }
});

/// The active [BookSearchProvider] implementation for the resolved source.
final bookSearchProvider = Provider<BookSearchProvider>((ref) {
  switch (ref.watch(bookSearchSourceProvider)) {
    case BookSearchSource.kakao:
      return KakaoBookSearchProvider();
    case BookSearchSource.googleBooks:
      // Prefer Google Books; fall back to keyless Open Library when Google is
      // unavailable (e.g. keyless quota exceeded / 429).
      return FallbackBookSearchProvider([
        GoogleBooksSearchProvider(),
        OpenLibrarySearchProvider(),
      ]);
  }
});
