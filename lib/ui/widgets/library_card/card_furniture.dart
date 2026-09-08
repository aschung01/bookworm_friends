/// Strings printed on the Library Card as furniture rather than as content.
///
/// **Deliberately not in the ARB files, and that is the decision this file exists to
/// record.** Everything else the card says is localised, because everything else is
/// read by the person holding the phone. These are read by whoever the image is sent
/// to, and an exported card that names itself differently depending on who exported
/// it is two products in circulation instead of one. It is the same argument that
/// pins the artifact's stock in both themes.
///
/// Being bilingual is therefore the point, not a compromise: a Korean passport
/// prints 대한민국 / REPUBLIC OF KOREA on its data page whoever is reading it, and the
/// machine-readable strip stays Latin-only for the same reason.
library;

/// The line under the hero's label, and the artifact's own subtitle.
///
/// 도서관 대출 카드 — the checkout card in the paper pocket at the back of a library
/// book — is the object this card is imitating, and it is a known object to any
/// Korean reader over thirty. The English half is what makes the artifact legible to
/// everyone else in the thread.
const String kCardStampLine = '도서관 카드 · LIBRARY · CARD';

/// The artifact's title, over [kCardStampLine].
///
/// English, with the bilingual line beneath it, exactly as a passport prints
/// PASSPORT over its national-language equivalent. Takes the year because a card
/// filtered to 2026 that calls itself `MY LIBRARY CARD` is the one place the year
/// capsules could make the export lie.
String cardStampTitle(int year) =>
    year == 0 ? 'MY LIBRARY CARD' : 'MY $year LIBRARY CARD';

/// Who issued the card. Both names, because the artifact travels.
///
/// `책벌레 친구들` is the Korean display name and `LIBSTACK` the English one and the
/// host. Printing one of them would give a stranger a name that does not match the
/// address underneath it; printing whichever matches the *exporter's* locale would
/// put two different products into circulation.
const String kCardAuthority = '책벌레 친구들 · LIBSTACK';

/// The blind-embossed stamp in the cover well, and the prefix on a card number.
///
/// `LS`, not the `BF` the drawings show: those were drawn before the rename, and
/// every string file in the app now says Libstack.
const String kCardSeal = 'LS';

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
