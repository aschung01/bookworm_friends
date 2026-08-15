// Tests for the shelf picker used when saving a book.
//
// Two renderings, one behaviour: on iOS 26 the trailing control is a native
// `CNPopupMenuButton` (a real UIMenu, checkmark on the current shelf); anywhere
// else it is the themed Material dropdown. Both report the chosen shelf name.
//
// `debugDefaultTargetPlatformOverride` selects the rendering (together with the
// host OS version) and has to be set *and* cleared inside each test body:
// flutter_test asserts no foundation debug variable outlives a test.

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';
import 'package:bookworm_friends/ui/widgets/shelf_selector.dart';

const _shelves = ['자기계발', 'Novels', 'Textbooks'];

Widget _wrap({
  required List<String> shelves,
  String? selected,
  required ValueChanged<String> onChanged,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ShelfSelector(
          label: 'Select shelf',
          shelves: shelves,
          selected: selected,
          onChanged: onChanged,
        ),
      ),
    ),
  );
}

/// Runs [body] with [platform] reported as the target platform.
Future<void> _asPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  testWidgets('Given no shelves, Then nothing is rendered', (tester) async {
    await tester.pumpWidget(_wrap(shelves: const [], onChanged: (_) {}));

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.byType(CNPopupMenuButton), findsNothing);
    expect(find.text('Select shelf'), findsNothing);
  });

  group('native glass rendering', () {
    testWidgets(
      'Given a selected shelf, Then a native menu button shows it and checks it',
      (tester) async {
        await _asPlatform(TargetPlatform.iOS, () async {
          // Only meaningful on a host that reports glass support.
          if (!useNativeGlass) return;

          await tester.pumpWidget(
            _wrap(shelves: _shelves, selected: 'Novels', onChanged: (_) {}),
          );

          final button = tester.widget<CNPopupMenuButton>(
            find.byType(CNPopupMenuButton),
          );

          expect(button.buttonLabel, 'Novels');
          expect(button.buttonStyle, CNButtonStyle.glass);
          expect(button.items.length, _shelves.length);

          final checked = button.items
              .whereType<CNPopupMenuItem>()
              .where((item) => item.checked)
              .map((item) => item.label)
              .toList();
          expect(checked, ['Novels']);

          // The field keeps its label alongside the native control.
          expect(find.text('Select shelf'), findsOneWidget);
        });
      },
    );

    testWidgets(
      'Given no explicit selection, Then the first shelf is shown as current',
      (tester) async {
        await _asPlatform(TargetPlatform.iOS, () async {
          if (!useNativeGlass) return;

          await tester.pumpWidget(_wrap(shelves: _shelves, onChanged: (_) {}));

          expect(
            tester
                .widget<CNPopupMenuButton>(find.byType(CNPopupMenuButton))
                .buttonLabel,
            _shelves.first,
          );
        });
      },
    );

    testWidgets('When a menu item is chosen, Then its shelf name is reported', (
      tester,
    ) async {
      await _asPlatform(TargetPlatform.iOS, () async {
        if (!useNativeGlass) return;

        final chosen = <String>[];
        await tester.pumpWidget(
          _wrap(
            shelves: _shelves,
            selected: _shelves.first,
            onChanged: chosen.add,
          ),
        );

        // The menu itself is native, so drive the callback the platform invokes.
        tester
            .widget<CNPopupMenuButton>(find.byType(CNPopupMenuButton))
            .onSelected(2);

        expect(chosen, ['Textbooks']);
      });
    });
  });

  group('material fallback', () {
    testWidgets('Given a selected shelf, Then the dropdown shows it', (
      tester,
    ) async {
      await _asPlatform(TargetPlatform.android, () async {
        await tester.pumpWidget(
          _wrap(shelves: _shelves, selected: 'Novels', onChanged: (_) {}),
        );

        expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
        expect(find.text('Novels'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('When another shelf is picked, Then it is reported', (
      tester,
    ) async {
      await _asPlatform(TargetPlatform.android, () async {
        final chosen = <String>[];
        await tester.pumpWidget(
          _wrap(
            shelves: _shelves,
            selected: _shelves.first,
            onChanged: chosen.add,
          ),
        );

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Textbooks').last);
        await tester.pumpAndSettle();

        expect(chosen, ['Textbooks']);
      });
    });
  });
}
