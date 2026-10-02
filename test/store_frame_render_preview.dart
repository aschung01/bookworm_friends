// Not a test — a renderer. Composites App Store frames from the device captures under
// `docs/store/screenshots/1.1.0/capture/<locale>/` and writes them to
// `build/store_frames/<locale>/`, which is the directory `asc_version.py` uploads from.
//
//   flutter test test/store_frame_render_preview.dart
//
// **Why this is a Flutter renderer and not an image editor.** The captions have to be set
// in the app's own type and colour — `AppFonts.serif`, `context.colors.primaryText`,
// `brandText` — or the storefront and the product drift apart, which is the whole failure
// mode a hand-composited set has. It also makes a reworded caption a re-run rather than a
// redraw.
//
// **That promise has now been collected on: there is a real Korean set.** It was the
// argument for building this as a renderer, and until this pass it was still a promise —
// every locale got the English frames byte for byte, so a Korean reader saw English
// captions. The second set cost 12 more captures and a caption table, not 12 more frames
// of hand-set Hangul. See `_locales`.
//
// Sizes are exact, not approximate: 440x956 logical at pixelRatio 3 is **1320x2868**,
// which is the iPhone 6.9" requirement. The iPad 13" pass is 1032x1376 at 2.
//
// The layout was chosen by rendering one capture in four caption treatments and looking,
// which is the only way it can be chosen. That comparison is **past tense** — one
// treatment is rendered now. See `_chosen`, which keeps the losing three named so the
// comparison can be re-run if it is questioned. (This paragraph said "renders one capture
// in four" and pointed at a `_treatments` list that does not exist, for long enough to be
// worth the correction: a header describing behaviour the file has lost is the trap every
// preview in this repo keeps falling into.)
//
// Two traps this file is deliberately built around, both of which have already cost this
// repo a round:
//
//   * `FontLoader` carries no weight information, so one cut per family. Two Pretendard
//     statics would let the engine answer any weight with whichever arrived first — which
//     is how a preview once drew the w600 that had just been rejected while the app
//     shipped w400.
//   * The ground goes *inside* the `RepaintBoundary`. On the `Scaffold` it is painted
//     outside, the capture comes back transparent, and every value gets judged against
//     the viewer's white matte instead of the ground it actually sits on.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
// `FontLoader` lives here, not in `flutter_test`.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';

/// The 6.9" requirement, in logical points at [_phoneRatio].
const _phoneLogical = Size(440, 956);
const _phoneRatio = 3.0;

/// The iPad 13" requirement: 1032x1376 at 2 is 2064x2752.
const _tabletLogical = Size(1032, 1376);
const _tabletRatio = 2.0;

/// Where the caption sits, and which edge the device bleeds off.
///
/// The device always bleeds off **one** edge. A fully contained phone floating in the
/// middle is what a template looks like; both references crop. Flighty crops off the
/// bottom and right for its hero frames and off the top and bottom for its feature
/// frames, and Duolingo has no device at all — so the cropping is the part the two
/// agree on, at opposite ends of everything else.
enum _Anchor { top, bottom }

class _Treatment {
  final String name;
  final _Anchor anchor;
  final TextAlign align;

  const _Treatment(this.name, this.anchor, this.align);
}

/// **Chosen by rendering four of these and looking**; the argument is in
/// `docs/store/listing-1.1.0.md` under "The layout, decided by looking". Top because
/// Apple crops the top in search results, so a bottom caption is invisible exactly where
/// the frame has to work; centre because the device is centred and a left-hang reads
/// unresolved at thumbnail size without Flighty's dark editorial ground beneath it.
///
/// Kept as a type rather than inlined so the comparison can be re-run if it is
/// questioned — the losing three are `top/left`, `bottom/centre` and `top/centre`
/// without a supporting line.
const _chosen = _Treatment('chosen', _Anchor.top, TextAlign.center);

/// A headline and the line under it, for one capture in one locale.
///
/// **No two headlines and no two supporting lines share an idea**, which is the
/// benchmark's observation 2 applied one level down — the strong listings never spend a
/// character twice. Slot 1's supporting line was `Covers, spines, or leaning.` for one
/// round, which is slot 2's *headline* verbatim, so the first two frames a reviewer sees
/// would have said the same thing twice. It carries the objection-removal move instead:
/// free, no ads, no subscription is what Flighty spends its own opening on, it is true
/// here, and nothing else in the set says it.
class _Caption {
  final String headline;
  final String supporting;

