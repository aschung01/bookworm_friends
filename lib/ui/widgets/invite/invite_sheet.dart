import 'dart:developer' as developer;
import 'dart:math';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/invite.dart';
import 'package:bookworm_friends/providers/invite_provider.dart';
import 'package:bookworm_friends/providers/shell_chrome_provider.dart';
import 'package:bookworm_friends/ui/widgets/avatar_circle.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book/generated_cover.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/shell_tab_bar.dart';

/// The base a token is appended to when a link is shared.
///
/// **A `https://` link, not the `bookworm-friends://` scheme the app already
/// registers.** The custom scheme works and is one line cheaper, and it is the wrong
/// thing to put in a message: it dies in in-app webviews — Kakao's included, which is
/// where most of these links will be tapped in this app's market — it cannot do
/// deferred install, and it renders in a chat as unlinked text nobody taps. A web URL
/// degrades into a landing page that can do all three.
///
/// Universal Links are wired: `ios/Runner/Runner.entitlements` claims
/// `applinks:libstack.app` and the AASA is served at that host, so on iOS a tapped link
/// opens the app and `InviteLinkService` routes it to consent. When the recipient does
/// not have the app the same URL degrades into the landing page, which hands them the
/// code and the App Store.
///
/// **Android App Links are deliberately absent** — `assetlinks.json` is keyed to a
/// package name plus signing certificate that `docs/APP_IDENTITY.md` expects to change
/// on Play re-registration, so publishing it now would pin it to a doomed value. The
/// link still works there, as a web page.
const String kInviteLinkBase = 'https://libstack.app/i/';

/// Create a link and hand it to the share sheet.
///
/// A modal rather than a page: inviting is an errand you come back from, and the
/// friends list behind it is the thing being added to.
Future<void> showInviteSheet(BuildContext context) {
  // Read from the calling context. `showModalBottomSheet` wraps its child in
  // `MediaQuery.removePadding(removeTop: true)`, which zeroes `viewPadding.top` as
  // well as `padding.top`, so the same read inside the builder measures 0. Same trap,
  // same fix as `showAddBookBottomSheet`.
  final topInset = max(MediaQuery.viewPaddingOf(context).top, 24.0);
  return CNBottomSheet.show<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.sheetBackground,
    builder: (ctx) => SizedBox(
      height: MediaQuery.sizeOf(ctx).height - topInset,
      child: const InviteSheet(),
    ),
  );
}

/// **Sells the payoff, not the link.**
///
/// The first draft of this was a URL in a read-only field with a Share button beside
/// it — an administrative screen for what is the app's only growth surface. Flighty's
/// equivalent shows neither a link nor a code: a globe carrying three friends' flights
/// with live status pills, then two paragraphs where the second is the emotional one.
/// This is that shape with a reading subject — three shelves, each with the status
/// this app actually reports.
///
/// **No code on this sheet, and no divergence from the reference at all.**
///
/// An earlier version showed the token below the button as "Or read them the code:
/// K7M2QP4X", tappable to copy, and called it a deliberate divergence: they have no
/// typed fallback and this app does, so a sender might read it down a phone. Both halves
/// of that were wrong.
///
/// The copy did not parse — "them" refers to nobody on a screen the sender is looking at
/// alone — and the sender never needs the code, because **the recipient gets it from the
/// landing page, not from the sender.** `libstack.app/i/<token>` prints it and copies it
/// to the clipboard inside the tap that leaves for the App Store; `InviteCodePage` reads
/// it back on first launch. The typed tier is real and complete, and none of it passes
/// through the sender's eyes. Reading eight characters down a phone was a scenario
/// invented to justify a control, not one anybody designed for.
///
/// So the sheet is the reference's shape exactly: mark, two paragraphs, contract, one
/// button.
class InviteSheet extends ConsumerStatefulWidget {
  const InviteSheet({super.key});

