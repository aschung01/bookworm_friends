import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/library_card_stats.dart';
import 'package:bookworm_friends/services/analytics.dart';
import 'package:bookworm_friends/services/card_destinations.dart';
import 'package:bookworm_friends/services/widget_png_renderer.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_cover_row.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_framing.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/library_card/share_destination_row.dart';
import 'package:bookworm_friends/ui/widgets/library_card/share_library_card.dart';
import 'package:bookworm_friends/ui/widgets/library_card/shareable_library_card.dart';

/// Everything [ShareCardPage] needs, as one value rather than a `Map`.
///
/// **Typed, unlike the two routes that came before it.** `/details` and
/// `/user_library` both read `Map<String, dynamic>` out of `settings.arguments` and
/// cast field by field, which is how `userId` ends up defaulting to `''` when a key is
/// misspelled. This route carries a `List<Book>` and two nullable `DateTime`s; a
/// mistyped key there is a card with no covers and no `Member since`, and nothing on
/// screen would say why.
///
/// **No `LibraryCardStats` field, deliberately.** The sheet has already computed one
/// by the time it pushes, so passing it would be free — and it would also be a second
/// copy of a figure derived from [books] and [year], free to disagree with the covers
/// drawn beside it. The page derives it instead, from the same [libraryCardStats] call
/// the sheet makes. This is the same rule `booksInCardYear` exists to enforce.
@immutable
class ShareCardArgs {
  /// Every finished book, unfiltered — the year is applied here, not by the caller,
  /// so the page and the export filter identically.
  final List<Book> books;

  /// The books the reader has open right now.
  ///
  /// **Not year-filtered, and not counted.** An open book has no finish date, so there is
  /// no year to filter it into and nothing for `libraryCardStats` to count — the hero
  /// figure stays a count of books *read*. It is drawn at the front of the shelf wearing a
  /// bookmark, which is what marks it out as the uncounted thing it is. See
  /// [CardCoverRow.reading].
  final List<Book> reading;

  /// Selected year, `0` for all time. Matching `ReadFilter`'s convention.
  final int year;

  /// The reader's display name, printed as the card's `Holder`. Korean is fine.
  final String? displayName;

  /// The reader's `profiles.handle`: the Latin identity the strip prints. Null until
  /// Task 7 adds the column, and null is a working state — see
  /// [ShareableLibraryCard.handle].
  final String? handle;

  /// `profiles.created_at`, printed as `Member since`. Null omits the row.
  final DateTime? memberSince;

  const ShareCardArgs({
    this.books = const [],
    this.reading = const [],
    this.year = 0,
    this.displayName,
    this.handle,
    this.memberSince,
  });
}

/// The close button, so a test taps a target rather than a glyph.
const Key kShareCardCloseKey = Key('share-card-close');

/// The artifact preview. Present only once the covers have decoded.
const Key kShareCardArtKey = Key('share-card-art');

/// The assembling state. Present only while they have not.
const Key kShareCardSkeletonKey = Key('share-card-skeleton');

/// The framing toggle, so a test presses a control rather than a glyph.
const Key kShareCardFramingKey = Key('share-card-framing');

/// The Candlelight pill.
const Key kShareCardCandleKey = Key('share-card-candlelight');

/// `More`: the platform sheet.
///
/// Re-exported from the row that owns it so the page's own tests do not have to know
/// which file a slot lives in.
const Key kShareCardMoreKey = kShareDestinationMoreKey;

