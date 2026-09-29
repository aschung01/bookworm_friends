import 'dart:ui' show ImageFilter;

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_bookmark.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';

/// How many stops the track has, so that its origin is **a stop rather than an
/// epsilon**.
///
/// The drag quantises to whole percents, which is what makes "leftmost" a place a
/// finger can actually land: with a continuous mapping the only way to reach the
/// origin would be to hit `0.0` exactly, and the smallest reachable non-null value
/// would be an arbitrarily small fraction that nothing can display. 101 stops is also
/// what `showSelectPercentBottomSheet` offers, so a position set here round-trips
/// through the wheel unchanged — a track that wrote `0.4632` would be *shown* as 46%
/// by every read-out in the app and saved as something else, which is the exact defect
/// `select_percent_bottom_sheet.dart` snaps its initial value to avoid.
const int _kStops = 100;

/// How far one assistive step moves, in stops.
///
/// Coarser than the drag's 1% on purpose: 100 swipes to cross a control is not an
/// accessible control, and the reader who needs an exact value has the percent wheel,
/// which is reachable by the read-out's own numeral and is a keypad rather than a
/// gesture. 20 steps end to end.
const int _kAssistStep = 5;

/// The ribbon's size on the track, as a fraction of the asset's own.
///
/// Solved backwards from the 48pt budget rather than chosen: the thumb row is the
/// *visible* ribbon, so `(38 − 8) × 0.8 + 8 + 16 = 48.0` exactly. See
/// [ReadingTrack.height].
const double _kThumbScale = 0.8;

/// The thumb row — the ribbon a reader can see, 24pt, and **not the asset's 38pt box**.
///
/// Sizing the row to the box was the first cut and it read wrong on sight: the ribbon
/// then hung from the row's top edge with the groove centred 3.2pt below its middle, so
/// the mark floated *above* the track with its tip just reaching it instead of passing
/// through it. The row is the drawing, and the asset's bleed hangs out of the bottom of
/// it into [_kEndGap], where nothing is drawn anyway.
const double _kThumbRowHeight =
    (kReadingBookmarkHeight - _kRibbonBottomBleed) * _kThumbScale;

/// Gap between the groove and the end labels.
///
/// 8, and it is real air rather than a remainder: it is also where the thumb's own
/// bottom bleed (6.4pt of empty asset box) and the tail of its shadow land, which is why
/// the [Stack] below does not clip.
const double _kEndGap = 8;

/// One line of [AppTextStyles.label], **as laid out rather than as multiplied**.
///
/// 13pt at `height: 1.2` with `leadingDistribution: even` is 15.6, and the engine
/// reports 16: a line box is rounded up to a whole pixel. [ReadingTrack.height] is a
/// promise about a rendered layout, so it is built from the measured figure, and
/// `reading_track_test.dart` holds it to the rendered height rather than to the
/// arithmetic — which is what would catch an engine that stopped rounding.
const double _kEndLabelLine = 16;

/// The groove.
///
/// 10pt on a 24pt visible ribbon, which is the mockup's 14-on-34 ratio at this scale.
/// Thin enough that the ribbon reads as the object and the bar as the space it moves
/// through; thick enough to hold a fill that means something. Centred in the thumb row,
/// so the ribbon crosses it with 7pt to spare above and below — the mockup's own
/// symmetry, and what makes the mark read as passing *through* the groove.
const double _kBarHeight = 10;

/// The empty box around the visible ribbon, mirrored from the private constants in
/// `reading_bookmark.dart`.
///
/// **Mirrored rather than imported, because they are private there, and this file may
/// not widen them** — its scope is the control. Two guards instead. The ribbon's own
/// width and height are *derived* from the published [kReadingBookmarkWidth] and
/// [kReadingBookmarkHeight] by taking the bleed off, so they are not a fourth
/// restatement of `13.5 x 30` but a consequence of the two numbers the asset already
/// publishes; and `reading_track_test.dart` asserts the results are the 13.5 and the 30
/// that file's doc describes, so a changed viewBox fails here rather than silently
/// moving the thumb. Promoting all three in `reading_bookmark.dart` is the right change
/// the moment a third caller needs them — the home-screen widget already restates them
/// in Swift.
const double _kRibbonLeftBleed = 4;
const double _kRibbonRightBleed = 4.5;
const double _kRibbonBottomBleed = 8;

/// The visible ribbon at [_kThumbScale] — 10.8pt, and the width the travel is short by.
const double _kThumbWidth =
    (kReadingBookmarkWidth - _kRibbonLeftBleed - _kRibbonRightBleed) *
    _kThumbScale;

