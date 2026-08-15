import 'dart:async';

import 'package:flutter/material.dart';

import 'package:bookworm_friends/ui/widgets/book/book_chassis.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
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

const Duration _kTurnDuration = Duration(milliseconds: 260);
const Duration _kReleaseDuration = Duration(milliseconds: 180);
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

  const BookWidget({
    super.key,
    this.height,
    required this.imageUrl,
    required this.isbn,
    required this.title,
    this.onTap,
    this.onLongPress,
    this.heroTag,
    this.pressEffect = true,
  });

  @override
  State<BookWidget> createState() => _BookWidgetState();
}

class _BookWidgetState extends State<BookWidget> with TickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: _kTurnDuration,
  );
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: _kPressDuration,
  );

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
      _turn.animateBack(0, duration: _kReleaseDuration, curve: Curves.easeOut);
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
    if (widget.imageUrl.isEmpty || _imageFailed || _provider == null) {
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
      jitter: BookJitter.fromIsbn(widget.isbn),
    );

    Widget child = RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_turn, _press]),
        builder: (context, _) => BookChassis(
          metrics: metrics,
          turn: _turn.value * kBookTurnAngle,
          press: _press.value,
          cover: _cover(metrics),
        ),
      ),
    );

    child = GestureDetector(
      onTap: _onTap,
      onTapDown: widget.pressEffect ? _onTapDown : null,
      onTapUp: widget.pressEffect ? (_) => _endHold() : null,
      onTapCancel: widget.pressEffect ? _endHold : null,
      child: child,
    );

    if (widget.heroTag != null) {
      child = Hero(tag: widget.heroTag!, child: child);
    }
    return child;
  }
}

/// Height a shelf row must reserve for a book of [baseHeight].
///
/// Jitter can make a book up to [BookJitter.maxHeightFactor] of its base, so a
/// row sized to `baseHeight` clips every book that hashes tall.
double bookRowExtent(double baseHeight) =>
    baseHeight * BookJitter.maxHeightFactor;
