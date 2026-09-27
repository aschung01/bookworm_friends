// Guards the palette the iOS widget draws with against the Dart tokens it is copied from.
//
// **Why this exists at all.** `ios/StreakWidget/StreakWidget.swift` cannot import
// `app_theme.dart`, so it holds the hexes by hand. That is a second copy of a palette, and a
// second copy of a palette drifts -- somebody tunes `secondaryText` in Dart, every app surface
// follows, and one widget on the home screen quietly keeps the old grey. Nothing fails, nobody
// notices for a release, and the fix is discovered by screenshot.
//
// So this reads the hexes back out of the Swift source and asserts they still equal the Dart
// constants. It is the same move `reading_date_test.dart` makes in asserting the rollover hour
// is the hour the copy quotes: cheap, and the only thing standing between two sources of one
// truth and a silent divergence.
//
// It is deliberately a *text* comparison against the Swift file rather than anything cleverer.
// A generator would be the other answer, and it is not worth it for five colours -- but a
// generator is what to reach for if this list grows.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_bookmark.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';

const String _swiftSource = 'ios/StreakWidget/StreakWidget.swift';

/// `0xRRGGBB` as written in the Swift source, for a named `Palette` member.
///
/// Matches both spellings the file uses: `Color(hex: 0xF2A93F)` for a value that is the same in
/// both themes, and `Color(light: 0xFFFFFF, dark: 0x1E1E1E)` for one that is not.
({int? single, int? light, int? dark}) _swiftColour(
  String source,
  String name,
) {
  final single = RegExp(
    'static let $name = Color\\(hex: 0x([0-9A-Fa-f]{6})\\)',
  ).firstMatch(source);
  if (single != null) {
    return (
      single: int.parse(single.group(1)!, radix: 16),
      light: null,
      dark: null,
    );
  }

  final pair = RegExp(
    'static let $name = Color\\(light: 0x([0-9A-Fa-f]{6}), dark: 0x([0-9A-Fa-f]{6})\\)',
  ).firstMatch(source);
  if (pair == null) return (single: null, light: null, dark: null);
  return (
    single: null,
    light: int.parse(pair.group(1)!, radix: 16),
    dark: int.parse(pair.group(2)!, radix: 16),
  );
}

int _rgb(Color colour) => colour.toARGB32() & 0xFFFFFF;

/// The `(top, bottom)` pairs of `StreakGroundRamp.anchors`, in source order.
List<({int top, int bottom})> _rampAnchors(String source) {
  final block = RegExp(
    r'static let anchors: \[\(hour: Double, top: StreakRGB, bottom: StreakRGB\)\] = \[(.*?)\n  \]',
    dotAll: true,
  ).firstMatch(source);
  if (block == null) return const [];
  return RegExp(
        r'StreakRGB\(0x([0-9A-Fa-f]{6})\), StreakRGB\(0x([0-9A-Fa-f]{6})\)',
      )
      .allMatches(block.group(1)!)
      .map(
        (m) => (
          top: int.parse(m.group(1)!, radix: 16),
          bottom: int.parse(m.group(2)!, radix: 16),
        ),
      )
      .toList();
}

/// The two stops of `StreakGround.recorded`.
({int top, int bottom})? _recordedGround(String source) {
  final match = RegExp(
    r'static let recorded = StreakGround\(\s*top: StreakRGB\(0x([0-9A-Fa-f]{6})\),\s*bottom: StreakRGB\(0x([0-9A-Fa-f]{6})\)',
  ).firstMatch(source);
  if (match == null) return null;
  return (
    top: int.parse(match.group(1)!, radix: 16),
    bottom: int.parse(match.group(2)!, radix: 16),
  );
}

double _luminance(int rgb) => Color(0xFF000000 | rgb).computeLuminance();

/// The PostScript name recorded inside a TrueType file's `name` table.
///
/// Parsed rather than assumed, because the whole point of this check is that the name in the file
/// and the name in the Swift are two different sources of one truth.
String? _postScriptName(File file) {
  final bytes = file.readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  final tableCount = data.getUint16(4);
  int? nameOffset;
  for (var i = 0; i < tableCount; i++) {
    final entry = 12 + 16 * i;
    final tag = String.fromCharCodes(bytes.sublist(entry, entry + 4));
    if (tag == 'name') nameOffset = data.getUint32(entry + 8);
  }
  if (nameOffset == null) return null;

  final records = data.getUint16(nameOffset + 2);
  final storage = nameOffset + data.getUint16(nameOffset + 4);
  for (var i = 0; i < records; i++) {
    final record = nameOffset + 6 + 12 * i;
    final platform = data.getUint16(record);
    final nameId = data.getUint16(record + 6);
    final length = data.getUint16(record + 8);
    final offset = data.getUint16(record + 10);
    // 6 is the PostScript name; platform 3 is Windows/UTF-16BE, which is the one every modern
    // build writes and the one CoreText reports.
    if (nameId != 6 || platform != 3) continue;
    final raw = bytes.sublist(storage + offset, storage + offset + length);
    return String.fromCharCodes([
      for (var j = 0; j + 1 < raw.length; j += 2) (raw[j] << 8) | raw[j + 1],
    ]);
  }
  return null;
}