  @override
  ConsumerState<InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<InviteSheet> {
  /// True between the tap and the share sheet appearing.
  ///
  /// **The link is minted on tap, not when the sheet opens**, and the button is never
  /// disabled on arrival. It used to be the other way round: `create()` ran in
  /// `initState` and the button was gated on `activated: _invite != null`, so the sheet's
  /// only action arrived greyed out and came alive a second or more later. On a slow
  /// network that is a dead primary CTA on the screen that is the app's whole growth
  /// surface.
  ///
  /// The old justification was that "the code has to be on screen before anyone decides
  /// how to send it" — which stopped being true when the code came off the sheet. What
  /// was left of it was a fear of putting a spinner between the intention and the share
  /// sheet, and that has it backwards: **latency belongs after the commitment, not
  /// before it.** Nobody minds a moment's wait for something they just asked for; a
  /// button that cannot be pressed on arrival is a fault.
  ///
  /// Two things fall out for free. Opening and closing the sheet no longer writes a row
  /// to `friend_invites` — which matters more now that `create_invite()` mints on every
  /// call rather than reusing a live link. And it matches the reference, which hands out
  /// a new id when its button is pressed.
  bool _pending = false;

  /// Set when minting the link failed, and cleared on the next attempt.
  Object? _error;

  /// The button, so its rect can be handed to the platform as the popover anchor.
  /// See [_share].
  final _shareButtonKey = GlobalKey();

  /// The Share button's rect in global coordinates, or null before it has laid out.
  ///
  /// **Required on iPad, where the share sheet is a popover and must be anchored.**
  /// Without it `share_plus` does not fall back to something reasonable — it returns a
  /// `FlutterError` and never presents the sheet at all
  /// (`FPPSharePlusPlugin.m:378-393`: a zero `origin` plus a non-null
  /// `popoverPresentationController` is a hard refusal). This app builds for iPad
  /// (`TARGETED_DEVICE_FAMILY = "1,2"`), so an unanchored share is a guaranteed silent
  /// failure there. `share_library_card.dart` has always passed one; this did not.
  Rect? get _shareOrigin {
    final box =
        _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Mints a link and hands it to the platform's share sheet.
  ///
  /// **Everything here is error handling, and it is not defensive padding.** The first
  /// version was a bare `await Share.share(...)` whose result was discarded and whose
  /// exceptions went nowhere, which is precisely why "nothing happens" was the whole of
  /// the evidence when it did not work: `Share.share` is documented to throw
  /// `PlatformException`, and on iPad it reliably does. A share that fails must say so.
  ///
  /// The two failures are reported differently because the reader's next move differs. A
  /// link that could not be minted is shown inline above the button — tapping again is
  /// the retry. A share sheet that would not open is a toast, because the link is fine
  /// and nothing on the sheet needs to change.
  Future<void> _share(AppLocalizations l10n) async {
    // Guards a second tap while the RPC is in flight, which would mint a second link and
    // stack a second share sheet.
    if (_pending) return;
    setState(() {
      _pending = true;
      _error = null;
    });

    // Read before the await: on iPad the anchor has to be the button's rect, and
    // measuring it after the share sheet is up would find a stale one.
    final origin = _shareOrigin;

    // **Two try blocks, because the two failures are not the same event.** Minting is
    // ours and recoverable by tapping again; the share sheet is the platform's. Folding
    // them together would report "couldn't open the share sheet" for a link that was
    // never created, which sends the reader looking in the wrong place.
    final Invite invite;
    try {
      invite = await ref.read(inviteActionsProvider).create();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _pending = false;
        });
      }
      return;
    }
    if (!mounted) return;

