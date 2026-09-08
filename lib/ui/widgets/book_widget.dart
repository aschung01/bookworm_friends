import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:bookworm_friends/ui/widgets/book/book_chassis.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book/cover_sample.dart';
import 'package:bookworm_friends/ui/widgets/book/generated_cover.dart';

/// How long a finger must stay down before the book begins to turn.
///
/// Long enough that an ordinary tap produces no rotation at all, short enough
/// that the turn still feels like a direct response to holding.
const Duration kBookHoldDelay = Duration(milliseconds: 140);

/// How long a hold must last before stage two fires.
///
/// Deliberately longer than the platform's 500ms long-press default. At 500ms
/// the book would only sit fully turned for about 100ms before edit mode
/// arrived, which is not long enough to look at.
const Duration kBookStageTwoDelay = Duration(milliseconds: 700);

/// How long the turn takes to reach [kBookTurnAngle], and how long it takes to
/// unwind afterwards.
///
/// Public because callers that drive the turn from outside the book — see
/// [BookWidget.turnDrive] — have to animate on exactly these timings, or the
/// miniature in a list row would turn at a visibly different rate from the book on
/// the shelf.
const Duration kBookTurnDuration = Duration(milliseconds: 260);
const Duration kBookReleaseDuration = Duration(milliseconds: 180);

const Duration _kStageTwoReturnDuration = Duration(milliseconds: 120);
const Duration _kPressDuration = Duration(milliseconds: 90);

/// A book: cover, spine binding, page block and back board, in perspective.
///
/// Holding the book turns it, which is this app's substitute for the hover the
/// reference component relies on. The turn doubles as a progress indicator for
/// the hold: on the home shelves, continuing to hold past [kBookStageTwoDelay]
/// fires [onLongPress] to enter edit mode, so the rotation telegraphs that
/// something is about to happen.
class BookWidget extends StatefulWidget {
  /// Base height before jitter. Defaults to 15% of screen height.
  final double? height;

  final String imageUrl;

  /// Drives the size jitter and the generated cover's colour. Books without an
  /// ISBN fall back to neutral values rather than hashing an empty string.
  final String isbn;

  /// The book's page count, when the catalogue supplied a credible one.
  ///
  /// Sets the book's thickness in place of the ISBN hash. Must come from a stored
  /// value rather than a live catalogue lookup: a count that arrives mid-session
  /// would make the book visibly change thickness while on screen.
  final int? pageCount;

  /// Shown on the generated cover when there is no usable thumbnail.
  final String title;

  final VoidCallback? onTap;

  /// Stage two of the hold. Fires at [kBookStageTwoDelay]; suppresses the
  /// [onTap] that would otherwise follow on release.
  final VoidCallback? onLongPress;

  final String? heroTag;

  /// Gates both stages of the hold. Passed `false` in edit mode, where holding
  /// belongs to the reorder drag instead.
  final bool pressEffect;

  /// Whether the book picks up its hashed height and thickness variation.
  ///
  /// True on the shelves, where the variation is the point: a row of books at
  /// slightly different heights reads as physical books rather than as a chart.
  ///
  /// The read view's month grid, whose cells are uniform by construction, wants
  /// half of that: there the same 6% of height reads as misalignment instead of as
  /// character, which is exactly how it looked on device. It says so with a
  /// [jitterOverride] of [BookJitter.atNeutralHeight] rather than with `false`
  /// here, because `false` drops the *thickness* too and a held cover in the grid
  /// then shows the thinnest fore-edge in the range whatever the book's length.
  final bool jitter;

  /// Jitter resolved by the caller, overriding both [jitter] and the ISBN hash.
  ///
  /// For a caller that has already computed the book's size and needs the drawing
  /// to agree with it to the pixel. The read pile is the case: it lays a row of
  /// flat spines out at their hashed thicknesses, and when one is tapped the
  /// chassis that replaces it **must be exactly as thick as the spine that was
  /// tapped**. Recomputing the same hash in two places is how the two come to
  /// disagree.
  ///
  /// Also how a caller asks for *part* of the variation — the month grid passes
  /// [BookJitter.atNeutralHeight], which is one book's thickness at every book's
  /// height.
  final BookJitter? jitterOverride;

  /// Turns the book from outside its own hold.
  ///
  /// For a caller whose gesture is not on the book. The Friends row is pressed as
  /// a whole and the finger is nearly always on a name rather than on the 34pt
  /// book at the end of the row, so the row drives the turn and the book's own
  /// recogniser never sees the pointer at all.
  ///
  /// Replaces the internal hold rather than adding to it: two sources animating
  /// one angle would fight each other whenever a press happened to land on the
  /// book itself. Drive it between 0 and 1 — [kBookTurnAngle] is applied here.
  final Animation<double>? turnDrive;

