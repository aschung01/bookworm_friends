import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/library_card_stats.dart';
import 'package:bookworm_friends/services/analytics.dart';
import 'package:bookworm_friends/services/widget_png_renderer.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_bookmark.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_cover_row.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_framing.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_furniture.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/library_card/shareable_library_card.dart';

/// Where a share was started from.
///
/// Logged rather than merely passed, because the two entry points are now genuinely
/// different experiences — one shows the reader the image first and one does not — and
/// this parameter is the only way to find out whether that matters.
enum ShareSurface {
  /// The `View and share` screen.
  preview,

  /// The library bar's own button, which still exports straight to the platform sheet.
  libraryBar,
}

/// The file name the platform sees.
///
/// **Branded, and the reason is that some targets print it next to the image.** The old
/// name was `library_card.png`, which says nothing about where the card came from — and
/// on a card whose whole design problem is "nothing points home", a filename is one more
/// place the name gets read.
///
/// Year-scoped, so a reader who shares 2026 and then all-time does not overwrite one with
/// the other while both are still in a chat's upload queue. The set of names is bounded by
/// the years the reader has read in, all of them in the temp directory.
String cardShareFileName(int year) =>
    year == 0 ? 'libstack-library-card.png' : 'libstack-library-card-$year.png';

/// Everything the card needs to be rendered, as one value.
///
/// **Extracted when the row grew past one slot.** Three destinations now render the same
/// card and hand the file somewhere different, and the alternative — three call sites each
/// passing eight arguments to `captureWidgetToPng` — is three places for the exported image
/// to drift apart. That drift is the exact failure `shareLibraryCard` was created to
/// prevent when there were two share buttons; this keeps the guarantee now that there are
/// three destinations behind one of them.
@immutable
class CardExportRequest {
  final LibraryCardStats stats;
  final List<Book> books;

  /// The books the reader has open, drawn at the front of the shelf and counted by
  /// nothing. See [ShareableLibraryCard.reading].
  final List<Book> reading;
  final int year;
  final String? displayName;
  final String? handle;
  final DateTime? memberSince;
  final CardFraming framing;
  final CardLighting lighting;

  const CardExportRequest({
    required this.stats,
    required this.books,
    required this.year,
    this.reading = const [],
    this.displayName,
    this.handle,
    this.memberSince,
    this.framing = CardFraming.fill,
    this.lighting = CardLighting.daylight,
  });

  /// The same request with a different framing.
  ///
  /// Used by exactly one caller and it is worth naming: **Stories always exports Fill**,
  /// whatever the toggle says, because Instagram paints the ground itself from the colours
  /// it is handed. Baking our own ground into the sticker would put one ground on top of
  /// another. See `shareCardToStory`.
  CardExportRequest framedAs(CardFraming value) => CardExportRequest(
    stats: stats,
    books: books,
    reading: reading,
    year: year,
    displayName: displayName,
    handle: handle,
    memberSince: memberSince,
    framing: value,
    lighting: lighting,
  );

  Widget build() => FramedShareableCard(
    framing: framing,
    lighting: lighting,
    card: ShareableLibraryCard(
      stats: stats,
      books: books,
      reading: reading,
      year: year,
      displayName: displayName,
      handle: handle,
      memberSince: memberSince,
      lighting: lighting,
    ),
  );
}

/// Renders a card and returns the path it was written to.
typedef CardExporter =
    Future<String> Function(BuildContext context, CardExportRequest request);

/// The render every destination goes through. Swappable, and it has to be.
///
/// **The render is the one half of a share that `flutter test` cannot execute.**
/// `captureWidgetToPng` waits on two real frames and then `toImage`, and PNG encoding only
/// runs inside `runAsync` — from which a test cannot pump. So a widget test that taps a
/// destination and lets the real exporter run does not fail, it *hangs*, which is the worst
/// of the available outcomes.
///
/// Swapping it also makes the assertion sharper rather than merely possible: a test can
/// read the [CardExportRequest] itself and check that Stories asked for Fill, instead of
/// inferring it from the pixels that came out.
CardExporter exportCardFile = exportLibraryCardFile;

/// Restores the real exporter. For a test's `tearDown`.
void resetCardExporter() => exportCardFile = exportLibraryCardFile;