    try {
      // `Share.share`, not `SharePlus.instance` — this is share_plus 10.x, where the
      // instance API does not exist yet. See `share_library_card.dart`, which uses the
      // same generation of the API for the card export.
      final result = await Share.share(
        '${l10n.inviteShareText}\n$kInviteLinkBase${invite.token}',
        subject: l10n.inviteTitle,
        sharePositionOrigin: origin,
      );
      // Debug-only, and deliberately not an analytics event: this is a diagnostic for
      // a defect being chased on the simulator, where `status` distinguishes the three
      // outcomes that all look identical from the outside — `success` (a destination
      // took it), `dismissed` (the reader backed out), and `unavailable` (the platform
      // declined, which is what an iOS simulator with no share destinations returns).
      if (kDebugMode) {
        developer.log(
          'share returned: status=${result.status.name} raw="${result.raw}"',
          name: 'invite',
        );
      }
    } catch (e, stack) {
      if (kDebugMode) {
        developer.log(
          'share threw',
          name: 'invite',
          error: e,
          stackTrace: stack,
        );
      }
      // A toast rather than the inline `_error` slot above the button: the link exists
      // and nothing on the sheet needs to change, so there is nothing to show there.
      EasyLoading.showError(l10n.inviteShareFailed);
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    // **Room for the floating tab bar, which is in front of this sheet.**
    // `ShellChrome` hosts the bar above the `Navigator` and it stays up for the
    // first modal over the shell, so on the native path its glass occupies the
    // band 21..83pt above the screen bottom. `SafeArea` alone only clears the
    // 34pt home-indicator inset, which put Share and the code underneath it — the
    // same reservation every shell sheet makes, via the same geometry, so the two
    // cannot drift apart.
    //
    // Gated on the bar actually being drawn rather than reserved unconditionally:
    // this sheet is also built with no shell above it (the render preview, and
    // any widget test), and 57pt of dead air at the bottom of those is a lie about
    // what is covering it.
    final reserve = ref.watch(shellBarVisibleProvider)
        ? ShellTabBar.geometryOf(context).reserve
        : 0.0;

    return SafeArea(
      top: false,
      child: Column(
        children: [
          // ✕ alone in the leading slot, which is the slot a reader looks for a
          // dismissal in. No title: the hero below is the title, and repeating it in
          // an 17pt bar would make the 30pt one look like a mistake.
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 0),
            child: Row(
              children: [
                AdaptiveIconButton(
                  symbol: 'xmark',
                  icon: Icons.close,
                  // [kIconButtonDiameter], the same target Add Book, Manage Shelves,
                  // the scanner and the share card all give their close button. It
                  // was 36, which is the size the *library bar* uses for a ✕ crowded
                  // in beside Poke; nothing is crowding this one, and shrinking the
                  // only way out of a full-height sheet to save 8pt buys nothing.
                  diameter: kIconButtonDiameter,
                  symbolSize: kIconButtonSymbolSize,
                  iconSize: kIconButtonIconSize,
                  semanticLabel: l10n.close,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              // **The horizontal inset is applied per-block, not to the scroll
              // view**, so the mark can go full-bleed. Three shelves of two books
              // plus their gaps come to more than a 393pt phone leaves inside 24pt
              // of padding on each side, and the wash behind them wants the whole
              // width anyway — a gradient that stops 24pt short reads as a panel
              // rather than as a horizon.
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _ThreeShelves(),
                  const SizedBox(height: 20),
                  _Inset(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.inviteTitle,
                          textAlign: TextAlign.center,
                          // The serif, and the reason [AppTextStyles.hero] exists.
                          // This is the app's own name in the app's own voice, on
                          // the one screen whose whole job is one sentence.
                          style: AppTextStyles.hero,
                        ),
                        const SizedBox(height: 12),
                        _Paragraph(l10n.inviteBody),
                        const SizedBox(height: 10),
                        // The emotional one. Flighty's second paragraph names a
                        // single recurring annoyance the product removes rather than
                        // a feature; this names the screenshot habit.
                        _Paragraph(l10n.inviteBodyEmotional),
                        const SizedBox(height: 16),
                        Text(
                          l10n.inviteFinePrint,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.caption.copyWith(
                            color: colors.secondaryText,
                            // The contract is fine print, not a caption label, so it
                            // keeps the token's size and drops the uppercase
                            // tracking.
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + reserve),
            child: Column(
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      l10n.inviteCreateFailed,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.label.copyWith(color: softRedColor),
                    ),
                  ),
                // **"Continue", not "Share invite" — and the key is `shareInvite`
                // only because renaming it would churn both `.arb` files for nothing.**
                //
                // The reference says Continue. It reads as wrong for a second, which is
                // why it is worth the note: this screen is an *explainer* standing
                // between the reader and the system share sheet, so the button's job is
                // to advance past the explanation. "Share invite" names the destination
                // instead, which makes the tap feel like the commitment — and then the
                // real share sheet appears and asks for the decision again. Two
                // share-shaped buttons in a row, the first of which does not share.
                ElevatedActionButton(
                  key: _shareButtonKey,
                  width: double.infinity,
                  height: 48,
                  borderRadius: 24,
                  buttonText: l10n.shareInvite,
                  // **Live from the first frame.** It was gated on the link existing,
                  // which meant the sheet's only action arrived greyed and woke up a
                  // second later once an RPC returned — see [_pending]. The only thing
                  // that disables it now is a tap already in flight, which is a state
                  // the reader caused and can see the result of.
                  activated: !_pending,
                  onPressed: _pending ? null : () => _share(l10n),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The sheet's horizontal margin, applied per-block so the mark can ignore it.
class _Inset extends StatelessWidget {
  final Widget child;
  const _Inset({required this.child});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: child,
  );
}

class _Paragraph extends StatelessWidget {
  final String text;
  const _Paragraph(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: AppTextStyles.body.copyWith(color: context.colors.secondaryText),
  );
}

/// Width of a book in the mark.
///
/// **[kGeneratedCoverMinWidth], and not a pixel less.** That constant is the width
/// below which a generated cover stops drawing its title — the title is 13.5% of the
/// width, so a narrower book sets it at a smudge, which is exactly what Phase 4
/// shipped on the friends rail and what looked like a rendering fault. These books
/// carry titles, so they sit at the floor rather than under it.
const double _kMarkBookWidth = kGeneratedCoverMinWidth;

/// A book's height, from the app's own cover aspect. Derived, so the mark cannot end
/// up drawing a differently-proportioned book from the shelves.
const double _kMarkBookHeight = _kMarkBookWidth / kDefaultCoverAspect;

/// Three friends' shelves, each carrying the status this app actually reports.
///
/// **The mark is made of the app's own book.** The first pass drew plain rounded
/// rectangles — bar-chart spines — which against Flighty's rendered globe is the
/// reading equivalent of a grey box, and which sells nothing: the payoff is *seeing
/// what someone is reading*, and a grey bar is not a book. These are
/// [GeneratedCover]s at [kGeneratedCoverMinWidth], so they carry real titles in the
/// app's real palette and cannot drift from what a shelf actually looks like.
///
/// Three groups rather than one row of six, and the gap is what says so. The status
/// pills are what make it read as live rather than illustrative: *reading now*, *24
/// read* and *just joined* are the three things a friend's row can actually say.
class _ThreeShelves extends StatelessWidget {
  const _ThreeShelves();

  /// Titles for the mark, in the app's primary market's language.
  ///
  /// Real titles, deliberately: lorem-ipsum spines would undo the point of drawing
  /// real covers. Not localised — these are props in an illustration of somebody
  /// else's shelf, not copy, and an English reader's friends read Korean books too.
  static const _titles = [
    '소년이 온다',
    '아몬드',
    '달러구트 꿈 백화점',
    '여행의 이유',
    '불편한 편의점',
    '코스모스',
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        // Atmosphere, and it is not decoration for its own sake. Three shelves on
        // flat sheet background read as UI — a row of controls — rather than as a
        // scene; the reference sits its globe on a soft gradient for the same
        // reason. A brand wash fading to nothing puts a horizon behind them.
        gradient: RadialGradient(
          center: const Alignment(0, -0.75),
          radius: 1.1,
          colors: [
            colors.brand.withValues(alpha: 0.16),
            colors.brand.withValues(alpha: 0.05),
            colors.brand.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 0.85],
        ),
      ),
      // **Scaled down to fit, never clipped or wrapped.** A pill's width is a
      // translated string — `JUST JOINED` against `방금 가입` — and the three shelves
      // are laid out from the book's own width, so the mark's natural width is not a
      // number this file gets to choose. `scaleDown` makes the whole scene shrink
      // together on a narrow phone or in a long locale, which is what an
      // illustration should do; a `Flexible` pill would instead reflow one caption
      // onto two lines and knock its shelf out of alignment with the other two.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _MiniShelf(
              emoji: '🦊',
              status: l10n.inviteStatusReading,
              tone: _PillTone.now,
              titles: _titles.sublist(0, 2),
            ),
            // Keyed to the book's own width rather than typed: three groups of two
            // books have to read as three libraries, and at a smaller gap they
            // merge into one continuous band of six.
            const SizedBox(width: _kMarkBookWidth * 0.56),
            _MiniShelf(
              emoji: '🐣',
              status: l10n.inviteStatusRead(24),
              titles: _titles.sublist(2, 4),
            ),
            const SizedBox(width: _kMarkBookWidth * 0.56),
            _MiniShelf(
              emoji: '🌙',
              status: l10n.inviteStatusJoined,
              tone: _PillTone.fresh,
              // One book. Somebody who just joined has one book on their shelf, and
              // drawing them two would be the mark contradicting its own caption.
              titles: _titles.sublist(4, 5),
            ),
          ],
        ),
      ),
    );
  }
}

/// How a status pill is painted. Three, because the three statuses are not peers:
/// *reading now* is the live one and earns the filled treatment.
enum _PillTone { neutral, now, fresh }

class _MiniShelf extends StatelessWidget {
  final String emoji;
  final String status;
  final List<String> titles;
  final _PillTone tone;

