import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;

/// Where the flame graphic lives.
///
/// Built from `rive/streak_flame/scene.rml` by `rive/streak_flame/build.sh`; both the text
/// and the binary are committed, because `flutter build` cannot run the Rive CLI.
/// `docs/streak-flame-rive.md` is the build sheet.
const String kStreakFlameAsset = 'assets/rive/streak_flame.riv';

/// The one-shot the artboard must expose: a shut book opening and a flame rising out of it.
///
/// **Flutter seeks this rather than playing it, and that is the whole reason Rive is
/// acceptable here.** An autoplaying one-shot would move the timing into the editor, where
/// no `Interval` can be read, `MediaQuery.disableAnimationsOf` would need the artboard
/// seeked to its last frame by hand, and the nine beats of `streak_celebration.dart` could
/// drift out of step with the graphic. Seeking by [rive.Animation.time] instead means the
/// artboard is a *drawing that can be posed* and the sequence stays in Dart — greppable,
/// golden-testable, and gated exactly once.
///
/// **What changed is who owns the easing.** This used to be the name of a state machine
/// scrubbing a 1D blend of six single-frame poses through a bound view-model number, and
/// the consequence was that the file contained no timeline at all: nothing to play in the
/// editor, nothing to play in `rive .`, nothing to iterate against. Every review went
/// through a contact sheet, and a timing defect hid there for days — the driving curve
/// crossed the whole sequence in three frames and then held for 470ms, which no still image
/// can show. Now the shape of the motion is authored in the timeline, where it can be
/// watched, and Dart drives time *linearly* across it. The host still decides how far
/// through the sequence is; it no longer decides what the sequence looks like.
const String kStreakFlameIgniteAnimation = 'Ignite';

/// The looping timeline that keeps the flame alive once it has caught: it flickers and
/// throws embers.
///
/// **This reverses an explicit rule that used to live in `streak_celebration.dart`** —
/// "nothing moves after the last cell lands, and there is no idle loop". The cost that rule
/// was protecting against is real and is still real: a loop repaints for as long as the
/// screen is up, and `pumpAndSettle` never returns anywhere this path is live. It was
/// overruled deliberately, because a flame that freezes the instant it arrives reads as a
/// decal of a flame. Three things keep the cost bounded: the celebration is a transient
/// sheet with one way out rather than a screen left open, the mix is forced to zero under
/// reduced motion, and [StreakFlame] stops advancing it when nobody has asked for it.
const String kStreakFlameIdleAnimation = 'Idle';

/// Which renderer decodes and draws the artboard.
///
/// **`Factory.flutter`, and `Factory.rive` is not a tuning knob here — it crashes the
/// process.** The Rive Renderer wants a GPU context, and a headless `flutter test` shell has
/// none, so `File.asset` trips a native assertion (`Assertion failed: (factory)`, `file.cpp`
/// line 206) and the shell dies with SIGABRT. That is not catchable: the `catch` below never
/// runs, the whole test file reports `did not complete`, and every case in
/// `streak_celebration_test.dart` goes with it, because that screen pumps this widget. A
/// screen presented over the streak page may not carry a renderer that can abort the process.
///
/// The Flutter factory draws through Flutter's own canvas instead. For a drawing this size — a
/// few dozen paths, no meshes, no images, no scripts — the Rive Renderer buys nothing that
/// would pay for that failure mode.
///
/// `final` rather than `const`: `Factory.flutter` is a getter, not a constant.
final rive.Factory kStreakFlameFactory = rive.Factory.flutter;

/// Where [StreakFlame] looks for the artboard, when a test needs it to look somewhere else.
///
/// **This exists because which path the widget takes depends on the machine, and a test may
/// not.** `rive_native`'s dynamic library is downloaded into `build/`, which is gitignored, so
/// the artboard renders on a developer machine that has run `dart run rive_native:setup` and
/// falls back on one that has not — and the failure is *printed*, not thrown, so the suite
/// stays green either way. Several cases in `streak_celebration_test.dart` assert the
/// hand-built choreography — the glyph's colour as it catches, the spark painter, the gleam's
/// `ShaderMask` — and those widgets exist only on the fallback path. Pointing this at a name
/// that cannot resolve makes that path certain rather than probable.
///
/// Nothing in `lib/` writes it. The artboard path is covered by `streak_flame_test.dart`,
/// which asks the file itself whether it decodes and exposes the contract.
@visibleForTesting
String? debugStreakFlameAssetOverride;

