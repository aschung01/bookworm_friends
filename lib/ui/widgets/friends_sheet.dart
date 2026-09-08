import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/friend_reading.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/ui/widgets/avatar_circle.dart';
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';

/// The Friends tab's sheet: everyone you follow, and the way into a visit.
///
/// **The shell's one switcher.** It is how a visit begins, how you move from one
/// friend to another, and — since it stays reachable inside a visit — the only
/// control that changes whose library is on screen. The `FriendRail` and the lateral
/// swipe that used to share that job are gone: a swipe with no affordance moved
/// people somewhere they had not asked to go, and the rail was a map of the same set
/// this list already names.
///
/// **Capped like the other two tabs.** It used to be the one uncapped sheet, laid
/// out at its own natural height with no ceiling and no scroll view of its own —
/// which was fine for a handful of friends and unbounded for anyone with a lot of
/// them: nothing scrolled, so past a certain list length the top of the sheet, header
/// included, simply ran off the top of the screen with no way back. It now takes the
/// same expanded/medium/full trio the read view and the Card do, so it gets the same
/// three snap positions and the same full-band ceiling, and the list itself scrolls
/// inside that ceiling via a lazy `ListView.builder`.
///
/// **One list at every position.** Unlike the read view there is no second, collapsed
/// body: the same rows show whether the sheet is resting, at the middle detent or at
/// the cap, and collapsing only shortens the viewport onto them. See
/// [LibrarySheet.collapsedBody].
///
/// **Not drawn as designed, deliberately.** The mockup's Everyone row carries
/// what each friend is reading and their read count. Both are per-friend queries
/// — `userLibraryProvider` and `userFinishedBooksProvider` are keyed by user id —
/// so rendering them here means one round trip per row, fired the moment the tab
/// opens. That wants a single batched query, which is a data change, and Phase 1
/// is the shell only. The row is name and avatar until that query exists; it is
/// already enough to be the entry point to a visit, which is what the shell needs
/// from it. Same reason the design puts the Activity capsule after Phase 1.
class FriendsSheet extends StatelessWidget {
  final List<Profile> following;

  /// The friend currently being looked at, ringed in the list, or `null` when you
  /// are in your own library.
  final Profile? selectedFriend;

  final ValueChanged<Profile> onSelectFriend;
  final VoidCallback onAddFriend;

  /// Height available to the whole sheet — the band it shares with the library. The
  /// expanded cap and the medium detent are both taken from this. See
  /// [sheetExpandedExtent].
  final double maxExtent;

  /// Springs the sheet shut and goes inert while the library is being edited.
  ///
  /// An edit can be started from any tab, so every sheet has to get out of the
  /// way — not just the read-books one. Left expanded, this sheet would sit there
  /// at full height taking room the library needs to be rearranged in.
  final bool isEditMode;

  /// See [LibrarySheet.bottomReserve].
  final double bottomReserve;

  /// See [LibrarySheet.onRestingExtent].
  final ValueChanged<double>? onRestingExtent;

  /// What each friend is reading and has read, keyed by friend id.
  ///
  /// Empty while [friendsReadingProvider] is in flight, which is why the row treats a
  /// missing key as "loading" and [FriendReading.none] as "loaded and empty". One
  /// batched query fills this for the whole list — see the provider's doc for why the
  /// drawn row could not ship in Phase 1.
  final Map<String, FriendReading> reading;

  /// The shell's shared sheet key, handed to the [LibrarySheet] inside rather than to
  /// this widget — which is what makes a tab switch spring the sheet's height instead
  /// of jumping it. See [LibrarySheet].
  final Key? sheetKey;