  const _MiniShelf({
    required this.emoji,
    required this.status,
    required this.titles,
    this.tone = _PillTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Chip(emoji: emoji),
        const SizedBox(height: 5),
        _StatusPill(label: status, tone: tone),
        const SizedBox(height: 6),
        SizedBox(
          // Room for the lean below without the rotated corners being clipped.
          height: _kMarkBookHeight + 4,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < titles.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Transform.rotate(
                    // The outer books lean, which is what stops a row of upright
                    // rectangles reading as a stack of paper. Kept slight — a shelf
                    // that leans this way at every stop looks broken, not lived in —
                    // and skipped entirely for a single book, which has nothing to
                    // lean against.
                    angle: titles.length == 1
                        ? 0
                        : (i == 0
                              ? -0.07
                              : (i == titles.length - 1 ? 0.05 : 0)),
                    alignment: i == 0
                        ? Alignment.bottomRight
                        : Alignment.bottomLeft,
                    child: _MarkBook(title: titles[i], seed: '$emoji$i'),
                  ),
                ),
            ],
          ),
        ),
        _Plank(width: titles.length * (_kMarkBookWidth + 2) + 3),
      ],
    );
  }
}

/// One book in the mark: the app's [GeneratedCover], at the smallest width that
/// still carries a title.
class _MarkBook extends StatelessWidget {
  final String title;