  const _Caption(this.headline, this.supporting);
}

/// One frame: a capture and the caption set against it. Zipped by [_slotsFor].
///
/// **The caption used to be fields on this class, and the Korean set is why it is not.**
/// A `List<_Slot>` per locale is the obvious shape and the wrong one: it writes the
/// *order* out once per locale, so the two can drift into shipping a different slot 3 to
/// Korea — and slot 3 is the last frame the App Store shows in search results. Order is a
/// product decision and a caption is a translation, so [_phoneCaptures] / [_tabletCaptures]
/// hold the first and the caption tables hold the second.
class _Slot {
  final String capture;
  final _Caption caption;

  const _Slot(this.capture, this.caption);
}

/// The eight iPhone captures, in upload order, shared by every locale.
///
/// The streak sits third because it is what this release is for, and because the App
/// Store shows the first three frames in search results.
const _phoneCaptures = <String>[
  'iphone69/01-library-covers',
  'iphone69/02-library-spines',
  'iphone69/08-streak',
  'iphone69/03-library-card',
  'iphone69/05-book-details',
  'iphone69/07-share-card',
  'iphone69/04-friends',
  'iphone69/06-search-results',
];

/// The four iPad captures, in upload order.
///
/// The fourth slot is the **streak**, not the book details it was for two rounds, and the
/// swap is about what the iPad does to a modal. The capture has to show the progress
/// sheet for `in one drag` to be true, and on a 13-inch screen that sheet is a small band
/// at the bottom behind a full-screen scrim — so the frame rendered as a uniformly grey
/// page with the sheet itself cut off below the device's bottom bleed, promising a control
/// it did not contain. Capturing the page *without* the sheet fixes the dimming and loses
/// the claim: the iPad details page is short, capped and centred, so it came out as a
/// cover and two lines of metadata over about half a screen of empty white.
///
/// The streak page has the opposite shape — it fills the width at any size, and the
/// month grid's hand-drawn rings read better large than small.
const _tabletCaptures = <String>[
  'ipad13/01-library',
  'ipad13/02-library-card',
  'ipad13/03-friends',
  'ipad13/04-streak',
];

/// Which phone caption each iPad capture borrows. This is one system at two sizes, not
/// two sets, so the iPad reuses four of the eight captions rather than writing four more.
///
/// **Here rather than as four more rows in every locale's caption table**, for the reason
/// the capture lists are shared: which caption the iPad borrows is a decision about the
/// set, so a locale must not be able to answer it differently. It also means there is
/// only ever one string, so rewording a phone caption cannot leave its iPad twin behind.
const _borrowedCaption = <String, String>{
  'ipad13/01-library': 'iphone69/01-library-covers',
  'ipad13/02-library-card': 'iphone69/03-library-card',
  'ipad13/03-friends': 'iphone69/04-friends',
  'ipad13/04-streak': 'iphone69/08-streak',
};

