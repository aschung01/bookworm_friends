import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/services/cover_read.dart';
import 'package:bookworm_friends/services/isbn.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/add_to_library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/empty_state_art.dart';

/// What the scanner hands back to Add Book.
///
/// Deliberately thin, because the happy path does **not** come back through here:
/// a barcode that resolves opens the save sheet on top of the scanner and the
/// save unwinds the whole stack, so Add Book is never resumed. What is left to
/// report is only how the user left — which matters for exactly one reason, below.
sealed class ScanOutcome {
  const ScanOutcome();
}

/// The user chose to type instead — from the nudge, or from a failure card.
///
/// Distinct from a plain dismissal: Add Book focuses its field on this, and
/// focusing the field on *every* return would put the keyboard up over a sheet
/// the user only wanted to get back to.
class ScanTypeInstead extends ScanOutcome {
  const ScanTypeInstead();
}

/// A cover was read into a search query.
///
/// A *query*, not a book, and that asymmetry against the barcode path is the
/// point: an ISBN is an identifier so it goes straight to the save sheet, while a
/// model's reading of stylised cover type is a guess and has to be confirmed
/// against the results grid. So this comes back to Add Book and lands in the
/// field, marked as not the user's own typing.
class ScanFoundQuery extends ScanOutcome {
  final String query;
  const ScanFoundQuery(this.query);
}

/// How long a frame may go without a hit before the nudge appears.
///
/// Long enough that a user who is simply lining the book up is not told they are
/// failing; short enough to arrive before they give up. Deliberately fires once
/// and does not reset when the camera moves — a timer that restarted on every
/// wobble would never fire for the person who needs it most.
///
/// The nudge **escalates** the cover control rather than revealing it: that button
/// is on screen from the first frame, so a user who already knows the barcode is
/// unusable never has to wait out this timer.
const Duration kScanNudgeDelay = Duration(seconds: 4);

/// Longest edge, in pixels, of the cover photo sent for reading.
///
/// A cover only has to be *legible*: the model is transcribing two lines of large
/// display type, not inspecting detail. A 12MP original is slower to upload,
/// slower to process, costs more tokens and is no more readable. `image_picker`
/// does this resize natively, so the full-size original never reaches Dart.
const double kCoverImageMaxEdge = 1600;

/// JPEG quality for that photo. Enough for type, small enough to upload on
/// cellular in about a second.
const int kCoverImageQuality = 85;

/// The scan window, in fractions of the preview's shorter and longer sides.
///
/// 300 x 190 on a 402pt-wide device, per `docs/mockups/scan-to-add`: wide enough
/// for an EAN-13 at reading distance and tall enough to hold the 5-digit 부가기호
/// a Korean book prints beside it, so the pair is framed together rather than the
/// user being made to isolate one of them.
const Size kScanWindowSize = Size(300, 190);

/// Full-screen barcode scanner for Add Book.
///
/// A pushed page rather than a stacked sheet. Both hide the shell's floating tab
/// bar — a page because `shellBarVisibleProvider` compares against the topmost
/// *page* route, a sheet through the stacked-modal counter — but only the sheet
/// would put a live camera platform view underneath two Flutter sheets once the
/// save sheet opens on top, which is the z-order case `autoHideOnModal` exists to
/// work around. The page also keeps the viewfinder full height: in a sheet the
/// framing room above the window collapses from 250pt to 150 and the book gets
/// clipped by the sheet's own top edge.
///
/// **The page owns the whole barcode→book sequence**, not just the decode. It
/// locks the symbol, resolves it through `getByIsbn`, and opens the save sheet on
/// top of itself. The alternative — pop the ISBN and let Add Book resolve it —
/// reads cleaner until you draw the failure: a clean decode that no catalogue
/// knows has to be reported *somewhere*, and the only honest place is over the
/// live viewfinder with "Scan another" next to it, because the fix is to scan a
/// different book. Popping first destroys the only screen that message belongs on.
class ScanBookPage extends ConsumerStatefulWidget {
  const ScanBookPage({super.key});