/// `View and share`: the Library Card, previewed before it leaves the phone.
///
/// **What this screen buys, stated as the four things a blind hand-off cannot do.**
/// Until now the Card tab's share button went straight from tap to the OS sheet behind
/// an `EasyLoading` spinner: the reader never saw the image, was never told which year
/// was in it, had no say in how it was framed, and there was nowhere to put a delight
/// toggle. This screen is where all four become possible, and it is Flighty's own
/// answer to the same problem.
///
/// **Full-screen, so bar, well and tab bar all go.** That is the shell's existing rule
/// for a focused dismissible context and the reason `ScanBookPage` is a page rather
/// than a sheet: `shellBarVisibleProvider` compares against the topmost *page* route,
/// so pushing this is all it takes to clear the tab bar. No name matching, nothing to
/// register.
///
/// **The subtitle is not decoration.** Once the presentation covers the sheet's year
/// capsules, the title line is the only thing on screen that can say which year is
/// about to leave the phone. Naming the scope here is what keeps a card from leaving
/// with a year nothing on screen named — which is what the library bar's own share
/// button used to do, before that entry point was removed.
///
/// **The wait lives in the preview.** Covers are `NetworkImage` and
/// `RepaintBoundary.toImage` paints only what is already decoded, so every cover has
/// to be precached or the exported PNG leaves with holes in it — invisible on screen,
/// invisible to a widget test that asserts geometry, visible only by opening the file.
/// So the precache happens on arrival, the card assembles in place while it runs, and
/// the destinations are inert until it finishes.
class ShareCardPage extends ConsumerStatefulWidget {
  /// Normally null: the arguments arrive through `settings.arguments`, which is how
  /// every route in this app is parameterised.
  ///
  /// Non-null is the test seam. A widget test that pumps this page directly has no
  /// `ModalRoute`, and the alternative — wrapping every test in a `Navigator` and
  /// pushing by name — tests `AppRoutes` rather than the page.
  final ShareCardArgs? args;

  const ShareCardPage({super.key, this.args});

  @override
  ConsumerState<ShareCardPage> createState() => _ShareCardPageState();
}

class _ShareCardPageState extends ConsumerState<ShareCardPage> {
  ShareCardArgs? _args;

  /// Whether the covers have decoded, and therefore whether an export taken now
  /// would be whole.
  bool _ready = false;

  /// How the image is composed around the card.
  ///
  /// **Float on arrival**, which is what `sh-open` draws. The ground is what makes the
  /// card read as an object being held out rather than as a screenshot of one, and it
  /// is also the only framing whose exported edge is opaque — see [FramedShareableCard].
  CardFraming _framing = CardFraming.float;

  /// How the card is lit.
  ///
  /// Daylight on arrival: Candlelight is a reveal, and something has to be revealed
  /// *from*. **The export carries whatever this is** — a delight toggle that changed
  /// only the screen would be a toy, and the reader who pressed it is precisely the one
  /// about to share. The cost accepted is that a lit card is a little harder for a
  /// stranger to read *as a library card* than the daylight one.
  CardLighting _lighting = CardLighting.daylight;

  /// Whether the Stories slot is drawn.
  ///
  /// Resolved once, while the covers precache, so the row never gains a slot after the
  /// reader has looked at it. False until answered — offering a destination that might not
  /// work is worse than offering one fewer.
  bool _instagramInstalled = false;

