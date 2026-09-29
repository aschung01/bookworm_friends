// Not a test — a renderer. Writes PNGs of the read sheet's completion filter to
// build/read_filter_preview/ so it can be judged by eye.
//
//   flutter test test/read_set_filter_render_preview.dart
//
// **Three things here can only be judged by looking, and two of them are geometry the
// suite is structurally unable to see.**
//
//  1. **The card occludes the year rail.** That is recorded in the design as accepted
//     rather than designed away, and "accepted" is a judgement about how much of the
//     rail goes — which no assertion states. Drawn to scale it should cover the first
//     capsules and leave the reader in no doubt the rail is still there under it.
//  2. **The dog-ear.** A widget test can find the fold and measure its box; whether a
//     triangle of the sheet's own ground reads as a *folded corner* rather than as a
//     rendering glitch is a looking question, and it is the whole point of the mark.
//  3. **The fold against a pale cover.** The flap is the sheet's ground, so on a cover
//     that happens to be near the sheet's colour only the cast shadow remains. The
//     generated covers here are hashed off the ISBN, so this frame carries a light one
//     on purpose.
//
// Both themes, because the fold's flap *is* the theme's `sheetBackground`: in light it
// is a pale corner cut out of a coloured jacket, and in dark it is a dark one. Those are
// two different drawings of one idea and only one of them has been reasoned about.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
// `FontLoader` lives here, not in `flutter_test`.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/finished_books_sheet.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';

/// The narrowest phone the app supports, at a height that leaves the sheet its real
/// band — the point is the sheet's own proportions, not a tall frame.
const _surface = Size(390, 800);

Book _book(String id, String title, DateTime? closed, {required int status}) =>
    Book(
      id: id,
      userId: 'u',
      shelfId: 's',
      isbn: id,
      title: title,
      thumbnail: '',
      status: status,
      position: 0,
      finishDate: closed,
      createdAt: DateTime(2024),
    );

/// Eight finished books in one month plus four in the next, so the grid shows two
/// headers and two full rows — the fold has to be judged in a row of covers, not alone.
List<Book> _finished() => [
  for (var i = 0; i < 8; i++)
    _book('fin-$i', 'Book $i', DateTime(2026, 3, 28 - i), status: 2),
  for (var i = 0; i < 4; i++)
    _book('feb-$i', 'Older $i', DateTime(2026, 2, 20 - i), status: 2),
];

/// Three set aside, spread through the first row rather than bunched at its end, which
/// is also the check that the merge sorts by date.
List<Book> _setAside() => [
  _book('aside-a', 'Ulysses', DateTime(2026, 3, 26), status: 3),
  _book('aside-b', 'Wolf Hall', DateTime(2026, 3, 21), status: 3),
  _book('aside-c', 'Middlemarch', DateTime(2026, 2, 18), status: 3),
];

Widget _host(ThemeData theme) {
  return ProviderScope(
    child: RepaintBoundary(
      key: const ValueKey('shot'),
      // **Outside the `MaterialApp`, deliberately.** The filter is a route, so its card
      // is drawn into the app's own `Overlay`; a boundary inside the sheet would capture
      // the frame the card is over and none of the card.
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            backgroundColor: context.colors.pageBackground,
            body: _Host(theme: theme),
          ),
        ),
      ),
    ),
  );
}

class _Host extends StatefulWidget {
  const _Host({required this.theme});

  final ThemeData theme;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int _year = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Stands in for the library behind the sheet: the rail and the card are both
        // drawn over *something*, and a transparent gap would flatter both.
        Expanded(child: ColoredBox(color: context.colors.pageBackground)),
        FinishedBooksSheet(
          books: _finished(),
          setAsideBooks: _setAside(),
          isEditMode: false,
          filterYear: _year,
          maxExtent: _surface.height,
          onFilterChanged: (year) => setState(() => _year = year),
        ),
      ],
    );
  }
}