/// The flame at the top of the celebration: the Rive book-and-flame if it decoded, and the
/// hand-built ignition if it did not.
///
/// **Rive draws the flame and nothing else.** The counter, the week row, the milestone bar
/// and every line of copy stay in Flutter, because they are localised strings and themed
/// colours — baking them into an artboard would put `l10n` and `AppColors` inside a binary
/// nobody can grep, which is the objection that kept Rive out of here in the first place. The
/// boundary is: Rive owns the *drawing*, Dart owns the *timing*, the *text* and the *theme*.
///
/// **It resolves the file itself instead of handing the asset name to `FileLoader`, and that
/// is not a preference.** `RiveWidgetBuilder` documents a `RiveFailed` state, but a missing
/// asset does not reach it: `FileLoader.file` throws `RiveFileLoaderException` out of
/// `initState`, which takes down the subtree and fails every widget test that pumps this
/// screen. Loading the bytes first and only mounting the painter once they decoded means an
/// absent or unreadable artboard is an ordinary `null`, not an exception.
class StreakFlame extends StatefulWidget {
  const StreakFlame({
    super.key,
    required this.progress,
    required this.liveness,
    required this.size,
    required this.fallback,
  });

  /// The square the celebration draws the artboard into.
  ///
  /// **Its own number, and not `_Ignition.stageSize`, which is what it used to be.** That
  /// constant is `flameSize * 2`, where `flameSize` is the point size of
  /// [kReadingStreakIcon] in the hand-built fallback — "twice the flame, so a spark can
  /// leave the glyph and still be drawn". Sizing the Rive artboard off the fallback's font
  /// metrics was never a decision; it was the artboard inheriting the only box that already
  /// existed. The two have no reason to agree, and holding them together is what made the
  /// flame un-growable.
  ///
  /// That mattered because a reader called the flame small and was right: measured off a
  /// render it was 134 of the artboard's 304 units, so 44% of the frame. The artboard's own
  /// frame was then grown to 480 to hold a flame three times as tall — and **on its own that
  /// reached the screen as nothing at all**, because [rive.Fit.contain] maps the artboard
  /// onto this box and only the flame's *fraction* of the artboard survives the mapping.
  /// Growing an artboard and growing a drawing inside it are opposite moves; the first is
  /// cancelled exactly by the fit.
  ///
  /// 252 is that arithmetic run backwards. On-screen flame height is `fraction × size`: it
  /// was 0.44 × 152 = 67px and is now 0.84 × 252 = 211px, which is the 3x that was asked
  /// for. The artboard-to-screen scale goes 152/304 = 0.500 to 252/480 = 0.525, so the
  /// *book* comes out a hair larger rather than smaller, and the page-edge hairlines stay
  /// above a pixel. That last point was raised as a risk and was wrong — the box grew by
  /// more than the artboard did (1.66x against 1.58x), so every detail in the drawing gained
  /// 5% instead of losing a third.
  ///
  /// **What this does cost is vertical room**, and the celebration is a column of fixed
  /// pieces between two `Spacer`s, which is the shape that overflows first. 100 extra points
  /// of flame comes out of that slack. `streak_celebration_test.dart` pins it at 375×667 as
  /// well as 393×852 for exactly this reason: before this change nothing in the suite set a
  /// surface short enough to fail.
  ///
  /// **This is now the box's *height*, and the width comes from [artboardAspect].** It was the
  /// side of a square while the artboard was one.
  static const double stageSize = 252;

  /// The artboard's own width over its height, so the box can match it.
  ///
  /// **The box has to carry the artboard's aspect or [rive.Fit.contain] letterboxes**, and a
  /// letterbox is not cosmetic here: `contain` takes `min(W / artboardW, H / artboardH)`, so a
  /// square box around a 6:5 artboard scales by the *width* ratio and the flame comes out a
  /// sixth smaller than the same box gives it today. The room the artboard just gained would be
  /// spent shrinking the drawing rather than on the spray it was gained for.
  ///
  /// **Why the artboard is 360 × 300 rather than square, which is the interesting part.** The
  /// burst spray is drawn behind the flame, so a bit only reads once it is clear of the
  /// silhouette — and at 300 square the field between the settled body (half-width 93) and the
  /// frame's edge (150) was 57 units, falling to 10 at the burst. Measured against the Duolingo
  /// still the brief came from, its particles reach about 2.0–2.5× their flame's half-width;
  /// ours reached 1.61×. 360 puts it at 1.94×.
  ///
  /// **And the growth is horizontal because that is the axis with slack.** On-screen flame
  /// height is `(flame ÷ artboard) × box`, so growing the artboard and the box together cancels
  /// exactly and the flame does not change size — 195px before and after. Doing it by shrinking
  /// the drawing inside a *square* artboard and raising [stageSize] to compensate reaches the
  /// same ratio, but grows the box in both directions: the 33%-of-frame share that would match
  /// the reference's crop needs a 475pt box, wider than the phone, and every point of height is
  /// taken from the slack described above. Widening costs nothing vertically. The celebration
  /// pads itself 28 points each side, so the box's width budget is 319 on a 375pt phone; this
  /// lands at 302 and leaves 17.
  ///
  /// Note the reference's crop includes part of a numeral below its flame, so it is a card
  /// region rather than a tight box, and "share of the frame" overstates what is wanted. Reach
  /// in flame half-widths is the comparable number, and it is the one above.
  static const double artboardAspect = 360 / 300;

