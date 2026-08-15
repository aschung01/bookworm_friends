// Tests for the generated cover — the stand-in used when a book has no usable
// thumbnail.
//
// This replaces what used to be a gray box reading "no image", so the cases that
// matter are the two ways a cover can be absent: never supplied, and supplied
// but failed to load. Network images always fail under `flutter_test` (all HTTP
// returns 400), which makes the failure path the default rather than something
// that needs mocking.

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/book/generated_cover.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';

Future<void> _pumpBook(
  WidgetTester tester, {
  required String imageUrl,
  String isbn = '9788936434120',
  String title = '아몬드',
  double height = 130,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(
        body: Center(
          child: BookWidget(
            imageUrl: imageUrl,
            isbn: isbn,
            title: title,
            height: height,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('when there is no thumbnail at all', () {
    testWidgets('the generated cover is used', (tester) async {
      await _pumpBook(tester, imageUrl: '');
      expect(find.byType(GeneratedCover), findsOneWidget);
    });

    testWidgets('the title is shown on the cover', (tester) async {
      await _pumpBook(tester, imageUrl: '', title: '소년이 온다');
      expect(find.text('소년이 온다'), findsOneWidget);
    });

    testWidgets('a long title is clamped rather than overflowing', (
      tester,
    ) async {
      await _pumpBook(
        tester,
        imageUrl: '',
        title: '아주 아주 아주 아주 아주 아주 아주 아주 아주 긴 제목을 가진 책 한 권',
      );
      final text = tester.widget<Text>(find.byType(Text).first);
      expect(text.maxLines, 3);
      expect(text.overflow, TextOverflow.ellipsis);
      // No overflow is reported by the test binding.
      expect(tester.takeException(), isNull);
    });
  });

  group('when the thumbnail fails to load', () {
    testWidgets('the generated cover is used instead of an error box', (
      tester,
    ) async {
      // Any network image fails in tests, which is exactly the case being
      // covered: a real cover URL that cannot be fetched.
      await _pumpBook(tester, imageUrl: 'https://example.com/missing.jpg');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(GeneratedCover), findsOneWidget);
    });
  });

  group('size tiers', () {
    testWidgets('the mascot is dropped at shelf size', (tester) async {
      // ~86px wide, the width used on every shelf.
      await _pumpBook(tester, imageUrl: '', height: 130);
      expect(find.byType(SvgPicture), findsNothing);
    });

    testWidgets('the mascot appears at details-page size', (tester) async {
      // 180px tall is what the details page passes; at 2/3 that is 120px wide,
      // clearing the 110px threshold. If the threshold were ever raised above
      // 120 the mascot would become dead code, so this pins it.
      await _pumpBook(tester, imageUrl: '', height: 180);
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('the threshold sits below the widest book in the app', (
      tester,
    ) async {
      expect(kMascotMinWidth, lessThan(180 * (2 / 3)));
    });
  });

  group('colour selection', () {
    test('is stable for a given ISBN', () {
      expect(
        generatedCoverColor('9788936434120'),
        generatedCoverColor('9788936434120'),
      );
    });

    test('comes from the palette', () {
      expect(
        kGeneratedCoverPalette,
        contains(generatedCoverColor('9780451524935')),
      );
    });

    test('spreads across the palette rather than favouring one swatch', () {
      final used = <Color>{};
      for (var i = 0; i < 400; i++) {
        used.add(generatedCoverColor('978${1000000000 + i * 7919}'));
      }
      expect(used.length, kGeneratedCoverPalette.length);
    });

    test('falls back to the first swatch without an ISBN', () {
      expect(generatedCoverColor(''), kGeneratedCoverPalette.first);
    });
  });

  group('dark mode', () {
    testWidgets('renders without the light-mode page block', (tester) async {
      // The page block and back board are near-white in light mode; if they were
      // reused verbatim they would glow on #121212.
      await _pumpBook(tester, imageUrl: '', brightness: Brightness.dark);
      expect(find.byType(GeneratedCover), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