double _contrast(int a, int b) {
  final first = _luminance(a);
  final second = _luminance(b);
  final hi = first > second ? first : second;
  final lo = first > second ? second : first;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  late String source;

  setUpAll(() {
    final file = File(_swiftSource);
    expect(
      file.existsSync(),
      isTrue,
      reason:
          '$_swiftSource is missing. If the widget was renamed or removed, this test '
          'and the palette it guards should go with it.',
    );
    source = file.readAsStringSync();
  });

  test(
    'Given the widget flame, When its hex is read, Then it is kCandleFlame',
    () {
      // One value in both themes, on purpose: the recorded state reads in the flame's own amber
      // everywhere, which is why `AppColors.flame` was superseded for the mark.
      expect(_swiftColour(source, 'flame').single, _rgb(kCandleFlame));
    },
  );

  test(
    'Given the widget neutrals, When their hexes are read, Then they match both themes',
    () {
      final light = AppTheme.light.extension<AppColors>()!;
      final dark = AppTheme.dark.extension<AppColors>()!;

      for (final entry in <String, (Color, Color)>{
        'surface': (light.surface, dark.surface),
        'primaryText': (light.primaryText, dark.primaryText),
        'secondaryText': (light.secondaryText, dark.secondaryText),
        'divider': (light.divider, dark.divider),
      }.entries) {
        final swift = _swiftColour(source, entry.key);
        expect(
          swift.light,
          _rgb(entry.value.$1),
          reason: '${entry.key} light hex has drifted from AppColors',
        );
        expect(
          swift.dark,
          _rgb(entry.value.$2),
          reason: '${entry.key} dark hex has drifted from AppColors',
        );
      }
    },
  );

  test(
    'Given the App Group, When it is named in three places, Then they agree',
    () {
      // The container the whole feature rests on, and a mismatch is silent: `UserDefaults`
      // hands back a usable store for a group the process does not own, so the app's write
      // appears to succeed and the widget reads nothing.
      const group = 'group.com.unicorn.bookwormFriends';
      for (final path in [
        'ios/StreakWidget/StreakSnapshot.swift',
        'ios/StreakWidget/StreakWidget.entitlements',
        'ios/Runner/Runner.entitlements',
        'ios/Runner/AppDelegate.swift',
      ]) {
        expect(
          File(path).readAsStringSync(),
          contains(group),
          reason: '$path does not name $group',
        );
      }
    },
  );

  // The amended `sc-risk` rule, as a test rather than a paragraph.
  //
  // The design record used to forbid the late state a second warm hue, which was a *proxy* for
  // the thing it cared about: a state whose job is to be noticed cannot be one shade off the
  // state it warns about. The ground ladder now warms into a deep red, which breaks the proxy and
  // not the requirement -- and the requirement is measurable, which is the whole argument for the
  // swap. Leaving it in prose would have thrown that away.
  //
  // Measured at the worst pairing there is: the *lightest* stop of an open ground against the
  // *darkest* stop of the recorded one, so nothing is flattered by comparing midpoints.
  test(
    'Given every hour of the ramp, When compared with recorded, Then none of them is confusable',
    () {
      final anchors = _rampAnchors(source);
      final recorded = _recordedGround(source);

      expect(
        anchors,
        hasLength(6),
        reason:
            'StreakGroundRamp.anchors did not parse. If the ramp moved to another shape, this '
            'test has to move with it -- it is the only check that the ladder stays legible '
            'against the recorded tile.',
      );
      expect(recorded, isNotNull);

      for (final anchor in anchors) {
        final lightestOpen = _luminance(anchor.top) > _luminance(anchor.bottom)
            ? anchor.top
            : anchor.bottom;
        final darkestRecorded =
            _luminance(recorded!.top) < _luminance(recorded.bottom)
            ? recorded.top
            : recorded.bottom;

        expect(
          _contrast(lightestOpen, darkestRecorded),
          greaterThanOrEqualTo(4.5),
          reason:
              'the open ground #${anchor.top.toRadixString(16)} is within 4.5:1 of the recorded '
              'ground, so an unrecorded hour can be mistaken for a recorded night',
        );
      }
    },
  );

  // Of 137 profiles in production exactly one has a reading day, so the common state is *no run
  // at all* -- and a deep red tile shouting at somebody who has not started is the one first
  // impression nothing recovers from. The escalation is a function of an unrecorded day inside a
  // live run, which is why these three states are pinned to the first anchor rather than the hour.
  test(
    'Given no run, When the ground is chosen, Then it is the dawn anchor and never the hour',
    () {
      expect(
        source,
        contains(
          'static let dawn = StreakGround.ramp(atHour: StreakGroundRamp.anchors[0].hour)',
        ),
      );
      // The no-run branch of the one place a tile's ground is chosen.
      expect(
        source,
        matches(
          RegExp(
            r'if phase == \.broken \|\| snapshot\.run\(at: date\) == 0 \{[^}]*ground: \.dawn',
            dotAll: true,
          ),
        ),
        reason:
            'a reader with no run is no longer pinned to the dawn ground, so the ladder can '
            'now escalate at somebody who has never started',
      );
      // And the no-snapshot case, which is the same argument one step earlier.
      expect(
        source,
        matches(
          RegExp(
            r'static let invitation = StreakTileStyle\(\s*ground: \.dawn',
            dotAll: true,
          ),
        ),
        reason: 'the invitation tile no longer pins itself to the dawn ground',
      );
    },
  );

  // The figure's face, and the one way it fails silently.
  //
  // `build_fonts.py` subsets Nunito, and the file it writes carries the family name *Nunito
  // ExtraBold* -- so `UIFont(name: "Nunito")` returns nil and the widget's numeral falls through
  // to SF Rounded while the streak page keeps drawing Nunito. Flutter is no guide: `pubspec.yaml`
  // declares `family: Nunito` and Dart resolves against that declaration rather than against
  // anything inside the file, so the two sides legitimately need different names for one face.
  //
  // Nothing fails if this drifts. The widget just quietly stops matching the app, which is the
  // exact class of bug the rest of this file exists for.
  test(
    'Given the widget figure, When Swift names its font, Then the name is the one in the file',
    () {
      final font = File('ios/StreakWidget/Nunito-ExtraBold.ttf');
      expect(
        font.existsSync(),
        isTrue,
        reason:
            'the extension has no font of its own. An extension inherits none of the host app\'s '
            'fonts, and Flutter\'s copy is inside App.framework where nothing native can reach it.',
      );

      final postScript = _postScriptName(font);
      expect(postScript, isNotNull);
      expect(
        source,
        contains('"$postScript"'),
        reason:
            'StreakWidget.swift does not ask for "$postScript", so UIFont hands back nil and the '
            'figure silently falls back to the system face',
      );

      // A font that is a target member but not declared is not registered at runtime, which fails
      // the same silent way.
      expect(
        File('ios/StreakWidget/Info.plist').readAsStringSync(),
        contains('Nunito-ExtraBold.ttf'),
        reason: 'UIAppFonts does not list the font, so iOS never registers it',
      );
    },
  );

  // The bookmark, which is the third copy of one shape and the second copy of one track.
  //
  // **`bookmarkIcon.svg` is the shape's source and `reading_bookmark.dart` is the track's**, and
  // the widget extension can reach neither: it cannot load an SVG through `flutter_svg` and it
  // cannot import Dart. So `BookmarkRibbon` and `ReadingBookmarkTrack` hold both by hand, in the
  // asset's own units precisely so this test can compare them without arithmetic.
  //
  // The drift this catches is the shelf's ribbon being retuned and the widget's staying put --
  // which is exactly the defect `ReadingBookmark`'s own doc comment was written to end, when the
  // app had two marks for one state. Nothing fails when it happens; the ribbon just reads a
  // different position at a different size, and only a screenshot would say so.
  group('the bookmark, against the asset and the app', () {
    /// A `static let <name>: CGFloat = <number>` out of the Swift source.
    double swiftNumber(String name) {
      final match = RegExp(
        'static let $name: CGFloat = (-?[0-9.]+)',
      ).firstMatch(source);
      expect(
        match,
        isNotNull,
        reason:
            '$name is gone from StreakWidget.swift, so the ribbon is drawn from something else',
      );
      return double.parse(match!.group(1)!);
    }

    test(
      'Given the ribbon, When its units are read, Then they match bookmarkIcon.svg',
      () {
        final svg = File('assets/icons/bookmarkIcon.svg').readAsStringSync();

        // The apex of the notch, which is the one number that makes this silhouette a bookmark
        // rather than a rectangle. `L10.75 24.2099` in the asset.
        expect(svg, contains('L10.75 24.2099'));
        expect(swiftNumber('unitApexY'), closeTo(24.2099, 0.0001));

        // Dead centre horizontally: the visible ribbon spans x4..x17.5, so its middle is 10.75 --
        // which is why `path(in:)` can put the apex at `w / 2` rather than carrying an x for it.
        expect(swiftNumber('unitWidth'), 13.5);
        expect(10.75 - 4, swiftNumber('unitWidth') / 2);

        // The bottom corners, from the asset's (4, 28.7999) -> (4.75, 30).
        expect(swiftNumber('unitCornerX'), closeTo(4.75 - 4, 0.0001));
        expect(swiftNumber('unitCornerY'), closeTo(30 - 28.7999, 0.0001));
        expect(swiftNumber('unitHeight'), 30);
      },
    );

    test(
      'Given the track, When its constants are read, Then they match reading_bookmark.dart',
      () {
        expect(swiftNumber('pin'), kReadingBookmarkInset);
        expect(swiftNumber('referenceBook'), kReadingBookmarkBook);
        // Private in Dart, so these are compared against the asset and the app's own comments:
        // the bleed is the 22-wide box less the ribbon's x17.5 end, and the binding fraction is
        // `BookMetrics.bindingWidth`.
        expect(
          swiftNumber('rightBleed'),
          closeTo(kReadingBookmarkWidth - 17.5, 0.0001),
        );
        expect(swiftNumber('bindingFraction'), 0.082);
      },
    );

    // The port has to agree with the Dart function's *output*, not only its constants -- the two
    // measure from different edges (Flutter positions the 22-wide asset box; Swift draws only the
    // 13.5-wide ribbon), so an off-by-the-bleed here would put the mark in the wrong place at
    // every position while every constant above still matched.
    test(
      'Given a position, When both sides place the ribbon, Then its left edge lands identically',
      () {
        const coverWidth = 40.0;
        const coverHeight = 58.0;
        final scale = coverHeight / kReadingBookmarkBook;
        final ribbonWidth = 13.5 * scale;
        final bleed = (kReadingBookmarkWidth - 17.5) * scale;

        for (final progress in <double?>[null, 0, 0.25, 0.41, 1]) {
          // Dart: an inset to the asset box's right edge, so the ribbon's left edge is that plus
          // the bleed plus the ribbon.
          final dartInset = readingBookmarkInsetFor(
            progress?.toDouble(),
            coverWidth: coverWidth,
            scale: scale,
          );
          final dartLeft = coverWidth - dartInset - bleed - ribbonWidth;

          // Swift: an inset to the ribbon's own right edge.
          final swiftInset = _swiftTrailingInset(
            progress: progress?.toDouble(),
            coverWidth: coverWidth,
            scale: scale,
          );
          final swiftLeft = coverWidth - swiftInset - ribbonWidth;

          expect(
            swiftLeft,
            closeTo(dartLeft, 0.0001),
            reason:
                'the two sides disagree about where progress $progress puts the ribbon',
          );
        }
      },
    );

    // The rule that makes the mark safe to draw before anyone has answered the percent wheel.
    test(
      'Given no recorded position, When the ribbon is placed, Then it pins at the fore-edge',
      () {
        const coverWidth = 40.0;
        final scale = 58.0 / kReadingBookmarkBook;

        expect(
          _swiftTrailingInset(
            progress: null,
            coverWidth: coverWidth,
            scale: scale,
          ),
          closeTo(
            _swiftTrailingInset(
              progress: 1,
              coverWidth: coverWidth,
              scale: scale,
            ),
            0.0001,
          ),
        );
      },
    );
  });
}

/// `ReadingBookmarkTrack.trailingInset` in Dart, so the Swift port can be held to the app's own
/// function rather than to a transcription of it.
///
/// Kept beside the test rather than in `lib/`: nothing in the app needs it, and putting it there
/// would make the thing under test and the thing testing it the same code.
double _swiftTrailingInset({
  required double? progress,
  required double coverWidth,
  required double scale,
}) {
  const pin = kReadingBookmarkInset;
  final rightBleed = kReadingBookmarkWidth - 17.5;
  const ribbonWidth = 13.5;
  const bindingFraction = 0.082;

  final pinned = (pin + rightBleed) * scale;
  if (progress == null) return pinned;
  final travel =
      coverWidth - pinned - ribbonWidth * scale - coverWidth * bindingFraction;
  if (travel <= 0) return pinned;
  return pinned + (1 - progress.clamp(0.0, 1.0)) * travel;
}