/// Renders the card off-screen and writes it to a file, returning the path.
///
/// The render is off-screen and pure Flutter on purpose — see [captureWidgetToPng].
/// Capturing what is on screen would punch a hole where the native year capsules are, and
/// would hand the reader the sheet's chrome along with the card.
///
/// **One render path for every destination.** Whatever the reader picks, the bytes are
/// produced here, so no two destinations can send different images of the same card.
Future<String> exportLibraryCardFile(
  BuildContext context,
  CardExportRequest request,
) async {
  // The covers the card is about to draw, decoded before the capture rather than during
  // it. Without this the PNG leaves the phone with holes where they should be: `toImage`
  // paints only what is already decoded, and nothing on screen would ever show it.
  // `cardCoverProviders` and the row take the same selection *and the same setting*, so
  // the list cannot drift from what is drawn — under `spines` it is correctly empty,
  // because a spine is toned from stored colour and needs no network at all.
  final covers = cardCoverProviders(
    booksInCardYear(request.books, request.year),
    readingCount: request.reading.length,
  );
  final bytes = await captureWidgetToPng(
    context: context,
    widget: request.build(),
    logicalSize: framedCardSize,
    // The seal's brand mark rides along with the covers: it is an asset rather than a
    // network fetch, but `toImage` does not care where undecoded bytes were going to
    // come from — an unresolved AssetImage exports as the same hole. A cache hit on
    // every share after the first.
    precache: [...covers, const AssetImage(kCardSealMarkAsset)],
    // The same failure in a smaller shape, and `precache` cannot carry it: an
    // `SvgPicture` is not an `ImageProvider`, so the ribbon an open book wears has to be
    // warmed separately or it is missing from exactly the covers whose job is to be
    // marked. A cache hit after the first share.
    warm: [warmReadingBookmark()],
  );

  // The temp directory, not documents: this file exists only long enough for the target to
  // copy it, and the reader did not ask for a file in their app's storage.
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/${cardShareFileName(request.year)}');
  await file.writeAsBytes(bytes);
  return file.path;
}

/// Renders the Library Card and hands the PNG to the platform share sheet.
///
/// Lives here rather than on the Card sheet because there are two buttons: the sheet's, in
/// its expanded header, and the library bar's.
///
/// **The payload is the PNG and nothing else: no `text:`, no URL.** This reverses the
/// plan's original premise, which called a link back into the app the highest-ratio change
/// in the phase. A caption does not survive a screenshot, a re-save or a forward and the
/// pixels do, so the return path is *printed on the card* instead — see
/// `kCardBrandHandle`. `subject` stays, for the targets that use one; the messengers drop
/// it for an image.
///
/// [origin] is the button's rect in global coordinates, required on iPad where the share
/// sheet is a popover and has to be anchored to something.
Future<void> shareLibraryCard(
  BuildContext context, {
  required LibraryCardStats stats,
  required List<Book> books,
  required int year,
  required String? displayName,
  required DateTime? memberSince,
  required Rect? origin,
  String? handle,
  List<Book> reading = const [],
  CardFraming framing = CardFraming.fill,
  CardLighting lighting = CardLighting.daylight,
  ShareSurface surface = ShareSurface.libraryBar,
  String destination = 'system',
}) async {
  final l10n = AppLocalizations.of(context);
  // Composed once and reused, so `share_opened` and `share_completed` cannot describe two
  // different shares.
  final dimensions = <String, Object>{
    'surface': surface.name,
    'format': framing.name,
    'lighting': lighting.name,
    'destination': destination,
  };
  try {
    EasyLoading.show();
    final path = await exportCardFile(
      context,
      CardExportRequest(
        stats: stats,
        books: books,
        reading: reading,
        year: year,
        displayName: displayName,
        handle: handle,
        memberSince: memberSince,
        framing: framing,
        lighting: lighting,
      ),
    );

    EasyLoading.dismiss();
    await analytics.log(kShareOpened, dimensions);
    final result = await Share.shareXFiles(
      [XFile(path)],
      subject: l10n.libraryCardShareSubject,
      sharePositionOrigin: origin,
    );
    // The return value used to be discarded, which is why nothing in this app has ever
    // known whether a share landed. `raw` is the chosen activity where the platform
    // reports one — empty on a dismissal, and empty is a fact worth keeping rather than a
    // gap to fill.
    await analytics.log(kShareCompleted, {
      ...dimensions,
      'outcome': result.status.name,
      'activity': result.raw,
    });
  } catch (_) {
    EasyLoading.showError(l10n.libraryCardShareFailed);
    await analytics.log(kShareCompleted, {
      ...dimensions,
      'outcome': 'failed',
      'activity': '',
    });
  }
}

