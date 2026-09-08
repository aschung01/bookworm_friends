// Not a test — a renderer. Draws **the real library** as spines, before and after the
// background-colour policy, so the change can be rejected on sight.
//
//   # 1. produce the ledger (see cover_color_backfill_tool.dart for the dump step)
//   flutter test test/cover_color_backfill_tool.dart \
//     --dart-define=user=<uuid> --dart-define=verify=true
//
//   # 2. draw it
//   flutter test test/read_pile_real_preview.dart
//
// `read_pile_render_preview.dart` renders a hand-picked corpus of ten, which is the
// right tool for checking silhouettes and the turn. It is the wrong tool for checking
// a *colour policy*, and the history of this widget is the argument: the design it
// replaced was validated on thirteen drawn books, of which exactly one was pale. At
// that ratio a dark-on-pale label reads as a mistake, so the design darkened
// everything — and on the real library 76% of covers were being darkened and roughly
// half of them are pale. **The corpus was the bug.**
//
// So this reads the tool's TSV and draws every row of it twice: the `stored` column as
// it is on the shelf today, and the `resolved` column as the policy would leave it.
// Rows of 18, because 74 spines do not fit across a phone.
//
// Real fonts are not loaded, so the titles are boxes. What is being looked at is
// whether the row still reads as a row of books.

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
import 'package:bookworm_friends/ui/widgets/read_pile.dart';

const String _ledger = 'build/backfill/cover_colors.tsv';
const int _perRow = 18;

/// One row of the tool's TSV: title, the colour on the shelf now, the colour the
/// policy resolves to.
typedef _Row = ({String title, Color? stored, Color resolved});

Color _parse(String hex) =>
    Color(0xFF000000 | int.parse(hex.replaceAll('#', ''), radix: 16));

List<_Row> _read() {
  final file = File(_ledger);
  if (!file.existsSync()) {
    fail('missing $_ledger — run cover_color_backfill_tool.dart first');
  }
  final lines = file
      .readAsLinesSync()
      .skip(1)
      .where((l) => l.trim().isNotEmpty);
  return [
    for (final line in lines)
      if (line.split('\t') case [final title, final stored, final res, ...])
        (
          title: title,
          stored: stored == '-' ? null : _parse(stored),
          resolved: _parse(res),
        ),
  ];
}

/// Books whose only meaningful field is the colour under test.
///
/// The ISBN is synthesised from the index rather than taken from the dump, so a
/// spine's *size* is identical in the before and after frames. Two images that differ
/// in width as well as in colour cannot be compared by flicking between them, which is
/// the only way a reviewer will actually look at them.
List<Book> _books(List<_Row> rows, int from, int to, bool after) => [
  for (var i = from; i < to && i < rows.length; i++)
    Book(
      id: 'b$i',
      userId: 'u',
      shelfId: 's1',
      isbn: '978890121${(9000 + i).toString().padLeft(4, '0')}',
      title: rows[i].title,
      thumbnail: '',
      status: 2,
      position: i,
      createdAt: DateTime(2024),
      authors: const [],
      finishDate: DateTime(2024, 3, 1),
      coverColor: after ? rows[i].resolved : rows[i].stored,
    ),
];

Widget _host(List<List<Book>> rows) => ProviderScope(
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      backgroundColor: AppColors.light.sheetBackground,
      body: Center(
        child: RepaintBoundary(
          key: const ValueKey('shot'),
          child: DecoratedBox(
            // `sheetBackground`, not `surface`, because that is what is actually
            // behind the pile: it is the `collapsedBody` of a bottom sheet. Worth
            // being exact about, because `BookVertical` decides whether a spine needs
            // an outline by measuring against `surface` (#FFFFFF) while the colour it
            // is really seen against is #EFF5EF. The two are close enough that the
            // outline still fires, so this is a latent bug rather than a live one —
            // but it is measuring the wrong thing.
            decoration: BoxDecoration(color: AppColors.light.sheetBackground),
            child: SizedBox(
              width: 720,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [for (final books in rows) ReadPile(books: books)],
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _shoot(
  WidgetTester tester,
  Directory dir,
  String name, {
  double pixelRatio = 2,
}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  late Uint8List png;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    png = data!.buffer.asUint8List();
  });
  File('${dir.path}/$name.png').writeAsBytesSync(png);
}

Future<void> _frame(
  WidgetTester tester,
  Directory dir,
  List<_Row> rows,
  bool after,
) async {
  final slices = <List<Book>>[];
  for (var i = 0; i < rows.length; i += _perRow) {
    slices.add(_books(rows, i, i + _perRow, after));
  }
  await tester.pumpWidget(_host(slices));
  await tester.pumpAndSettle();
  await _shoot(tester, dir, after ? 'after' : 'before');
}

void main() {
  testWidgets('render the real library before and after', (tester) async {
    final rows = _read();
    final height = 60 + ((rows.length / _perRow).ceil()) * 200;
    tester.view.physicalSize = Size(760 * 2, height * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final dir = Directory('build/pile_preview')..createSync(recursive: true);

    await _frame(tester, dir, rows, false);
    await _frame(tester, dir, rows, true);

    // The pale run, magnified. A full frame at 2x cannot answer the question that
    // matters about it — whether a 1pt hairline is enough to make a white spine a
    // *shape* — and this design's whole history is of colour decisions that measured
    // fine and looked wrong. So the palest twelve books in the library are drawn
    // together at 6x, which is both the worst case and the case a shelf will actually
    // produce, because a reader's white books arrive in runs.
    final palest =
        (rows.toList()..sort(
              (a, b) => b.resolved.computeLuminance().compareTo(
                a.resolved.computeLuminance(),
              ),
            ))
            .take(12)
            .toList();
    tester.view.physicalSize = const Size(760 * 6, 260 * 6);
    tester.view.devicePixelRatio = 6;
    await tester.pumpWidget(_host([_books(palest, 0, 12, true)]));
    await tester.pumpAndSettle();
    await _shoot(tester, dir, 'after_palest', pixelRatio: 6);

    // ignore: avoid_print
    print('${rows.length} books → ${dir.path}/before.png, after.png');
    // ignore: avoid_print
    print(
      'palest twelve: '
      '${palest.map((r) => r.resolved.toARGB32().toRadixString(16).substring(2)).join(' ')}',
    );
  });
}
