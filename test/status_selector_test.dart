// Tests for the reading-status picker used when saving a book.
//
// Three mutually exclusive options, so on iOS 26 this is a native
// `CNSegmentedControl`; everywhere else it stays the app's pill chips. Both
// report the chosen status as its index (0 interested, 1 reading, 2 finished).
//
// `debugDefaultTargetPlatformOverride` picks the rendering and must be cleared
// inside the test body: flutter_test asserts no debug variable outlives a test.

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';
import 'package:bookworm_friends/ui/widgets/status_selector.dart';

const _labels = ['Interested', 'Reading', 'Read'];

Widget _wrap({required int status, required ValueChanged<int> onChanged}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: BookStatusSelector(
          labels: _labels,
          status: status,
          onChanged: onChanged,
        ),
      ),
    ),
  );
}

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
  group('native glass rendering', () {
    testWidgets(
      'Given a status, Then a native segmented control shows it as selected',
      (tester) async {
        await _asPlatform(TargetPlatform.iOS, () async {
          if (!useNativeGlass) return;

          await tester.pumpWidget(_wrap(status: 1, onChanged: (_) {}));

          final control = tester.widget<CNSegmentedControl>(
            find.byType(CNSegmentedControl),
          );
          expect(control.labels, _labels);
          expect(control.selectedIndex, 1);
        });
      },
    );

    testWidgets('When a segment is chosen, Then its status index is reported', (
      tester,
    ) async {
      await _asPlatform(TargetPlatform.iOS, () async {
        if (!useNativeGlass) return;

        final chosen = <int>[];
        await tester.pumpWidget(_wrap(status: 0, onChanged: chosen.add));

        tester
            .widget<CNSegmentedControl>(find.byType(CNSegmentedControl))
            .onValueChanged(2);

        expect(chosen, [2]);
      });
    });

    testWidgets(
      'Given an out-of-range status, Then the selection stays within bounds',
      (tester) async {
        await _asPlatform(TargetPlatform.iOS, () async {
          if (!useNativeGlass) return;

          await tester.pumpWidget(_wrap(status: 7, onChanged: (_) {}));

          expect(
            tester
                .widget<CNSegmentedControl>(find.byType(CNSegmentedControl))
                .selectedIndex,
            _labels.length - 1,
          );
          expect(tester.takeException(), isNull);
        });
      },
    );
  });

  group('material fallback', () {
    testWidgets('Given a status, Then every option is offered as a chip', (
      tester,
    ) async {
      await _asPlatform(TargetPlatform.android, () async {
        await tester.pumpWidget(_wrap(status: 0, onChanged: (_) {}));

        expect(find.byType(CNSegmentedControl), findsNothing);
        for (final label in _labels) {
          expect(find.text(label), findsOneWidget);
        }
      });
    });

    testWidgets('When a chip is tapped, Then its status index is reported', (
      tester,
    ) async {
      await _asPlatform(TargetPlatform.android, () async {
        final chosen = <int>[];
        await tester.pumpWidget(_wrap(status: 0, onChanged: chosen.add));

        await tester.tap(find.text('Read'));
        await tester.pump();

        expect(chosen, [2]);
      });
    });
  });
}
