// Tests for the reading-date rules shared by the "save a book" and "change
// status" sheets.
//
// A book cannot be finished before it was started, and cannot be read in the
// future. Two enforcement points:
//   1. The finish-date picker is bounded below by the start date.
//   2. Moving the start date past an existing finish date carries the finish
//      date along, so the pair can never end up inverted.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_date_bottom_sheet.dart';

Future<void> _pumpPicker(
  WidgetTester tester, {
  required DateTime initialDate,
  DateTime? minimumDate,
  required ValueChanged<DateTime> onDateSelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showSelectDateBottomSheet(
                context,
                initialDate: initialDate,
                minimumDate: minimumDate,
                onDateSelected: onDateSelected,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

CupertinoDatePicker _picker(WidgetTester tester) =>
    tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));

void main() {
  group('date bounds', () {
    testWidgets(
      'Given a start date, Then the finish picker cannot go earlier than it',
      (tester) async {
        final start = DateTime(2026, 8, 10);

        await _pumpPicker(
          tester,
          initialDate: start,
          minimumDate: start,
          onDateSelected: (_) {},
        );

        expect(_picker(tester).minimumDate, start);
      },
    );

    testWidgets(
      'Given a finish date already before the start, Then the picker opens on the start date',
      (tester) async {
        final start = DateTime(2026, 8, 10);

        // This is the state from the bug report: finish (08.09) precedes start
        // (08.10). The picker must not open on an out-of-bounds value.
        await _pumpPicker(
          tester,
          initialDate: DateTime(2026, 8, 9),
          minimumDate: start,
          onDateSelected: (_) {},
        );

        expect(_picker(tester).initialDateTime, start);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Given no minimum, Then only the future is excluded', (
      tester,
    ) async {
      await _pumpPicker(
        tester,
        initialDate: DateTime(2020, 1, 5),
        onDateSelected: (_) {},
      );

      final picker = _picker(tester);
      expect(picker.minimumDate, isNull);
      expect(picker.maximumDate, dateOnly(DateTime.now()));
    });

    testWidgets('Given a future initial date, Then it is clamped to today', (
      tester,
    ) async {
      await _pumpPicker(
        tester,
        initialDate: DateTime.now().add(const Duration(days: 30)),
        onDateSelected: (_) {},
      );

      expect(_picker(tester).initialDateTime, dateOnly(DateTime.now()));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'When a date is confirmed, Then it is reported without a time',
      (tester) async {
        final reported = <DateTime>[];

        await _pumpPicker(
          tester,
          initialDate: DateTime(2026, 8, 10, 13, 45),
          onDateSelected: reported.add,
        );

        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();

        expect(reported, [DateTime(2026, 8, 10)]);
      },
    );
  });

  group('dateOnly', () {
    test('strips the time so same-day values compare equal', () {
      expect(
        dateOnly(DateTime(2026, 8, 10, 23, 59)),
        dateOnly(DateTime(2026, 8, 10, 0, 1)),
      );
    });
  });
}
