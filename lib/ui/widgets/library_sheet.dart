import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';

/// The expanded cap for a sheet that shares the screen with the library: **all of
/// the band it is given**.
///
/// This used to subtract one shelf row, so that a shelf of the library stayed
/// visible behind an expanded sheet — the drawings' 74% (Card) and 79% (read view)
/// were consequences of that rule. It is gone deliberately for the read view and the
/// Card: both are sheets whose contents are worth the whole screen (a year of covers,
/// a card of statistics), and stopping 130pt short of the top to show a strip of
/// shelf nobody was looking at cost a row of covers on every phone.
///
/// Friends takes the same cap for a different reason. A list of friends has no
/// natural ceiling of its own — left uncapped it grew with the list, without bound,
/// and off the top of the screen once it out-grew the band. The same full-band cap
/// the other two use doubles as that ceiling, and gives a long list somewhere to stop
/// and scroll inside instead.
///
/// What keeps them sheets rather than pages is the rest of the shell, not this
/// number: the handle, the collapsed detent that is the default on launch, the app
/// bar they never cover, and the library they spring back down to.
///
/// [available] is the height the sheet's **collapsible content** may occupy, not the
/// whole band: the sheet's box is this plus the band it keeps below itself for the
/// tab bar and the home indicator. Getting that wrong is not a rounding error — an
/// earlier version of the shelf rule took the tab bar's 66pt out of the library
/// instead of out of the sheet, and `library_clearance_test.dart` measured the shelf
/// it was supposed to leave coming out at 40pt instead of 106pt.
///
/// Kept as a named function even though it is now the identity, because it is the
/// one place the expanded position is *defined* and every capped sheet reads it. A
/// constant that three files inline is a constant that will end up with three values.
double sheetExpandedExtent(double available) => available;

/// The intermediate snap position, for the sheets given one: **65% of the band**.
///
/// [available] is the same figure [sheetExpandedExtent] takes — the height the
/// sheet's *collapsible content* may occupy — so this is 65% of the content and not
/// of the screen. The sheet's box is that plus the band it keeps below itself, which
/// on an iPhone 17 Pro puts its top edge at 69% of the band it shares with the
/// library and 60% of the whole screen. Which of those three numbers you quote
/// depends on what you measure against; this one is in the units the API already
/// speaks, so it is the one that can be checked against the code.
///
/// Why a middle position exists at all: [sheetExpandedExtent] is the whole band,
/// which is the right ceiling for a year of covers or a full card but is also the
/// entire shell gone. The position people actually rest at is the one that shows most
/// of the sheet with a strip of library still behind it — which is what the drawings
/// had (`card-open` at h:74, the read view at 79) before the expanded cap grew to
/// swallow it. Adding it back as a *detent* keeps both: the strip of library at rest,
/// and the whole screen for anyone who drags again.
///
/// Every capped sheet takes one, Friends included: a fraction of the band is a real
/// resting point once the band is the ceiling, whatever the length of the list under
/// it — it is only when a sheet has no cap to take a fraction *of* that a middle
/// position stops meaning anything.
double sheetMidExtent(double available) => available * 0.65;

/// The floor every one of the shell's three sheets passes as
/// [LibrarySheet.minHeightFraction]: **20% of the screen**, so a resting sheet is
/// never so short it reads as barely there. A named constant rather than a bare
/// `0.2` inlined three times, for the reason [sheetMidExtent] is one: three copies
/// of the same number is a number that eventually stops agreeing with itself.
const double sheetMinHeightFraction = 0.2;

/// Where a [LibrarySheet] rests.
///
/// An enum rather than the boolean this used to be, because "expanded" stopped being
/// one thing: [medium] and [expanded] are both open, and the difference between them
/// is which height the sheet is laid out at.
///
/// Public because it is also what a caller names its *opening* position with — see
/// [LibrarySheet.initialDetent].
enum LibrarySheetDetent {
  /// Handle + header, plus whatever [LibrarySheet.collapsedBody] states.
  collapsed,

  /// [LibrarySheet.midExtent], for the sheets that ask for one. Falls back to
  /// [expanded] on a sheet with no room for a third position.
  medium,

  /// [LibrarySheet.expandedExtent], or the content's natural height when uncapped.
  expanded,
}

/// The bottom sheet that sits above the library, pinned to the bottom of the
/// screen (e.g. as the last child of a [Column] whose other child is an
/// [Expanded] library).
///
/// This widget owns only the *chrome and the motion*; what it shows is passed
/// in. That split exists because the shell gives every tab its own sheet over
/// one shared library background: the drag handle, the corner radius, the
/// shadow, the home-indicator inset, the snap positions and the spring must
/// be identical on all of them, and duplicating a spring is how tabs drift apart.
///
/// [header] is the row that survives a collapse — it defines the collapsed snap
/// position along with [minHeightFraction], so it should stay a fixed-height row.
/// [body] is everything the collapse hides.
///
/// The sheet snaps between:
/// * collapsed — only the drag handle and [header] are meaningful; [minHeightFraction]
///   may still floor the box below them at empty card, so it never reads as barely a
///   sheet at all.
/// * medium — [midExtent], for the sheets that ask for one. Reached by dragging, and
///   where the Card opens.
/// * expanded — [expandedExtent], or the content's natural height when uncapped.
///
/// Which of the three it opens at is [initialDetent]'s.
///
/// Anywhere short of covering the screen it also **pulls its edges in**: the card
/// floats, inset from the screen's sides and lifted off its bottom edge, with its
/// bottom corners concentric with the screen's own. It goes full width and flush
/// only when it actually fills the screen — which our capped sheets never quite do,
/// so they keep a few points of gap even at their expanded position. Full width is
/// what covering the screen looks like, not what "expanded" looks like.
///
/// The inset is a continuous function of the drag, not a per-state constant, so the
/// gap closes under the finger.
///
/// A scrolling [body] runs all the way to the card's bottom edge and passes under
/// whatever floats over the sheet; only chrome is kept clear of it. See
/// [bottomReserve].
///
/// Motion is a genuine under-damped spring, so it overshoots the target and
/// settles back, and it can be overdragged past either position with
/// rubber-band resistance.
///
/// **It also turns sideways**, for the sheets whose body is one of a horizontal
/// series — the read view and the Card, each of which is showing one year of a
/// list of them. A swipe left or right across the sheet asks for the next or the
/// previous, and the body slides a page's width to answer. See [pageIndex] for
/// the API and [_LibrarySheetState._turnPage] for the motion.
///
/// **The same sheet is handed from tab to tab.** Every tab in the shell wraps this
/// widget in one of its own — `FinishedBooksSheet`, `FriendsSheet`,
/// `LibraryCardSheet` — and the shell gives all three the *same* `GlobalKey`, so a
/// tab switch re-parents this one element instead of building a new one. That is what
/// lets the height be **sprung** rather than jumped: the contents swap on the frame
/// of the switch (the outgoing tab's widgets are gone — there is nothing else they
/// could do), and the box then travels from the height the old tab was showing to the
/// incoming tab's [initialDetent]. The switch itself is announced by [contentId].
/// Given neither, it still works and simply arrives instantly, which is what it did
/// before, and what a jump-cut looks like.
///
/// Because the sheet reports its (possibly collapsed) height to its parent, the
/// library above is laid out in whatever space is left over: the sheet is always
/// fully visible without scrolling to the bottom of the page, and the library
/// grows as the sheet is dragged down.
class LibrarySheet extends StatefulWidget {
  /// The row kept visible when collapsed, drawn below the drag handle and inset
  /// to the sheet's horizontal gutter.
  final Widget header;

  /// Replaces [header] once expanded, for sheets whose header changes with the
  /// state — the read view moves its filter out of the header and into a capsule
  /// row when it expands. Defaults to [header].
  final Widget? expandedHeader;

  /// Shown when expanded. Laid out at its natural height and clipped rather than
  /// squeezed — so it must not scroll vertically — **unless** [expandedExtent] is
  /// given, in which case it is handed a bounded height and may scroll.
  ///
  /// A scrolling body must leave `physics` unset and pass **`primary: false`**, so
  /// the sheet can decide which of the two a swipe belongs to. Both halves of that
  /// are load-bearing and the second one is not obvious: a vertical [ScrollView]
  /// with no controller and no `primary` computes `AlwaysScrollableScrollPhysics`
  /// *in its constructor*, and `Always` is one of the two physics that answer
  /// `shouldAcceptUserOffset` themselves rather than deferring — so it silently
  /// outranks the sheet's [ScrollConfiguration] and the body scrolls at every detent.
  /// `SingleChildScrollView` has no such default and needs nothing. See
  /// [_SheetBodyScrollBehavior].
  final Widget body;

  /// A *different* body for the collapsed snap position, drawn below the header in
  /// place of [body].
  ///
  /// The read view is the one sheet that wants one: "collapsed is today's spine pile
  /// with the count" in the design record, with the month grid as [body] above it.
  ///
  /// `null` — the default — means [body] shows at every position, and collapsing
  /// only shortens the viewport onto it: on a capped sheet the body keeps its bounded,
  /// scrollable box and the row the collapsed edge cuts through is clipped at the
  /// card's edge, which is what Friends and the Card both want. It is worth being
  /// explicit that this is *not* "handle and header alone" any more — it was, while
  /// nothing floored the collapsed position, and a floor ([minHeightFraction]) turned
  /// the difference into a card of visible empty space.
  final Widget? collapsedBody;

  /// Height of [collapsedBody], which the caller has to state because the sheet
  /// cannot measure a subtree it is not currently rendering — and it needs the
  /// collapsed snap position while the expanded body is on screen.
  ///
  /// Passing it is honest rather than a shortcut: the pile is a fixed-height
  /// horizontal scroller (`ReadPile.extent`), so its height is a constant and not
  /// something a measurement would tell us more accurately.
  final double collapsedBodyExtent;

  /// Floors the collapsed snap position at this fraction of the **full screen
  /// height** — `vh`-style, deliberately, rather than a fraction of the band the
  /// sheet shares with the library or of [expandedExtent]: it holds regardless of
  /// how tall a tab's own header and [collapsedBody] happen to be. `null` — the
  /// default — leaves collapsed exactly [collapsedBodyExtent] plus the header, no
  /// matter how short that is.
  ///
  /// See [sheetMinHeightFraction] for the value every one of the shell's three
  /// sheets passes. Left `null` here rather than defaulted to it, so a caller that
  /// wants the old, unfloored collapse — `library_sheet_test.dart`'s generic sheet,
  /// which is about the chrome and not about any tab's own sizing decisions — does
  /// not have to fight a default meant for someone else.
  final double? minHeightFraction;