/// How long the thumb takes to glide to a value it did **not** get by being dragged.
const Duration _kGlide = Duration(milliseconds: 260);

/// The overshoot, and the one thing reduced motion removes.
///
/// A bookmark being placed is a small physical act, so the thumb arrives slightly past
/// the stop and settles back. Clamped to the track at paint time, so the overshoot is
/// visible in the middle of the range and simply absent at either end — which is
/// correct, since a bookmark cannot be further in than the last page.
const Curve _kGlideCurve = Curves.easeOutBack;

/// How much the thumb grows while a finger is on it.
///
/// **The only confirmation that the drag was recognised**, and it has to exist because
/// this control refuses the feedback every other control gets: a tap does nothing, so
/// without a state change at the moment the recognizer wins, a reader whose finger has
/// not yet travelled `kTouchSlop` gets no answer about whether the control is live.
/// Scaled about the box's centre, which is 0.25pt right of and 4pt above the *ribbon's*
/// centre — so the mark shifts 0.03pt sideways and 0.5pt down at full grow. Measured,
/// and below the threshold of anything.
const double _kDragGrow = 1.12;

/// One glassy, drag-only track spanning the whole book, from _Not started_ to
/// _Finished_, with the app's bookmark ribbon as its thumb.
///
/// **The status word is read off this control rather than picked beside it.** Position
/// and status were two controls for one fact — `null` is "never asked", `0 ≤ p < 1` is
/// Reading, `p == 1` is Finished — which is why every arrangement of a segmented picker
/// next to a percent field felt like a compromise. So the ends carry the *same
/// localised strings* the read-out above prints ([AppLocalizations.statusInterested]
/// and [AppLocalizations.statusFinished]), not `0%` and `100%`. That is not a copy
/// preference: sharing the strings is what makes it impossible for the track's ends and
/// the word above them to disagree.
///
/// **A tap does nothing. Only a deliberate horizontal drag moves the thumb, and this is
/// the load-bearing rule in the file.** The same control was drawn once before, as
/// `band-scrubber` in `docs/mockups/streaks/index.html`, and **rejected** — three times
/// on the record — because _"a stray touch could silently rewrite your position"_ and
/// for _"being able to rewrite a position irrecoverably"_. The house-approved answer
/// there was *arming*: tap to arm, then drag, with a Cancel. An inert tap reaches the
/// same safety one tap cheaper — nothing needs arming because a tap was never live, and
/// dismissing the sheet discards, so this control owes no Cancel of its own. Do not add
/// `onTapDown`/`onTapUp` "for convenience", and do not add the arming step back: either
/// one re-opens the rejection. **Making the tap inert took more than leaving the handler
/// out** — see `_onDragStart` for the arena rule that had it firing anyway.
///
/// A **vertical** drag is likewise not ours. The sheet this lives in may scroll, and a
/// control that swallowed a vertical pan would trap the sheet's own gesture.
///
/// **The origin reports `null`, not `0`.** `null` means "never asked" and `0` means
/// "opened it and got nowhere" — two states the model keeps apart deliberately, with
/// `kProgressPageFloor` and the deleted progress field's own doc enforcing it. So
/// the leftmost stop is what makes Reading → Not started reachable, and `0%` is
/// deliberately *unreachable* from here, staying reachable through the percent wheel's
/// own `0` stop. Hence [ValueChanged] of a nullable double: the state is in the type
/// rather than in a sentinel.
///
/// **Controlled, exactly like [Slider].** [progress] is the truth and [onChanged] is a
/// request; the thumb follows this widget's own field, so a parent that swallows the
/// callback gets a thumb that does not move. That is deliberate for a pure presentation
/// widget — the alternative, a shadow copy held here, is a second value that can
/// disagree with the one that gets saved.
///
/// **48pt including the end labels**, against 256 for a wheel and its rider. That
/// figure is what makes the merged sheet shorter than either sheet it replaces, so
/// anything added here has to come out of something.
///
/// Rejected: **−/+ steppers** beside the bar, drawn to cover what a drag cannot reach
/// (roughly 2.6 pages per point on a 912-page book over a 353pt track). They make the
/// sheet a form again, which is the complaint that killed the three-control stack in
/// `streaks/index.html` — _"too many ways to say the same thing"_. Exactness is the
/// read-out's numerals, not this control's.
///
/// Rejected: a **relative** drag, where the gesture moves the thumb by its own delta
/// instead of putting it under the finger. It avoids the small jump when a drag starts
/// away from the thumb, and it costs the whole point of having no steppers: the far end
/// stops being reachable in one gesture. The jump is bounded by how deliberate the
/// gesture already is — nothing moves until the finger has travelled `kTouchSlop`
/// horizontally, so the thumb arrives under a finger that is already on its way.
class ReadingTrack extends StatefulWidget {
  const ReadingTrack({
    super.key,
    required this.progress,
    required this.onChanged,
    this.semanticsLabel,
  });