  const FriendsSheet({
    super.key,
    required this.following,
    required this.selectedFriend,
    required this.onSelectFriend,
    required this.onAddFriend,
    required this.maxExtent,
    this.reading = const {},
    this.isEditMode = false,
    this.bottomReserve = 0,
    this.onRestingExtent,
    this.sheetKey,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // What the *content* may occupy: the sheet keeps the tab bar's band and the home
    // indicator below the collapsible area, so both come off the top. Same shape as
    // `FinishedBooksSheet`'s and `LibraryCardSheet`'s `available`.
    final available =
        maxExtent - bottomReserve - MediaQuery.viewPaddingOf(context).bottom;

    return LibrarySheet(
      key: sheetKey,
      // See [LibrarySheet.contentId] — the sheet's own identity, so a tab switch is
      // told apart from a rebuild.
      contentId: FriendsSheet,
      isEditMode: isEditMode,
      bottomReserve: bottomReserve,
      onRestingExtent: onRestingExtent,
      // **No `collapsedBody`, deliberately.** Friends shows the same list at every
      // position; collapsed is just a shorter viewport onto it, with the row it cuts
      // through clipped at the card's edge. That is what `LibrarySheet` does with a
      // capped sheet that states no collapsed body of its own — there is nothing here
      // worth swapping in the way the read view has its pile, and a strip of avatars
      // with no names beside them is worse than the list itself.
      //
      // That last clause used to point at the rail as the thing it was declining to
      // become. The rail no longer exists, and the reasoning survives it: what a
      // collapsed switcher would have to show is *names*, and at the shared 20% floor
      // this sheet has room for 1.6 rows of them. The sheet opens at the medium detent
      // instead, which is where the list is a list.
      initialDetent: LibrarySheetDetent.medium,
      fullExtent: maxExtent,
      expandedExtent: sheetExpandedExtent(available),
      midExtent: sheetMidExtent(available),
      minHeightFraction: sheetMinHeightFraction,
      header: Row(
        children: [
          Expanded(
            child: LibrarySheetTitle(
              title: l10n.friends,
              count: following.length,
            ),
          ),
          // **Invite, not search.** This used to open `search_user_page`, and its
          // tooltip said so. Both senses of that are now wrong: there is no handle
          // search, and the only way to gain a friend is to send someone a link.
          // `person_add_alt` survives the change because the *meaning* did not — it
          // was never a magnifying glass.
          //
          // Glass, like every other sheet-header action in the app — Add Book's
          // scanner and close, Manage Shelves' close. A sheet corner is the right
          // place for it: this is the header's only action, so it cannot invert the
          // hierarchy against the title beside it.
          //
          // `person.badge.plus` is the SF Symbol counterpart of `person_add_alt`,
          // checked rather than recalled per the warning `native_glass.dart` gives
          // twice: a symbol name that does not exist is dropped silently and leaves
          // the disc empty. It has existed since SF Symbols 1.
          //
          // The default 40pt diameter is what `VisualDensity.compact` gave the
          // `IconButton` this replaces, so the collapsed detent — which is measured
          // from this row's height — does not move.
          AdaptiveIconButton(
            symbol: 'person.badge.plus',
            icon: Icons.person_add_alt,
            // Doubles as the Material fallback's tooltip, which is what the old
            // `tooltip:` was and what `friends_empty_states_test` looks for.
            semanticLabel: l10n.inviteFriends,
            onPressed: isEditMode ? null : onAddFriend,
          ),
        ],
      ),
      // Lazy, like `ReadMonthGrid`: the sheet hands this a bounded height once
      // expanded, so only the rows that fit get built rather than every avatar and
      // subtitle a heavy follower has the moment the tab opens.
      //
      // The bottom padding is the band the tab bar floats in, same number as
      // `bottomReserve` elsewhere: the viewport reaches the card's bottom edge, so
      // this is what keeps the last row clear of the bar once the list is long
      // enough to scroll.
      body: following.isEmpty
          ? _NoFriends(onInvite: isEditMode ? null : onAddFriend)
          : ListView.builder(
              // Lets `LibrarySheet` decide whether a swipe scrolls this or opens the
              // sheet: without it the constructor bakes in
              // `AlwaysScrollableScrollPhysics` and the list scrolls at every detent.
              // See [LibrarySheet.body].
              primary: false,
              padding: EdgeInsets.only(
                bottom:
                    6 +
                    bottomReserve +
                    MediaQuery.viewPaddingOf(context).bottom,
              ),
              itemCount: following.length,
              itemBuilder: (context, index) {
                final friend = following[index];
                return _FriendRow(
                  friend: friend,
                  isSelected: friend.id == selectedFriend?.id,
                  reading: reading[friend.id],
                  // Inert with the rest of the sheet: leaving an edit by
                  // opening someone else's library is not a way out anyone
                  // asked for.
                  onTap: isEditMode ? null : () => onSelectFriend(friend),
                );
              },
            ),
    );
  }

  // **There is no "nobody is mid-book" banner, and there was one for a day.**
  //
  // The drawings call for a second empty state, and the reasoning behind it is sound:
  // for a reading app, friends with nothing in progress is the common state rather
  // than the edge case. But it was drawn against a row that shows a *read count* — a
  // row that says nothing about whether the person is reading right now — and the row
  // this app actually ships already prints `friendNothingInProgress` on its own second
  // line. With three friends idle the sheet said it four times: once per row, then
  // again in a banner summarising the rows immediately beneath it.
  //
  // A summary earns its place when it tells you something the list does not. This one
  // could not: the list is right there, every row already answers the question, and
  // the banner had no action to offer either — inviting is not the fix for friends who
  // are between books. So the state stays; it is just already expressed, by the rows.
  //
  // If the row ever loses that second line, this is the note to come back to.
}

class _FriendRow extends StatefulWidget {
  final Profile friend;
  final bool isSelected;
  final VoidCallback? onTap;