  /// Total content height at the expanded snap position, capping it.
  ///
  /// `null` keeps Phase 1's behaviour: expanded is the content's natural height.
  /// Given a value, the expanded position is exactly that and [body] is handed
  /// the leftover after the header — which is what lets a month grid scroll inside
  /// a sheet that deliberately stops short of the top of the screen.
  final double? expandedExtent;

  /// An intermediate snap position between collapsed and [expandedExtent], in the
  /// same units: content height, excluding the reserve. `null` — the default — leaves
  /// the sheet with the two ends only.
  ///
  /// Dropped rather than clamped when it does not clear both neighbours by
  /// [_LibrarySheetState._detentGap]: a third position a few points from the second
  /// is not a detent, it is somewhere the sheet appears to refuse to leave.
  ///
  /// Only meaningful alongside [expandedExtent]. An uncapped sheet is laid out at its
  /// content's natural height, and a medium detent would clip content that has no
  /// way to scroll.
  ///
  /// See [sheetMidExtent] for the value every capped sheet passes.
  final double? midExtent;

  /// The height of the band the sheet shares with the library — what it would take
  /// to cover everything it can — which is what "full width" is measured against.
  ///
  /// The sheet cannot work this out for itself: a [Column] hands its non-flex
  /// children unbounded height, so its own constraints do not say. `null` falls back
  /// to the screen, which is never shorter, so the floating gutter errs towards
  /// staying open. That was good enough while every capped sheet stopped a shelf
  /// short of the top; now that they expand to the whole band, the difference between
  /// the two anchors is the difference between flush and a 1.5pt seam of library down
  /// each side.
  ///
  /// Also the ceiling the rendered box is clamped to. An overdrag or the spring's
  /// overshoot past the expanded position has nowhere to go once that position is the
  /// whole band — without this, both would push the sheet past the bottom of the
  /// `Column` that holds it and overflow the library out of existence.
  final double? fullExtent;

  /// Identifies **what the sheet is showing**, so that a swap can be told apart from
  /// a rebuild.
  ///
  /// Each tab's wrapper passes its own type, which is the one thing about it that
  /// cannot drift out of step with what it draws. When this changes, the sheet takes
  /// the update as a handover: it holds the height it was at, and springs to
  /// [initialDetent] instead of appearing there. Every other rebuild — a year filter,
  /// a query landing, an edit starting, a rotation — leaves the position alone, which
  /// is why this is a stated identity rather than something inferred from the geometry
  /// changing, and why it is not [activate]: a re-activated `State` means some
  /// *ancestor* moved, which the shell's pager does on its own.
  ///
  /// `null`, the default, means "never swapped": one set of contents for the sheet's
  /// whole life.
  ///
  /// Only meaningful alongside a shared `GlobalKey`. Without one the incoming tab
  /// builds a new `State`, and a new `State` has no height to spring from.
  final Object? contentId;

  /// Where the sheet rests before anyone touches it.
  ///
  /// [LibrarySheetDetent.expanded] is the default, for a sheet with nothing better to
  /// rest on and no cap to make opening there a problem — none of the shell's three
  /// currently ask for it, but a future one with no pile, no card and a short list
  /// could. Both Friends and the Card open somewhere shy of it on purpose: expanded is
  /// the whole band, and launching there would open the app onto a screen of mostly
  /// empty white with the library the shell is built around completely hidden behind
  /// it, for however few friends you follow or however short your card is that day.
  ///
  /// The read view opens [LibrarySheetDetent.collapsed], which the drawings label its
  /// "default state on launch", because it has a collapsed body — the pile — worth
  /// resting on. The Card and Friends both open [LibrarySheetDetent.medium] instead:
  /// neither has a collapsed body — a title and nothing else, and for Friends an
  /// add-friend button beside it — so collapsed would show none of what the tab is
  /// for. See [midExtent].
  ///
  /// A [LibrarySheetDetent.medium] start needs [midExtent]; without one it falls back
  /// to the cap, which is what [LibrarySheetDetent.medium] means everywhere else.
  final LibrarySheetDetent initialDetent;

  /// While the library is being edited the sheet springs shut to get out of the
  /// way and goes inert (no dragging, no tapping the handle), then springs back
  /// to wherever it was when editing ends.
  ///
  /// **Shut, not gone.** `HomePage._hiddenWhileEditing` is what actually takes the
  /// sheet off the screen for the duration — a collapsed sheet still covers the
  /// shelves an edit-mode drag has to be able to drop onto. Springing shut is still
  /// this widget's job, because it is what remembers the detent to come back to and
  /// what makes the return a spring rather than a reveal.
  ///
  /// Interactive controls *inside* [header] and [body] are the caller's to gate:
  /// children win hit tests, so this widget cannot disable them from outside.
  final bool isEditMode;

  /// Room the sheet keeps at its bottom for chrome that floats over it — in the
  /// shell, the tab bar (`ShellTabBarGeometry.reserve`).
  ///
  /// Reserved *inside* the sheet rather than by insetting the floating widget,
  /// because the sheet is what would otherwise be covered: at the collapsed snap
  /// position the header is all that is left, and a bar floating over the bottom
  /// edge would land straight on it.
  ///
  /// **It is not empty space.** A scrolling body's viewport runs the whole way to
  /// the card's bottom edge and its rows pass *under* the floating bar, which is
  /// what the band is for — an empty strip of card behind a translucent bar is the
  /// one thing that reads as a Flutter sheet rather than an iOS one. What keeps the
  /// last row reachable is the body's own bottom scroll padding, and it has to be
  /// this same number: see `ReadMonthGrid.bottomPadding`. What the band does
  /// guarantee is that no *chrome* — handle, header, the collapsed body — is ever
  /// under the bar, because the snap positions are measured above it.
  ///
  /// Additive with the home-indicator inset, which is always reserved below —
  /// `ShellTabBarGeometry.reserve` is measured from the top of that inset for
  /// exactly this reason, so do not add it here as well.
  ///
  /// Also what pays for the floating gap below the sheet at anything short of
  /// covering the screen: the band shortens by what the gap grows by, so the
  /// contents this protects never move. A sheet given no reserve therefore does not
  /// lift.
  final double bottomReserve;

  /// Which of [pageCount] horizontally-arranged pages [body] is showing, and where
  /// a sideways swipe is measured from.
  ///
  /// The sheet knows nothing about *what* a page is. The read view and the Card each
  /// pass an index into the year list their capsule rail is built from, in the rail's
  /// own order, so a swipe and a tap cannot disagree about which way is "next".
  ///
  /// Paging is off unless [onPageChanged] is given **and** [pageCount] is more than
  /// one: a series of one has no page to turn to, and a sheet that swallowed a swipe
  /// to do nothing would just feel unresponsive. Friends passes neither.
  final int pageIndex;

  /// How many pages [body] is one of. See [pageIndex].
  final int pageCount;

  /// Asks the caller for another page, by index. Called once per committed swipe,
  /// *before* the slide is drawn — the sheet needs the caller's new [body] to have
  /// something to slide in.
  ///
  /// The caller is expected to honour it by rebuilding with the new [pageIndex]. One
  /// that does not gets the outgoing page put back where it was when the slide ends,
  /// which is the only sane recovery: the sheet cannot invent a page.
  final ValueChanged<int>? onPageChanged;

  /// Reports the height the sheet takes at its **collapsed** position — the band of
  /// screen it always covers — whenever that changes.
  ///
  /// Exists because the sheet now floats over its background instead of sitting
  /// above it in a `Column`: nothing shrinks to make room any more, so the
  /// background has to inset its own scrollable content by this much or its last
  /// row is stranded behind a collapsed sheet forever.
  ///
  /// Reported after layout rather than returned, because it is a *measurement*. The
  /// collapsed position is the header's height, and a header's height is whatever
  /// the labels and the text scale make it — which is also why the caller must not
  /// try to compute it instead: the two would drift by exactly the amount nobody
  /// notices until an accessibility size shows up.
  final ValueChanged<double>? onRestingExtent;

  const LibrarySheet({
    super.key,
    required this.header,
    required this.body,
    this.expandedHeader,
    this.collapsedBody,
    this.collapsedBodyExtent = 0,
    this.minHeightFraction,
    this.expandedExtent,
    this.midExtent,
    this.fullExtent,
    this.initialDetent = LibrarySheetDetent.expanded,
    this.contentId,
    this.isEditMode = false,
    this.bottomReserve = 0,
    this.pageIndex = 0,
    this.pageCount = 1,
    this.onPageChanged,
    this.onRestingExtent,
  });

  @override
  State<LibrarySheet> createState() => _LibrarySheetState();
}

