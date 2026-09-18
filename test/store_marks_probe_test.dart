// A proof sheet for the four store marks, rendered exactly as `_Glyph` draws
// them (30pt chip, tinted to primaryText).
//
// **This exists to be looked at, not asserted on.** Three of the marks are solid
// fills and Libby's is a stroke, so they do not carry equal ink at equal size --
// which is why `_Glyph` gives Libby 20 of the 30pt box where the others get 16.
// The left column is what ships; the right column forces all four to 16, which is
// the imbalance being corrected. Regenerate and *view the PNG* before changing
// any mark or size:
//
//     flutter test --update-goldens test/store_marks_probe_test.dart
//
// The behavioural assertions live in `store_links_sheet_test.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';

const _marks = <String, (String, double)>{
  'Play Books': ('assets/icons/storePlayIcon.svg', 16),
  'Apple Books': ('assets/icons/storeAppleIcon.svg', 16),
  'Kindle': ('assets/icons/storeKindleIcon.svg', 16),
  // 20, not 16: a stroked mark carries less ink than a solid one at equal size.
  'Libby': ('assets/icons/storeLibbyIcon.svg', 20),
};

Widget _chip(
  String? asset,
  String letter,
  Color chip,
  Color ink,
  double size,
) => Container(
  width: 30,
  height: 30,
  alignment: Alignment.center,
  decoration: BoxDecoration(
    color: chip,
    borderRadius: BorderRadius.circular(8),
  ),
  child: asset == null
      ? Text(letter, style: TextStyle(color: ink, fontSize: 15))
      : SvgPicture.asset(
          asset,
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
        ),
);

void main() {
  testWidgets('store marks proof sheet', (tester) async {
    const chipBg = Color(0xFFE9ECEF);
    const ink = Color(0xFF212529);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          backgroundColor: const Color(0xFFEFF5EF),
          body: Center(
            child: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Left: as shipped, each at its chosen optical size. Right:
                  // every mark forced to 16, which is what the imbalance the
                  // per-store size exists to correct looks like.
                  for (final e in _marks.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          _chip(
                            e.value.$1,
                            e.key.characters.first,
                            chipBg,
                            ink,
                            e.value.$2,
                          ),
                          const SizedBox(width: 16),
                          _chip(
                            e.value.$1,
                            e.key.characters.first,
                            chipBg,
                            ink,
                            16,
                          ),
                          const SizedBox(width: 16),
                          Text(e.key, style: const TextStyle(fontSize: 15)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/store_marks_probe.png'),
    );
  });
}