/// The share affordance for the Library Card, wherever it is drawn.
///
/// Stateful only to hold its own `GlobalKey`, which is how the iPad popover gets an
/// anchor — the whole reason this is a widget rather than a call to `IconButton`.
/// Icon-only, because the sheet's header also has to hold a title and a capsule row.
///
/// **One control, two materials, and which one is the caller's to say.** See [glass].
class LibraryCardShareButton extends StatefulWidget {
  final bool enabled;

  /// Handed the button's global rect, for [shareLibraryCard]'s `origin`.
  final ValueChanged<Rect?> onShare;

  /// The glyph. The tap target is [tapTarget] square regardless.
  final double iconSize;

  /// The SF Symbol's size on the [glass] path, where the glyph sits inside a disc
  /// that fills the whole tap target and therefore reads larger at the same number.
  /// Mirrors `AdaptiveIconButton`'s own 18-against-22 pairing.
  final double symbolSize;

  final double tapTarget;

  /// Null inherits the ambient `IconTheme`.
  final Color? color;

  /// Whether to wear the platform's Liquid Glass material on iOS 26.
  ///
  /// **Opt-in, and the Card sheet's header is the one site that opts in:** the card
  /// *is* the shareable artifact, and Flighty's Passport does the same thing in the
  /// same place. (The library bar carried a second copy of this control, bare and then
  /// glass; that entry point is gone — see `home_page._LibraryBar`.)
  ///
  /// The cost is real and is paid knowingly: glass here is a `UiKitView`, so it is
  /// subject to everything `native_glass.dart` records about platform views inside a
  /// sheet — hence the cover handling in [ModalCoverBuilder], which this route needed
  /// extending to reach. It also means the selected year capsule below is no longer
  /// the only glass object in the header; if the two start competing, this flag is the
  /// one line to flip back.
  final bool glass;

  const LibraryCardShareButton({
    super.key,
    required this.enabled,
    required this.onShare,
    this.iconSize = 22,
    this.symbolSize = 18,
    this.tapTarget = 40,
    this.color,
    this.glass = false,
  });

  @override
  State<LibraryCardShareButton> createState() => _LibraryCardShareButtonState();
}

class _LibraryCardShareButtonState extends State<LibraryCardShareButton> {
  final _key = GlobalKey();

  Rect? get _origin {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onPressed = widget.enabled ? () => widget.onShare(_origin) : null;

    if (widget.glass) {
      return AdaptiveIconButton(
        key: _key,
        // The platform's own share mark, and the counterpart of `Icons.ios_share`
        // below. Checked rather than recalled, per the warning `native_glass.dart`
        // gives twice: a symbol name that does not exist is dropped silently and
        // leaves the disc empty. `square.and.arrow.up` has existed since SF Symbols 1.
        symbol: 'square.and.arrow.up',
        icon: Icons.ios_share,
        onPressed: onPressed,
        diameter: widget.tapTarget,
        symbolSize: widget.symbolSize,
        iconSize: widget.iconSize,
        // Rides the symbol rather than the button's `tint`, so the mark is brand green
        // and the disc stays glass — see `AdaptiveIconButton.iconColor`.
        iconColor: widget.color,
        semanticLabel: l10n.libraryCardShare,
      );
    }

    return IconButton(
      key: _key,
      onPressed: onPressed,
      icon: Icon(
        // `ios_share` rather than `share`: the platform glyph is what a reader
        // recognises as "send this somewhere", and `friends_sheet.dart` sets the
        // precedent of using Material's own icons here.
        Icons.ios_share,
        size: widget.iconSize,
        color: widget.color,
      ),
      tooltip: l10n.libraryCardShare,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: widget.tapTarget,
        minHeight: widget.tapTarget,
      ),
    );
  }
}