  /// Feeds [generatedCoverColor], which hashes it to pick a palette entry. A per-book
  /// string rather than the title, so the three shelves come out in different colours
  /// even where two titles are the same length.
  final String seed;

  const _MarkBook({required this.title, required this.seed});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _kMarkBookWidth,
    height: _kMarkBookHeight,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 3,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: GeneratedCover(isbn: seed, title: title, width: _kMarkBookWidth),
      ),
    ),
  );
}

/// The shelf the books stand on.
///
/// A real plank with a shadow under it, not a hairline. The first pass drew a 3pt
/// divider-coloured line, which is invisible against the sheet and left the books
/// floating. Only a slight overhang: at a wider one the three planks nearly meet
/// across the gap and re-join the shelves the gap just separated.
class _Plank extends StatelessWidget {
  final double width;
  const _Plank({required this.width});

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 3,
    decoration: BoxDecoration(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(1.5),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.22),
          blurRadius: 2,
          offset: const Offset(0, 1.5),
        ),
      ],
    ),
  );
}

/// The friend's glyph, as a lifted disc rather than a bare emoji.
///
/// The circle is what makes it read as a person standing above a shelf; a floating
/// emoji reads as a label on the shelf itself.
///
/// **[AvatarCircle], not a hand-rolled circle with a `Text` in it.** That widget
/// exists precisely because six sites once drew their own and disagreed three ways
/// about the fallback glyph; it also sizes the glyph from the circle, which is the
/// case `kEmojiGlyphSize` explicitly does not cover. The shadow is the only thing
/// added here, and it belongs to the illustration rather than to avatars.
class _Chip extends StatelessWidget {
  static const double _diameter = 24;

  final String emoji;
  const _Chip({required this.emoji});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.10),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ],
    ),
    child: AvatarCircle(emoji: emoji, diameter: _diameter),
  );
}

class _StatusPill extends StatelessWidget {
  final String label;
  final _PillTone tone;

  const _StatusPill({required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, foreground, border) = switch (tone) {
      // Filled brand: this is the live one, and it is the single thing on the mark
      // that should catch the eye first.
      _PillTone.now => (colors.brandFill, Colors.white, Colors.transparent),
      _PillTone.fresh => (
        colors.brand.withValues(alpha: 0.18),
        colors.brandText,
        Colors.transparent,
      ),
      _PillTone.neutral => (
        colors.surface,
        colors.secondaryText,
        colors.divider,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.caption.copyWith(color: foreground),
      ),
    );
  }
}