  @override
  ConsumerState<ScanBookPage> createState() => _ScanBookPageState();
}

/// Which card, if any, is covering the preview.
enum _Failure {
  none,
  denied,
  cameraFailed,
  noCatalogueMatch,
  lookupFailed,
  coverUnreadable,
  coverLimitReached,
}

class _ScanBookPageState extends ConsumerState<ScanBookPage>
    with WidgetsBindingObserver {
  /// `autoStart: false` because this widget owns the lifecycle: the permission
  /// dialog itself drives app lifecycle changes, so leaving the controller to
  /// start itself races with them.
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    // One format. Every other symbol a shelf might have in frame is noise here,
    // and the add-on beside a Korean ISBN decodes as EAN-8 — excluding it is
    // cheaper than resolving it afterwards.
    formats: const [BarcodeFormat.ean13],
    detectionSpeed: DetectionSpeed.normal,
  );

  StreamSubscription<BarcodeCapture>? _barcodes;
  Timer? _nudgeTimer;

  /// Set the moment a symbol resolves, and never cleared.
  ///
  /// The stream keeps delivering the same barcode while it stays in frame, so
  /// without this the ISBN would be handed back and the route popped on every
  /// subsequent frame.
  String? _locked;

  bool _nudging = false;
  _Failure _failure = _Failure.none;

  /// True while `getByIsbn` is in flight.
  ///
  /// Not a [_Failure] and not a card: the preview stays live and the window stays
  /// locked underneath, because nothing has gone wrong and the ISBN on screen is
  /// still the thing the user wants to see.
  bool _lookingUp = false;

  /// True from the moment the cover control is tapped until the read resolves.
  ///
  /// Covers the OS camera being up as well as the network call, because from the
  /// user's side those are one wait, and because it is what stops a second tap
  /// launching a second picker over the first.
  bool _readingCover = false;

  final ImagePicker _picker = ImagePicker();

  bool get _covered => _failure != _Failure.none;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _barcodes = _controller.barcodes.listen(_onCapture);
    _start();
  }

  Future<void> _start() async {
    // Asked for explicitly rather than letting the first camera access trigger
    // it, because the denied card has to distinguish "refused just now" from
    // "refused permanently" to know whether Settings is the way out.
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() => _failure = _Failure.denied);
      return;
    }
    try {
      await _controller.start();
    } on Exception {
      if (!mounted) return;
      setState(() => _failure = _Failure.cameraFailed);
      return;
    }
    if (!mounted) return;
    _armNudge();
  }

  void _armNudge() {
    _nudgeTimer?.cancel();
    _nudgeTimer = Timer(kScanNudgeDelay, () {
      if (!mounted || _locked != null || _covered) return;
      setState(() => _nudging = true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The controller may not be ready: a permission dialog produces lifecycle
    // changes before it is, and start/stop on a controller without permission
    // throws.
    if (!_controller.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
      case AppLifecycleState.resumed:
        _barcodes ??= _controller.barcodes.listen(_onCapture);
        unawaited(_controller.start());
      case AppLifecycleState.inactive:
        unawaited(_barcodes?.cancel());
        _barcodes = null;
        unawaited(_controller.stop());
    }
  }

  void _onCapture(BarcodeCapture capture) {
    if (_locked != null || _covered) return;
    final isbn = chooseIsbn(
      capture.barcodes.map((b) => b.rawValue),
      distancesFromCentre: _distancesFromCentre(capture),
    );
    if (isbn == null) return;
    setState(() {
      _locked = isbn;
      _nudging = false;
    });
    _nudgeTimer?.cancel();
    unawaited(_resolve(isbn));
  }

  /// Turns the locked ISBN into a book, or into the card that explains why not.
  ///
  /// The three outcomes are kept apart on purpose. "No catalogue has it" and "the
  /// lookup did not get through" look identical from here if you only check for
  /// null — `FallbackBookSearchProvider` swallows each provider's throw and returns
  /// null once they have all missed — but they need opposite advice: one is fixed
  /// by typing the title, the other by trying the same scan again on better wifi.
  /// Telling an offline user their book does not exist is the worse of the two lies.
  Future<void> _resolve(String isbn) async {
    setState(() => _lookingUp = true);
    BookSearchResult? book;
    try {
      book = await ref.read(bookSearchProvider).getByIsbn(isbn);
    } on Exception {
      if (!mounted) return;
      setState(() {
        _lookingUp = false;
        _failure = _Failure.lookupFailed;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _lookingUp = false);
    if (book == null) {
      setState(() => _failure = _Failure.noCatalogueMatch);
      return;
    }

    // Straight to the save sheet, skipping the results grid an exact identifier
    // does not need. The asymmetry is deliberate and is the reason the deferred
    // cover path must *not* do this: an ISBN is the book, an LLM's reading of a
    // cover is a guess, and a guess has to be confirmed against a grid first.
    final shelves = ref.read(libraryProvider).valueOrNull ?? const [];
    await showAddToLibrarySheet(context, ref, book: book, shelves: shelves);

    // Only reached when the sheet was dismissed *without* saving — a save calls
    // `popUntil` and takes this page with it. Dismissing means "not that book", so
    // the scanner goes back to hunting rather than sitting on a stale green lock.
    if (!mounted) return;
    _rescan();
  }

  /// How far each candidate's centre sat from the middle of the frame.
  ///
  /// Only consulted for the rare tie of two separate books in shot. Null when the
  /// platform gave no corner points, which is its own answer: without geometry
  /// there is nothing to compare and the first valid candidate wins.
  Map<String, double>? _distancesFromCentre(BarcodeCapture capture) {
    final size = capture.size;
    if (size.isEmpty) return null;
    final out = <String, double>{};
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      final corners = barcode.corners;
      if (value == null || corners.isEmpty) continue;
      var x = 0.0;
      var y = 0.0;
      for (final c in corners) {
        x += c.dx;
        y += c.dy;
      }
      out[value] = Offset(
        x / corners.length - size.width / 2,
        y / corners.length - size.height / 2,
      ).distance;
    }
    return out.isEmpty ? null : out;
  }

  /// Photographs the cover and turns it into a search query.
  ///
  /// **The OS camera, not ours, and that is a forced choice.** `mobile_scanner`
  /// cannot take a still: `returnImage` only yields a frame *when a barcode is
  /// found*, which is precisely the case this path exists for, and the maintainer
  /// considers capture out of scope (issues #1262 and #1496; PR #1479 was closed
  /// unmerged). The alternative was replacing the plugin with `camera` +
  /// `google_mlkit_barcode_scanning`, which pins `ios.deployment_target` at 15.5
  /// and would have dropped every user on iOS 15.0–15.4 to improve the *rarer* of
  /// the two paths. So the barcode path keeps the plugin, and the cover path
  /// borrows the system camera.
  ///
  /// The control is labelled "Read the cover" rather than drawn as a shutter for
  /// exactly this reason: a shutter glyph promises an instant in-place capture and
  /// would then be a lie. A labelled button reads as a doorway, so the OS camera
  /// appearing is not a surprise.
  Future<void> _readCover() async {
    if (_readingCover) return;

    setState(() {
      _readingCover = true;
      _nudging = false;
    });
    _nudgeTimer?.cancel();

    // Ours down before theirs comes up. Two live camera sessions is the failure
    // mode every report of this pattern describes: a black preview on return, or a
    // picker that never opens.
    await _controller.stop();

    XFile? shot;
    try {
      shot = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        // Resized natively, so the original never crosses into Dart.
        maxWidth: kCoverImageMaxEdge,
        maxHeight: kCoverImageMaxEdge,
        imageQuality: kCoverImageQuality,
        // The read only needs pixels. Skipping metadata avoids asking for photo
        // library permission on iOS, which this path has no use for.
        requestFullMetadata: false,
      );
    } on Exception catch (error) {
      debugPrint('cover capture failed: $error');
    }

    if (!mounted) return;

    // Cancelled in the OS camera. Not a failure and not worth a card — back to
    // scanning, which is what they were doing before they tapped.
    if (shot == null) {
      setState(() => _readingCover = false);
      await _restartScanning();
      return;
    }

    final Uint8List bytes;
    try {
      bytes = await File(shot.path).readAsBytes();
    } on Exception catch (error) {
      debugPrint('cover read failed: $error');
      if (!mounted) return;
      setState(() {
        _readingCover = false;
        _failure = _Failure.coverUnreadable;
      });
      return;
    }

    final result = await readBookCover(bytes);
    if (!mounted) return;
    setState(() => _readingCover = false);

    switch (result) {
      case CoverReadQuery(:final query):
        // Straight back to Add Book. The scanner does *not* look this up or open
        // the save sheet: the grid is the confirmation step a guess has to earn.
        Navigator.pop<ScanOutcome>(context, ScanFoundQuery(query));
      case CoverReadUnreadable():
        setState(() => _failure = _Failure.coverUnreadable);
      case CoverReadRateLimited():
        setState(() => _failure = _Failure.coverLimitReached);
      case CoverReadFailed(:final detail):
        debugPrint('cover read failed: $detail');
        setState(() => _failure = _Failure.coverUnreadable);
    }
  }

  /// Brings the preview back after the OS camera has been over it.
  ///
  /// Separate from [_rescan] because the controller was genuinely stopped here, so
  /// this has to restart the camera as well as reset the UI — and it must not
  /// re-request permission, which is already granted by the time anyone can reach
  /// the cover control.
  Future<void> _restartScanning() async {
    try {
      await _controller.start();
    } on Exception catch (error) {
      debugPrint('scanner restart failed: $error');
      if (!mounted) return;
      setState(() => _failure = _Failure.cameraFailed);
      return;
    }
    if (!mounted) return;
    _rescan();
  }

  /// Retries the lookup for the ISBN already on screen.
  ///
  /// Separate from [_rescan] because a connection failure did not invalidate the
  /// decode — making the user re-frame a book whose barcode was read perfectly
  /// would be blaming them for the network.
  void _retryLookup() {
    final isbn = _locked;
    if (isbn == null) {
      _rescan();
      return;
    }
    setState(() => _failure = _Failure.none);
    unawaited(_resolve(isbn));
  }

  void _rescan() {
    setState(() {
      _failure = _Failure.none;
      _lookingUp = false;
      _locked = null;
    });
    _armNudge();
  }

  void _typeInstead() =>
      Navigator.pop<ScanOutcome>(context, const ScanTypeInstead());

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nudgeTimer?.cancel();
    unawaited(_barcodes?.cancel());
    _barcodes = null;
    // Fire and forget, and it has to be: `dispose` is synchronous as far as the
    // framework is concerned, so an `async` override here would return a future
    // nobody awaits while reading as though the teardown were ordered.
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Dark tokens regardless of the app's theme: a camera preview is dark
    // whatever the theme says, so `AppColors.dark`'s vivid brand green is the one
    // that may be read against it (6.8:1 on its surface, where the light map's
    // decorative green is 2.45:1 on white).
    const dark = AppColors.dark;
    final size = MediaQuery.sizeOf(context);
    final window = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.395),
      width: kScanWindowSize.width,
      height: kScanWindowSize.height,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF15171A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!_covered)
            MobileScanner(
              controller: _controller,
              scanWindow: window,
              // The preview is the whole screen; the window only bounds what is
              // decoded, so a symbol outside it is ignored rather than the user
              // being shown a letterboxed camera.
              fit: BoxFit.cover,
              errorBuilder: (context, error) => const SizedBox.shrink(),
            ),
          if (!_covered)
            _ScanWindowOverlay(window: window, locked: _locked != null),
          if (!_covered && _locked != null)
            _ReadoutBanner(
              top: window.bottom + 30,
              text: formatIsbnForDisplay(_locked!),
              color: dark.brandText,
              monospace: true,
              // The ISBN stays the banner's text while the lookup runs rather than
              // being replaced by "Looking it up…": it is the user's only proof
              // that the book about to appear is the book they pointed at, and
              // swapping it out at the exact moment the app goes quiet removes the
              // evidence just when they would want to check it. The spinner
              // carries the progress; the label carries it for screen readers,
              // which cannot see a spinner at all.
              busy: _lookingUp,
              busyLabel: l10n.scanLookingUp,
            ),
          if (!_covered && _locked == null)
            _ReadoutBanner(
              top: window.bottom + 30,
              text: l10n.scanHint,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          if (_nudging && !_covered)
            _Nudge(
              text: l10n.scanNudge,
              actionLabel: l10n.scanTypeInstead,
              onPressed: _typeInstead,
            ),
          // On screen from the first frame, and the reason a second entry button in
          // Add Book's search row would buy nothing: the cover route is never
          // hidden behind the nudge, only *named* by it. A user who already knows
          // the barcode is unusable does not wait 4s for permission to act.
          //
          // Sits above the nudge so the nudge's sentence and the control it points
          // at are one glance apart.
          if (!_covered)
            _CoverButton(
              label: _readingCover ? l10n.scanReadingCover : l10n.scanReadCover,
              busy: _readingCover,
              // Disabled while a read is in flight rather than hidden: a control
              // that vanished under the user's thumb would read as a crash, and
              // the label is carrying the progress.
              onPressed: _readingCover ? null : () => unawaited(_readCover()),
            ),
          if (_covered) _failureCard(l10n, dark),
          Positioned(
            left: 20,
            right: 20,
            top: MediaQuery.viewPaddingOf(context).top,
            height: 44,
            child: Row(
              children: [
                AdaptiveIconButton(
                  symbol: 'xmark',
                  icon: Icons.close,
                  diameter: kIconButtonDiameter,
                  symbolSize: kIconButtonSymbolSize,
                  iconSize: kIconButtonIconSize,
                  semanticLabel: l10n.close,
                  onPressed: () => Navigator.pop<ScanOutcome>(context),
                ),
                const Spacer(),
                if (!_covered)
                  AdaptiveIconButton(
                    symbol: 'flashlight.on.fill',
                    icon: Icons.flashlight_on_outlined,
                    diameter: kIconButtonDiameter,
                    symbolSize: kIconButtonSymbolSize,
                    iconSize: kIconButtonIconSize,
                    semanticLabel: l10n.scanTorch,
                    onPressed: () => unawaited(_controller.toggleTorch()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One card shape for every failure, with two ways onward and no bare OK.
  ///
  /// A flow whose only job is "add this book" must not end in a wall, so the
  /// secondary action always reaches a book by another route even when the
  /// primary cannot fix anything.
  Widget _failureCard(AppLocalizations l10n, AppColors dark) {
    final (String title, String body, Widget? primary) = switch (_failure) {
      _Failure.denied => (
        l10n.scanDeniedTitle,
        l10n.scanDeniedBody,
        _CardAction(
          label: l10n.scanOpenSettings,
          primary: true,
          onPressed: () => unawaited(openAppSettings()),
        ),
      ),
      _Failure.cameraFailed => (
        l10n.scanFailedTitle,
        l10n.scanFailedBody,
        null,
      ),
      _Failure.noCatalogueMatch => (
        l10n.scanNoMatchTitle,
        l10n.scanNoMatchBody(formatIsbnForDisplay(_locked ?? '')),
        _CardAction(label: l10n.scanAnother, primary: true, onPressed: _rescan),
      ),
      _Failure.lookupFailed => (
        l10n.scanLookupFailedTitle,
        l10n.scanLookupFailedBody,
        _CardAction(
          label: l10n.scanRetry,
          primary: true,
          onPressed: _retryLookup,
        ),
      ),
      // "Retake", not "Scan another": the advice above is about how the photo was
      // taken, so the primary action has to be the one that retakes it.
      _Failure.coverUnreadable => (
        l10n.scanCoverFailedTitle,
        l10n.scanCoverFailedBody,
        _CardAction(
          label: l10n.scanRetake,
          primary: true,
          onPressed: () {
            setState(() => _failure = _Failure.none);
            unawaited(_readCover());
          },
        ),
      ),
      // **No primary action at all.** The limit is the whole message and retrying
      // cannot help, so offering a button that re-fails would be a lie. Barcode
      // scanning is still live behind this card and typing still works, which is
      // what the body says and what the secondary action reaches.
      _Failure.coverLimitReached => (
        l10n.scanCoverLimitTitle,
        l10n.scanCoverLimitBody,
        _CardAction(
          label: l10n.scanAnother,
          primary: true,
          onPressed: () {
            setState(() => _failure = _Failure.none);
            unawaited(_restartScanning());
          },
        ),
      ),
      _Failure.none => ('', '', null),
    };

    // Only the no-match case gets a drawing, and it is deliberately kept out of
    // the switch above rather than added as a null to all seven arms. The other
    // failures are about the camera, the network or a quota -- an empty-shelf
    // illustration would misdescribe them. "We looked this book up and found
    // nothing" is the one that is the same state as a search miss, so it gets
    // the same art.
    final artwork = _failure == _Failure.noCatalogueMatch
        ? EmptyStateArtwork.noMatch
        : null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          decoration: BoxDecoration(
            color: dark.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // `dark.secondaryText`, not `context.colors` — the scanner is a
              // camera view and this card is always dark regardless of the app
              // theme, so the tint has to come from the same palette the text
              // beside it is using.
              if (artwork != null) ...[
                EmptyStateArt(artwork, size: 34, color: dark.secondaryText),
                const SizedBox(height: 12),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTextStyles.subtitle.copyWith(color: dark.primaryText),
              ),
              const SizedBox(height: 7),
              Text(
                body,
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(color: dark.secondaryText),
              ),
              const SizedBox(height: 17),
              if (primary != null) ...[primary, const SizedBox(height: 9)],
              _CardAction(
                label: l10n.scanTypeInstead,
                primary: false,
                onPressed: _typeInstead,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The corner brackets around the scan window.
///
/// Locking changes the bracket colour *and* adds a hairline around the whole
/// window, so the state is not carried by colour alone.
class _ScanWindowOverlay extends StatelessWidget {
  final Rect window;
  final bool locked;

  const _ScanWindowOverlay({required this.window, required this.locked});

  @override
  Widget build(BuildContext context) {
    final color = locked ? AppColors.dark.brandText : Colors.white;
    return Positioned.fromRect(
      rect: window,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: locked
                ? Border.all(color: color.withValues(alpha: 0.55), width: 2)
                : null,
          ),
          child: Stack(
            children: [
              for (final corner in const [
                Alignment.topLeft,
                Alignment.topRight,
                Alignment.bottomLeft,
                Alignment.bottomRight,
              ])
                Align(
                  alignment: corner,
                  child: CustomPaint(
                    size: const Size.square(34),
                    painter: _CornerPainter(alignment: corner, color: color),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Alignment alignment;
  final Color color;

  const _CornerPainter({required this.alignment, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final isLeft = alignment.x < 0;
    final isTop = alignment.y < 0;
    final x = isLeft ? 1.5 : size.width - 1.5;
    final y = isTop ? 1.5 : size.height - 1.5;
    canvas.drawLine(Offset(x, y), Offset(isLeft ? size.width : 0, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, isTop ? size.height : 0), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) =>
      old.color != color || old.alignment != alignment;
}

/// The line under the window: the hint before a lock, the ISBN after one.
///
/// Carries its own dark pill. Without one the vivid green measures under 2:1 on a
/// pale back cover, and a camera preview is not a surface whose colour anyone
/// gets to choose.
class _ReadoutBanner extends StatelessWidget {
  final double top;
  final String text;
  final Color color;
  final bool monospace;
  final bool busy;
  final String? busyLabel;

  const _ReadoutBanner({
    required this.top,
    required this.text,
    required this.color,
    this.monospace = false,
    this.busy = false,
    this.busyLabel,
  });

  @override
  Widget build(BuildContext context) {
    // Two roles in one banner: the locked readout is the scanned number itself,
    // the unlocked one is a sentence about aiming.
    final readout = monospace ? AppTextStyles.subtitle : AppTextStyles.body;
    return Positioned(
      left: 24,
      right: 24,
      top: top,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF0F1113).withValues(alpha: 0.66),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
            child: Semantics(
              label: busy && busyLabel != null ? '$text, $busyLabel' : null,
              excludeSemantics: busy && busyLabel != null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy) ...[
                    SizedBox.square(
                      dimension: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                    const SizedBox(width: 9),
                  ],
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: readout.copyWith(
                      color: color,
                      // Kept: the digits are set monospaced on purpose, and
                      // tracking is what makes a run of them readable.
                      letterSpacing: monospace ? 1 : null,
                      fontFamily: monospace ? 'monospace' : null,
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

/// Height of the cover-read control, and the room the nudge has to clear.
const double _kCoverButtonHeight = 48;

/// Gap between the viewfinder's bottom safe area and the cover control.
const double _kCoverButtonInset = 24;

/// The cover-read entry point, on screen from the first frame.
///
/// **A labelled pill, not a shutter glyph.** A shutter promises an instant
/// in-place capture, and this cannot deliver one: `mobile_scanner` has no still
/// capture, so the photo is taken in the *system* camera (see `_readCover`). A
/// button that says what it does makes the OS camera appearing a consequence
/// rather than a surprise, and it is honest about being a doorway.
class _CoverButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  const _CoverButton({required this.label, required this.busy, this.onPressed});

  @override
  Widget build(BuildContext context) {
    const dark = AppColors.dark;
    return Positioned(
      left: 20,
      right: 20,
      bottom: MediaQuery.viewPaddingOf(context).bottom + _kCoverButtonInset,
      height: _kCoverButtonHeight,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: dark.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(50),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(50),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(dark.brandText),
                      ),
                    )
                  else
                    Icon(
                      Icons.photo_camera_outlined,
                      size: 19,
                      color: dark.brandText,
                    ),
                  const SizedBox(width: 9),
                  Text(
                    label,
                    style: AppTextStyles.label.copyWith(color: dark.brandText),
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

/// Appears after [kScanNudgeDelay] with no hit.
///
/// Escalates a route that is already open rather than revealing a new one: the
/// point is to say out loud that not finding a barcode is not a dead end.
class _Nudge extends StatelessWidget {
  final String text;
  final String actionLabel;
  final VoidCallback onPressed;

  const _Nudge({
    required this.text,
    required this.actionLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 20,
      right: 20,
      // Clears the cover control rather than overlapping it. The nudge's sentence
      // names that button, so the two have to be visible together — a banner
      // sitting on top of the thing it points at was the first version and it read
      // as a single confusing block.
      bottom:
          MediaQuery.viewPaddingOf(context).bottom +
          _kCoverButtonInset +
          _kCoverButtonHeight +
          12,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1E21).withValues(alpha: 0.9),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.dark.primaryText,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: onPressed,
                child: Text(
                  actionLabel,
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.dark.brandText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onPressed;

  const _CardAction({
    required this.label,
    required this.primary,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    const dark = AppColors.dark;
    // A muted *fill* for the secondary action, not an outline. The obvious
    // spelling — `activated: false, disabledStyleOutline: true` — gives the right
    // picture and a dead button: [ElevatedActionButton] passes
    // `activated ? onPressed : null`, so `activated: false` genuinely disables it
    // and `disabledStyleOutline` exists to style a button that is *meant* to be
    // disabled. On a failure card the secondary action is the only guaranteed way
    // out, so that mistake is the difference between a recoverable error and a
    // wall. This follows the app's real secondary pattern instead (see
    // `delete_book_bottom_sheet.dart`): stay activated, mute the fill, and set the
    // label colour explicitly, since an activated button defaults to white text.
    return SizedBox(
      width: double.infinity,
      child: ElevatedActionButton(
        height: 44,
        buttonText: label,
        backgroundColor: primary ? dark.brandFill : dark.surfaceVariant,
        textStyle: AppTextStyles.label.copyWith(
          color: primary ? Colors.white : dark.brandText,
        ),
        overlayColor: dark.brandText,
        onPressed: onPressed,
      ),
    );
  }
}
