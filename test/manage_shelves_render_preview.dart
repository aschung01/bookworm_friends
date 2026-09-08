// Not a test — a renderer. Writes PNGs of the "Manage shelves" sheet to
// build/manage_shelves_preview/ so the cover previews can be judged by eye:
// their size against the row, how much of each face the overlap leaves, and
// whether the ring keeps two dark covers apart.
//
//   flutter test test/manage_shelves_render_preview.dart
//
// Two frames, light and dark, because the ring around each cover is drawn in the
// sheet's own colour and dark mode is the case it exists for — covers there are
// dark shapes on a dark ground and merge into one blob without it.
//
// Text renders as the test font's boxes, as in every renderer here. What is being
// looked at is geometry, not typography. Covers are the generated colour blocks
// rather than art: a widget test has no network, which also makes this the honest
// preview of a shelf of coverless books.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/manage_shelves_bottom_sheet.dart';

/// Serves a fixture; the sheet reads shelves straight from the provider.
class _FakeLibraryNotifier extends LibraryNotifier {
  _FakeLibraryNotifier(this.shelves);

  final List<Shelf> shelves;

  @override
  Future<List<Shelf>> build() async => shelves;
}

Shelf _shelf(String id, String name, int bookCount, {int status = 0}) => Shelf(
  id: id,
  userId: 'u',
  name: name,
  position: 0,
  createdAt: DateTime(2024),
  books: List.generate(
    bookCount,
    (i) => Book(
      id: '$id-$i',
      userId: 'u',
      shelfId: id,
      // The generated cover's hue is hashed from the ISBN, so these have to
      // differ or the stack is one colour and the overlap becomes invisible.
      isbn: '$id$i',
      title: 'Book $i',
      thumbnail: '',
      status: status,
      position: i,
      createdAt: DateTime(2024),
    ),
  ),
);

/// Counts chosen to cover every case the row has: more books than the cap allows,
/// a full stack, a long name, a single cover, an empty shelf, and a shelf whose
/// books are all read — which the library draws in its pile, so this row must show
/// the same nothing the plank does.
final _shelves = [
  _shelf('a', 'Leadership', 7),
  _shelf('b', 'Society', 3),
  _shelf('c', 'A shelf whose name is far too long to fit on one line', 4),
  _shelf('d', 'Finance', 1),
  _shelf('e', 'Empty', 0),
  _shelf('f', 'All read', 5, status: bookStatusFinished),
];

Widget _app(ThemeData theme) => ProviderScope(
  overrides: [
    libraryProvider.overrideWith(() => _FakeLibraryNotifier(_shelves)),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    // Wraps the Navigator rather than the home page, which is what puts the
    // modal route's overlay inside the boundary being captured.
    builder: (context, child) =>
        RepaintBoundary(key: const ValueKey('shot'), child: child!),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showManageShelvesBottomSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _shoot(WidgetTester tester, Directory dir, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  late Uint8List png;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    png = data!.buffer.asUint8List();
  });
  File('${dir.path}/$name.png').writeAsBytesSync(png);
}

Future<void> _renderSheet(
  WidgetTester tester,
  ThemeData theme,
  String name,
) async {
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final dir = Directory('build/manage_shelves_preview')
    ..createSync(recursive: true);

  await tester.pumpWidget(_app(theme));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await _shoot(tester, dir, name);

  // ignore: avoid_print
  print('wrote ${dir.absolute.path}/$name.png');
}

// One frame per test rather than a loop in one: re-pumping a new theme into the
// same tree leaves the first sheet's route mid-dismiss, and its barrier then eats
// the tap that would open the second — which rendered an empty screen.
void main() {
  testWidgets(
    'render the manage shelves sheet in light',
    (tester) => _renderSheet(tester, AppTheme.light, 'light'),
  );

  testWidgets(
    'render the manage shelves sheet in dark',
    (tester) => _renderSheet(tester, AppTheme.dark, 'dark'),
  );
}
