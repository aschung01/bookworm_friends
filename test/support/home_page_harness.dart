// Shared harness for widget tests that need the real `HomePage`.
//
// `HomePage` pulls in auth, profile, friends and library providers, so pumping
// it takes a fair amount of scaffolding. More than one test file needs it, so it
// lives here rather than being copied.
//
// Two traps to know about:
//   1. `Wiggle` calls `AnimationController.repeat()` in edit mode, so
//      `pumpAndSettle()` never returns once edit mode is on. Use `pump(duration)`
//      — which is what [enterEditMode] does.
//   2. Back is simulated with the same platform-channel message the engine
//      sends, mirroring Flutter's own `pop_scope_test.dart`.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/profile_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/providers/shell_chrome_provider.dart';
import 'package:bookworm_friends/ui/pages/home_page.dart';
import 'package:bookworm_friends/ui/widgets/shell_chrome.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/shell_tab_bar.dart';

import 'prefs.dart';

/// Sends the platform-channel message the engine sends on a system back.
/// Copied from Flutter's own `test/widgets/navigator_utils.dart`.
Future<void> simulateSystemBack() {
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'flutter/navigation',
        const JSONMessageCodec().encodeMessage(<String, dynamic>{
          'method': 'popRoute',
        }),
        (ByteData? _) {},
      );
}

/// Serves a fixture instead of hitting Supabase. Local mutations
/// (`removeBookLocally`, `reorderShelves`, …) still run for real.
class FakeLibraryNotifier extends LibraryNotifier {
  FakeLibraryNotifier(this.shelves);

  final List<Shelf> shelves;

  @override
  Future<List<Shelf>> build() async => shelves;
}

Book testBook(
  String id,
  String shelfId, {
  int position = 0,
  String? title,
  int status = 0,
  int? pageCount,
  DateTime? startDate,
  DateTime? finishDate,
  List<String> authors = const [],
}) => Book(
  id: id,
  userId: 'u',
  shelfId: shelfId,
  isbn: id,
  title: title ?? id,
  thumbnail: '',
  status: status,
  position: position,
  pageCount: pageCount,
  startDate: startDate,
  finishDate: finishDate,
  createdAt: DateTime(2024),
  authors: authors,
);

Shelf testShelf(String id, List<Book> books, {String? name}) => Shelf(
  id: id,
  userId: 'u',
  name: name ?? id,
  position: 0,
  createdAt: DateTime(2024),
  books: books,
);

/// A one-shelf, one-book library — enough for most edit-mode tests.
List<Shelf> singleBookLibrary() => [
  testShelf('s1', [testBook('b1', 's1', title: 'Clean Code')], name: 'Dev'),
];

/// `ShellChrome` sits above the navigator, so it needs a key to reach one. A
/// single global key is safe here because each test pumps one app at a time.
final _harnessNavigatorKey = GlobalKey<NavigatorState>();

/// Pumps [HomePage] with everything stubbed out. Pass [extraOverrides] to swap
/// in fakes for whatever the test under exercise touches (e.g.
/// `libraryActionsProvider`); they are applied last, so they win.
///
/// [textScaler] and [surfaceSize] exist for the clearance tests: the band of
/// library left between the bar and the sheet is worst on a small screen at a
/// large text scale, and that is exactly the case no default fixture covers.
///
/// Pass `settle: false` to stop at a couple of `pump`s. `LoadingLibrary`'s blocks
/// shimmer on a repeating animation, so `pumpAndSettle` never returns while the
/// library is still loading — the same trap [enterEditMode] documents for `Wiggle`.
Future<void> pumpHome(
  WidgetTester tester, {
  List<Shelf>? shelves,
  List<Override> extraOverrides = const [],
  TextScaler? textScaler,
  Size? surfaceSize,
  bool settle = true,
}) async {
  if (surfaceSize != null) {
    tester.view.physicalSize = surfaceSize * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // The card's display setting is a stored preference now, and the Card tab reads it
        // — so every tree with a `HomePage` in it needs somewhere to read it from.
        await sharedPreferencesOverride(),
        currentUserIdProvider.overrideWithValue('u'),
        libraryProvider.overrideWith(
          () => FakeLibraryNotifier(shelves ?? singleBookLibrary()),
        ),
        finishedBooksProvider.overrideWith((ref) async => <Book>[]),
        profileProvider.overrideWith(
          (ref) async => Profile(
            id: 'u',
            username: 'tester',
            emoji: '📚',
            createdAt: DateTime(2024),
            updatedAt: DateTime(2024),
          ),
        ),
        friendsProvider.overrideWith((ref) async => <Profile>[]),
        ...extraOverrides,
      ],
      child: Consumer(
        // `ref` for the observer, the way `main.dart` gets it from
        // `ConsumerState`. It has to be a provider instance rather than a fresh
        // `ShellRouteObserver` per build: an observer must outlive rebuilds.
        builder: (context, ref, _) => MaterialApp(
          navigatorKey: _harnessNavigatorKey,
          // The bar lives above the navigator now (see `ShellChrome`), so the
          // harness has to build the same shell the app does or no test would
          // find it. `ShellRouteObserver` publishes the top page route that
          // `shellBarVisibleProvider` compares against — without it the bar
          // never appears at all.
          navigatorObservers: [ref.watch(shellRouteObserverProvider)],
          // The app's own table, less its `/` entry — `home` may not coexist with
          // one. Without this any `pushNamed` from the shell throws instead of
          // navigating, which is the difference between a test that exercises a
          // destination and one that only proves a button exists.
          routes: {
            for (final entry in AppRoutes.routes.entries)
              if (entry.key != AppRoutes.splash) entry.key: entry.value,
          },
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) {
            final scaled = textScaler == null
                ? child!
                : MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: textScaler),
                    child: child!,
                  );
            return ShellChrome(
              navigatorKey: _harnessNavigatorKey,
              child: scaled,
            );
          },
          home: const HomePage(),
        ),
      ),
    ),
  );
  if (!settle) {
    // Two pumps rather than one: the first frame is where `ShellRouteObserver`
    // queues the microtask that publishes the top page route, and
    // `shellBarVisibleProvider` compares against it — without the second the tab
    // bar is not on screen yet and nothing about it can be asserted.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return;
  }
  await tester.pumpAndSettle();
}

