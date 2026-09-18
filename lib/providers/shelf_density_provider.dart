import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/providers/book_search_provider.dart';

const String _prefKey = 'shelf_density';

/// How a shelf draws the books that are not in progress.
///
/// A shelf is one horizontal row and only **3.57** face-out covers fit in it on a
/// 390pt phone, so a twelve-book shelf shows three and a sliver. These are two answers
/// to that, and the compressed one gets a shelf to about ten books — or about twelve
/// when nothing on it is in progress.
///
/// **There was a third, and it was withdrawn.** `leaning` shingled the compressed
/// books at a fixed step so they overlapped like cards, leaning right with the leftmost
/// frontmost. It was the densest of the three and it worked, in the end — but the
/// overlap is what a reader has to reason about to use it: at a quarter of a cover the
/// recognition is being done by colour rather than by type, taps have to be aimed at a
/// 20pt strip on each book's *trailing* edge, and bringing one book forward has to push
/// its neighbours both ways to get out from under them. A spine is a thing readers
/// already know how to look at, and it costs about two books of density to say so.
///
/// **Deliberately not a widening of `LibraryMode`.** That enum is about what the
/// reader is *doing*; this is about how books are *drawn*. The two are orthogonal
/// — edit mode draws each density as itself — so one enum of four states would have
/// two aliases in it.
enum ShelfDensity {
  /// Face-out covers, 15pt apart. The row as it has always been drawn.
  covers,

  /// In-progress books face-out; the rest spine-on, per `BookVertical`.
  spines,
}

extension ShelfDensityCycle on ShelfDensity {
  /// The next density the library bar's button moves to.
  ///
  /// Here rather than in the button, so the cycle has one definition and a second
  /// caller — a test, a shortcut, a settings row — cannot get a different order.
  ///
  /// At two states this is a toggle, and the button is still built as a cycle. Keeping
  /// it that way costs a modulo and leaves the third state re-addable without touching
  /// the control; collapsing it into `!` would put the shape of the enum into the
  /// button.
  ShelfDensity get next =>
      ShelfDensity.values[(index + 1) % ShelfDensity.values.length];
}

/// Persists the reader's preferred [ShelfDensity].
///
/// **A preference of the reader, not a property of a library**, so it applies to
/// every library on screen — their own and a friend's alike. An unfamiliar shelf is
/// where seeing all twelve books beats seeing three and a sliver, so there is no
/// case for exempting a visit.
///
/// **Persisted, and deliberately not in `library_shell_provider.dart`.** Everything
/// there is `StateProvider.autoDispose` that dies with the session — the tab, the
/// edit mode, the year filters — because it describes a moment. This is the same
/// category as [ThemeModeNotifier] and the search-source preference: a standing
/// answer about how the reader likes to be shown things, which should survive a
/// relaunch.
///
/// It is **not** stored on `profiles`, and that was a considered decision rather
/// than a shortcut. A profile field would make the toggle publish: the common use
/// is to flick to spines, check a shelf and flick back, and under a shared field
/// every friend's next visit would show spines because of it. Letting a reader
/// author how their library is presented to visitors is a *second* setting, with a
/// label and a preview, and it does not exist yet.
class ShelfDensityNotifier extends Notifier<ShelfDensity> {
  @override
  ShelfDensity build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return _parse(prefs.getString(_prefKey));
  }

  Future<void> set(ShelfDensity density) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_prefKey, _serialize(density));
    state = density;
  }

  /// Advances one step round the cycle. What the library bar's button calls.
  Future<void> cycle() => set(state.next);

  /// **Anything unrecognised is [ShelfDensity.covers], not an error.** A stored
  /// name that a later version has renamed or removed must not throw on launch,
  /// and the row as it has always been drawn is the safe thing to fall back to.
  ///
  /// `'leaning'` is the one exception, and it is a migration rather than a fallback.
  /// The withdrawn third density was the *other* compressed one, so a reader who had
  /// chosen it had asked for a shelf that fits rather than for covers; dropping them
  /// back to `covers` would answer a question they did not ask. This can go once no
  /// stored preference can plausibly still say it.
  static ShelfDensity _parse(String? value) {
    switch (value) {
      case 'spines':
      case 'leaning':
        return ShelfDensity.spines;
      default:
        return ShelfDensity.covers;
    }
  }

  static String _serialize(ShelfDensity density) {
    switch (density) {
      case ShelfDensity.covers:
        return 'covers';
      case ShelfDensity.spines:
        return 'spines';
    }
  }
}

final shelfDensityProvider =
    NotifierProvider<ShelfDensityNotifier, ShelfDensity>(
      ShelfDensityNotifier.new,
    );
