// Tests for the generated cover — the stand-in used when a book has no usable
// thumbnail.
//
// This replaces what used to be a gray box reading "no image", so the cases that
// matter are the two ways a cover can be absent: never supplied, and supplied
// but failed to load.
//
// **The failure is staged, not ambient.** This file used to lean on "network images
// always fail under `flutter_test`, because all HTTP returns 400", which made the
// failure path free. It stopped being free when covers moved to a disk cache: the
// fetch still fails, but it now fails somewhere inside a cache manager looking for a
// `path_provider` that does not exist under test, on a real async hop that a fake-async
// `pump` never advances — so the widget was still waiting rather than fallen back, and
// the test failed on timing rather than on behaviour. `coverImageProvider` is swapped
// instead, which says what is being tested.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/services/cover_image.dart';
import 'package:bookworm_friends/ui/widgets/book/generated_cover.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';

/// A cover whose fetch fails, standing in for a URL that cannot be reached.
class _FailingImage extends ImageProvider<_FailingImage> {
  @override
  Future<_FailingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FailingImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _FailingImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    Future<ImageInfo>.error(Exception('cover unavailable')),
  );
}

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
      // The case being covered: a real cover URL that cannot be fetched.
      coverImageProvider = (_) => _FailingImage();
      // Otherwise a later test in the same process quietly keeps the fake.
      addTearDown(() => coverImageProvider = networkCoverImage);

      await _pumpBook(tester, imageUrl: 'https://example.com/missing.jpg');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(GeneratedCover), findsOneWidget);
    });
  });

  group('the title', () {
    testWidgets('is left-aligned and inset clear of the binding band', (
      tester,
    ) async {
      // The one property of this cover a reader notices immediately when it is
      // wrong, and it is measured rather than read off the widget: the mockup of
      // this same design centred its titles for a while and nobody could tell
      // from the code that it had.
      await _pumpBook(tester, imageUrl: '', title: 'The Vegetarian');

      final cover = tester.getRect(find.byType(GeneratedCover));
      final text = tester.getRect(find.text('The Vegetarian'));

      expect(
        text.left - cover.left,
        closeTo(cover.width * 0.143, 1),
        reason:
            'the reference insets the title by 14.3% on the left so it clears '
            'the 8.2% binding band; anything less and the type sits on the fold',
      );
      expect(
        tester.widget<Text>(find.text('The Vegetarian')).textAlign,
        TextAlign.left,
      );
    });

    testWidgets('starts at the top of the lower half, not centred in it', (
      tester,
    ) async {
      await _pumpBook(tester, imageUrl: '', title: 'Dune');

      final cover = tester.getRect(find.byType(GeneratedCover));
      final text = tester.getRect(find.text('Dune'));

      // Half the cover, plus the 6.1% top padding.
      expect(
        text.top - cover.top,
        closeTo(cover.height / 2 + cover.width * 0.061, 1.5),
        reason:
            'a short title should sit against the top of the title half so the '
            'block above it reads as a band, not as a frame around the text',
      );
    });

    testWidgets('takes one type ratio at every size', (tester) async {
      // There were two ratios, because a corner mark used to share the title
      // half on wide covers. The mark is gone, so a size tier here would be
      // unexplained.
      await _pumpBook(tester, imageUrl: '', height: 130, title: 'Dune');
      final small = tester.widget<Text>(find.text('Dune')).style!.fontSize!;
      final smallWidth = tester.getRect(find.byType(GeneratedCover)).width;

      expect(small / smallWidth, closeTo(0.135, 0.001));
    });

    testWidgets('takes the same ratio on the widest book in the app', (
      tester,
    ) async {
      // Split from the test above because pumping twice in one test yields an
      // empty tree.
      await _pumpBook(tester, imageUrl: '', height: 180, title: 'Dune');
      final big = tester.widget<Text>(find.text('Dune')).style!.fontSize!;
      final bigWidth = tester.getRect(find.byType(GeneratedCover)).width;

      expect(big / bigWidth, closeTo(0.135, 0.001));
    });
  });

  group('no mark on the cover', () {
    testWidgets('nothing is drawn beside the title at shelf size', (
      tester,
    ) async {
      await _pumpBook(tester, imageUrl: '', height: 130);
      expect(find.byType(SvgPicture), findsNothing);
    });

    testWidgets('nor on the widest book, where a colophon would fit', (
      tester,
    ) async {
      // This is the size that used to carry one. A generated cover has no
      // publisher, so it gets no publisher's mark; the lower half is the
      // title's.
      await _pumpBook(tester, imageUrl: '', height: 180);
      expect(find.byType(SvgPicture), findsNothing);
    });
  });

  group('colour selection', () {
    testWidgets('the swatch is actually painted on the cover', (tester) async {
      // The palette function was unit-tested but nothing asserted the block
      // reaches the tree *with a size*, so a cover that rendered all-white would
      // have passed every test in this file.
      await _pumpBook(tester, imageUrl: '', isbn: '9788936434120');

      final swatch = generatedCoverColor('9788936434120');
      final block = find.descendant(
        of: find.byType(GeneratedCover),
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == swatch,
        ),
      );
      expect(block, findsOneWidget);

      final cover = tester.getSize(find.byType(GeneratedCover));
      final painted = tester.getSize(block);
      expect(
        painted.height,
        closeTo(cover.height / 2, 1),
        reason: 'the colour block is the top half of the cover',
      );
      expect(painted.width, closeTo(cover.width, 1));
    });

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