/// Enters edit mode by long-pressing a cover, which is the only way in since the
/// bar's pencil was removed: `+` and the pencil were duplicate entry points
/// sitting in the most valuable row on screen, and `ShelfRow` already wired a
/// long-press to it.
///
/// Hand-rolled rather than `tester.longPress`, because [BookWidget] does not use
/// `GestureDetector.onLongPress`: it runs its own two-stage hold off a `Timer`
/// from `onTapDown`, and [kBookStageTwoDelay] is 700ms. A 500ms `longPress`
/// releases before that timer fires, which reads as a plain tap and pushes the
/// book's details page instead.
///
/// Cannot use `pumpAndSettle` afterwards: the covers wiggle on a repeating
/// animation.
Future<void> enterEditMode(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(BookWidget).first),
  );
  // Two pumps, not one. `onTapDown` does not fire on pointer-down: the tap
  // recognizer holds it until it wins the arena or its ~100ms deadline passes,
  // and only then is the 700ms stage-two timer scheduled. A single pump of 750ms
  // advances the clock past the deadline in one step, so the timer is scheduled
  // at 800ms and never fires before the release.
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pump(kBookStageTwoDelay + const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// True while the library is in edit mode. Keyed off the confirm button, which
/// only exists in that mode.
///
/// By tooltip rather than by text: the button used to be the word `Done` and is a
/// checkmark disc now, so its accessible name is the only part of it a test can
/// hold on to. `AdaptiveIconButton` hands [semanticLabel] to the fallback
/// `IconButton` as its tooltip, and the fallback is the only path `flutter test`
/// ever takes.
bool isEditing() => libraryDoneButton().evaluate().isNotEmpty;

/// The library bar's confirm button — the check that leaves edit mode.
Finder libraryDoneButton() => find.byTooltip('Done');

/// The [ProviderContainer] the harness's `ProviderScope` is backing, reached through
/// the pumped page.
///
/// For assertions about shell state that has no single widget of its own —
/// `selectedFriendProvider` and `friendsSheetLevelProvider` are the pair that
/// matters, since the navigation design is a claim about how they move together and
/// the UI shows their *consequences* rather than their values.
ProviderContainer shellContainer(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(HomePage)));

/// Enters a visit the way the shell intends: the Friends tab's Everyone list.
///
/// There is no other way in, and there is deliberately no longer a second one. The
/// `FriendRail` and the lateral swipe that used to move between friends are gone, so
/// this list is both the entry point and the switcher — tapping a row here is what
/// every test means by "visiting".
///
/// Leaves the Friends sheet on its **second level**, showing that friend's read
/// books, which is where a tap on a row lands. `find.text(username)` will not match
/// afterwards: the list it was in has been swapped for her pile.
Future<void> enterVisit(WidgetTester tester, String username) async {
  await tester.tap(
    find.descendant(
      of: find.byType(ShellTabBar),
      matching: find.text('Friends'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(username));
  await tester.pumpAndSettle();
}

/// Goes back up to the Friends list from a friend's read books, **without** ending
/// the visit: her library stays behind the sheet.
///
/// Tapping the Friends tab — which is already the selected tab at that point — is the
/// whole of the gesture. There is no control inside the sheet, deliberately.
Future<void> backToFriendsList(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(ShellTabBar),
      matching: find.text('Friends'),
    ),
  );
  await tester.pumpAndSettle();
}

/// Ends the visit through the library bar's ✕, which is where the rail's used to be.
Future<void> endVisit(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.close));
  await tester.pumpAndSettle();
}