class _LibrarySheetState extends State<LibrarySheet>
    with TickerProviderStateMixin {
  /// Velocity (px/s) above which a drag is treated as a fling instead of
  /// snapping to the nearest position.
  static const double _flingVelocity = 220;

  /// How far a medium detent must clear both of its neighbours to be worth having.
  ///
  /// Below this the spring between the two is over before it reads as motion, and the
  /// sheet looks like it is refusing to move rather than snapping. Dropping the detent
  /// is the honest outcome: it means the band is too short for three positions, which
  /// is a real possibility on a small phone at an accessibility text size, where the
  /// collapsed header alone can be most of the sheet.
  static const double _detentGap = 24;

  /// The floor under both pairs of corners, and the whole radius on a screen with
  /// square corners — see [_cornerRadii].
  static const double _cornerRadius = 20;

  /// How far the card pulls in from the screen's side and bottom edges at the
  /// collapsed position, easing to zero as it comes to cover the screen.
  ///
  /// 14 is the same margin the fallback tab bar floats at
  /// (`ShellTabBarGeometry.sideInset`) — the two float over the same background,
  /// so a card inset differently from the bar above it reads as a mistake.
  ///
  /// **The bottom lift is taken out of the room the sheet already reserves below
  /// its content, never added to its height.** The content is top-anchored and the
  /// sheet's box is pinned to the bottom of the screen, so growing the box would
  /// move every pixel of the sheet — and shrink the library — as the gap closed.
  /// Spending the reserve instead leaves the content exactly where it was and only
  /// shortens the empty band the floating tab bar sits over, which is what that
  /// band is for. See [_lift].
  static const double _gutterInset = 14;

  /// The screen's own corner radius, which the card's corners are concentric with
  /// while it floats: an inset card's inner radius is its outer radius less the gap
  /// between them, so a 14pt gap wants 55 - 14. A 20pt corner inside a 55pt one is
  /// what the first version of this drew, and it reads as the card having the wrong
  /// shape rather than as a smaller radius.
  ///
  /// A constant because Flutter cannot ask: iOS keeps the number on
  /// `UIScreen._displayCornerRadius`, which is private API. The family runs from 39
  /// (iPhone X) through 47.33 (12–14) to 55 on the 15/16/17 generation, and a few
  /// points out on a ~40pt arc is invisible — 35 points out is what you can see.
  ///
  /// Only applied where there **is** a rounded screen corner to be concentric with,
  /// for which the home-indicator inset is the signal `ShellTabBarGeometry` already
  /// uses. An SE-shaped screen has square corners and gets [_cornerRadius], the
  /// card's own; being concentric with a square corner would mean square corners on
  /// a floating card. See [_cornerRadii].
  static const double _displayCornerRadius = 55;

  /// Horizontal gutter shared by the header and, by convention, by bodies — so
  /// a tab switch does not shift the title sideways.
  ///
  /// Measured from the card's edge, not the screen's, so it moves with
  /// [_gutterInset]: the title sits 25 inside the card at every position, which is
  /// what makes the card read as one object being resized.
  static const double _gutter = 25;

  /// Fraction of a drag that still moves the sheet once it is past a snap
  /// position, i.e. how rubbery it feels when overdragged.
  static const double _overdragResistance = 0.35;

  /// Under-damped on purpose: a ratio of ~0.55 overshoots by ~12%, which is the
  /// visible bounce. Anything above ~0.75 overshoots by single-digit pixels and
  /// just reads as a fast ease.
  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 0.55,
  );

  /// Velocity (px/s) above which a sideways drag turns the page whatever distance
  /// it covered. Lower than [_flingVelocity] because a page turn is a flick by
  /// nature — nobody drags a page across deliberately — and a swipe that dies just
  /// short of the commit distance is one that meant it.
  static const double _pageFlingVelocity = 320;

  /// Fraction of a page's width a *slow* drag has to cover to turn it. Well under
  /// half, because the alternative to committing is putting the page back, and a
  /// deliberate drag of a fifth of the screen was not asking for that.
  static const double _pageCommitFraction = 0.2;

  /// Fraction of the finger's sideways travel the page follows **before** it is
  /// committed.
  ///
  /// Damped rather than one-to-one, and this is the one number in the gesture worth
  /// arguing about. Following the finger exactly is what a `PageView` does, and it
  /// can only do it because it has the next page laid out beside the current one; the
  /// sheet does not — the caller builds one page, and the next one does not exist
  /// until [LibrarySheet.onPageChanged] has been answered. Undamped, a drag would
  /// therefore open an ever-widening band of empty card. At 0.4 the page moves enough
  /// to say "there is something over here" and the gap stays a sliver, and the moment
  /// the swipe commits the real page arrives to fill it. See [_turnPage].
  static const double _pagePeek = 0.4;

  /// The same, at either end of the series, where there is no page to turn to. Much
  /// stiffer: the resistance *is* the answer, in the way an iOS list resists at its
  /// top edge rather than refusing to move at all.
  static const double _pageEndPeek = 0.12;

  /// Stiffer and far better damped than [_spring].
  ///
  /// A page turn covers most of the screen's width, so the ~12% overshoot that reads
  /// as a pleasant bounce on a sheet's height would be a 45pt lurch here. It is not
  /// critically damped either: the two pages travel locked a span apart, so a small
  /// overshoot moves both and shows no gap — it reads as weight rather than as a
  /// mistake.
  static final SpringDescription _pageSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 500, ratio: 0.85);

  final _contentKey = GlobalKey();
  final _headerKey = GlobalKey();

  /// Unbounded because the simulation animates the sheet's height in pixels and
  /// is allowed to overshoot past both snap positions.
  late final AnimationController _snapController;

  /// Drives [_pageX] through a page turn, and through a swipe that did not earn one.
  /// Unbounded for the reason [_snapController] is: it animates pixels, and the
  /// spring is allowed past its target.
  late final AnimationController _pageController;

  /// How far the page the caller is currently showing sits from its resting place,
  /// in pixels, positive to the right. Zero except during a swipe or a turn.
  double _pageX = 0;

  /// The sideways drag before [_pagePeek]'s damping — what the commit distance is
  /// measured against, because the threshold is about the *finger*.
  double _pageDragRaw = 0;

  /// The body being left behind, held for the length of a turn so both pages can
  /// travel together. Null at rest.
  ///
  /// The **widget**, captured before the caller swaps it, rather than a snapshot: it
  /// is the same instance the sheet was already rendering, so keying the two pages by
  /// index (see [_pages]) hands the outgoing one its existing element and it slides
  /// away with its scroll offset and its decoded covers intact.
  Widget? _outgoingPage;

  /// [LibrarySheet.pageIndex] as it was when [_outgoingPage] was captured. Also how
  /// the sheet tells its own turn apart from a page change it did not ask for — a tap
  /// on the year rail — which arrives instantly rather than sliding.
  int _outgoingIndex = -1;

  /// `1` when the page arriving comes in from the right (a swipe left, the next page
  /// in the series), `-1` when it comes from the left.
  double _pageDirection = 1;

  /// The width the running turn travels, fixed when it starts so a rotation midway
  /// cannot leave the two pages a different distance apart than they were laid out.
  double _pageTravelSpan = 0;

  /// Height of the visible slice of content, or `null` while fully expanded —
  /// letting the content size itself keeps the sheet correct when the body, the
  /// header labels or the text scale changes.
  double? _clipHeight;

  /// How far the whole sheet is pushed below its resting position. Used instead
  /// of shrinking below [_minHeight] so an undershoot slides the sheet off the
  /// bottom of the screen rather than cutting the header in half.
  double _slideDown = 0;

  /// Drag position before overdrag resistance is applied.
  double _rawTravel = 0;

  late LibrarySheetDetent _detent = widget.initialDetent;

  /// Which body is on screen. Distinct from [_detent], which is the *target*:
  /// this flips as the sheet passes [_swapPoint] during a drag, so the content changes
  /// under the finger rather than waiting for the release.
  late bool _showExpanded =
      widget.initialDetent != LibrarySheetDetent.collapsed;

  /// Remembered across an edit-mode round trip so leaving edit mode doesn't
  /// override a sheet the user had deliberately collapsed — or deliberately left at
  /// the medium detent.
  late LibrarySheetDetent _detentBeforeEdit = _detent;

  /// Last value handed to [LibrarySheet.onRestingExtent]. Negative so the first real
  /// measurement always counts as a change.
  double _reportedResting = -1;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController.unbounded(vsync: this)
      ..addListener(_onSnapTick)
      ..addStatusListener(_onSnapStatus);
    _pageController = AnimationController.unbounded(vsync: this)
      ..addListener(_onPageTick)
      ..addStatusListener(_onPageStatus);
    if (widget.initialDetent == LibrarySheetDetent.medium) {
      // Applied before the first frame rather than after it, because unlike the
      // collapsed position this one is a *number the caller gave* and needs no
      // measurement. Left to the callback below, the sheet's first frame would be the
      // cap — the whole band — and the drop to the medium detent one frame later is
      // exactly the flash of full-screen white that opening at medium exists to avoid.
      _clipHeight = widget.midExtent;
    }
    if (widget.initialDetent != LibrarySheetDetent.expanded) {
      // Corrects the guess above against the laid-out sheet, and is the *only* thing
      // that puts a collapsed sheet at its position: the first frame already looks
      // right there — with `_showExpanded` false the content is the collapsed body, so
      // its natural height is the collapsed position — but `_travel` is derived from
      // `_clipHeight`, which is null for "expanded", so without this the first drag
      // would start from the cap and jump. Deferred because the position can only be
      // measured once laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _maxHeight <= 0) return;
        final resting = _heightOf(widget.initialDetent);
        if (resting <= 0 || _clipHeight == resting) return;
        setState(() {
          _clipHeight = resting;
          _slideDown = 0;
        });
      });
    }
  }

  /// Takes the sheet from the height the outgoing tab was showing to the incoming
  /// tab's [LibrarySheet.initialDetent], instead of letting it arrive there.
  ///
  /// Driven by [LibrarySheet.contentId] rather than by [activate], which was the first
  /// attempt and is not the same event: a re-activated `State` means *some* ancestor
  /// was re-parented, and in the shell the pager does that on its own — so a swipe
  /// between libraries sprang the sheet as if the tab had changed.
  void _springAfterHandover(LibrarySheet oldWidget) {
    // Pins the height the sheet is leaving, so the frame that swaps the contents
    // renders them in the *old* box and the spring has somewhere to start from.
    //
    // Measured against the outgoing widget's cap rather than `_maxHeight`, which now
    // reads the incoming one: a null `_clipHeight` means "as tall as my content",
    // which for an uncapped sheet resting at the top is the only state it is ever in —
    // and left null it would be read against the new cap, putting the sheet there
    // instantly. That is the jump this exists to remove. `_measure` still reports the
    // outgoing layout, because this runs before the incoming one.
    _clipHeight ??= oldWidget.expandedExtent ?? _measure(_contentKey);
    // Adopts the incoming tab's target *now*, in the frame that swaps the contents,
    // rather than letting [_snapTo] spend a frame on it: it flips [_showExpanded]
    // before it dares measure a target, because a target taken from the outgoing
    // header is wrong by the difference between the two. Setting both here means the
    // swap frame already lays out the header and body the sheet is heading for, so
    // the callback below can measure and spring on the spot — two frames of
    // stillness after a tab tap read as latency, and three read as a stutter.
    //
    // [_detent] has to move with it. It is what [_atRest] compares the pinned height
    // against, and a sheet that called itself at rest here would lay the incoming
    // header out in the outgoing box — which is the `RenderFlex` overflow
    // [_buildContent] documents, 61pt of it.
    _detent = widget.initialDetent;
    _showExpanded = widget.initialDetent != LibrarySheetDetent.collapsed;
    // Deferred for the reason the edit-mode spring is: the target is measured from the
    // layout this build produces, and this build has not run yet.
    //
    // Where the incoming tab's *collapsed* height is taller than the height being left
    // — Friends is only as tall as its friends, and can rest below the read view's
    // pile — the spring runs entirely under [_minHeight], so [_setTravel]'s undershoot
    // rule turns it into a slide up from the bottom edge instead of a box that grows.
    // That is the right end to give: the alternative is a header cut in half, which is
    // the case that rule exists for.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _snapTo(widget.initialDetent);
    });
  }

  @override
  void didUpdateWidget(LibrarySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.contentId != oldWidget.contentId) {
      // A tab switch is not a page turn: whatever was sliding belongs to the tab that
      // just left, and its body is about to be replaced wholesale anyway.
      _resetPage();
      _springAfterHandover(oldWidget);
      return;
    }
    if (widget.pageIndex != oldWidget.pageIndex && !_turnArriving(oldWidget)) {
      // Somebody else moved the page — a tap on the year rail — and that arrives
      // instantly rather than sliding. Deliberately: the tap has already been
      // answered, by the capsule shrinking under the finger and the selection haptic,
      // and a page that then slid in of its own accord would read as the sheet
      // deciding to move. `FinishedBooksSheet` makes the same call about the grid's
      // scroll offset, for the same reason.
      _resetPage();
    }
    if (widget.isEditMode != oldWidget.isEditMode) {
      if (widget.isEditMode) _detentBeforeEdit = _detent;
      final target = widget.isEditMode
          ? LibrarySheetDetent.collapsed
          : _detentBeforeEdit;
      // Deferred so the snap positions are measured against the layout that
      // this build produces, and so no setState happens mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _snapTo(target);
      });
    }
  }

  @override
  void dispose() {
    _snapController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  double _measure(GlobalKey key) {
    final context = key.currentContext;
    // An element that is out of the tree has no render object to ask for, and asking
    // asserts rather than answering null. Reachable during a re-parent: the shell's
    // pager can hand this whole subtree to a new slot, and every widget in it is
    // re-activated top-down — so a build here can run while the content below is
    // still inactive.
    if (context == null || !context.mounted) return 0;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return 0;
    return box.size.height;
  }

  /// The expanded snap position.
  ///
  /// Either the cap the caller set, or the content's natural height when it did
  /// not. Known without laying out the expanded body, which matters because the
  /// midpoint and the spring target are needed while the *collapsed* body is the
  /// one on screen.
  double get _maxHeight => widget.expandedExtent ?? _measure(_contentKey);

  /// The collapsed snap position: handle + header, plus the collapsed body's
  /// stated height — or [LibrarySheet.minHeightFraction] of the screen, whichever
  /// is taller.
  ///
  /// The floor exists because a bare header (Friends, the Card) collapsed to
  /// something that read as barely a sheet at all: a thin strip a drag could
  /// easily miss. Below the floor the extra room shows as empty card under the
  /// header rather than more content — there is nothing else stated to fill it
  /// with — which is the tradeoff for resting at a height that actually reads as
  /// "there is a sheet here."
  double get _minHeight {
    final max = _maxHeight;
    final headerExtent = _measure(_headerKey);
    if (max <= 0 || headerExtent <= 0) return max;
    final natural = headerExtent + widget.collapsedBodyExtent;
    final fraction = widget.minHeightFraction;
    final floor = fraction == null
        ? 0.0
        : MediaQuery.sizeOf(context).height * fraction;
    final min = natural < floor ? floor : natural;
    return min > max ? max : min;
  }

  /// Current position of the sheet's top edge, expressed as a height. May sit
  /// outside `[_minHeight, _maxHeight]` while bouncing or being overdragged.
  double get _travel => (_clipHeight ?? _maxHeight) - _slideDown;

  /// The medium snap position, or `null` when there is no room for one. See
  /// [LibrarySheet.midExtent] and [_detentGap].
  double? get _mediumHeight {
    final mid = widget.midExtent;
    if (mid == null) return null;
    final min = _minHeight;
    final max = _maxHeight;
    if (max <= 0 || mid < min + _detentGap || mid > max - _detentGap) {
      return null;
    }
    return mid;
  }

  /// The detents this sheet actually has, shortest first.
  List<LibrarySheetDetent> get _detents => _mediumHeight == null
      ? const [LibrarySheetDetent.collapsed, LibrarySheetDetent.expanded]
      : const [
          LibrarySheetDetent.collapsed,
          LibrarySheetDetent.medium,
          LibrarySheetDetent.expanded,
        ];

  double _heightOf(LibrarySheetDetent detent) => switch (detent) {
    LibrarySheetDetent.collapsed => _minHeight,
    // Falls back to the top rather than to the bottom: a sheet asked for a medium
    // detent it has no room for should still open when something asks it to.
    LibrarySheetDetent.medium => _mediumHeight ?? _maxHeight,
    LibrarySheetDetent.expanded => _maxHeight,
  };

  /// Where a released drag settles when it was not a fling: whichever detent is
  /// closest to where the finger left the sheet.
  LibrarySheetDetent _nearestDetent(double travel) {
    var nearest = _detents.first;
    var best = double.infinity;
    for (final detent in _detents) {
      final distance = (_heightOf(detent) - travel).abs();
      if (distance < best) {
        best = distance;
        nearest = detent;
      }
    }
    return nearest;
  }

  /// The next detent past [travel] in the direction of a fling, or the one at that
  /// end when there is nothing past it.
  ///
  /// One detent per fling, rather than running to the end. With three positions,
  /// "fast means all the way" would make the medium detent reachable only by a slow
  /// and deliberate drag: every flick from collapsed would blow straight past it,
  /// which is the opposite of what a detent is for.
  LibrarySheetDetent _detentBeyond(double travel, {required bool up}) {
    final ordered = up ? _detents : _detents.reversed;
    for (final detent in ordered) {
      final height = _heightOf(detent);
      // Half a point of slack, so a fling that starts from a detent the sheet is
      // already resting at moves on instead of snapping back to where it began.
      if (up ? height > travel + 0.5 : height < travel - 0.5) return detent;
    }
    return up ? _detents.last : _detents.first;
  }

  /// Where a drag swaps [LibrarySheet.collapsedBody] for [LibrarySheet.body]:
  /// halfway to the sheet's **first** open detent.
  ///
  /// Halfway to the medium detent rather than to the top, for the sheets that have
  /// one. Measured against the top, a drag from collapsed to medium would spend three
  /// quarters of its length still showing the collapsed body and then swap almost at
  /// the moment it settled.
  double get _swapPoint => (_minHeight + (_mediumHeight ?? _maxHeight)) / 2;

  /// Whether the sheet is settled on a detent, as opposed to being dragged or
  /// springing between two of them.
  ///
  /// Derived by comparing the layout against the target rather than tracked with a
  /// flag, because it is a *fact about the layout* and a flag would have four places
  /// to get wrong: drag start, drag end, the spring settling, and the extra frame
  /// [_snapTo] inserts to measure a new header. A drag that happens to pass exactly
  /// through a detent reads as at rest here, which is harmless — at that height the
  /// two answers are the same.
  bool get _atRest =>
      _slideDown == 0 &&
      (_clipHeight == null || (_clipHeight! - _heightOf(_detent)).abs() < 0.5);

  /// How open the sheet is: 0 at the collapsed snap position, 1 once its box
  /// reaches the top of the screen's safe area. What the floating inset is drawn
  /// from.
  ///
  /// **Measured against the screen, not against the expanded snap position.** That
  /// one deliberately stops short so a shelf of library stays visible
  /// ([sheetExpandedExtent]), and a sheet that went full width and flush there
  /// would be claiming the whole screen while showing three quarters of it — which
  /// is exactly the note this rule came from: at 70% the width must not be full.
  /// Our capped sheets therefore keep ~6-7pt of gutter at rest, and only something
  /// that really fills the screen closes it.
  ///
  /// The screen rather than the band the sheet shares with the library, which would
  /// be the stricter anchor: the band is the app bar shorter, so this leaves the gap
  /// about a point wider at the expanded position than a band-anchored version
  /// would (7.3 against 6.4 on an iPhone 17 Pro). The band can only be had by
  /// threading `home_page`'s `LayoutBuilder` height down through three sheets — a
  /// `Column` hands its non-flex children unbounded height, so the sheet cannot
  /// read it from its own constraints — and one point of gap does not buy that. The
  /// screen is never shorter than the band, so the error always leaves the gutter
  /// open rather than closing it early.
  ///
  /// Clamped, so an overdrag or the spring's overshoot past either end holds the
  /// shape it arrived with rather than inverting it.
  ///
  /// **Measured against the band the sheet shares with the library** — or, when the
  /// caller does not say what that is, against the screen. See [fullExtent].
  ///
  /// Not against the expanded snap position: a sheet whose expanded state stops
  /// short of the top would go full width and flush there, claiming the whole screen
  /// while showing three quarters of it. At 70% the width must not be full. All three
  /// tabs' sheets expand to the whole band now, so all three reach 1 and go flush.
  ///
  /// Clamped, so an overdrag or the spring's overshoot past either end holds the
  /// shape it arrived with rather than inverting it.
  ///
  /// Falls back to the collapsed end until the header has a size, because
  /// [_minHeight] reports the cap when it cannot measure one and that would read as
  /// "fully open" on the first frame. Capped sheets still come out close, since
  /// their [_maxHeight] is a number rather than a measurement.
  double _coverage(double full) {
    final min = _measure(_headerKey) > 0 ? _minHeight : 0.0;
    if (full <= min) return 1;
    return ((_travel - min) / (full - min)).clamp(0.0, 1.0);
  }

  /// The tallest content the sheet may show: the band less the reserve, or the
  /// screen's own when no band was given.
  double _fullTravel(BuildContext context, double reserve) {
    final band =
        widget.fullExtent ??
        MediaQuery.sizeOf(context).height -
            MediaQuery.viewPaddingOf(context).top;
    return band - reserve;
  }

  /// The measured heights [_coverage] is derived from, as one number to compare
  /// frames by. See [_syncGutterAfterLayout].
  double get _gutterInputs => _maxHeight + _measure(_headerKey);

  /// Build runs before layout, so [_coverage] reads the sizes the *previous* frame
  /// produced. On any frame where the content changes height — the first frame of
  /// all, a tab swapping the body, a filter redrawing it, a text-scale change — that
  /// is the wrong number, and nothing else would ever correct it: a sheet sitting at
  /// its expanded position does not call `setState` on its own, so the stale gutter
  /// would simply stay on screen.
  ///
  /// So each build records what it read and checks it once the frame is laid out,
  /// asking for one more frame if it has moved. Converges by construction — the
  /// rebuild reads the layout the first pass produced — and costs one closure per
  /// frame plus, on a genuine change, one extra frame with the previous gutter on it.
  ///
  /// The same pass publishes [LibrarySheet.onRestingExtent], for the same reason and
  /// on the same terms: it is a measurement, so it cannot be known during build.
  void _syncAfterLayout(double inputs, double reserve) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final resting = _minHeight + reserve;
      if ((resting - _reportedResting).abs() > 0.5) {
        _reportedResting = resting;
        widget.onRestingExtent?.call(resting);
      }
      if ((_gutterInputs - inputs).abs() < 0.5) return;
      setState(() {});
    });
  }

  /// Splits [travel] into a clip height and, when it undershoots, a downwards
  /// slide. Overshoot above the natural height simply stretches the box: the
  /// content is top-anchored, so it rises and the extra white is invisible
  /// against the sheet.
  void _setTravel(double travel) {
    final min = _minHeight;
    final max = _maxHeight;
    // Swap the body as the sheet passes [_swapPoint], so a drag shows the state it is
    // heading for instead of stretching the one it is leaving.
    final showExpanded = max > min ? travel >= _swapPoint : _showExpanded;
    setState(() {
      _showExpanded = showExpanded;
      if (travel < min) {
        _clipHeight = min;
        _slideDown = min - travel;
      } else {
        _clipHeight = travel;
        _slideDown = 0;
      }
    });
  }

  void _onSnapTick() {
    if (_maxHeight <= 0) return;
    _setTravel(_snapController.value);
  }

  void _onSnapStatus(AnimationStatus status) {
    // Hand height control back to the content once fully settled at the top. Only
    // there: a medium detent *is* a height, and letting the content size itself would
    // put the sheet straight back at its cap.
    if (status == AnimationStatus.completed &&
        _detent == LibrarySheetDetent.expanded) {
      setState(() {
        _clipHeight = null;
        _slideDown = 0;
      });
    }
  }

  /// Springs the sheet to one of its snap positions, carrying [velocity]
  /// (px/s, positive = downwards) over from the gesture that triggered it.
  ///
  /// Swaps the body *before* measuring when it is about to change. The two states
  /// can have different headers — the read view's grows a capsule row when it
  /// expands — so a target computed against the outgoing header is wrong by the
  /// difference, and the sheet would spring to a height it then had to jump away
  /// from. One frame of the new content at the old height is invisible, because it
  /// is clipped.
  void _snapTo(LibrarySheetDetent target, {double velocity = 0}) {
    // Set before the frame below, not just in [_springTo]: [_atRest] compares the
    // layout against this, and a sheet that still called itself collapsed while
    // rendering the expanded header would lay that header out in the collapsed box.
    _detent = target;
    final expand = target != LibrarySheetDetent.collapsed;
    if (_showExpanded != expand) {
      setState(() => _showExpanded = expand);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _springTo(target, velocity: velocity);
      });
      return;
    }
    _springTo(target, velocity: velocity);
  }

  void _springTo(LibrarySheetDetent target, {double velocity = 0}) {
    final max = _maxHeight;
    final min = _minHeight;
    if (max <= 0 || min >= max) return;

    _detent = target;
    _showExpanded = target != LibrarySheetDetent.collapsed;
    final from = _travel;
    final to = _heightOf(target);
    if ((from - to).abs() < 0.5 && velocity.abs() < 1) {
      _snapController.stop();
      setState(() {
        _clipHeight = target == LibrarySheetDetent.expanded ? null : to;
        _slideDown = 0;
      });
      return;
    }
    // Drag velocity is in screen space (down = positive) while the simulation
    // animates height (down = shrinking), hence the sign flip.
    _snapController.animateWith(SpringSimulation(_spring, from, to, -velocity));
  }

  void _onDragStart(DragStartDetails details) {
    _snapController.stop();
    _rawTravel = _travel;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final max = _maxHeight;
    if (max <= 0) return;
    final min = _minHeight;
    _rawTravel -= details.delta.dy;
    // Rubber-band past either snap position instead of hitting a hard stop.
    final travel = _rawTravel > max
        ? max + (_rawTravel - max) * _overdragResistance
        : _rawTravel < min
        ? min - (min - _rawTravel) * _overdragResistance
        : _rawTravel;
    _setTravel(travel);
  }

  void _onDragEnd(DragEndDetails details) {
    final max = _maxHeight;
    if (max <= 0) return;
    _settleFrom(details.primaryVelocity ?? 0);
  }

  /// Where a released drag lands: one detent along on a fling, the nearest otherwise.
  ///
  /// Shared with the scroll hand-off ([_onBodyScroll]), because a drag that started
  /// inside the body and a drag that started on the header have to settle the same
  /// way — the reader cannot tell which one they made.
  void _settleFrom(double velocity) {
    final target = velocity.abs() > _flingVelocity
        ? _detentBeyond(_travel, up: velocity < 0)
        : _nearestDetent(_travel);
    _snapTo(target, velocity: velocity);
  }

  // ---------------------------------------------------------------------------
  // Turning the page sideways.
  //
  // The sheet's body is one of a horizontal series for two of the shell's tabs —
  // the read view and the Card, each showing one year of several — and a swipe
  // across the sheet moves along it. What makes this the sheet's job rather than
  // something wrapped around a body is that the gesture is about the *whole card*:
  // the reader swipes wherever their thumb happens to be, over the title as
  // readily as over the covers, and only the body moves. The same argument as for
  // the vertical drag, one axis over.
  //
  // Nothing here knows what a page *is*. See [LibrarySheet.pageIndex].
  // ---------------------------------------------------------------------------

  bool get _pagingEnabled =>
      widget.onPageChanged != null && widget.pageCount > 1;

  /// How far a turn travels: the screen's width.
  ///
  /// The card's own would be more exact — it is inset by up to [_gutterInset] a side
  /// while it floats — but the card's width changes with the vertical position, and a
  /// page span that moved as the sheet was dragged would put the two pages a
  /// different distance apart than the frame they started on. The screen is the one
  /// width that holds still, and being ~28pt generous only means a page finishes
  /// clear of the card's edge, which is where it is clipped anyway.
  double _pageSpan() => MediaQuery.sizeOf(context).width;

  /// Whether there is a page to turn to. [forward] is the direction the *content*
  /// moves — a swipe left, towards the next page in the series.
  bool _hasPage({required bool forward}) =>
      forward ? widget.pageIndex < widget.pageCount - 1 : widget.pageIndex > 0;

  /// True on the frame the page a swipe asked for actually arrives. See
  /// [_outgoingIndex].
  bool _turnArriving(LibrarySheet oldWidget) =>
      _pageController.isAnimating && _outgoingIndex == oldWidget.pageIndex;

  /// Puts the body back where it belongs and forgets the page it was leaving.
  ///
  /// No `setState`: every caller is either inside one or inside [didUpdateWidget],
  /// which a build follows.
  void _resetPage() {
    _pageController.stop();
    _pageX = 0;
    _pageDragRaw = 0;
    _outgoingPage = null;
    _outgoingIndex = -1;
  }

  void _onPageDragStart(DragStartDetails details) {
    // A swipe that lands mid-turn cuts the turn short rather than compounding with
    // it. Carrying the old motion over would mean tracking two pages leaving at
    // once, and the honest reading of a second swipe is that the reader has already
    // stopped looking at the page the first one was bringing in.
    if (_pageController.isAnimating || _outgoingPage != null) {
      setState(_resetPage);
    }
    _pageDragRaw = 0;
  }

  void _onPageDragUpdate(DragUpdateDetails details) {
    _pageDragRaw += details.delta.dx;
    // Content moving left is the next page in the series coming from the right.
    final resistance = _hasPage(forward: _pageDragRaw < 0)
        ? _pagePeek
        : _pageEndPeek;
    setState(() => _pageX = _pageDragRaw * resistance);
  }

  void _onPageDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final fling = velocity.abs() > _pageFlingVelocity;
    // A fling decides its own direction; a slow drag's is wherever it ended up. The
    // two can disagree — a drag left that flicks back right on release — and the
    // flick is the more recent intention.
    final forward = fling ? velocity < 0 : _pageDragRaw < 0;
    final far = _pageDragRaw.abs() > _pageSpan() * _pageCommitFraction;
    if ((fling || far) && _hasPage(forward: forward)) {
      _turnPage(forward: forward, velocity: velocity);
    } else {
      // Damped on the way back by exactly what damped it on the way out, so the page
      // leaves the finger at the speed it was moving under it.
      _springPageHome(velocity * _pagePeek);
    }
  }

  /// Asks the caller for the next page and slides this one out to meet it.
  ///
  /// The two pages travel **locked one span apart** on a single value: [_pageX] is
  /// where the caller's current page sits, and the one being left is always
  /// `_pageX - direction * span` behind it. One spring for both is what keeps the
  /// seam between them from ever opening, including through the overshoot.
  ///
  /// The caller's page does not arrive on this frame — a rebuild is a frame away at
  /// best — so [_pages] draws the body it still has in the outgoing slot until it
  /// does. That is why [_pageX] can be set to the far side of the span here without
  /// the card going blank for a frame.
  void _turnPage({required bool forward, required double velocity}) {
    final span = _pageSpan();
    final direction = forward ? 1.0 : -1.0;
    _pageController.stop();
    setState(() {
      _outgoingPage = _bodyForState;
      _outgoingIndex = widget.pageIndex;
      _pageDirection = direction;
      _pageTravelSpan = span;
      // The peek carries over: the page under the finger keeps going from where it
      // was let go, and the arriving one starts exactly a span behind it.
      _pageX += direction * span;
    });
    // The year rail gives one for a tap, and a swipe changes the same thing.
    HapticFeedback.selectionClick();
    widget.onPageChanged!(widget.pageIndex + (forward ? 1 : -1));
    _pageController.animateWith(
      SpringSimulation(_pageSpring, _pageX, 0, velocity),
    );
  }

  void _springPageHome(double velocity) {
    if (_pageX == 0 && velocity.abs() < 1) {
      if (_outgoingPage != null) setState(_resetPage);
      return;
    }
    _pageController.animateWith(
      SpringSimulation(_pageSpring, _pageX, 0, velocity),
    );
  }

  void _onPageTick() => setState(() => _pageX = _pageController.value);

  void _onPageStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed &&
        status != AnimationStatus.dismissed) {
      return;
    }
    // Snapped to exactly zero rather than left within the spring's tolerance, so a
    // settled sheet renders its body at no offset at all — and so a caller that
    // ignored [LibrarySheet.onPageChanged] gets its page put back rather than left
    // parked a span off screen.
    setState(_resetPage);
  }

  /// Whether the body's own scroll view may take a **vertical** drag, or whether the
  /// sheet does.
  ///
  /// **Only at the cap.** Below it, a swipe up inside the body belongs to the sheet:
  /// it opens one detent further, and it takes another swipe to reach the top and a
  /// third before the list underneath starts moving. That is what an iOS sheet does,
  /// and Flighty with it — the sheet is the thing the gesture is about until there is
  /// no more sheet to open.
  ///
  /// Enforced by handing the body physics that refuse a vertical user offset, through
  /// a [ScrollConfiguration], rather than by fighting for the gesture: a `Scrollable`
  /// that cannot accept a user offset builds no drag recognisers at all, so the
  /// sheet's own wins uncontested instead of the two racing in the arena. See
  /// [_SheetBodyScrollBehavior] for what the caller's body has to do to let that work.
  ///
  /// Keyed to the *detent* and not to [_atRest] on purpose: during the hand-off
  /// below, the sheet is moving while still nominally expanded, and flipping the
  /// physics mid-gesture would cancel the very drag that is driving it.
  bool get _bodyMayScroll => _detent == LibrarySheetDetent.expanded;

  /// True while a downward overscroll of the body is driving the sheet.
  bool _scrollHandoff = false;

  /// The other half of [_bodyMayScroll]: at the cap, a drag *down* that runs the body
  /// out of scroll offset carries on into the sheet rather than stopping dead.
  ///
  /// Read from the body's overscroll rather than from a gesture, because the gesture
  /// belongs to the `Scrollable` by then and it will not be given up mid-drag. The
  /// body is left on clamping physics for the same reason: a bouncing overscroll
  /// rubber-bands the list and reports no overscroll to hand over, and an iOS sheet
  /// moves the sheet there rather than stretching the list anyway.
  bool _onBodyScroll(ScrollNotification notification) {
    // Only the body's own scroller. A nested one — the read view's per-month grids —
    // is inert, but depth is what says so rather than what it happens to be built as.
    if (notification.depth > 0) return false;
    // And only a vertical one. The read view's collapsed body *is* a horizontal
    // scroller, so it reports at depth 0 too: without this, running the spine pile
    // off its left edge would drag the sheet sideways-by-proxy.
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is OverscrollNotification) {
      // Negative is the top edge: the list has run out of offset and the finger is
      // still pulling down. Positive would be the bottom, where there is nothing to
      // hand the drag to.
      if (notification.overscroll >= 0 || notification.dragDetails == null) {
        return false;
      }
      final min = _minHeight;
      if (!_scrollHandoff) {
        _scrollHandoff = true;
        _snapController.stop();
        _rawTravel = _travel;
      }
      _rawTravel += notification.overscroll;
      _setTravel(
        _rawTravel < min
            ? min - (min - _rawTravel) * _overdragResistance
            : _rawTravel,
      );
    } else if (notification is ScrollEndNotification && _scrollHandoff) {
      _scrollHandoff = false;
      // Same settle as a released drag on the header, carrying the fling over so a
      // flick down puts the sheet away rather than dropping it at the nearest detent.
      _settleFrom(notification.dragDetails?.primaryVelocity ?? 0);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // The band the floating tab bar and the home indicator live in. Kept clear of
    // the sheet's *chrome* by the snap positions, and passed under by its body — see
    // [LibrarySheet.bottomReserve].
    final reserve =
        MediaQuery.viewPaddingOf(context).bottom + widget.bottomReserve;

    // Never taller than the band: at the expanded position these sheets *are* the
    // band, so an overdrag or an overshoot would otherwise push the box past the
    // bottom of the `Column` holding it. The stop is deliberate rather than rubbery —
    // there is nowhere above "the whole screen" for a sheet to stretch into.
    final full = _fullTravel(context, reserve);
    final clipHeight = _clipHeight == null
        ? null
        : math.min(_clipHeight!, full);

    final content = _buildContent(context, reserve, clipHeight);
    // Pinned shut while the library is being edited.
    final interactive = !widget.isEditMode;

    final expansion = _coverage(full);
    final inset = _gutterInset * (1 - expansion);
    final lift = _lift(inset, reserve);
    _syncAfterLayout(_gutterInputs, reserve);

    // The corners follow the *lift* rather than the coverage: a corner rounded
    // against an edge it is still flush with is a notch cut out of the sheet.
    final radius = _cornerRadii(context, lift);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: interactive ? _onDragStart : null,
      onVerticalDragUpdate: interactive ? _onDragUpdate : null,
      onVerticalDragEnd: interactive ? _onDragEnd : null,
      // Sideways, the sheet turns the page — for the tabs whose body is one of a
      // series. Both axes on one detector so they compete in the same arena and the
      // dominant one wins, rather than a wrapper deciding for them; a diagonal drag
      // then resolves to whichever way it is actually going.
      //
      // Withheld entirely when there is nowhere to page, so no recogniser is built
      // and a sheet with one year behaves exactly as it did. A horizontal scroller
      // *inside* the body still wins over this by being deeper in the tree — and only
      // when it has something to scroll, which is what the sheet's own physics already
      // decide (see [_NoVerticalScrollPhysics]). So the spine pile takes a swipe while
      // it is long enough to move and hands it over when it is not.
      onHorizontalDragStart: interactive && _pagingEnabled
          ? _onPageDragStart
          : null,
      onHorizontalDragUpdate: interactive && _pagingEnabled
          ? _onPageDragUpdate
          : null,
      onHorizontalDragEnd: interactive && _pagingEnabled
          ? _onPageDragEnd
          : null,
      // Undershoot slides the sheet off the bottom of the screen, revealing the
      // library behind it, rather than shrinking it below the collapsed height.
      child: Transform.translate(
        offset: Offset(0, _slideDown),
        child: Padding(
          // The floating gap. Inside the gesture detector, so the gap drags the
          // sheet like the sheet does.
          padding: EdgeInsets.only(left: inset, right: inset, bottom: lift),
          child: DecoratedBox(
            // A rounded superellipse, not a circular-cornered rectangle: the
            // curvature is continuous, which is the corner iOS itself draws and
            // the only shape that does not read as slightly pinched at this
            // radius. It matters more once the card floats and all four corners
            // are visible against the library.
            decoration: ShapeDecoration(
              color: context.colors.surface,
              shape: RoundedSuperellipseBorder(borderRadius: radius),
              shadows: [
                BoxShadow(
                  // A floating card is lit from every side, so the shadow opens
                  // up and loses its upward offset as the sheet pulls in.
                  blurRadius: 6 + 6 * (1 - expansion),
                  offset: Offset(0, -3 * expansion),
                  color: Colors.black.withValues(alpha: 0.15),
                ),
              ],
            ),
            child: ClipRSuperellipse(
              // The clip **is** the card, all four corners, so content may run right
              // up to its bottom edge and under the floating tab bar. It used to sit
              // inside the padding below, which stopped content dead at the top of
              // the reserved band — the empty strip of card behind a translucent bar
              // that the reference does not have.
              borderRadius: radius,
              child: Padding(
                padding: EdgeInsets.only(bottom: reserve - lift),
                child: clipHeight == null
                    ? content
                    : SizedBox(
                        height: clipHeight,
                        // Keeps the content at its natural height while the box
                        // shrinks, so the overflow is simply clipped away.
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          minHeight: 0,
                          maxHeight: double.infinity,
                          child: content,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// How far the card's bottom edge rises off the screen's, given the [inset] the
  /// current position asks for and the [reserve] the sheet keeps below its
  /// content.
  ///
  /// Never more than the reserve, because the lift is *spent* out of it: the
  /// padding below the content shrinks by exactly what the outer gap grows by, so
  /// the sheet's total height — and therefore the library's — is the same at every
  /// position. A sheet with no reserve at all cannot lift without either moving
  /// its own content or eating into the library, and does neither.
  double _lift(double inset, double reserve) =>
      reserve <= 0 ? 0 : math.min(inset, reserve);

  /// The card's corners: concentric with the screen's own corner while the card
  /// floats, so the two arcs run parallel rather than one cutting across the other.
  /// See [_displayCornerRadius].
  ///
  /// **One arc, top and bottom.** Two radii on one card read as the card having the
  /// wrong shape whichever of them is the odd one out, and the top corners are the
  /// ones with nothing of their own to be: they sit in the middle of the screen, so
  /// the shape they should hold is the one the card is already showing below them.
  /// The pair therefore open together as the gap closes, from 55 - 14 while it
  /// floats to the display's own 55 once flush.
  ///
  /// The bottom is zero once flush, where the display's own mask draws that same
  /// arc. A radius of our own guessing at it would show as a sliver of library
  /// inside the corner on any device whose real radius is larger than the
  /// constant — and square is exactly right for the case a mask is about to round.
  /// The top has no mask to hand the job to, so it keeps drawing the arc itself.
  ///
  /// Never tighter than the card's own [_cornerRadius], which is what a screen with
  /// square corners falls back to: concentric with a square corner is a square
  /// corner, and a floating card with hard corners is not a card.
  BorderRadius _cornerRadii(BuildContext context, double lift) {
    final screen = MediaQuery.viewPaddingOf(context).bottom > 0
        ? _displayCornerRadius
        : 0.0;
    final concentric = screen - lift;
    final radius = concentric > _cornerRadius ? concentric : _cornerRadius;
    return BorderRadius.vertical(
      top: Radius.circular(radius),
      bottom: Radius.circular(lift <= 0 ? 0 : radius),
    );
  }

  /// Which body the sheet's current state shows: [LibrarySheet.body], or
  /// [LibrarySheet.collapsedBody] for a sheet that has one and is resting on it.
  ///
  /// A getter because a page turn has to capture the same answer [_buildContent] is
  /// rendering, and two copies of that rule would drift the moment a third state
  /// showed up.
  Widget get _bodyForState => _showExpanded || widget.collapsedBody == null
      ? widget.body
      : widget.collapsedBody!;

  /// [live] — the body the caller is showing now — over the page it is replacing,
  /// both offset from [_pageX] and always exactly one span apart. See [_turnPage].
  ///
  /// **Always a [Stack], even at rest with one page in it, and always keyed by page.**
  /// Both halves are load-bearing. A wrapper that appeared when a turn started would
  /// re-parent the body on that very frame and cost it the scroll offset the turn is
  /// supposed to be sliding away; and without keys, the [Stack] would match its
  /// children by position, so the arriving page would inherit the outgoing page's
  /// element and then be rebuilt again when the outgoing one is dropped.
  ///
  /// The consequence of keying by page is that a page change **remounts** the body,
  /// scroll offset and all. That is what the read view wants anyway and says so
  /// explicitly — a different filter is a different list, read from the top — and it
  /// is what the Card wants for the same reason.
  Widget _pages(Widget live) {
    // Between the swipe and the caller's rebuild the sheet is still holding the page
    // it is leaving as its *live* body, so it is drawn where the outgoing page
    // belongs and no second page exists yet. See [_turnPage].
    final turning = _outgoingPage;
    final arrived = turning != null && _outgoingIndex != widget.pageIndex;
    final outgoingX = _pageX - _pageDirection * _pageTravelSpan;
    return Stack(
      // Passes the sheet's own constraints straight through to both pages, so a single
      // page is laid out exactly as it would be with none of this here: tight on the
      // capped path, the content's own height on the uncapped one.
      fit: StackFit.passthrough,
      // The card's clip is what cuts a travelling page off. Clipping here would cut it
      // at the body's box instead, which is inside the shadows the covers cast.
      clipBehavior: Clip.none,
      children: [
        if (arrived)
          _page(
            index: _outgoingIndex,
            dx: outgoingX,
            // On its way out, so a tap on it would act on a year that is no longer
            // selected.
            inert: true,
            child: turning,
          ),
        _page(
          index: widget.pageIndex,
          dx: turning != null && !arrived ? outgoingX : _pageX,
          inert: false,
          child: live,
        ),
      ],
    );
  }

  /// One page in the [Stack] above.
  ///
  /// Every wrapper is unconditional — the translation at zero offset, the
  /// [IgnorePointer] that is not ignoring — because inserting or removing one would
  /// change the shape of the chain above the body and re-inflate it. That is the same
  /// rule the [Stack] itself is there for.
  Widget _page({
    required int index,
    required double dx,
    required bool inert,
    required Widget child,
  }) => KeyedSubtree(
    key: ValueKey(index),
    child: IgnorePointer(
      ignoring: inert,
      child: Transform.translate(offset: Offset(dx, 0), child: child),
    ),
  );

  /// [showing] is the height the sheet is currently showing, or `null` once settled
  /// at the top, where the cap is the height.
  Widget _buildContent(BuildContext context, double reserve, double? showing) {
    final interactive = !widget.isEditMode;
    final expanded = _showExpanded;
    final header = expanded
        ? (widget.expandedHeader ?? widget.header)
        : widget.header;

    final chrome = Column(
      key: _headerKey,
      mainAxisSize: MainAxisSize.min,
      // Load-bearing, and its absence showed as a **centred title**. A Column's
      // default `center` hands its children loose cross-axis constraints, so a
      // header that shrink-wraps gets centred while one that fills the width does
      // not. The read view's header is a `Row` with `Expanded` children and the
      // Friends sheet's fills too, so both happened to look correct; the Card's
      // collapsed header is a bare `LibrarySheetTitle`, which is a
      // `Row(mainAxisSize: min)` — and it sat dead centre while the same title sat
      // hard left when expanded. Stretching here means a header is laid out in the
      // sheet's full width whatever shape it is, which is the only way every tab
      // can agree about where a title starts.
      //
      // Also widens the handle's tap target to the sheet, which is a real
      // improvement: `SheetGrabHandle` centres its own pill, so nothing moves.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          // The handle toggles the two ends: it opens a collapsed sheet fully and
          // puts any open one away. A medium detent is not a stop on that toggle,
          // which is also how iOS behaves — a tap that cycled all three would mean
          // two taps to put the sheet away, and putting the sheet away is the
          // handle's job. It stays reachable by dragging, and for the Card it is
          // where the sheet started.
          onTap: interactive
              ? () => _snapTo(
                  _detent == LibrarySheetDetent.collapsed
                      ? LibrarySheetDetent.expanded
                      : LibrarySheetDetent.collapsed,
                )
              : null,
          child: const SheetGrabHandle(),
        ),
        Padding(
          padding: const EdgeInsets.only(
            left: _gutter,
            right: _gutter,
            bottom: 6,
          ),
          child: header,
        ),
      ],
    );

    // Swap only when there is something to swap to. Without a `collapsedBody`
    // this keeps Phase 1's behaviour exactly: one body, always rendered, clipped
    // by the box as it shrinks. Swapping it for an empty box instead would make
    // the measured natural height collapse with the sheet, and it could never
    // expand again.
    final chosenBody = _bodyForState;

    // The sheet takes a swipe before the body does, until there is no more sheet to
    // open, and takes it back when the body runs out of offset going the other way.
    // See [_bodyMayScroll], [_onBodyScroll] and [_SheetBodyScrollBehavior] — and
    // [LibrarySheet.body] for the one thing a caller's scroll view has to do to let
    // this work (`primary: false`).
    final body = NotificationListener<ScrollNotification>(
      onNotification: _onBodyScroll,
      child: ScrollConfiguration(
        behavior: _SheetBodyScrollBehavior(mayScroll: _bodyMayScroll),
        // Inside the configuration and the listener rather than outside, so a page on
        // its way out is handed the same physics it had while it was the live one —
        // changing them mid-slide would re-layout a viewport nobody is looking at.
        child: _pages(chosenBody),
      ),
    );

    // Capped: the content is a fixed height and the body takes whatever the header
    // leaves, which is what gives a scrollable body a bounded height to scroll inside.
    // Uncapped keeps Phase 1's behaviour exactly — a min-sized column measured at its
    // natural height, clipped by [build] as the box shrinks.
    //
    // **The collapsed position takes the bounded path too, when the body itself is
    // what shows there.** A sheet with a separate [LibrarySheet.collapsedBody] swaps
    // in something naturally sized — the read view's pile — and an [Expanded] would
    // stretch it. A sheet without one shows the *same* scrollable body at every
    // position, and collapsed is then just a shorter viewport onto it: a partial row
    // clipped at the card's edge, which is what a collapsed sheet is supposed to look
    // like. Left on the uncapped path it got handed unbounded height instead, which a
    // `ListView` asserts on rather than laying out — and working around *that* is what
    // had Friends rendering a separate strip of avatars at rest for one commit.
    //
    // **That height is the detent it is resting on, and the height of the state it is
    // *showing* while it moves.**
    //
    // At rest it has to be the visible height: clipped from the cap instead, the body's
    // viewport at the medium detent would be a third taller than the card, so the last
    // rows would sit below the card's bottom edge with no scroll offset able to bring
    // them up.
    //
    // While the sheet is moving it used to be the cap unconditionally, and that quietly
    // destroyed the body's scroll offset. A viewport laid out at the cap while the
    // sheet is barely off its collapsed position is tall enough to hold the whole list,
    // so `maxScrollExtent` goes to zero, the offset is clamped to zero with it, and the
    // list is back at the top by the time the sheet settles — measured on Friends with
    // seven friends: viewport 115 → 501, max 349 → 0, offset 40 → 0, on the *first*
    // frame of a 30pt drag. So the height follows [_showExpanded] instead: whichever
    // state's header and body are on screen, the box is the one that state rests at.
    //
    // That is also what keeps the `RenderFlex` overflow away, and more precisely than
    // the cap did. The overflow case is the *expanded* header rendered inside the
    // *collapsed* box — the extra frame [_snapTo] inserts to measure a new header, 61pt
    // of it on the Card. Here the expanded header only ever appears with [_showExpanded]
    // true, which is the cap; the collapsed header appears with [_minHeight], which is
    // that header plus the collapsed body by construction. Neither can be starved.
    final cap = widget.expandedExtent;
    final Widget content;
    if (cap != null && (expanded || widget.collapsedBody == null)) {
      final boxHeight = _atRest
          ? (showing ?? cap)
          : (_showExpanded ? cap : _minHeight);
      // What the card is showing of that box, as a signed difference: the box is laid
      // out at the height of the *state* on screen (see above) while the card is
      // clipped at the height the sheet currently *is*, so a moving sheet is almost
      // always showing less of the body than the body was laid out at. Published
      // below as [SheetBodyViewport] for the bodies that have to place something
      // against the visible slice rather than against their own box — an empty
      // state's centre, which would otherwise sit wherever the box happens to be and
      // jump every time the sheet settles.
      final visibleDelta = (showing ?? cap) - boxHeight;
      content = SizedBox(
        height: boxHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            chrome,
            // The viewport runs [reserve] past the bottom of the content box and is
            // clipped at the card's edge instead, so rows pass under the floating
            // tab bar rather than stopping above it. The box itself does not grow,
            // which is why this is an overflow and not a taller `SizedBox`: every
            // snap position, and the height the library is left, are measured in
            // content that excludes the band.
            //
            // The body's own bottom scroll padding is what keeps its last row
            // reachable, and it has to be the same number — see [bottomReserve].
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // `constraints.maxHeight` is the box less the chrome, laid out
                  // this frame — which is why the visible slice is derived here
                  // rather than from [_measure]. The header's height changes with
                  // the state and with the text scale, and a number taken from the
                  // previous frame's header would be wrong by the difference on
                  // exactly the frame the two states swap.
                  final viewport = SheetBodyViewport(
                    visibleExtent: constraints.maxHeight + visibleDelta,
                    child: body,
                  );
                  return reserve <= 0
                      ? viewport
                      : OverflowBox(
                          alignment: Alignment.topCenter,
                          minHeight: constraints.maxHeight + reserve,
                          maxHeight: constraints.maxHeight + reserve,
                          child: viewport,
                        );
                },
              ),
            ),
          ],
        ),
      );
    } else {
      // Uncapped, and the collapsed sheet showing its [LibrarySheet.collapsedBody]:
      // the body is handed its natural height and the card is whatever that comes to,
      // so the slice it can see is the card's height less the chrome. Measured, since
      // there is no box of our own making to read it off.
      //
      // Withheld until both numbers are real. On the first frame the header has no
      // size yet and [_clipHeight] is null for a sheet whose position has not been
      // applied — [_travel] would answer with the cap, and a body that sized itself
      // to the whole band there would flash it for a frame before the sheet dropped
      // to its collapsed position. `_syncAfterLayout` brings the rebuild that fills
      // this in, one frame later.
      final headerExtent = _measure(_headerKey);
      final visible = showing == null || headerExtent <= 0
          ? null
          : showing - headerExtent;
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          chrome,
          if (visible == null)
            body
          else
            SheetBodyViewport(visibleExtent: visible, child: body),
        ],
      );
    }

    return KeyedSubtree(key: _contentKey, child: content);
  }
}