  /// The stored fraction 0..1, or null for a book nobody has answered for.
  ///
  /// Not snapped on the way in: a row holding `0.463` draws its thumb at 46.3% and
  /// keeps that value until a drag replaces it. Snapping here would rewrite a stored
  /// position for the crime of being looked at.
  final double? progress;

  /// Called with each stop a drag or an assistive step lands on, and **never twice with
  /// the same value in a row** — a drag that does not reach `kTouchSlop` reports nothing
  /// at all, and one that wanders back over a stop it has already passed reports each
  /// change rather than each move. What that buys the sheet is that a report is always a
  /// real change of position, which is what its Save can be keyed on.
  final ValueChanged<double?> onChanged;

  /// Names the slider for assistive technology. The parent's to supply, because a
  /// pure presentation widget reads no `l10n` beyond its two end labels.
  final String? semanticsLabel;

  /// 48pt — the whole control, end labels included.
  ///
  /// Published because the sheet's height budget is the reason the merge is a
  /// simplification, and a caller doing that arithmetic should not have to re-derive
  /// this. Measured at text scale 1; the labels are free to grow past it, which is
  /// why nothing here is a fixed-height box.
  static const double height = _kThumbRowHeight + _kEndGap + _kEndLabelLine;

  @override
  State<ReadingTrack> createState() => _ReadingTrackState();
}

