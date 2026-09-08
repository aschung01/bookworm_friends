import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bookworm_friends/providers/book_search_provider.dart'
    show sharedPreferencesProvider;

/// An override for [sharedPreferencesProvider], backed by the plugin's own in-memory fake.
///
/// **Needed by any test that pumps a tree reading a stored preference.**
/// [sharedPreferencesProvider] throws unless it is overridden — deliberately, so that a
/// preference is never read from a half-initialised store — and `main()` overrides it with
/// an instance loaded before `runApp`. A test has no `main()`, so it needs this.
///
/// [values] seeds the store, which is how a test asserts what the app does with a
/// preference it finds rather than only with one it writes.
Future<Override> sharedPreferencesOverride([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  return sharedPreferencesProvider.overrideWithValue(
    await SharedPreferences.getInstance(),
  );
}