  /// The width the box gets, given a height of [size].
  static double stageWidthFor(double height) => height * artboardAspect;

  /// 0 → 1 across the ignition window, driven by the celebration's own controller.
  ///
  /// **Linear.** The artboard's `Ignite` timeline carries its own easing — a hold on the shut
  /// book, a back-out on the covers, a settle on the flame — so a curve here would be applied
  /// on top of that one and would compress or stretch beats that were authored against real
  /// time. The caller's job is to say *how far through*, at a steady rate.
  final Animation<double> progress;

  /// 0 → 1 as the ignition lands: how much of the idle loop to mix in.
  ///
  /// At 0 the loop is not advanced at all and the artboard stops repainting, which is what
  /// makes the resting state actually rest. Ramping rather than switching avoids a step in
  /// the flame's scale at the handoff, because the loop's own values sit a few percent either
  /// side of the pose the ignition ends on.
  final Animation<double> liveness;

  /// The height of the box the artboard is drawn into; the width follows [artboardAspect].
  final double size;

  /// What to draw when there is no artboard to draw.
  final WidgetBuilder fallback;

  @override
  State<StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<StreakFlame> {
  /// Null while resolving, and null forever if there is nothing to resolve.
  rive.File? _file;
  rive.Artboard? _artboard;
  final _FlamePainter _painter = _FlamePainter();
  bool _settled = false;

  /// Whether the reader has asked the system to stop animating. Read in
  /// [didChangeDependencies] rather than `build` so that [_push] — which runs from an
  /// animation listener, outside a build — can see it.
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _resolve();
    widget.progress.addListener(_push);
    widget.liveness.addListener(_push);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _push();
  }

  @override
  void didUpdateWidget(StreakFlame old) {
    super.didUpdateWidget(old);
    if (old.progress != widget.progress) {
      old.progress.removeListener(_push);
      widget.progress.addListener(_push);
    }
    if (old.liveness != widget.liveness) {
      old.liveness.removeListener(_push);
      widget.liveness.addListener(_push);
    }
    _push();
  }

  Future<void> _resolve() async {
    rive.File? file;
    try {
      file = await rive.File.asset(
        debugStreakFlameAssetOverride ?? kStreakFlameAsset,
        riveFactory: kStreakFlameFactory,
      );
    } catch (_) {
      // Absent, truncated, or authored against a newer format than this runtime reads. All
      // three mean the same thing to this screen: draw the fallback. `File.asset` is
      // nullable *and* throws, so this needs both the catch and the null check below.
      file = null;
    }
    final artboard = file?.defaultArtboard();
    if (!mounted || artboard == null) {
      artboard?.dispose();
      file?.dispose();
      if (mounted) setState(() => _settled = true);
      return;
    }
    setState(() {
      _file = file;
      _artboard = artboard;
      _settled = true;
    });
    _push();
  }

  /// **Reduced motion forces [_FlamePainter.liveness] to zero rather than to whatever the
  /// beat says.** Every other beat on this screen is built so that its t=1 state is the
  /// resting one, and the celebration honours the gate by jumping its controller to 1 — which
  /// would leave `liveness` at 1 and hand a reader who asked for stillness a flame that
  /// flickers forever. This is the one beat whose finished state is *motion*, so it has to be
  /// gated here as well.
  void _push() {
    _painter.progress = widget.progress.value;
    _painter.liveness = _reducedMotion ? 0 : widget.liveness.value;
  }