  /// The book's pose, in radians, set by whatever placed it.
  ///
  /// Distinct from [turnDrive] in *both* respects, and the difference is worth
  /// being precise about because the two look interchangeable:
  ///
  ///  * **Range.** [turnDrive] maps `0..1` onto [kBookTurnAngle] and so cannot
  ///    express `-π/2`. The read pile's books rest spine-on, which is exactly
  ///    `-π/2`, so they need the angle itself rather than a fraction of the hold.
  ///  * **Composition.** [turnDrive] *replaces* the internal hold; this **adds to
  ///    it**. They are not two drivers of one quantity: this is where the book has
  ///    been put, and the hold is how it answers your finger — an offset from
  ///    wherever that is. That is precisely what makes a book turned out of the
  ///    pile behave like a book on a shelf: it is the same hold, on the same
  ///    timings, running on top of a pose of 0 instead of a pose of nothing.
  ///
  /// May not be combined with [turnDrive], which owns the hold outright.
  final Animation<double>? turnRadians;

  /// The face seen along the binding, for a book turned far enough to show one.
  ///
  /// Passed through to [BookChassis.spine]. Null everywhere but the read pile.
  final Widget? spine;

  /// What the turn rotates about. Passed through to [BookChassis.pivot];
  /// [Alignment.centerLeft] hinges the book on its spine.
  final Alignment pivot;

  /// Reports the average colour of the cover, once it has decoded.
  ///
  /// This is the backfill for `books.cover_color`. [_sampleCoverColor] already
  /// runs on every successful decode to choose the back board, so the value costs
  /// nothing extra — this only exposes it. Fires once per decode and only for a
  /// real cover: a generated one's colour is derived from the ISBN and there is
  /// nothing about it worth storing.
  ///
  /// A callback and not a write, deliberately. [BookWidget] does no I/O and has no
  /// Riverpod dependency; it stays a presentation widget, and what to do with the
  /// colour is the caller's business.
  final ValueChanged<Color>? onCoverSampled;

  const BookWidget({
    super.key,
    this.height,
    required this.imageUrl,
    required this.isbn,
    required this.title,
    this.onTap,
    this.onLongPress,
    this.heroTag,
    this.pageCount,
    this.turnDrive,
    this.turnRadians,
    this.spine,
    this.jitterOverride,
    this.onCoverSampled,
    this.pressEffect = true,
    this.jitter = true,
    this.pivot = Alignment.center,
  }) : assert(
         turnDrive == null || turnRadians == null,
         'turnDrive replaces the hold and turnRadians composes with it; '
         'passing both leaves it ambiguous which one the hold answers to',
       );

  @override
  State<BookWidget> createState() => _BookWidgetState();
}