/// Turns the body's scrolling on and off, so the sheet can take a swipe first.
///
/// A [ScrollBehavior] rather than a `physics:` argument on each tab's scroll view, and
/// the reason is not the obvious one. A view's own `physics` does not *replace* the
/// ambient one — `applyTo` makes the ambient one its **parent** — and
/// `shouldAcceptUserOffset`, which is the only question that matters here, is answered
/// by whichever link in that chain overrides it. Most physics do not, so the gate holds
/// through them: a body may state `ClampingScrollPhysics` and still be frozen. Only
/// [AlwaysScrollableScrollPhysics] and [NeverScrollableScrollPhysics] override it, so
/// `Always` is the one thing that overrules the sheet.
///
/// Which is unfortunately the *default*. [ScrollView]'s constructor — not its `build` —
/// substitutes `AlwaysScrollableScrollPhysics` for an unset `physics` whenever the view
/// is vertical with no controller and no `primary`, so iOS's tap-the-status-bar-to-go-top
/// keeps working on the page's main list. That is why a scrolling body has to pass
/// **`primary: false`**, and why forgetting it looks like this class never took effect at
/// all: the list scrolls at every detent and the sheet never gets a swipe.
/// [PrimaryScrollController.none] does not help — it clears the controller, and the
/// physics were already decided. `SingleChildScrollView` has no such default, which is
/// why the Card's body needs nothing.
///
/// Clamping rather than the platform default when scrolling *is* allowed, and that is
/// load-bearing: an iOS bouncing overscroll rubber-bands the list at its top edge and
/// reports nothing to hand over, so the sheet could never take the drag back. Clamped,
/// the same gesture reports overscroll and the sheet follows the finger down — which is
/// also what iOS itself does with a sheet's scroll view. It reaches the horizontal lists
/// inside a body too, which is no loss: every other horizontal list in the app states
/// clamping itself.
///
/// See [_LibrarySheetState._bodyMayScroll].
class _SheetBodyScrollBehavior extends ScrollBehavior {
  final bool mayScroll;