const _captionsEnUs = <String, _Caption>{
  'iphone69/01-library-covers': _Caption(
    'A bookshelf you actually keep',
    'Free. No ads, no subscription.',
  ),
  // **This said `Covers, spines, or leaning` and that named a mode the app does not have.**
  // `ShelfDensity` has two values and its own doc records `leaning` as withdrawn — the spine
  // row rakes, but raking is not a third selectable thing. The Korean caption had always
  // said two (`표지로, 책등으로`), so this is the English being brought into line with it
  // rather than a new decision. The same overclaim was in both locales' description and
  // What's New and in the App Review walkthrough's step 4, where it was worst: a reviewer
  // following "cycles three shelf views" would have found two and had a step fail.
  //
  // **Known cost: `cover` is now also in slot 8's headline**, the same category as the
  // `friend` collision noted on slot 7. Accepted because the app's own vocabulary gives a
  // cover two unrelated jobs — how a shelf is drawn, and what you photograph to add a book
  // — so the two frames are not saying one thing twice. The Korean set has carried the same
  // overlap (`표지로, 책등으로` and `표지 찍어도 찾아요`) since it shipped.
  'iphone69/02-library-spines': _Caption(
    'Covers out, or spines lined up',
    'Drag them into the order you want.',
  ),
  // The streak's two lines deliberately avoid every idea already spent: `keep` belongs to
  // slot 1, `page` to slot 5, and the card's `days` is one item in a list of stats rather
  // than the subject of a sentence.
  'iphone69/08-streak': _Caption(
    'The days add up',
    'Mark today, and watch the month fill in.',
  ),
  'iphone69/03-library-card': _Caption(
    'Your reading becomes a card',
    'Books, days, pace, most-read author.',
  ),
  'iphone69/05-book-details': _Caption(
    'Log the page you\u2019re on',
    'By page or percent, in one drag.',
  ),
  // Reworded twice. It was `Share it, or keep it`: "it" had no referent this side of slot
  // 3, and the second clause described the absence of an action. Then `Made to be handed
  // over` / `Nothing is public until you send it.`, which traded one fault for two —
  // "handed over" is the verb for surrendering something, and the supporting line was a
  // privacy disclaimer answering, in the negative, an objection the viewer has not formed
  // yet. This pair leads with the act and names the three destinations that actually
  // exist in the app: `shareCardDestinationStories`, `shareCardDestinationPhotos`, and
  // the system share sheet.
  //
  // **Known cost: `friend` is also in slot 7's headline**, which is the one thing the
  // no-shared-idea rule on [_Caption] warns about. Accepted because the two frames are
  // about opposite directions — sending yours out, watching theirs come in.
  'iphone69/07-share-card': _Caption(
    'Show someone what you read',
    'Straight to Stories, Photos, or a friend.',
  ),
  'iphone69/04-friends': _Caption(
    'Read alongside your friends',
    'See what they have open right now.',
  ),
  // **Slot 8 leads with the cover photo, not the barcode.** Three things decided that, and
  // the middle one is why it claims coverage rather than speed:
  //
  // - **Cover reading was unsold.** It is shipped and prominent — `_CoverButton` in
  //   `scan_book_page.dart` is "on screen from the first frame", not behind the nudge — and
  //   the whole listing mentioned it nowhere, in either locale, while barcode and ISBN were
  //   in the headline, the description, the keywords and the review walkthrough.
  // - **It is not actually the faster path, so this does not say it is.** `mobile_scanner`
  //   has no still capture, so the photo is taken in the *system* camera: tap, leave the
  //   app, shoot, come back. A barcode decodes live in the viewfinder. What the cover wins
  //   is the books a barcode cannot do — a library sticker over the ISBN, an old or foreign
  //   edition, a dust jacket, a book already in your hand — which is a coverage claim and
  //   is true.
  // - **It ends at this capture.** `cover_read.dart` returns a *search query*, never a book,
  //   because "a model reading stylised cover type is a guess, and it can be confidently
  //   wrong in ways an ISBN cannot" — so the flow lands on the results grid for the reader
  //   to confirm. That is exactly the screen this slot already shows, so leading with the
  //   cover needed no recapture. It also could not have had one: a simulator has no camera.
  //
  // So the headline does not say *added* and the Korean does not say `끝`. `Add it by its
  // cover` is the idiom read straight, and it is what the feature does.
  'iphone69/06-search-results': _Caption(
    'Add it by its cover',
    'Works when the barcode won\u2019t.',
  ),
};