  /// What this friend is reading and how many books they have read.
  ///
  /// Null while the batched query is in flight — distinct from
  /// [FriendReading.none], which means "loaded, and there is nothing". The row
  /// renders the same height either way; see the subtitle below.
  final FriendReading? reading;

  const _FriendRow({
    required this.friend,
    required this.isSelected,
    required this.onTap,
    this.reading,
  });

  @override
  State<_FriendRow> createState() => _FriendRowState();
}

class _FriendRowState extends State<_FriendRow>
    with SingleTickerProviderStateMixin {
  /// Whether a finger is currently down on this row.
  ///
  /// Tracked from **raw pointer events** rather than `onTapDown`, for the same reason
  /// `_Capsule` does it: the tap may not be ours. [AvatarCircle] carries its own
  /// gesture detector and wins the arena for taps that land on it, which would leave
  /// `onTapDown` unfired and the row looking dead when you press the very thing that
  /// most looks pressable. Pointer events arrive either way.
  bool _pressed = false;

  /// How long the highlight takes to appear and fade. Matches `_Capsule`'s press.
  static const Duration _pressDuration = Duration(milliseconds: 110);

  /// Inset of the highlight from the sheet's edge, and its own padding, which add up
  /// to the 25pt gutter the row's content sat at before. Keeping that sum fixed is
  /// what stops the highlight shifting the text sideways.
  static const double _highlightInset = 13;
  static const double _contentInset = 12;

  /// Turns the row's miniature book, on exactly the shelf's timings.
  ///
  /// Lives here rather than inside [BookWidget] because the gesture is the row's:
  /// the finger is nearly always on a name, not on the book at the end of the row,
  /// so the book's own recogniser never sees it.
  ///
  /// Created in [initState] and not as a `late final` initialiser. [dispose] reads it,
  /// so a row that was never tapped would otherwise *construct* the controller while
  /// unmounting, and creating a ticker reads `TickerMode.of(context)` from an element
  /// that is already defunct.
  late final AnimationController _turn;

  @override
  void initState() {
    super.initState();
    _turn = AnimationController(vsync: this, duration: kBookTurnDuration);
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  void _setPressed(bool pressed) {
    // Gated on the callback rather than on a disabled flag: during an edit the sheet
    // is inert as a whole, and a row that highlighted under the finger while doing
    // nothing would be a worse lie than one that ignores you.
    if (widget.onTap == null || _pressed == pressed) return;
    setState(() => _pressed = pressed);
    _driveTurn(pressed);
  }

  /// Turns the miniature book while the row is held, and lets it fall back on release.
  ///
  /// Driven by the press and **not** by the tap, which is not where this started. A tap
  /// looked like the right trigger — it is the moment worth marking, and the sheet
  /// appeared to stay put. It does not: `onSelectFriend` also flips the library mode, so
  /// the shell swaps the Friends sheet for the library and the friend rail within a
  /// frame or two. The row unmounts, and a turn played on tap is never seen by anyone.
  /// Found by tapping a row on the device and screenshotting what should have been the
  /// middle of the animation — a different screen entirely.
  ///
  /// One deliberate difference from the shelves: no [kBookHoldDelay]. There the delay
  /// exists so an ordinary tap produces no rotation, because the book stays on screen
  /// and the turn means "keep holding, something is about to happen". Here holding
  /// longer changes nothing, and release navigates away, so a delay would mean an
  /// ordinary tap showed no motion at all. The angle, timings and curve are the shelf's.
  void _driveTurn(bool pressed) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    if (pressed) {
      _turn.forward();
    } else {
      _turn.animateBack(
        0,
        duration: kBookReleaseDuration,
        curve: Curves.easeOut,
      );
    }
  }

  /// Selecting a friend, from either the row or the avatar inside it.
  ///
  /// Shared so the haptic fires whichever of the two won the gesture. Without that,
  /// tapping the name buzzes and tapping the avatar does not.
  void _activate() {
    if (widget.onTap == null) return;
    // A selection, and the same feedback the filter capsules give: this swaps the
    // whole library behind the sheet, which is worth feeling.
    HapticFeedback.selectionClick();
    widget.onTap!();
  }

  /// Manage this friend.
  ///
  /// **The gesture survives; what it opens does not.** This was `friend_info_dialog`,
  /// inherited from the deleted `FriendRail`, showing a follower/following pair that
  /// a mutual model makes one number. `ManageFriendPage` replaces it, and the gear in
  /// the visit bar is what *advertises* it — a long press with nothing pointing at it
  /// is not an affordance, which is why the gear had to exist regardless. This stays
  /// as the shortcut for people who already know it is here.
  ///
  /// Wired on the row *and* on the avatar for the same reason [_activate] is:
  /// [AvatarCircle] carries its own recogniser and wins the arena for gestures that
  /// land on it, so a long press on the avatar would otherwise do nothing.
  ///
  /// Gated on [_FriendRow.onTap] like every other gesture here: during an edit the
  /// sheet is inert as a whole.
  void _showInfo() {
    if (widget.onTap == null) return;
    Navigator.pushNamed(
      context,
      AppRoutes.manageFriend,
      arguments: widget.friend,
    );
  }

  /// The row's second line.
  ///
  /// Three states, all of them drawn in the `EVERYONE` fixture: several titles joined
  /// with a middle dot (`minho` is `Reading Snow · Circe`, so more than one at a time
  /// is a normal state), a placeholder when nothing is in progress (`sora`), and an
  /// empty string while loading.
  ///
  /// Goes through `friendReading` rather than concatenating a prefix, because Korean
  /// puts the verb last — `'{titles} 읽는 중'` — and `'Reading ' + titles` cannot
  /// express that.
  String _subtitle(AppLocalizations l10n) {
    final reading = widget.reading;
    if (reading == null) return '';
    if (!reading.hasInProgress) return l10n.friendNothingInProgress;
    return l10n.friendReading(
      reading.inProgress.map((book) => book.title).join(' · '),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);
    final reading = widget.reading;
    final cover = reading != null && reading.hasInProgress
        ? reading.inProgress.first
        : null;

    // `surfaceVariant`, deliberately not `sheetBackground`. The drawing spends
    // `sheetBg` on `.erow.hit` — the friend whose library you are currently visiting —
    // so a press tinted the same would be indistinguishable from "selected", and would
    // read as though the tap had already taken effect. This is the stronger of the two,
    // which is also the right way round: a press is transient and has to be felt
    // immediately, while a selection can afford to be quiet.
    final tint = colors.surfaceVariant;

    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: GestureDetector(
        // Opaque, so the whole row answers a tap and not only the glyphs in it.
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null ? null : _activate,
        onLongPress: widget.onTap == null ? null : _showInfo,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _highlightInset),
          child: AnimatedContainer(
            duration: _pressDuration,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              // **Fades to a transparent `tint`, never to `Colors.transparent`.**
              // `Colors.transparent` is `0x00000000` — transparent *black* — and
              // `Color.lerp` walks the RGB channels alongside the alpha, so a fade from
              // it to a light grey passes through semi-opaque **dark** grey. On a
              // device that reads as the row flashing dark for a moment and then
              // settling lighter, which is exactly what it did. Holding the RGB fixed
              // and moving only alpha makes it a clean fade in and out.
              //
              // Not caught by the press tests as first written: they asserted the tint
              // was present, then absent, and never looked at a frame in between. The
              // mid-animation assertion pins it — on `Colors.transparent` that frame
              // measures RGB 0.48, a mid grey exactly halfway to black.
              color: _pressed ? tint : tint.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _contentInset,
                vertical: 8,
              ),
              child: Row(
                children: [
                  AvatarCircle(
                    emoji: widget.friend.emoji,
                    avatarPath: widget.friend.avatarPath,
                    isSelected: widget.isSelected,
                    onTap: _activate,
                    onLongPress: _showInfo,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.friend.username ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.subtitle,
                        ),
                        // Always rendered, even while loading, and that is what keeps
                        // the row's height constant. An empty string still occupies
                        // one line at this size, so the list does not jump when the
                        // query lands — which it would for every row at once.
                        Text(
                          _subtitle(l10n),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.label.copyWith(
                            color: colors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (cover != null) ...[
                    const SizedBox(width: 10),
                    _MiniBook(book: cover, turn: _turn),
                  ],
                  // The count replaces the chevron the row used to carry. The drawing
                  // has no chevron — `.ecnt` is the trailing element — and the row is
                  // pressable as a whole, so the affordance is the highlight rather
                  // than an arrow.
                  if (reading != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      '${reading.finishedCount}',
                      style: AppTextStyles.label.copyWith(
                        color: colors.brandText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The book beside a friend's name, showing what they are part-way through.
///
/// **The same [BookWidget] the shelves draw, at a fraction of the size** — same cover,
/// same 3D chassis, same page block and back board, same ISBN-hashed height and
/// page-count thickness. Not a lookalike: a miniature of the identical object, so a
/// book you recognise from a shelf is recognisably that book here.
///
/// This reverses an earlier decision, and it is worth saying why rather than quietly
/// overwriting it. The first build used the real thing, the second cut back to a bare
/// colour swatch because `GeneratedCover` sets its title at 13.5% of the width — 3pt on
/// a 22pt swatch, an illegible smudge on the device — and the drawing specified
/// `.cv { width:10px; height:15px; background:<colour> }` with no text in it. That
/// reasoning was sound about the *type* and wrong about the *book*: it threw away the
/// chassis to solve a font-size problem. Reinstated at an explicit request, with the
/// height raised so the type has somewhere to go.
///
/// Two of the old objections do genuinely not apply here:
///
/// - **Jitter.** The read grid's bug was a *row* of books at hashed heights reading as
///   misalignment. There is one book per row here, and the row's height is set by the
///   40pt avatar, so a book between 32 and 36pt cannot move it — the height-stability
///   test still holds. Keeping the jitter is what makes the thickness reflect the real
///   page count, which is most of what makes it the same book.
/// - **The press and turn animations.** [BookWidget.pressEffect] is off, because the
///   finger is on the row and not on this. The turn is driven from the row instead, so
///   it plays on the tap that visits the friend.
class _MiniBook extends StatelessWidget {
  final Book book;

  /// The row's turn, 0 to 1.
  final Animation<double> turn;

  /// Base height before jitter, against the row's 40pt avatar.
  ///
  /// Up from the swatch's 32pt for the sake of the generated cover's title, which is a
  /// proportion of the width: this is the difference between roughly 3pt of type and
  /// roughly 4pt. Small, and it does not make a coverless book's title *readable* —
  /// nothing at this scale would. What it buys is type that reads as the texture of a
  /// cover rather than as a smear, which is how it looks on a shelf across the room.
  static const double _height = 34;

  const _MiniBook({required this.book, required this.turn});

  @override
  Widget build(BuildContext context) {
    return BookWidget(
      height: _height,
      imageUrl: book.thumbnail,
      isbn: book.isbn,
      title: book.title,
      pageCount: book.pageCount,
      turnDrive: turn,
      // The row owns the gesture; this must not compete for the pointer.
      pressEffect: false,
    );
  }
}

/// No friends at all, and the one action that changes it.
///
/// **The sheet's one empty state, and the only one that earns a CTA.** An invite is
/// the only way anyone gains a friend now — handle search is gone — so a reader with
/// an empty list has exactly one thing to do, and this says what it is. The header's
/// ✉ does the same job, but a 22pt icon in a corner is not an answer to a blank
/// sheet.
///
/// The state that *was* here alongside it — friends, none of them mid-book — is gone;
/// see the note on [FriendsSheet] for why the rows already say it.
class _NoFriends extends StatelessWidget {
  /// Null during an edit, which is when the whole sheet is inert.
  final VoidCallback? onInvite;

  const _NoFriends({required this.onInvite});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    // [SheetBodyCenter], like every other empty state: centred in the slice the card
    // is *showing* rather than in the box this was laid out at, which is what keeps
    // it tracking the sheet through a drag instead of jumping on each snap.
    //
    // **This state is what taught that widget to scroll.** It is three things
    // stacked, and the collapsed detent is a fifth of the screen — so pinned to the
    // slice's exact height it overflowed by 20pt and pushed the button off the card.
    // The fix belongs there rather than here: every empty state in the app has the
    // same floor under it, and a single line at a large text scale hits it too.
    return SheetBodyCenter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 12, 32, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.noFriendsYet,
              textAlign: TextAlign.center,
              style: AppTextStyles.subtitle,
            ),
            const SizedBox(height: 6),
            Text(
              l10n.noFriendsYetBody,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: colors.secondaryText),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onInvite,
              style: TextButton.styleFrom(
                backgroundColor: colors.brandFill,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(l10n.inviteFriends, style: AppTextStyles.label),
            ),
          ],
        ),
      ),
    );
  }
}