  const _SheetBodyScrollBehavior({required this.mayScroll});

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    const allowed = ClampingScrollPhysics();
    return mayScroll
        ? allowed
        : const _NoVerticalScrollPhysics(parent: allowed);
  }

  @override
  bool shouldNotify(_SheetBodyScrollBehavior old) => old.mayScroll != mayScroll;
}

/// Refuses a vertical drag and passes everything else through — a
/// [NeverScrollableScrollPhysics] that only says no on the axis the sheet moves on.
///
/// The axis matters because a [ScrollConfiguration] reaches every scroll view under it,
/// not just the one the sheet is coordinating with, and one of the bodies *is* a
/// horizontal list: `ReadPile`, the read view's collapsed spine pile, states no physics
/// of its own and so takes whatever the sheet's behaviour hands it. Blanket
/// `NeverScrollableScrollPhysics` froze it solid at the very position it exists for.
///
/// Deferring to `super` for the horizontal case rather than returning a bare `true`
/// keeps the ordinary rule with it: a list with nothing to scroll still declines the
/// drag, so a pile shorter than its viewport does not swallow one.
class _NoVerticalScrollPhysics extends ScrollPhysics {
  const _NoVerticalScrollPhysics({super.parent});

  @override
  _NoVerticalScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _NoVerticalScrollPhysics(parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      position.axis == Axis.horizontal &&
      super.shouldAcceptUserOffset(position);
}

/// The grab handle at the top of a sheet.
///
/// Shared with the Add Book modal, which draws its own rather than using
/// Material's `showDragHandle`: that one is added outside the builder's child, so
/// it silently adds its height to a sheet asked for an exact fraction of the
/// screen — a 95% sheet came out at ~98% with no barrier left to see.
class SheetGrabHandle extends StatelessWidget {
  const SheetGrabHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: context.colors.secondaryText,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

/// How much of a [LibrarySheet]'s body is **on screen**, measured from the body's
/// own top edge.
///
/// The body is laid out at the height of the state it is showing rather than at the
/// height the sheet currently is — that is what keeps a scrollable body's offset
/// alive through a drag, and [_LibrarySheetState._buildContent] explains why at
/// length. The consequence is that a moving sheet clips its body: the box is (say)
/// the whole band while the card is halfway up it, and anything a body places
/// against its *box* therefore sits somewhere off screen until the sheet settles.
///
/// Which is invisible for a list — the rows that matter are at the top — and very
/// visible for anything centred, or for anything that belongs at the *bottom* of the
/// card. This is what a body reads instead. See [SheetBodyCenter] for the centred
/// case, and `ReadPile`, which grows to this so its shelf stays at the bottom edge
/// while the sheet is dragged up rather than leaving empty card below it.
///
/// Published by both paths, and derived differently by each. The capped one reads its
/// own box against the height the card is showing; the uncapped one — an uncapped
/// sheet, or a collapsed sheet showing its [LibrarySheet.collapsedBody] — has no box
/// of its own and measures the chrome instead. Absent for a frame or two on either
/// path before the sizes are real; consumers fall back to their natural layout there,
/// which is the layout the collapsed position is defined in terms of anyway.
class SheetBodyViewport extends InheritedWidget {
  /// Height of the body's visible slice, from its top edge down. May exceed the
  /// body's own box — a sheet dragged up from its collapsed position shows card
  /// below the body it was laid out at — and may be a good deal shorter than it.
  final double visibleExtent;

