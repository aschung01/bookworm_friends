/// Strings printed on the Library Card as furniture rather than as content.
///
/// **What is left here is Latin in every locale, and that is now the whole membership
/// rule.** This file used to hold the card's two bilingual strings as well, on the
/// argument that furniture is read by whoever the image is sent to rather than by the
/// person holding the phone — so an exported card that names itself differently
/// depending on who exported it would be two products in circulation instead of one,
/// the same argument that pins the artifact's stock in both themes.
///
/// **That argument was overtaken by a plainer one: an English reader was being shown
/// Hangul.** Two of these strings carried a Korean half — `도서관 카드 · LIBRARY · CARD`
/// and `책벌레 친구들 · LIBSTACK` — and the first of them was drawn in the Card tab's
/// hero as well as on the artifact, where the reader *is* the person holding the phone.
/// So the old rule was being broken by its own strings: an `en` user got Korean
/// furniture in their own UI, and got it again on the image they sent to
/// English-speaking friends. Both are now `libraryCardStamp` and
/// `libraryCardAuthority` in the ARB files, and the hero no longer prints either — see
/// `LibraryCardBody`.
///
/// **The passport argument survives inside the Korean translation, which is where it
/// was actually doing work.** The line beneath the artifact's title exists to give the
/// card's name in the reader's language; `ko` supplies `도서관 카드`, and `en` supplies
/// nothing, because [cardStampTitle] above it is already the English name. See
/// [cardStampLine].
///
/// **One invariant survives the move into the ARB files, and nothing there enforces
/// it:** every translation of `libraryCardAuthority` has to keep `LIBSTACK` in it,
/// because the `Authority` row is printed a few millimetres above [kCardBrandHandle]
/// and a name that does not match the address underneath it reads as a forgery. `ko`
/// keeps it by staying bilingual; `en` is the bare word.
///
/// So what remains below is the furniture that is Latin *by construction* rather than
/// by choice: a title that a translation would not improve, a two-letter seal, and a
/// domain. The machine-readable strip stays Latin-only for its own reason — see
/// `cardStripLines`.
library;

import 'package:bookworm_friends/l10n/app_localizations.dart';

/// The line under the artifact's title, or **null when the title already says it**.
///
/// The card names itself once. `libraryCardStamp` is deliberately empty under `en`,
/// because [cardStampTitle] directly above reads `MY LIBRARY CARD` and a sub-line
/// reading `LIBRARY · CARD` under it was the same words twice — which is exactly what
/// the old bilingual constant hid, by carrying a Korean half that *did* add something.
/// Strip the Korean and the redundancy is all that is left. Under `ko` it reads
/// `도서관 카드`: the checkout card in the paper pocket at the back of a library book,
/// a known object to any Korean reader over thirty, and the thing this card imitates.
///
/// **Resolved through a function rather than read straight off `l10n`, because "empty
/// means absent" is not something a `Text` can be told.** The artifact is the only
/// caller — the Card tab's hero used to draw this line too and no longer does, since
/// its own label already names the card in the reader's language — so this exists to
/// keep the empty-string convention next to the reason for it rather than as a bare
/// `.isEmpty` at the call site.
///
/// Empty rather than absent from the ARB file because the template has to carry every
/// key. A translator who fills it in for `en` reintroduces the duplicate.
String? cardStampLine(AppLocalizations l10n) {
  final line = l10n.libraryCardStamp;
  return line.isEmpty ? null : line;
}

/// The artifact's title, over [cardStampLine].
///
/// English in both locales, exactly as a passport prints PASSPORT over its
/// national-language equivalent — and it is the reason [cardStampLine] is null under
/// `en`: this *is* the English name, so there is nothing for the line beneath to add.
///
/// Takes the year because a card filtered to 2026 that calls itself `MY LIBRARY CARD`
/// is the one place the year capsules could make the export lie.
String cardStampTitle(int year) =>
    year == 0 ? 'MY LIBRARY CARD' : 'MY $year LIBRARY CARD';

/// The blind-embossed stamp in the cover well: the brand mark, not a monogram.
///
/// The drawings show `BF` and the card shipped with `LS`, both of which were initials
/// standing in for an emblem — but an embossing die is exactly where an emblem belongs,
/// and `LS` said nothing the record's `LIBSTACK` line and the strip's `@LIBSTACK.APP`
/// were not already saying twice. The launcher's own mark says it once, pictorially.
///
/// This is `app_icon_mark.png` — white on transparency — because the seal is drawn by
/// *tinting* pure alpha with `sealInk`, the same constraint the Android monochrome
/// layer puts on this artwork. The full-bleed `app_icon.png` carries its green plate
/// and cannot be tinted. The one runtime asset bundled from `assets/branding/`; see
/// the note in `pubspec.yaml`.
///
/// **Any export drawing this must precache it** — `RepaintBoundary.toImage` paints
/// only what is already decoded. `exportLibraryCardFile` hands
/// `AssetImage(kCardSealMarkAsset)` to its `precache` list for exactly this reason.
const String kCardSealMarkAsset = 'assets/branding/app_icon_mark.png';

/// The one printed return path, and it is deliberately one string rather than two.
///
/// Flighty prints `@FLIGHTY` on the strip's first line and `FLIGHTY.COM` on its
/// second, which are two different strings pointing at two different places. Ours
/// would be `@LIBSTACK.APP` and `LIBSTACK.APP` — the same thing twice — so it is
/// printed once, in the second line's right-aligned tail, which is the most legible
/// slot on the strip.
///
/// **With the `@`, because that is the destination that exists.** There is no landing
/// page: the domain is bought and nothing is served, so `LIBSTACK.APP` typed into a
/// browser reaches nothing, while the Instagram account is live today. It still reads
/// as the domain if that changes.
///
/// Uppercase because the strip is a machine-readable zone and a passport's is
/// upper-case Latin only.
const String kCardBrandHandle = '@LIBSTACK.APP';