class _BookWidgetState extends State<BookWidget> with TickerProviderStateMixin {
  /// Both created in [initState] rather than lazily.
  ///
  /// `late final` on these was a latent crash: [dispose] touches them, so a book that
  /// never read one during its life would *construct* it while unmounting, and
  /// creating a ticker calls `TickerMode.of(context)` on a defunct element. Harmless
  /// while `build` always read both — and reachable the moment [turnDrive] was added,
  /// since a book driven from outside never touches `_turn` at all.
  late final AnimationController _turn;
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _turn = AnimationController(vsync: this, duration: kBookTurnDuration);
    _press = AnimationController(vsync: this, duration: _kPressDuration);
  }

  Timer? _holdTimer;
  Timer? _stageTwoTimer;

  /// Set when stage two fires, so the release that follows doesn't also
  /// navigate. A tap recogniser has no upper time bound, so without this a
  /// 2-second hold would enter edit mode *and* push the details route.
  bool _stageTwoFired = false;

  ImageStream? _stream;
  ImageStreamListener? _streamListener;
  ImageProvider<Object>? _provider;

  /// Intrinsic aspect ratio of the cover, once decoded.
  double? _coverAspect;
  bool _imageFailed = false;

  /// The cover's resolved tone, once sampled. Drives the back board.
  Color? _sampledCover;

  /// Whether the generated cover is standing in for a real one.
  bool get _usesGeneratedCover =>
      widget.imageUrl.isEmpty || _imageFailed || _provider == null;

  /// Tone for the back board.
  ///
  /// Known immediately for a generated cover, since we picked its swatch. For a
  /// real cover it needs a decode first, and until then this is null and the
  /// chassis falls back to the theme's neutral board.
  Color? get _boardColor {
    if (_usesGeneratedCover) {
      return bookBoardColorFor(generatedCoverColor(widget.isbn));
    }
    final sampled = _sampledCover;
    return sampled == null ? null : bookBoardColorFor(sampled);
  }

  /// Samples the decoded cover and adopts its resolved tone.
  ///
  /// The resolving itself lives in [coverToneColor], shared with the backfill tool so
  /// that a stored colour and a live one cannot disagree — which matters more than it
  /// sounds, because `recordCoverColor` skips any book that already has a colour, so
  /// a value written by one policy would never be revisited by the other.
  ///
  /// [coverToneColor] rather than [averageCoverColor], and the board takes the same
  /// value the spine does. That is the point: the board is the far side of the book
  /// the cover is on, so it should be a tone of the background the reader can see,
  /// not of a mean that mixes the type in.
  ///
  /// What stays here is the part that belongs to a widget: the `mounted` check across
  /// the await, and reporting the result on.
  Future<void> _sampleCoverColor(ui.Image image) async {
    final sampled = await coverToneColor(image);
    if (sampled == null || !mounted) return;
    setState(() => _sampledCover = sampled);
    // After the setState, so a listener that rebuilds this subtree sees the
    // board already toned rather than triggering a second frame at the old one.
    widget.onCoverSampled?.call(sampled);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeToImage();
  }

  @override
  void didUpdateWidget(BookWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _coverAspect = null;
      _imageFailed = false;
      _sampledCover = null;
      _subscribeToImage();
    }
  }

  /// Resolves the cover to learn its intrinsic ratio, which decides the book's
  /// width. The same provider is handed to the [Image] below, so this shares the
  /// image cache rather than fetching twice.
  void _subscribeToImage() {
    if (widget.imageUrl.isEmpty) {
      _detachStream();
      return;
    }
    final provider = NetworkImage(widget.imageUrl);
    if (_provider == provider && _stream != null) return;

    _detachStream();
    _provider = provider;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        final aspect = info.image.width / info.image.height;
        if (!mounted) return;
        setState(() {
          _coverAspect = aspect;
          _imageFailed = false;
        });
        // Cloned because the stream owns `info.image` and may dispose it as soon
        // as this callback returns, while the sample is still awaiting.
        final retained = info.clone();
        _sampleCoverColor(retained.image).whenComplete(retained.dispose);
      },
      onError: (Object error, StackTrace? stack) {
        if (!mounted) return;
        setState(() => _imageFailed = true);
      },
    );
    stream.addListener(listener);
    _stream = stream;
    _streamListener = listener;
  }

  void _detachStream() {
    if (_stream != null && _streamListener != null) {
      _stream!.removeListener(_streamListener!);
    }
    _stream = null;
    _streamListener = null;
  }

  @override
  void dispose() {
    // A book scrolled off-screen mid-hold must not fire stage two after unmount.
    _holdTimer?.cancel();
    _stageTwoTimer?.cancel();
    _detachStream();
    _turn.dispose();
    _press.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  void _onTapDown(TapDownDetails _) {
    if (!widget.pressEffect) return;
    _stageTwoFired = false;
    _press.forward();

    _holdTimer = Timer(kBookHoldDelay, () {
      if (!mounted || _reduceMotion) return;
      _turn.forward();
    });

    if (widget.onLongPress != null) {
      _stageTwoTimer = Timer(kBookStageTwoDelay, () {
        if (!mounted) return;
        _stageTwoFired = true;
        _holdTimer?.cancel();
        _press.reverse();
        _turn.animateBack(
          0,
          duration: _kStageTwoReturnDuration,
          curve: Curves.easeOut,
        );
        widget.onLongPress!.call();
      });
    }
  }

  void _endHold() {
    _holdTimer?.cancel();
    _stageTwoTimer?.cancel();
    _press.reverse();
    if (_turn.value > 0) {
      _turn.animateBack(
        0,
        duration: kBookReleaseDuration,
        curve: Curves.easeOut,
      );
    }
  }

  void _onTap() {
    if (_stageTwoFired) {
      _stageTwoFired = false;
      return;
    }
    widget.onTap?.call();
  }

  Widget _cover(BookMetrics metrics) {
    if (_usesGeneratedCover) {
      return GeneratedCover(
        isbn: widget.isbn,
        title: widget.title,
        width: metrics.width,
      );
    }
    return Image(
      image: _provider!,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => GeneratedCover(
        isbn: widget.isbn,
        title: widget.title,
        width: metrics.width,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseHeight =
        widget.height ?? MediaQuery.of(context).size.height * 0.15;
    final metrics = BookMetrics.from(
      baseHeight: baseHeight,
      // 2/3 until the real ratio is known, so the book never jumps size
      // mid-load.
      coverAspect: _coverAspect ?? kDefaultCoverAspect,
      // An override wins over both the hash and `jitter: false`, because a caller
      // that resolved the size itself is the only one that can know it.
      jitter:
          widget.jitterOverride ??
          (widget.jitter
              ? BookJitter.fromIsbn(widget.isbn, pageCount: widget.pageCount)
              : BookJitter.neutral),
    );

    // An externally driven turn replaces the internal one outright, so the two
    // never contribute to the same angle. A *pose* is different: it is added to
    // the hold rather than replacing it. See [BookWidget.turnRadians].
    final hold = widget.turnDrive ?? _turn;
    final pose = widget.turnRadians;

    Widget child = RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([hold, _press, pose]),
        builder: (context, _) => BookChassis(
          metrics: metrics,
          turn: (pose?.value ?? 0) + hold.value * kBookTurnAngle,
          press: _press.value,
          boardColor: _boardColor,
          cover: _cover(metrics),
          spine: widget.spine,
          pivot: widget.pivot,
        ),
      ),
    );

    // Callbacks are wired unconditionally and gate on `pressEffect` internally.
    // Conditioning them here changed the recogniser set mid-gesture, because the
    // long press that enters edit mode flips `pressEffect` to false while the
    // finger is still down: the in-flight tap was dropped, the page-level
    // "tap anywhere to leave edit mode" handler claimed it on release, and edit
    // mode ended the instant you let go of the book that started it.
    child = GestureDetector(
      onTap: _onTap,
      onTapDown: _onTapDown,
      onTapUp: (_) => _endHold(),
      onTapCancel: _endHold,
      child: child,
    );

    if (widget.heroTag != null) {
      child = Hero(
        tag: widget.heroTag!,
        createRectTween: _heroRectTween,
        flightShuttleBuilder: _heroFlightShuttle,
        child: child,
      );
    }
    return child;
  }
}

