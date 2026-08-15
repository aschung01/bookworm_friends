// Shared harness for widget tests that need the real `HomePage`.
//
// `HomePage` pulls in auth, profile, following and library providers, so pumping
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

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/profile_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/pages/home_page.dart';

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
}) => Book(
  id: id,
  userId: 'u',
  shelfId: shelfId,
  isbn: id,
  title: title ?? id,
  thumbnail: '',
  status: status,
  position: position,
  createdAt: DateTime(2024),
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

/// Pumps [HomePage] with everything stubbed out. Pass [extraOverrides] to swap
/// in fakes for whatever the test under exercise touches (e.g.
/// `libraryActionsProvider`); they are applied last, so they win.
Future<void> pumpHome(
  WidgetTester tester, {
  List<Shelf>? shelves,
  List<Override> extraOverrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('u'),
        libraryProvider.overrideWith(
          () => FakeLibraryNotifier(shelves ?? singleBookLibrary()),
        ),
        finishedBooksProvider.overrideWith((ref, filter) async => <Book>[]),
        profileProvider.overrideWith(
          (ref) async => Profile(
            id: 'u',
            username: 'tester',
            emoji: '📚',
            createdAt: DateTime(2024),
            updatedAt: DateTime(2024),
          ),
        ),
        followingListProvider.overrideWith((ref) async => <Profile>[]),
        ...extraOverrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Enters edit mode via the pencil. Cannot use `pumpAndSettle` afterwards: the
/// covers wiggle on a repeating animation.
Future<void> enterEditMode(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// True while the library is in edit mode. Keyed off the `Done` button, which
/// only exists in that mode.
bool isEditing() => find.text('Done').evaluate().isNotEmpty;
