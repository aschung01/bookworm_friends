/// The reader's Libby library, remembered so they are asked once.
///
/// **Three states, not two, and the third one is why this is not just a nullable
/// string.** `reader_app` taught the same lesson: "never asked" and "asked and
/// declined" look identical if absence is the only signal, and they call for
/// opposite behaviour. Never-asked must show the picker; declined must not, because
/// re-asking on every book is nagging a reader who already said no.
///
/// **Stored in `SharedPreferences`, not a database column, which is a deliberate
/// departure from the drawn design** (it said "one nullable column"). Three reasons,
/// in order of weight:
///
///  * It is a device preference of exactly the same character as
///    `book_source_preference`, and it sits beside that row in Settings. The same
///    kind of setting living in two different mechanisms is a thing to explain
///    forever.
///  * `books.reader_app` sat **unapplied on production for this feature's entire
///    life**, silently killing its second intent. That is a recent and expensive
///    argument against adding a column when nothing requires one.
///  * Nothing here needs to be queried, joined, or shared between users.
///
/// The cost is real and small: a reinstall re-asks. One field, once.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/providers/book_search_provider.dart'
    show sharedPreferencesProvider;
import 'package:bookworm_friends/services/libby_library_lookup.dart';

const String _keyPref = 'libby_library_key';
const String _namePref = 'libby_library_name';
const String _askedPref = 'libby_library_asked';

/// The `SharedPreferences` keys this notifier owns, exposed **for tests only**.
///
/// A widget test cannot call [LibbyLibraryNotifier.choose] before pumping, so it
/// seeds the store instead. Naming the keys here rather than letting each test
/// hard-code `'libby_library_key'` means a rename cannot leave a suite quietly
/// asserting against a preference nothing reads any more — and seeding the real
/// store has the side benefit of exercising [build]'s own parsing.
const libbyLibraryPrefKeys = (
  key: _keyPref,
  name: _namePref,
  asked: _askedPref,
);

/// Which library the reader picked, or the fact that they were asked and did not.
class LibbyLibraryChoice {
  const LibbyLibraryChoice({this.key, this.name, required this.asked});

  /// Never offered the picker. The one state that may open it unprompted.
  const LibbyLibraryChoice.unasked() : this(asked: false);

  /// Offered and dismissed. Links stay at the keyless fallback, and **the picker
  /// does not reappear** — Settings is where they change their mind.
  const LibbyLibraryChoice.declined() : this(asked: true);

  /// The `preferredKey`, e.g. `sfpl`. Null unless a library was chosen.
  final String? key;

  /// The system's display name, kept only so Settings can show what is stored
  /// without a network round trip to turn a key back into a name.
  final String? name;

  /// Whether the reader has been offered the picker at all.
  final bool asked;

  bool get hasLibrary => key != null;

  /// True only for a reader who has never seen the picker.
  bool get shouldAsk => !asked && key == null;

  @override
  String toString() => 'LibbyLibraryChoice($key, $name, asked: $asked)';
}

class LibbyLibraryNotifier extends Notifier<LibbyLibraryChoice> {
  @override
  LibbyLibraryChoice build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final key = prefs.getString(_keyPref);
    return LibbyLibraryChoice(
      // An empty stored string reads as absent. Cheap insurance: it is the shape a
      // half-finished write would leave, and an empty key in a URL would produce
      // `library//title/…`, which is Libby's malformed-library error all over again.
      key: (key != null && key.isNotEmpty) ? key : null,
      name: prefs.getString(_namePref),
      asked: prefs.getBool(_askedPref) ?? false,
    );
  }

  /// Records a chosen library. Also marks the reader as asked, so a later `clear()`
  /// does not resurrect the picker.
  Future<void> choose(String key, String name) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_keyPref, key);
    await prefs.setString(_namePref, name);
    await prefs.setBool(_askedPref, true);
    state = LibbyLibraryChoice(key: key, name: name, asked: true);
  }

  /// Records that the picker was shown and dismissed.
  ///
  /// Deliberately still `asked: true` with no key: the reader gets the keyless
  /// fallback, which works, and is not asked again.
  Future<void> decline() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_keyPref);
    await prefs.remove(_namePref);
    await prefs.setBool(_askedPref, true);
    state = const LibbyLibraryChoice.declined();
  }

  /// Forgets the stored library from Settings.
  ///
  /// **Lands in `declined`, not `unasked`.** Clearing it in Settings is a considered
  /// act; having the picker then ambush them on the next book would read as the app
  /// arguing. Settings is where they set it again.
  Future<void> clear() => decline();
}

final libbyLibraryProvider =
    NotifierProvider<LibbyLibraryNotifier, LibbyLibraryChoice>(
      LibbyLibraryNotifier.new,
    );

/// Search results for a query, debounced by the caller.
///
/// `autoDispose` and `family`: the sheet is transient and every keystroke is a
/// different key, so results are cached while the sheet lives and dropped with it.
/// Never throws — `libbyLibrarySearch` turns every failure into an empty list.
final libbyLibrarySearchProvider = FutureProvider.autoDispose
    .family<List<LibbyLibrary>, String>(
      (ref, query) => libbyLibrarySearch(query),
    );