  /// Resolved here rather than in `initState` because `ModalRoute.of` needs the
  /// element to be in the tree, and `didChangeDependencies` is the first callback
  /// where it is. Guarded so a `MediaQuery` change does not restart the precache.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    _args =
        widget.args ??
        ModalRoute.of(context)?.settings.arguments as ShareCardArgs? ??
        const ShareCardArgs();
    _assemble();
  }

  /// Decodes every cover the card is about to draw, then lets the destinations live.
  ///
  /// [precacheAll] swallows its own errors and gives up after [kPrecacheBudget], so a
  /// dead thumbnail degrades to `GeneratedCover` and a stalled one still produces a
  /// card. Either way this completes, which is what stops the screen becoming a
  /// spinner with no way out.
  /// Decodes every cover the card is about to draw and asks whether Instagram is there,
  /// then lets the destinations live.
  ///
  /// **This method's one hard promise is that it finishes.** [precacheAll] already swallows
  /// its own errors and gives up after [kPrecacheBudget], so a dead thumbnail degrades to
  /// `GeneratedCover` and a stalled one still produces a card — but relying on *callees* to
  /// be well behaved is how the promise gets broken by a change somewhere else. A widget
  /// test proved it: a probe that threw left the screen assembling forever, because
  /// `Future.wait` rejects as soon as either side does and the `setState` below never ran.
  /// So the guarantee is enforced here, where it is made.
  Future<void> _assemble() async {
    final args = _args!;
    var installed = false;
    try {
      // Both at once. The probe is a channel round trip and the precache is a network wait;
      // running them in sequence would add the first to the second for no reason, and the
      // screen is not usable until both are done anyway.
      final results = await Future.wait([
        precacheAll(
          context,
          // Every cover the shelf is going to draw, decoded before anything captures it:
          // `toImage` paints only what is decoded, so a cover still in flight is exported
          // as a hole that nothing on screen would show.
          cardCoverProviders(booksInCardYear(args.books, args.year)),
        ).then((_) => false),
        instagramInstalledProbe(),
      ]);
      installed = results.last;
    } catch (_) {
      // A cover that will not decode is drawn by its fallback and a probe that will not
      // answer governs the least important thing on the screen. Neither is a reason to
      // strand the reader on a spinner with nothing to press.
    }
    if (!mounted) return;
    setState(() {
      _ready = true;
      _instagramInstalled = installed;
    });
  }

  /// The card as it currently stands, ready to be rendered.
  CardExportRequest _request({CardFraming? framing}) {
    final args = _args!;
    return CardExportRequest(
      stats: libraryCardStats(args.books, year: args.year),
      books: args.books,
      year: args.year,
      displayName: args.displayName,
      handle: args.handle,
      memberSince: args.memberSince,
      framing: framing ?? _framing,
      lighting: _lighting,
      reading: args.reading,
    );
  }

  Map<String, Object> _dimensions(String destination) => {
    'surface': ShareSurface.preview.name,
    'format': _framing.name,
    'lighting': _lighting.name,
    'destination': destination,
  };

  /// Hands the card to the Instagram Stories composer.
  ///
  /// **Always the Fill render, whatever the framing toggle says.** Instagram paints the
  /// ground itself from the two colours it is given, so a Float export would put our ground
  /// underneath Instagram's — see `shareCardToStory`. The toggle still reaches this
  /// destination through the *ground colours*, which come from the lighting state, and that
  /// is the honest amount of control there is over a layer another app owns.
  Future<void> _shareToStories() async {
    final l10n = AppLocalizations.of(context);
    final ground = FramedShareableCard(
      framing: CardFraming.float,
      lighting: _lighting,
      card: const SizedBox.shrink(),
    ).groundColors;

    try {
      EasyLoading.show();
      // Rendered before anything is awaited, so `context` is used synchronously. Logging
      // `share_opened` first read better and put an await between the tap and the only
      // `BuildContext` use in the method, which is the lint's whole point.
      final path = await exportCardFile(
        context,
        _request(framing: CardFraming.fill),
      );
      EasyLoading.dismiss();
      await analytics.log(kShareOpened, _dimensions('instagram_stories'));
      final outcome = await shareCardToStory(
        imagePath: path,
        groundTop: ground.first,
        groundBottom: ground.last,
      );
      if (outcome != StoryOutcome.shared && mounted) {
        EasyLoading.showError(l10n.shareCardStoriesFailed);
      }
      await analytics.log(kShareCompleted, {
        ..._dimensions('instagram_stories'),
        'outcome': outcome.name,
        'activity': '',
      });
    } catch (_) {
      EasyLoading.showError(l10n.shareCardStoriesFailed);
      await analytics.log(kShareCompleted, {
        ..._dimensions('instagram_stories'),
        'outcome': 'failed',
        'activity': '',
      });
    }
  }

  /// Saves the card to the photo library.
  ///
  /// The escape hatch, and the only destination that leaves the reader holding the file —
  /// which is why it exports **exactly what is on screen**, framing and lighting included,
  /// rather than a canonical version.
  Future<void> _saveToPhotos() async {
    final l10n = AppLocalizations.of(context);
    try {
      EasyLoading.show();
      final path = await exportCardFile(context, _request());
      await analytics.log(kShareOpened, _dimensions('photos'));
      final saved = await saveCardToGallery(path);
      EasyLoading.dismiss();
      if (!mounted) return;
      if (saved) {
        EasyLoading.showSuccess(l10n.shareCardSavedToPhotos);
      } else {
        EasyLoading.showError(l10n.shareCardSaveFailed);
      }
      await analytics.log(kShareCompleted, {
        ..._dimensions('photos'),
        'outcome': saved ? 'saved' : 'refused',
        'activity': '',
      });
    } catch (_) {
      EasyLoading.showError(l10n.shareCardSaveFailed);
      await analytics.log(kShareCompleted, {
        ..._dimensions('photos'),
        'outcome': 'failed',
        'activity': '',
      });
    }
  }

  /// Hands the PNG to the platform sheet.
  ///
  /// Straight through [shareLibraryCard] rather than a capture of its own: that
  /// function is the app's one export path, and the whole reason it lives outside the
  /// sheet is that two capture sites would drift into producing two different images.
  /// The precache it runs is a second call over providers that have already resolved,
  /// which is a cache hit.
  Future<void> _shareToPlatform(Rect? origin) {
    final args = _args!;
    return shareLibraryCard(
      context,
      stats: libraryCardStats(args.books, year: args.year),
      books: args.books,
      reading: args.reading,
      year: args.year,
      displayName: args.displayName,
      handle: args.handle,
      memberSince: args.memberSince,
      framing: _framing,
      lighting: _lighting,
      // Which entry point this was, so the funnel can answer the question this whole
      // screen is a bet on: does showing the reader the image first make them more or
      // less likely to send it than the library bar's blind hand-off?
      surface: ShareSurface.preview,
      destination: 'more',
      origin: origin,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final args = _args ?? const ShareCardArgs();
    final lighting = _lighting;

    return Scaffold(
      // No `AppBar`: the chrome is a row inside the body, because the title is two
      // lines of different weights and the framing toggle sits opposite the dismiss. An
      // `AppBar` would give this a surface and an elevation the drawing does not have.
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: shareChromeGround(colors, lighting: lighting),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _Chrome(
                year: args.year,
                framing: _framing,
                lighting: lighting,
                onFramingChanged: (framing) =>
                    setState(() => _framing = framing),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Center(
                    child: _ready
                        ? _CardPreview(
                            args: args,
                            framing: _framing,
                            lighting: lighting,
                          )
                        : _Assembling(
                            label: l10n.shareCardAssembling,
                            framing: _framing,
                            lighting: lighting,
                          ),
                  ),
                ),
              ),
              _CandlePill(
                lighting: lighting,
                onChanged: (value) => setState(() => _lighting = value),
              ),
              ShareDestinationRow(
                enabled: _ready,
                lighting: lighting,
                instagramInstalled: _instagramInstalled,
                onStories: _shareToStories,
                onPhotos: _saveToPhotos,
                onMore: _shareToPlatform,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dismiss, title, and the framing toggle.
class _Chrome extends StatelessWidget {
  final int year;
  final CardFraming framing;
  final CardLighting lighting;
  final ValueChanged<CardFraming> onFramingChanged;

  const _Chrome({
    required this.year,
    required this.framing,
    required this.lighting,
    required this.onFramingChanged,
  });

  /// Both edges of the chrome row, so the title is centred on the screen rather than
  /// on whatever is left over. Matches the buttons that sit in them.
  static const double _edge = kIconButtonDiameter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final ink = shareChromeInk(colors, lighting: lighting);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          SizedBox(
            width: _edge,
            child: AdaptiveIconButton(
              key: kShareCardCloseKey,
              // `xmark`/`close`, not a chevron: this is a presentation over the shell,
              // and the gesture that ends it is dismissal rather than going up a level.
              symbol: 'xmark',
              icon: Icons.close,
              // Matches the other three ways out of a focused context in this app —
              // the scanner, Add Book and Manage Shelves all use exactly this size.
              diameter: _edge,
              symbolSize: kIconButtonSymbolSize,
              iconSize: kIconButtonIconSize,
              iconColor: ink,
              semanticLabel: l10n.shareCardClose,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  year == 0
                      ? l10n.shareCardTitleAllTime
                      : l10n.shareCardTitleYear(year),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.subtitle.copyWith(color: ink),
                ),
                Text(
                  l10n.shareCardSubtitle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.label.copyWith(
                    color: shareChromeMutedInk(colors, lighting: lighting),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: _edge,
            child: _FramingToggle(
              framing: framing,
              lighting: lighting,
              onChanged: onFramingChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// The framing control: one button, two positions.
///
/// **One button rather than two named segments, and the glyph shows the state.** That
/// is what the drawings put in the corner and there is 44pt of chrome for it; a
/// two-segment `Fill | Float` control needs about 72 and would push the title into a
/// second line on a 375pt phone for a distinction the glyph already makes. What a
/// single button costs is a screen reader's understanding, so the state is carried
/// explicitly: the tooltip names the *control* rather than either position, and the
/// current position is the `Semantics` value.
class _FramingToggle extends StatelessWidget {
  final CardFraming framing;
  final CardLighting lighting;
  final ValueChanged<CardFraming> onChanged;

  const _FramingToggle({
    required this.framing,
    required this.lighting,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final isFloat = framing == CardFraming.float;
    final lit = lighting == CardLighting.candlelight;

    return Semantics(
      value: isFloat ? l10n.shareCardFramingFloat : l10n.shareCardFramingFill,
      child: AdaptiveIconButton(
        key: kShareCardFramingKey,
        // Both glyphs are the *state*, not the action, which is why the accessible
        // name is the control's own name rather than "switch to Float" — the label
        // and the picture would otherwise describe different things.
        //
        // `inset.filled.rectangle.portrait` is a portrait card with an inset fill,
        // which is Float drawn exactly; `rectangle.portrait.fill` fills the whole
        // canvas, which is Fill. Both were checked against the iOS 26.5 runtime's
        // own `symbol_order.plist` rather than recalled — a name that does not exist
        // is dropped silently and leaves the corner empty, which is the failure
        // `native_glass.dart` warns about twice.
        symbol: isFloat
            ? 'inset.filled.rectangle.portrait'
            : 'rectangle.portrait.fill',
        // Material has no inset-card glyph: `filter_frames` is a frame within a
        // frame, which is the same idea, and the plain portrait outline is the bleed.
        icon: isFloat ? Icons.filter_frames : Icons.crop_portrait,
        diameter: kIconButtonDiameter,
        symbolSize: kIconButtonSymbolSize,
        iconSize: kIconButtonIconSize,
        // Tinted only in the non-default position, so the chrome says at a glance that
        // something has been changed from how it arrived.
        iconColor: isFloat
            ? (lit ? kCandleFlame : colors.brandText)
            : shareChromeInk(colors, lighting: lighting),
        semanticLabel: l10n.shareCardFraming,
        onPressed: () =>
            onChanged(isFloat ? CardFraming.fill : CardFraming.float),
      ),
    );
  }
}

/// Candlelight: one pill under the artifact, and the only delight control on the screen.
///
/// **A flame rather than Flighty's blacklight**, because the object is different. A
/// passport really does hide fluorescent print, so UV is the correct light for one. A
/// library card hides nothing under UV and does hide something under a flame — gilt
/// ruling, an embossed seal, a rubber date stamp — so this is the same idea with the
/// physics corrected rather than a rename of it. See [CardLighting.candlelight].
class _CandlePill extends StatelessWidget {
  final CardLighting lighting;
  final ValueChanged<CardLighting> onChanged;

  const _CandlePill({required this.lighting, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final lit = lighting == CardLighting.candlelight;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        toggled: lit,
        child: Material(
          color: lit
              ? kCandleFlame.withValues(alpha: 0.16)
              : colors.surface.withValues(alpha: 0.94),
          shape: StadiumBorder(
            side: BorderSide(
              color: lit ? kCandleFlame : colors.divider,
              width: lit ? 1 : 0.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: kShareCardCandleKey,
            onTap: () => onChanged(
              lit ? CardLighting.daylight : CardLighting.candlelight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    // A flame, not a bulb and not a UV glyph. Material has no candle;
                    // this is the closest thing that reads as an open flame.
                    Icons.local_fire_department,
                    size: 16,
                    color: lit ? kCandleFlame : colors.secondaryText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.shareCardCandlelight,
                    style: AppTextStyles.label.copyWith(
                      color: lit ? kCandleGlow : colors.primaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The artifact, previewed at exactly the size it will be exported at.
///
/// **The preview and the export are the same widget at the same size, scaled.** A
/// preview laid out to the screen's width would be a second layout of the card, free
/// to break a line the export does not break — and the reader would have approved an
/// image that is not the one that left. So the card is built into a box of
/// [kShareableCardSize] and a `FittedBox` shrinks the result.
class _CardPreview extends StatelessWidget {
  final ShareCardArgs args;
  final CardFraming framing;
  final CardLighting lighting;

  const _CardPreview({
    required this.args,
    required this.framing,
    required this.lighting,
  });

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      // The reader's text scale is removed here for the same reason
      // `captureWidgetToPng` removes it: the card is laid out to a fixed size, and at
      // 200% text it clips. Without this the preview clips where the export does not,
      // so the one screen whose job is to show the reader what they are about to send
      // would be showing them something else.
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: FittedBox(
        child: RepaintBoundary(
          key: kShareCardArtKey,
          child: FramedShareableCard(
            framing: framing,
            lighting: lighting,
            card: ShareableLibraryCard(
              stats: libraryCardStats(args.books, year: args.year),
              books: args.books,
              reading: args.reading,
              year: args.year,
              displayName: args.displayName,
              handle: args.handle,
              memberSince: args.memberSince,
              lighting: lighting,
            ),
          ),
        ),
      ),
    );
  }
}

/// The assembling state: the card's shape, at the card's size, with nothing in it yet.
///
/// **Not a spinner, and that is the point of the screen.** A spinner says "wait"; this
/// says what is being built and how big it will be, so the card appears to fill in
/// rather than to pop into existence. It holds the exported size so nothing on screen
/// jumps when the covers land.
class _Assembling extends StatelessWidget {
  final String label;

  /// Framed and lit the same way the artifact will be, so the shape that arrives is the
  /// shape that was already there.
  final CardFraming framing;
  final CardLighting lighting;

  const _Assembling({
    required this.label,
    required this.framing,
    required this.lighting,
  });

  @override
  Widget build(BuildContext context) {
    final palette = cardPalette(lighting);
    return Semantics(
      label: label,
      child: FittedBox(
        child: SizedBox.fromSize(
          key: kShareCardSkeletonKey,
          size: framedCardSize,
          child: FramedShareableCard(
            framing: framing,
            lighting: lighting,
            card: SizedBox.fromSize(
              size: kShareableCardSize,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // The stock, so what fills in is what was outlined.
                  color: palette.stock.last,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.stockLine, width: 2),
                ),
                child: Center(
                  child: SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: palette.labelInk,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