/// The Korean set. Three things about it that are expensive to rediscover.
///
/// **The headlines borrow the app's own Korean vocabulary**, so a caption and the screen
/// under it say the same word: `표지` and `책등` are the nouns inside `shelfDensityCovers`
/// and `shelfDensitySpines`, `가장 많이 읽은 작가` is `libraryCardTopAuthor` verbatim, `쪽` is
/// `progressPageColumn`, `스토리` and `사진` are `shareCardDestinationStories` and
/// `shareCardDestinationPhotos`, `기록` is `streakMonthDaysReadCaption`, and `표지` in slot 8 is
/// the noun inside `scanReadCover` (`표지 읽기`). A storefront that names a control the app
/// calls something else is the same drift this whole file exists to avoid, one layer out.
///
/// **`표지로, 책등으로` was right and the English was wrong, so the English changed.**
/// `ShelfDensity` in `lib/providers/shelf_density_provider.dart` has two values, `covers`
/// and `spines`; the spine row does rake, but raking is not a third selectable mode — its
/// own doc records `leaning` as withdrawn. The Korean caption never promised a third and
/// the English headline did, so slot 2 is now `Covers out, or spines lined up`. Worth
/// knowing how far that one claim had spread before anyone checked it against the enum: it
/// was in both locales' description bullet and What's New bullet, and in the App Review
/// walkthrough's step 4, which told a reviewer the switcher "cycles three shelf views" — a
/// step that would simply have failed in front of them.
///
/// **Written, not natively reviewed** — the same caveat `AGENTS.md` records for the other
/// agent-written Korean strings.
///
/// **A Korean headline has about eight full-width glyphs per line, and the ninth orphans.**
/// The headline is set at `w * 0.102`, so on the 1320pt frame roughly eight Hangul
/// syllables fit; a nine-syllable line fills the first line and drops its last syllable
/// alone onto the second. `읽은 책을 보여주세요` rendered exactly that way — a line reading
/// `읽은 책을 보여주세` with a bare `요` under it, which looks like a clipping bug rather
/// than a wrap. It is `읽은 책 보여주기` instead: seven glyphs, one line like the other
/// seven, and the nominal `-기` ending slots 2 and 7 already use, since the Korean set
/// turns the English imperatives into nominals throughout (`Read alongside your friends`
/// is `친구와 함깘 읽기`). Counting glyphs is the check — an explicit `\n` would fix the
/// break and silently re-break if the size ever moves.
///
/// Slot 8 is the second instance and confirms the budget: `표지만 찍어도 찾아요` is nine
/// glyphs and rendered `표지만 찍어도 찾아` with a bare `요` beneath it. **Note the break
/// is mid-word, not at a space** — Korean wraps between syllables, so counting words tells
/// you nothing and a line that happens to end on a particle is not safer. The fix was to
/// drop the `-만` particle rather than restructure: `표지 찍어도 찾아요`, eight glyphs, one
/// line, same claim.
///
/// **It says `찾아요` (finds), not `끝` (done), for the reason the English does not say
/// *added*.** `cover_read.dart` hands back a search query and the flow lands on the results
/// grid for the reader to confirm, so a completion claim would be the one thing this
/// feature cannot promise. The supporting line inverts the English rather than translating
/// it — English says the cover works where the barcode will not, Korean says the barcode
/// and the title work too — because once the headline leads with the cover, the useful
/// second line is the one that says the familiar paths are still there.
///
/// Every headline is set in `GowunBatang-Bold.ttf`, which is subset to Latin-1 plus KS X
/// 1001's 2,350 syllables, so **do not alter a Hangul character here without checking it
/// is in that cut.** Note what the failure looks like, because it is not a box:
/// `AppTextStyles.hero` carries `fontFamilyFallback: [AppFonts.sans]`, so a syllable
/// outside the subset sets in **Pretendard** — half a serif headline silently in a sans,
/// which reads as a weight bug rather than a coverage one. Measured with fontTools: the
/// cut holds 2,645 codepoints and every character below is in it, as is every supporting
/// line's in Pretendard's 11,427.
const _captionsKo = <String, _Caption>{
  'iphone69/01-library-covers': _Caption('계속 쓰게 되는 책장', '무료. 광고도, 구독도 없습니다.'),
  'iphone69/02-library-spines': _Caption('표지로, 책등으로', '원하는 순서로 끌어 옮기세요.'),
  'iphone69/08-streak': _Caption('하루하루 쌓입니다', '오늘을 기록하면, 달력이 채워져요.'),
  'iphone69/03-library-card': _Caption(
    '내 독서가 카드로',
    '권수, 읽은 날, 속도, 가장 많이 읽은 작가.',
  ),
  'iphone69/05-book-details': _Caption('지금 읽는 쪽을 기록', '쪽이나 퍼센트로, 한 번에.'),
  'iphone69/07-share-card': _Caption('읽은 책 보여주기', '스토리로, 사진으로, 또는 그대로 공유.'),
  'iphone69/04-friends': _Caption('친구와 함께 읽기', '지금 어떤 책을 펼쳤는지 보세요.'),
  'iphone69/06-search-results': _Caption('표지 찍어도 찾아요', '바코드나 제목으로도 추가할 수 있어요.'),
};