class _ReadingTrackState extends State<ReadingTrack>
    with SingleTickerProviderStateMixin {
  /// Built in [initState] rather than `late final`, because a lazy field is built the
  /// first time it is *read* and [dispose] is a read: a track that never glided created
  /// its controller while its element was already deactivated, which throws
  /// "Looking up a deactivated widget's ancestor is unsafe" out of
  /// `SingleTickerProviderStateMixin.createTicker`. It failed only in the cases where
  /// nothing had animated, which is most of them.
  late final AnimationController _glide;

  /// The fraction actually drawn, which is [ReadingTrack.progress] except while it is
  /// gliding to a value that arrived from somewhere else — the percent wheel, or the
  /// parent resetting the sheet.
  late Animation<double> _shown;

  /// Where the finger went down, local to the thumb row, for as long as a pointer is
  /// held. See [_onDragUpdate] for why this file measures its own slop.
  double? _downDx;

  /// The value last handed to [ReadingTrack.onChanged] which the parent has not echoed
  /// back yet, and whether there is one.
  ///
  /// **Not a shadow of the position** — [ReadingTrack.progress] stays the only thing
  /// drawn. This is only what [_report] compares against, and it exists because a frame
  /// can carry more than one pointer move: touch sampling runs ahead of the display, so
  /// two updates arrive, the parent's rebuild lands after both, and the second one is
  /// then measured against a [ReadingTrack.progress] that is one move stale. Comparing
  /// against `widget.progress` alone silently dropped any second move in a frame that
  /// happened to land back on the stop the parent still thinks it is at.
  double? _pendingValue;
  bool _pending = false;

  /// Whether that pointer has earned the right to move the thumb.
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _glide = AnimationController(vsync: this, duration: _kGlide);
    _shown = AlwaysStoppedAnimation(_fractionOf(widget.progress));
  }

  @override
  void dispose() {
    _glide.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ReadingTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent has spoken, so whatever we last asked for is no longer the better
    // guess at what it holds. See [_pendingValue].
    _pending = false;
    final to = _fractionOf(widget.progress);
    if (to == _shown.value && !_glide.isAnimating) return;

    // **No glide under a finger, and none under reduced motion.** The first is not a
    // preference: the value arriving *is* the drag, so animating towards it would put
    // the thumb a fixed lag behind the finger for the whole gesture. The second
    // follows `StreakFlame`, which forces its liveness to zero on the same flag
    // rather than shortening anything — a spring is the thing the flag is about.
    if (_dragging || MediaQuery.disableAnimationsOf(context)) {
      _glide.stop();
      _shown = AlwaysStoppedAnimation(to);
      return;
    }

    _shown = _glide.drive(
      Tween<double>(
        begin: _shown.value,
        end: to,
      ).chain(CurveTween(curve: _kGlideCurve)),
    );
    _glide.forward(from: 0);
  }

  /// Where the thumb sits for a value, as 0..1 of the travel. Null is the origin,
  /// which is the *same place* as `0` and a different report — see the class doc.
  static double _fractionOf(double? progress) =>
      progress == null ? 0 : progress.clamp(0.0, 1.0);

  /// The stop a fraction belongs to, and the value that stop reports.
  static double? _valueOfStop(int stop) =>
      stop <= 0 ? null : stop.clamp(0, _kStops) / _kStops;

  int get _currentStop => (_fractionOf(widget.progress) * _kStops).round();

  /// Hands a new stop up, unless it is the one already shown — or the one already asked
  /// for and not yet echoed. See [_pendingValue].
  void _report(int stop) {
    final next = _valueOfStop(stop);
    if (next == (_pending ? _pendingValue : widget.progress)) return;
    _pendingValue = next;
    _pending = true;
    widget.onChanged(next);
  }

  /// Maps a finger to a stop. [dx] is local to the thumb row, so the mapping is the
  /// inverse of the one the thumb is painted with — both measured to the *visible*
  /// ribbon, which is what cancels the asset's bleed out of the travel rather than
  /// shifting one end of it. Same reasoning as `readingBookmarkInsetFor`, which cannot
  /// be reused directly: its track is a cover, with a gutter at one end and the shelf's
  /// pin at the other.
  void _reportPosition(double dx, double width) {
    final travel = width - _kThumbWidth;
    if (travel <= 0) return;
    final raw = (dx - _kThumbWidth / 2) / travel;
    _report((raw.clamp(0.0, 1.0) * _kStops).round());
  }

  /// **Nothing is reported here, and that is what makes the tap inert.**
  ///
  /// The obvious reading of "use a horizontal drag recognizer and no tap recognizer" is
  /// that a tap then reaches nothing. It does not, and the reason is worth keeping:
  /// `GestureArenaManager.close` resolves an arena **by default** when it holds exactly
  /// one member, in a microtask straight after the pointer goes down. So a lone
  /// [HorizontalDragGestureRecognizer] wins before the finger has moved at all, and
  /// `onHorizontalDragStart` fires for a plain tap — which is how the first cut of this
  /// file rewrote a position from a tap at 80% of the width, the exact defect the
  /// `band-scrubber` rejection was about, in code that looked like it could not.
  ///
  /// The same default win is why a **vertical** pan reaches here too: the recognizer is
  /// accepted, so it is handed every move, and it reports them with `dx` alone — a
  /// stream of updates at the position the finger went down.
  ///
  /// Hence [_downDx] and the slop in [_onDragUpdate], which is this file re-measuring
  /// what the recognizer's own `kTouchSlop` would have measured had it been allowed to.
  /// Rejected alternative: a no-op [TapGestureRecognizer] alongside, so the arena has
  /// two members and the drag has to earn its win. It fixes the tap and not the vertical
  /// pan — the tap recognizer rejects itself once the pointer leaves its own tolerance,
  /// which leaves the drag alone in the arena and default-resolved again — and it puts a
  /// live-looking `onTap` in a file whose whole point is that there is not one.
  void _onDragStart(DragStartDetails details) =>
      _downDx = details.localPosition.dx;

  void _onDragUpdate(DragUpdateDetails details, double width) {
    final down = _downDx;
    if (down == null) return;
    if (!_dragging) {
      if ((details.localPosition.dx - down).abs() < kTouchSlop) return;
      // The thumb grows at the same instant it starts moving, so the grow is the
      // answer to "is this control live" rather than a decoration on a state the
      // reader cannot otherwise see.
      setState(() => _dragging = true);
    }
    _reportPosition(details.localPosition.dx, width);
  }

  void _onDragDone() {
    _downDx = null;
    if (!_dragging) return;
    setState(() => _dragging = false);
  }

  /// One assistive step. **The assistive path is allowed to do what the touch path
  /// refuses**, and the inconsistency is the design rather than an oversight: what was
  /// rejected is a *stray* touch rewriting a position, and an explicit increment
  /// gesture aimed at a focused slider is not stray. Nobody should "fix" this into
  /// symmetry — the symmetric versions are either a live tap (rejected) or a slider
  /// with no adjustable actions (unusable under VoiceOver).
  void _step(int steps) =>
      _report((_currentStop + steps * _kAssistStep).clamp(0, _kStops));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final atOrigin = _currentStop <= 0;
    final atEnd = _currentStop >= _kStops;
    // **Not `atOrigin`, and the difference is the whole `null` vs `0` rule.** `0%` puts
    // the thumb on the origin without *being* the origin's state, so a reader who set
    // `0%` from the percent wheel still has one step left to take — down to Not started.
    // Gating this on position rather than on state left that step reachable by drag and
    // not by VoiceOver, which is the asymmetry this file exists to avoid.
    final canDecrease = widget.progress != null;

    final labelStyle = AppTextStyles.label.copyWith(
      color: atOrigin ? colors.brandText : colors.secondaryText,
    );
    final endStyle = AppTextStyles.label.copyWith(
      color: atEnd ? colors.brandText : colors.secondaryText,
    );

    return Semantics(
      container: true,
      slider: true,
      label: widget.semanticsLabel,
      value: _spoken(l10n, widget.progress),
      increasedValue: atEnd
          ? null
          : _spoken(l10n, _valueOfStop(_currentStop + _kAssistStep)),
      decreasedValue: canDecrease
          ? _spoken(l10n, _valueOfStop(_currentStop - _kAssistStep))
          : null,
      // Null at the ends rather than a no-op, so the announcement is honest about
      // there being nowhere further to go.
      onIncrease: atEnd ? null : () => _step(1),
      onDecrease: canDecrease ? () => _step(-1) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        // **Stretch, not the default centre.** A `Column` centres its children, so a
        // groove given only a height collapses to zero width — the defect the
        // celebration's progress bar shipped with, where a `FractionallySizedBox`
        // inside a width-less box sized the track to its own fill and drew as a short
        // floating dash. Nothing here takes a fraction of space it was not given.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _kThumbRowHeight,
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  _buildRow(context, constraints.maxWidth),
            ),
          ),
          const SizedBox(height: _kEndGap),
          // **Excluded, because the slider's own value already says these words.**
          // That is the whole reason the ends borrow the status strings: at the origin
          // the value *is* "Not started", at the far end it *is* "Finished". Left in,
          // VoiceOver would offer two unfocusable labels either side of a slider that
          // announces one of them.
          ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Flexible with two lines allowed: the row degrades by wrapping and
                // only then by ellipsising, never by overflowing. `Not started` at 2x
                // text scale is 150pt of a 187pt share on a 375pt phone, so English
                // does not reach it — Korean and 3x are what this is for.
                Flexible(
                  child: Text(
                    l10n.statusInterested,
                    style: labelStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Flexible(
                  child: Text(
                    l10n.statusFinished,
                    style: endStyle,
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// What assistive technology reads out.
  ///
  /// The ends speak their own words, which keeps this widget's `l10n` surface to the
  /// two strings the ends already need; everything between is a numeral and a percent
  /// sign, which sit the same way round in both supported locales — the same rule
  /// the deleted progress field stated for its own value.
  String _spoken(AppLocalizations l10n, double? progress) {
    if (progress == null) return l10n.statusInterested;
    if (progress >= 1) return l10n.statusFinished;
    return '${(progress * 100).round()}%';
  }

  Widget _buildRow(BuildContext context, double width) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return GestureDetector(
      // Opaque so a touch anywhere in the 30pt band starts a drag, and so a tap that
      // lands here stops here — an inert tap must not fall through to whatever the
      // sheet has behind the control.
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: (details) => _onDragUpdate(details, width),
      onHorizontalDragEnd: (_) => _onDragDone(),
      onHorizontalDragCancel: _onDragDone,
      child: AnimatedBuilder(
        animation: _shown,
        builder: (context, _) {
          // Clamped because `easeOutBack` leaves the range on purpose. See
          // [_kGlideCurve].
          final shown = _shown.value.clamp(0.0, 1.0);
          final travel = width - _kThumbWidth;
          final thumbCentre = travel * shown + _kThumbWidth / 2;
          return Stack(
            // The asset is 4.5pt of empty box wider than its ribbon and 8pt taller, so
            // the thumb's own box leaves the row on three sides with nothing drawn in
            // it. Clipping would cost only the soft tail of the ribbon's shadow, and a
            // shadow that stops at a straight edge is worse than one that spills.
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: (_kThumbRowHeight - _kBarHeight) / 2,
                height: _kBarHeight,
                // **No fill at all for a null position**, which is what the record
                // settled: an empty groove with the thumb at the origin is both where
                // the drag starts and what "not started" looks like. The dashed
                // treatment an earlier drawing gave it is explicitly what had to go.
                child: _Groove(
                  fillWidth: widget.progress == null ? 0 : thumbCentre,
                ),
              ),
              Positioned(
                // Measured to the visible ribbon, then backed off by the bleed down
                // its left-hand side, so `shown == 0` puts the ribbon's own left edge
                // exactly on the groove's.
                left: travel * shown - _kRibbonLeftBleed * _kThumbScale,
                // Top, not centre: the row *is* the visible ribbon, so the mark fills it
                // exactly and the groove — centred in the same row — is crossed with 7pt
                // of ribbon either side of it. The asset's 6.4pt of bottom bleed hangs
                // into [_kEndGap] below, where nothing else is drawn.
                top: 0,
                child: AnimatedScale(
                  scale: _dragging ? _kDragGrow : 1,
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 120),
                  child: const ReadingBookmark(scale: _kThumbScale),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The groove, and the fill inside it.
///
/// **The app's existing glass, not a third idiom**: `LiquidGlassContainer` on iOS 26
/// and a `BackdropFilter` everywhere else, which is the pair `shelf_picker_popover.dart`
/// already uses, with the division of labour the house keeps — *Flutter draws every
/// pixel of content, the platform supplies the material behind it*. So the fill and the
/// lit edge are Flutter's, drawn as the glass container's child, and nothing about the
/// value is handed to the platform.
///
/// **The fallback is the path that matters most here**, because `useNativeGlass` is
/// false under `flutter test` (which reports Android) and on every phone below iOS 26.
/// It is a blur and not glass — no rim highlight, no specular edge, which is most of
/// what the real material is — so the recess is drawn instead: a [AppColors.surfaceVariant]
/// ground at 60%, the hairline `shelf_picker_popover.dart` uses at these two alphas, and
/// a lit top edge. `surfaceVariant` rather than a translucent white because it is the
/// token for a recessed field in *both* themes (the deleted progress field sat on it); white at
/// 50% is the mockup's value and reads as a groove only on a light sheet.
///
/// [LiquidGlassContainer.autoHideOnModal] is left at its default true, unlike the shelf
/// popover, which turns it off because it *is* the topmost modal. This control is not:
/// the read-out above it opens the percent wheel over the top, and a platform view left
/// live under that sheet is the composited-rectangle bleed the flag exists to stop.
class _Groove extends StatelessWidget {
  const _Groove({required this.fillWidth});

  /// In points, resolved by the caller from the width it measured — never a fraction
  /// of whatever this widget happens to be given. See the `CrossAxisAlignment.stretch`
  /// note in [ReadingTrack.build] for the bar that shipped without a track by doing
  /// the opposite.
  final double fillWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        if (fillWidth > 0)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: fillWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                // **Lit from above, like the material it sits in.**
                // [AppColors.brand] to [AppColors.brandFill] — the vivid green is
                // decoration-only by its own doc and this is decoration, while the
                // dark stop is what keeps a white ribbon legible against the bottom
                // two thirds of the fill. A flat `brandFill` was the first version
                // and read as a painted bar inside a glass groove.
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [colors.brand, colors.brandFill],
                ),
              ),
            ),
          ),
        // One highlight over both the groove and the fill, rather than one each:
        // Flutter has no inset shadow, so the lit top edge is a hairline drawn inside
        // the clip — and a single line across the whole bar is also the physical
        // reading, since one light source lights one surface.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 0.75,
          child: ColoredBox(
            color: Colors.white.withValues(alpha: isDark ? 0.16 : 0.9),
          ),
        ),
      ],
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(_kBarHeight / 2),
      child: useNativeGlass
          ? LiquidGlassContainer(
              config: const LiquidGlassConfig(
                effect: CNGlassEffect.regular,
                // A 10pt bar's capsule is its own radius, so the shape needs no
                // `cornerRadius` and cannot drift from the `ClipRRect` above.
                shape: CNGlassEffectShape.capsule,
                // Not interactive: the glass is material, not a control. The drag
                // recognizer above owns every touch, and a platform view that
                // responded to one would be a second opinion about it.
                interactive: false,
              ),
              child: content,
            )
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceVariant.withValues(alpha: 0.6),
                  border: Border.all(
                    color: colors.primaryText.withValues(
                      alpha: isDark ? 0.14 : 0.1,
                    ),
                    width: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(_kBarHeight / 2),
                ),
                child: content,
              ),
            ),
    );
  }
}