  @override
  void dispose() {
    widget.progress.removeListener(_push);
    widget.liveness.removeListener(_push);
    _painter.dispose();
    _artboard?.dispose();
    _file?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final artboard = _artboard;
    // **The fallback is what shows while resolving, not a spinner and not a gap.** Reading an
    // asset takes a frame or two, and this is the first beat of a 1.5s sequence: a hole where
    // the flame belongs would be more visible than the swap.
    //
    // **It is boxed to [size] rather than returned bare, and that is a layout invariant
    // rather than tidiness.** Returned bare, this widget's height was whatever the fallback
    // happened to be — `_Ignition`'s 152 — so the celebration's column was 100 points
    // shorter on a machine where the artboard failed to resolve than on one where it
    // succeeded. Which of those a run gets depends on whether `rive_native`'s dylib has been
    // downloaded into the gitignored `build/`, so the column's layout depended on a file
    // nobody commits, and the 375×667 case in `streak_celebration_test.dart` was measuring
    // the short path while claiming to cover the tall one. `Center` rather than a tight box:
    // `_Ignition` sizes its own spark field off `_Ignition.stageSize` and lays sparks out
    // across it, so forcing it wider would silently rescale the hand-built choreography.
    if (!_settled || artboard == null) {
      return SizedBox(
        width: StreakFlame.stageWidthFor(widget.size),
        height: widget.size,
        child: Center(child: widget.fallback(context)),
      );
    }

    return SizedBox(
      width: StreakFlame.stageWidthFor(widget.size),
      height: widget.size,
      child: rive.RiveArtboardWidget(artboard: artboard, painter: _painter),
    );
  }
}

/// Poses the artboard: seeks `Ignite` to wherever `progress` says, and mixes `Idle` over the
/// top of it at `liveness`.
///
/// **A painter rather than `RiveWidget` plus a controller, because there is no state machine
/// to control any more.** `RiveWidgetController` exists to drive one, and driving two plain
/// timelines through it meant a view model, a data bind and a `StateMachineNamed` selector
/// that between them added a failure mode per layer — a loaded artboard with no view model
/// had to fall back rather than draw. [rive.BasicArtboardPainter] is the documented seam for
/// exactly this: `SingleAnimationPainter` in `rive_native/lib/src/rive_widget.dart` is the
/// same shape with one animation and no seeking.
base class _FlamePainter extends rive.BasicArtboardPainter {
  _FlamePainter() : super(fit: rive.Fit.contain);

  rive.Animation? _ignite;
  rive.Animation? _idle;

  double _progress = 0;
  double _liveness = 0;

  set progress(double value) {
    if (value == _progress) return;
    _progress = value;
    scheduleRepaint();
  }

  set liveness(double value) {
    if (value == _liveness) return;
    _liveness = value;
    scheduleRepaint();
  }

  @override
  void artboardChanged(rive.Artboard artboard) {
    super.artboardChanged(artboard);
    // **A name that does not resolve is a silent fallback, not an error.** `animationNamed`
    // returns null, `advance` then poses nothing, and the artboard sits on its authored rest
    // frame — a book lying open with a flame already on it, which looks deliberate. That is
    // why `streak_flame_test.dart` greps the built binary for both names.
    _ignite = artboard.animationNamed(kStreakFlameIgniteAnimation);
    _idle = artboard.animationNamed(kStreakFlameIdleAnimation);
    scheduleRepaint();
  }

  @override
  bool advance(double elapsedSeconds) {
    // Seek, do not advance: `progress` is the clock. `apply` writes the pose onto the
    // artboard without moving the animation's own time.
    final ignite = _ignite;
    if (ignite != null) {
      ignite.time = _progress.clamp(0, 1) * ignite.duration;
      ignite.apply();
    }

    // The loop *is* advanced, because a loop has no outside clock to seek by, and mixed in
    // rather than applied, so its values land around the pose the ignition left rather than
    // replacing it. Skipped entirely at zero: not advancing it is what lets the return value
    // below stop the ticker without the loop silently accumulating time in the background.
    final idle = _idle;
    if (idle != null && _liveness > 0) {
      idle.advance(elapsedSeconds);
      idle.apply(mix: _liveness);
    }

    super.advance(elapsedSeconds);

    // **The return value gates the ticker, and getting it wrong is a 60fps repaint on a
    // screen a reader opens nightly.** It is true exactly while the loop is live, which is the
    // point of the loop. Otherwise it is false, the render box stops its ticker, and the
    // drawing still paints: `false` means "no more frames are needed", not "do not draw". A
    // later change to `progress` or `liveness` calls `scheduleRepaint`, which the render box
    // listens to and which restarts the ticker — so the ignition gets one frame per change and
    // stillness in between.
    //
    // **It deliberately does *not* also return true while the ignition is mid-flight**, which
    // was the first version and looked like an optimisation: it saves a stop/start per frame
    // while the drive is moving, and it means an artboard parked at any value between 0 and 1
    // asks for frames forever. `streak_flame_golden_test.dart` renders six of those side by
    // side and timed out on all of them.
    return _liveness > 0;
  }

  @override
  void dispose() {
    _ignite?.dispose();
    _idle?.dispose();
    super.dispose();
  }
}