/// One App Store locale: where its captures and frames live, which Flutter locale the
/// captions are laid out under, and its caption table.
///
/// [code] is App Store Connect's own locale code, and `asc_version.py` iterates the same
/// two — so one string is the capture directory, the render output directory and the
/// upload's source directory, and a typo cannot put frames somewhere the uploader still
/// finds stale ones.
///
/// **[locale] is not derived from [code]**, because the store wants a language-region
/// where Flutter wants a language: `en-US` renders under `Locale('en')`, which is what
/// `AppLocalizations.supportedLocales` holds.
class _LocaleSet {
  final String code;
  final Locale locale;
  final Map<String, _Caption> captions;

  const _LocaleSet(this.code, this.locale, this.captions);
}

const _locales = <_LocaleSet>[
  _LocaleSet('en-US', Locale('en'), _captionsEnUs),
  _LocaleSet('ko', Locale('ko'), _captionsKo),
];

/// Zips [captures] against [set]'s captions, in order, resolving [_borrowedCaption].
///
/// **Fails rather than skipping a capture it has no caption for.** A caption table that
/// has fallen behind a new capture would otherwise render a frame with an empty headline
/// — and the only place anyone would see that is the contact sheet, which the upload
/// never looks at. So an uncaptioned frame cannot reach Apple by being overlooked.
List<_Slot> _slotsFor(List<String> captures, _LocaleSet set) {
  final slots = <_Slot>[];
  for (final capture in captures) {
    final key = _borrowedCaption[capture] ?? capture;
    final caption = set.captions[key];
    if (caption == null) {
      fail(
        'no ${set.code} caption for the capture `$capture`'
        '${key == capture ? '' : ' (which borrows `$key`)'}. '
        'Add it to the ${set.code} table, or point _borrowedCaption at an existing '
        'one — a capture with no caption renders a frame with an empty headline.',
      );
    }
    slots.add(_Slot(capture, caption));
  }
  return slots;
}

/// **The captures are stale and these frames are still worth rendering.** Five of the
/// twelve draw the rust flame or the unfilled grey streak tile, and the two frames Apple
/// shows in search results have the finished-books sheet half open across the bottom
/// third. What this pass settles is the copy and the fit — neither of which depends on
/// what is inside the screen. Re-capture, then re-run.
///
/// One directory per locale under here, named by [_LocaleSet.code], each holding the same
/// twelve basenames. **A locale's directory is never created speculatively**: its absence
/// is how an unrun capture pass is detected, so `main` fails on it by name rather than
/// rendering a short set.
const _captureRoot = 'docs/store/screenshots/1.1.0/capture';

// --------------------------------------------------------------------------- the frame

/// One store frame: ground, caption, and a bezelled device bleeding off an edge.
class _StoreFrame extends StatelessWidget {
  final ui.Image shot;
  final _Slot slot;
  final _Treatment treatment;

  const _StoreFrame({
    required this.shot,
    required this.slot,
    required this.treatment,
  });

  /// Fraction of the canvas width the whole device occupies, bezel included.
  static const _deviceWidthFraction = 0.82;

  /// Bezel thickness in logical points at [_phoneLogical]'s width.
  static const _bezel = 9.0;

  /// Screen corner radius as a fraction of screen width. An iPhone 16 Pro Max is about
  /// 62pt on 440, so 0.141 — measured off the hardware rather than picked, because a
  /// radius that is merely "rounded" is the tell that a mockup is drawn rather than real.
  static const _screenRadiusFraction = 0.141;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;

        final deviceWidth = w * _deviceWidthFraction;
        final screenWidth = deviceWidth - _bezel * 2;
        // The screen's aspect is the capture's aspect, so the screenshot is never
        // stretched — the one distortion a reviewer would notice immediately.
        final screenHeight = screenWidth * shot.height / shot.width;
        final screenRadius = screenWidth * _screenRadiusFraction;