Future<void> _shoot(WidgetTester tester, Directory dir, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  late Uint8List png;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    png = data!.buffer.asUint8List();
  });
  File('${dir.path}/$name.png').writeAsBytesSync(png);
}

/// Registers the app's real sans, so the title is type rather than Ahem boxes.
///
/// One cut, `subtitle`'s w600: `FontLoader` carries no weight information, so handing it
/// several Pretendard statics would let the engine answer any weight with whichever
/// arrived first. The title is the object under review here, so it gets the cut — which
/// draws the popover's w400 rows a little heavy, and that is the right way round.
///
/// **And the icon font, which is the one nobody remembers.** `flutter test` replaces
/// every font with Ahem, icons included, so without this the chevron and the menu's
/// check both render as an empty square — which looks exactly like a missing glyph in
/// the app and is the detail this frame exists to judge. See [_materialIcons].
Future<void> _loadRealFonts() async {
  final loader = FontLoader('Pretendard')
    ..addFont(_font('assets/fonts/Pretendard-SemiBold.otf'));
  await loader.load();

  final icons = _materialIcons();
  if (icons == null) {
    stdout.writeln('no MaterialIcons font found; icons will be squares');
    return;
  }
  await (FontLoader('MaterialIcons')..addFont(_font(icons.path))).load();
}

/// The SDK's icon font, found by walking up from whatever binary is running us.
///
/// Not a hardcoded path, and not one fixed number of `parent`s either: under
/// `flutter test` the executable is `flutter_tester`, three levels under
/// `bin/cache/artifacts`, and under `dart test` it is `bin/cache/dart-sdk/bin/dart`,
/// four levels down a different branch. Walking up until `artifacts/material_fonts`
/// appears is the one rule that holds for both.
File? _materialIcons() {
  var dir = Directory(Platform.resolvedExecutable).parent;
  for (var up = 0; up < 8; up++) {
    final font = File(
      '${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (font.existsSync()) return font;
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  return null;
}

Future<ByteData> _font(String path) async {
  final bytes = File(path).readAsBytesSync();
  return ByteData.view(Uint8List.fromList(bytes).buffer);
}

void main() {
  setUpAll(_loadRealFonts);

  testWidgets('render the read sheet\'s completion filter', (tester) async {
    tester.view.physicalSize = _surface * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final dir = Directory('build/read_filter_preview')
      ..createSync(recursive: true);

    for (final theme in {
      'light': AppTheme.light,
      'dark': AppTheme.dark,
    }.entries) {
      // **A bare re-pump would carry the filter over.** `FinishedBooksSheet` holds the
      // chosen mode in its own `State`, and re-pumping the same widget type at the same
      // position hands that state to the new tree — so the dark run would open on
      // `Books read` and its first two frames would be the wrong screens. An empty frame
      // in between unmounts it.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_host(theme.value));
      await tester.pumpAndSettle();

      // The sheet opens on its pile; the chevron and the grid are both expanded-only.
      await tester.drag(find.text('Books finished'), const Offset(0, -700));
      await tester.pumpAndSettle();
      await _shoot(tester, dir, '${theme.key}-finished');

      // **The chevron, which is the whole target now.** It used to be the title: title,
      // count and chevron were one tap target until the menu became the platform's, and
      // UIKit presents a `UIMenu` from the button's own tap. See
      // `read_set_filter_popover.dart`.
      await tester.tap(
        find.descendant(
          of: find.byType(LibrarySheetTitle),
          matching: find.byIcon(Icons.keyboard_arrow_down),
        ),
      );
      await tester.pumpAndSettle();
      await _shoot(tester, dir, '${theme.key}-popover');

      await tester.tap(find.text('Show all read'));
      await tester.pumpAndSettle();
      await _shoot(tester, dir, '${theme.key}-all-read');
    }

    stdout.writeln('wrote ${dir.absolute.path}');
  });
}
