// Widget tests for BookStatusBadge.
//
// This doubles as a guard for the localization (gen-l10n) setup: the badge
// renders status labels via AppLocalizations, so these tests verify that the
// English and Korean ARB strings resolve and render correctly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/book_status_badge.dart';

Widget _wrap(Widget child, Locale locale) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  group('BookStatusBadge', () {
    testWidgets(
        'Given English locale, When status is reading, Then the English label is shown',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const BookStatusBadge(status: 1), const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('읽는 중'), findsNothing);
    });

    testWidgets(
        'Given Korean locale, When status is reading, Then the Korean label is shown',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const BookStatusBadge(status: 1), const Locale('ko')),
      );
      await tester.pumpAndSettle();

      expect(find.text('읽는 중'), findsOneWidget);
    });

    testWidgets(
        'Given English locale, When status is finished, Then the "Read" label is shown',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const BookStatusBadge(status: 2), const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Read'), findsOneWidget);
    });

    testWidgets(
        'Given an unknown status, When rendered in English, Then the "Other" label is shown',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const BookStatusBadge(status: 99), const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Other'), findsOneWidget);
    });
  });
}