        final caption = _caption(colors, w);
        // **The device takes what the caption leaves, and bleeds off by the difference.**
        // Positioning it from the frame's edge instead — which is what this did first —
        // ignores the caption's height, so the supporting-line variant drew its second
        // line underneath the phone with the last word clipped. A taller caption now
        // means a deeper crop rather than a collision, which is also the honest trade:
        // the more you say, the less app you show.
        final device = Expanded(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                top: treatment.anchor == _Anchor.top ? 0 : null,
                bottom: treatment.anchor == _Anchor.bottom ? 0 : null,
                left: (w - deviceWidth) / 2,
                width: deviceWidth,
                height: screenHeight + _bezel * 2,
                child: _Device(
                  shot: shot,
                  bezel: _bezel,
                  screenRadius: screenRadius,
                ),
              ),
            ],
          ),
        );

        return DecoratedBox(
          // A flat cream ground gives a near-white screenshot nothing to sit on. The
          // faintest green cast at the far end hints the brand without competing with
          // the covers, which are the loudest thing in this frame by design.
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: treatment.anchor == _Anchor.top
                  ? Alignment.topCenter
                  : Alignment.bottomCenter,
              end: treatment.anchor == _Anchor.top
                  ? Alignment.bottomCenter
                  : Alignment.topCenter,
              colors: [Colors.white, const Color(0xFFE7F0EC)],
            ),
          ),
          child: Column(
            children: treatment.anchor == _Anchor.top
                ? [caption, device]
                : [device, caption],
          ),
        );
      },
    );
  }

  Widget _caption(AppColors colors, double w) {
    // Sized against the canvas rather than in absolute points, so the iPad pass and the
    // phone pass produce the same *proportions* instead of the same numbers. 10.2% of
    // width lands the headline near Flighty's, which sets its hero line at roughly a
    // tenth of frame width.
    final headline = w * 0.102;

    return Padding(
      // The top figure is generous on purpose: Flighty leaves about 9% of the frame's
      // height clear above its first mark, and that air is most of why the frame reads
      // as composed rather than as a screenshot with a label on it.
      padding: EdgeInsets.fromLTRB(w * 0.085, w * 0.155, w * 0.085, w * 0.11),
      child: Column(
        crossAxisAlignment: treatment.align == TextAlign.left
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Text(
            slot.caption.headline,
            textAlign: treatment.align,
            style: AppTextStyles.hero.copyWith(
              fontSize: headline,
              height: 1.14,
              letterSpacing: -headline * 0.018,
              color: colors.primaryText,
            ),
          ),
          SizedBox(height: w * 0.035),
          Text(
            slot.caption.supporting,
            textAlign: treatment.align,
            style: AppTextStyles.body.copyWith(
              fontSize: headline * 0.40,
              height: 1.35,
              color: colors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

/// The bezel, the screen, and the shadow that separates a light device from a light ground.
class _Device extends StatelessWidget {
  final ui.Image shot;
  final double bezel;
  final double screenRadius;

  const _Device({
    required this.shot,
    required this.bezel,
    required this.screenRadius,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(screenRadius + bezel),
        // Not pure black. A titanium rail reads as a very dark warm grey, and true black
        // against a cream ground is a hole rather than an object.
        color: const Color(0xFF1B1B1E),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 42,
            spreadRadius: 2,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(bezel),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(screenRadius),
          // `RawImage` takes a decoded `dart:ui` image directly. `Image.memory` would
          // need its load to complete inside the pump, which a widget test does not
          // drive — the frame captures before the bytes resolve and the screen is blank.
          child: RawImage(image: shot, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------- plumbing

Future<ui.Image> _decode(String path) async {
  final bytes = File(path).readAsBytesSync();
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

Future<Uint8List> _shoot(WidgetTester tester, double pixelRatio) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  late Uint8List png;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    png = data!.buffer.asUint8List();
  });
  return png;
}

/// One cut per family: `AppFonts.serif` for the headline, `AppFonts.sans` for the
/// supporting line. Registering a second Pretendard static would make every weight
/// resolve to whichever loaded first.
Future<void> _loadRealFonts() async {
  for (final entry in const {
    AppFonts.serif: 'assets/fonts/GowunBatang-Bold.ttf',
    AppFonts.sans: 'assets/fonts/Pretendard-Regular.otf',
  }.entries) {
    final bytes = File(entry.value).readAsBytesSync();
    final loader = FontLoader(entry.key)
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();
  }
}

Widget _host(ui.Image shot, _Slot slot, Locale locale) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.light,
  // **The app's own localization configuration, not a hand-set `locale:`.** Passing
  // `locale` alone looks like it works and does not: `MaterialApp`'s default
  // `supportedLocales` is `[en-US]`, so `Locale('ko')` resolves *back* to `en_US` through
  // `basicLocaleListResolution` with no warning, and adding `supportedLocales` without
  // the delegates throws "not supported by all of its localization delegates" — which, in
  // a widget test, is a failed render rather than a printed warning. The app's own two
  // lines fix both, and are what this file is for: the frames should resolve exactly what
  // the product resolves. Measured: `ko` and `en` both arrive at `Localizations.localeOf`.
  //
  // What it is **not** buying is line-breaking, despite the obvious guess. `Text` leaves
  // the paragraph's own locale null here exactly as it does in the app, and a Korean
  // headline laid out with the locale forced to `en`, `ko` or null measures the same
  // 190x150 in three lines — Hangul breaks by UAX #14 regardless. It is here so the
  // captions cannot be laid out under a configuration the app never uses.
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: locale,
  home: RepaintBoundary(
    key: const ValueKey('shot'),
    // **`Material` is not optional here, and its absence does not look like its absence.**
    // It is where `AnimatedDefaultTextStyle` comes from; without it the ambient default is
    // `MaterialApp`'s `_errorTextStyle`, and `Text` merges that with the style given here.
    // The explicit colour, family and size win — so the headline came out correct in every
    // respect except the `decoration: underline` and yellow `decorationColor` that nothing
    // here overrides, i.e. a frame that looks *selectively* broken and reads as a font bug.
    // Transparent because `_StoreFrame` paints the ground itself, inside this boundary.
    child: Material(
      color: Colors.transparent,
      child: _StoreFrame(shot: shot, slot: slot, treatment: _chosen),
    ),
  ),
);

/// Renders [slots] at [logical] x [ratio] into `<dir>/<prefix>-NN-<basename>.png`.
Future<List<ui.Image>> _renderSet(
  WidgetTester tester,
  Directory dir, {
  required String prefix,
  required List<_Slot> slots,
  required _LocaleSet set,
  required Size logical,
  required double ratio,
  required Size required,
}) async {
  tester.view.physicalSize = logical * ratio;
  tester.view.devicePixelRatio = ratio;

  final written = <ui.Image>[];
  for (var i = 0; i < slots.length; i++) {
    final slot = slots[i];

    late ui.Image shot;
    await tester.runAsync(() async {
      shot = await _decode('$_captureRoot/${set.code}/${slot.capture}.png');
    });

    await tester.pumpWidget(_host(shot, slot, set.locale));
    await tester.pumpAndSettle();

    // Slot order is the upload order, so it leads the filename: Apple shows the first
    // three and nothing in the image says which one it is. The device prefix is there
    // because the two sets reuse captions, so the numbers alone repeat.
    final name = '${i + 1}'.padLeft(2, '0');
    final path =
        '${dir.path}/$prefix-$name-${slot.capture.split('/').last}.png';
    File(path).writeAsBytesSync(await _shoot(tester, ratio));

    final decoded = await tester.runAsync(() => _decode(path));
    expect(
      Size(decoded!.width.toDouble(), decoded.height.toDouble()),
      required,
      reason: 'store sizes are exact; Apple rejects anything else',
    );
    written.add(decoded);
  }
  return written;
}

/// All of [frames] side by side on a dark ground, scaled to [cell].
///
/// Judging 1320x2868 files one at a time is how a set ends up inconsistent, and a
/// thumbnail is closer to how Apple serves them in search results anyway.
Future<void> _contactSheet(
  WidgetTester tester,
  Directory dir, {
  required String name,
  required List<ui.Image> frames,
  required List<_Slot> slots,
  required Size cell,
}) async {
  tester.view.physicalSize = Size(cell.width * frames.length, cell.height + 46);
  tester.view.devicePixelRatio = 1;

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: RepaintBoundary(
        key: const ValueKey('shot'),
        child: Material(
          color: const Color(0xFF15171A),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < frames.length; i++)
                SizedBox(
                  width: cell.width,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Text(
                          '${i + 1}. ${slots[i].caption.headline}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.sans,
                            fontSize: 14,
                            color: Color(0xFFE8EAED),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: cell.width - 16,
                        height: cell.height - 16,
                        child: RawImage(image: frames[i], fit: BoxFit.contain),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  File('${dir.path}/$name').writeAsBytesSync(await _shoot(tester, 1));
}

void main() {
  setUpAll(_loadRealFonts);

  testWidgets('render the eight iPhone and four iPad frames, per locale', (
    tester,
  ) async {
    addTearDown(tester.view.reset);

    final root = Directory('build/store_frames')..createSync(recursive: true);
    // Loose files at the root are the flat single-locale layout this replaced, which
    // nothing reads any more. They go for the same reason the locale directories are
    // wiped below: output nobody writes is output nobody checks, and a 1320x2868 frame
    // with an English caption sitting beside `en-US/` and `ko/` reads as current.
    for (final entry in root.listSync()) {
      if (entry is File) {
        entry.deleteSync();
      }
    }

    // **Each locale is checked as its turn comes, not all of them up front.** Checking
    // first is tidier and was written that way for a round: it reports a missing capture
    // pass in a second rather than after twelve 1320x2868 frames have been composited.
    // It also renders nothing at all, which is the wrong trade for this file — the whole
    // reason it exists is that captions are chosen by looking, so while one locale is
    // being captured the other's set has to stay reviewable. Nothing is risked by that:
    // the failure is a failed test either way, and `asc_version.py` checks each locale's
    // directory again before it uploads, so a short render cannot reach Apple.
    for (final set in _locales) {
      final captures = Directory('$_captureRoot/${set.code}');
      if (!captures.existsSync()) {
        fail(
          '${captures.path} does not exist, so the capture pass has not been run '
          'for ${set.code}. Capture the twelve screens into that directory '
          '(iphone69/ and ipad13/, the same basenames the other locales use) and '
          're-run. Rendering only the locales that do exist is deliberately not a '
          'pass: a short set uploads cleanly and leaves ${set.code} on whatever it '
          'had, which is how English frames shipped to Korea in the first place.',
        );
      }

      // Before the wipe below, because these are pure: a caption table that has fallen
      // behind a new capture should not cost this locale the frames it already had.
      final phoneSlots = _slotsFor(_phoneCaptures, set);
      final tabletSlots = _slotsFor(_tabletCaptures, set);

      final dir = Directory('build/store_frames/${set.code}')
        ..createSync(recursive: true);
      // Stale output from an earlier run is worse than none: a renamed slot leaves a file
      // behind and the contact sheet is the only place anyone would notice. Per locale
      // rather than over the whole tree, because the tree now holds the other locale's
      // finished frames and a re-run of one locale must not take them with it.
      for (final f in dir.listSync()) {
        f.deleteSync();
      }

      final phone = await _renderSet(
        tester,
        dir,
        prefix: 'iphone69',
        slots: phoneSlots,
        set: set,
        logical: _phoneLogical,
        ratio: _phoneRatio,
        required: const Size(1320, 2868),
      );
      final tablet = await _renderSet(
        tester,
        dir,
        prefix: 'ipad13',
        slots: tabletSlots,
        set: set,
        logical: _tabletLogical,
        ratio: _tabletRatio,
        required: const Size(2064, 2752),
      );

      await _contactSheet(
        tester,
        dir,
        name: '_sheet-iphone69.png',
        frames: phone,
        slots: phoneSlots,
        cell: const Size(210, 456),
      );
      await _contactSheet(
        tester,
        dir,
        name: '_sheet-ipad13.png',
        frames: tablet,
        slots: tabletSlots,
        cell: const Size(300, 400),
      );

      // ignore: avoid_print
      print('wrote ${dir.absolute.path}');
    }
  });
}