  const SheetBodyViewport({
    super.key,
    required this.visibleExtent,
    required super.child,
  });

  static double? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SheetBodyViewport>()
      ?.visibleExtent;

  @override
  bool updateShouldNotify(SheetBodyViewport oldWidget) =>
      oldWidget.visibleExtent != visibleExtent;
}

/// Centres [child] in the part of a [LibrarySheet]'s body that is on screen, rather
/// than in the box the body was laid out at.
///
/// For the sheets' empty states — a line of text, or a short stack of them, with a
/// whole body to sit in. Centred in the box, that line moved in steps rather than with the
/// sheet: it sat at the middle of the *expanded* body for the whole of a drag —
/// halfway down a card that was not open yet, or below its bottom edge entirely —
/// and then jumped the moment the sheet settled on a detent, because settling is
/// where the box stops being the cap and becomes the visible height. Two jumps per
/// drag, both of them the text apparently deciding to move on its own.
///
/// Against the visible slice it simply tracks the card: it is centred at every
/// height the sheet passes through, so there is nothing left to jump. The slice is
/// [SheetBodyViewport]'s, which the sheet republishes every frame of a drag or a
/// spring.
///
/// An [OverflowBox] rather than a [SizedBox], because the slice is sometimes taller
/// than the box: a sheet dragged up from collapsed shows card below its body, and a
/// clamped height would stall the text there and then jump it. Drawing past the box
/// is safe — the card's own clip is exactly the visible slice.
///
/// **Centred when it fits, scrolled from the top when it does not**, and the second
/// half is not hypothetical. This pinned its child to the slice's exact height, which
/// is right for one line and wrong the moment an empty state is a heading, a sentence
/// and a button: the collapsed detent is a fifth of the screen, so Friends' no-friends
/// state overflowed by 20pt and put its call to action off the bottom of the card. A
/// large text scale does the same thing to a single line on a small phone.
///
/// Centring is the default and stays the default — an empty state is one small thing
/// in a large space, and pinning it to the top would waste the space at every detent
/// to survive the shortest one. The scroll view only earns its keep in the cases that
/// would otherwise clip, and in those it is strictly better than the alternatives:
/// shrinking the type, or letting the reader reach nothing.
class SheetBodyCenter extends StatelessWidget {
  final Widget child;