/// Interpolates the flight rect's *centre* along the Material arc and its size
/// linearly.
///
/// [MaterialApp] installs [MaterialRectArcTween] as the default, which arcs the
/// rect's top-left and bottom-right corners along two *separate* circles. That
/// does not preserve an aspect ratio even when both ends share one: flying a 61×92
/// shelf book to the 122×183 details header, the rect bulges through 107×114 —
/// 0.94 where both endpoints are 0.667. The cover is [BoxFit.cover] inside a
/// [ClipRRect] pinned to that box, so a third of the artwork's height is cropped
/// away and slides back in as the flight lands.
///
/// A book's two rects always share an aspect ratio — same cover, same jitter, only
/// the base height differs — so lerping width and height directly holds it fixed
/// for the whole flight while keeping the curved path Material asks for.
RectTween _heroRectTween(Rect? begin, Rect? end) =>
    MaterialRectCenterArcTween(begin: begin, end: end);

/// Renders the flying book at its own size and *scales* it, rather than letting
/// the flight's constraints squeeze it.
///
/// [BookChassis] composes three faces from absolute pixel values — the binding
/// band at 8.2% of the cover width, the corner radii, the perspective distance,
/// the page block's translations. None of those are derived from the incoming
/// constraints, so handed the flight rect directly the chassis keeps its
/// destination-sized numbers while the box shrinks around it: the enclosing
/// [Stack] passes loose constraints, each face is clamped per axis, and the page
/// block ends up translated to where the fore-edge of a *full-size* book would be
/// — outside a cover half that wide.
///
/// [FittedBox] lays the subtree out unconstrained, so it builds at its natural
/// metrics, and scales the finished composition into the flight rect. Every
/// proportion then holds at every point of the flight. Paired with
/// [_heroRectTween] the fit is exact, so `contain` never letterboxes.
Widget _heroFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  // The destination's subtree, matching Flutter's default shuttle. It is the end
  // of the flight that has to be seamless: there the shuttle is at scale 1 and is
  // swapped for this very widget.
  final hero = toHeroContext.widget as Hero;
  return FittedBox(child: hero.child);
}

/// Height a shelf row must reserve for a book of [baseHeight].
///
/// Jitter can make a book up to [BookJitter.maxHeightFactor] of its base, so a
/// row sized to `baseHeight` clips every book that hashes tall.
double bookRowExtent(double baseHeight) =>
    baseHeight * BookJitter.maxHeightFactor;