  const SheetBodyCenter({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final visible = SheetBodyViewport.maybeOf(context);
    if (visible == null || visible <= 0) return Center(child: child);
    return OverflowBox(
      alignment: Alignment.topCenter,
      minHeight: visible,
      maxHeight: visible,
      // The standard centre-or-scroll idiom, and each of the three pieces is
      // load-bearing. The scroll view hands its child unbounded height, so nothing
      // can overflow; the `minHeight` puts that height back up to the slice, so
      // [Center] has the full slice to centre within whenever the child is smaller
      // than it; and when the child is larger the constraint is simply exceeded and
      // the content scrolls instead of being clipped.
      child: SingleChildScrollView(
        // Lets [LibrarySheet] decide whether a swipe scrolls this or opens the
        // sheet, the same reason the bodies' own lists pass it: without it the
        // constructor adopts the primary controller and always-scrollable physics,
        // and a drag on an empty state would fight the sheet instead of moving it.
        primary: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: visible),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// The title-and-count pair every sheet header opens with, so the three tabs
/// share one type size and one spacing rather than three approximations of it.
class LibrarySheetTitle extends StatelessWidget {
  final String title;

  /// Drawn in the brand colour beside [title]. Omitted when there is nothing to
  /// count (the Card tab).
  final int? count;

  const LibrarySheetTitle({super.key, required this.title, this.count});

  @override
  Widget build(BuildContext context) {
    const style = AppTextStyles.subtitle;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Flexible, not fixed: at accessibility text sizes a 17pt semibold title
        // plus whatever sits beside it in the header overflowed the row outright.
        Flexible(
          child: Text(
            title,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 12),
          Text(
            '$count',
            // `subtitle` carries no `tabularFigures`, and it does not need to:
            // this count sits at the *end* of a `MainAxisSize.min` row, so it has
            // nothing to its right to nudge. The counts that did need fixed-width
            // digits are the ones in a column — see `ReadMonthGrid`.
            style: style.copyWith(color: context.colors.brandText),
          ),
        ],
      ],
    );
  }
}
