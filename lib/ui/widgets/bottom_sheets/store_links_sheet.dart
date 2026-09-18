import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/services/store_links_service.dart';

/// The "where to read this" sheet.
///
/// One list of shops, and the whole design rests on **the second line of each
/// row**. It is the only place a destination can admit what it actually reaches:
/// Amazon publishes no per-book deep link, so Kindle can only be a search, and
/// its only claimed URL reaches the reader's library rather than a title. A sheet
/// that showed four interchangeable-looking rows would be promising something it
/// cannot keep in most of them.
///
/// So no label here is written by hand. Every one is derived from the
/// [StoreLink.reach] the service returned, which means the copy cannot drift from
/// the capability — if a row says "Opens this book" it is because a per-book URL
/// came back.
///
/// Two states, and the title carries the difference because the app-bar icon that
/// opens this sheet cannot: identical glyph whether or not a shop is known.
/// That is the acknowledged cost of putting the entry point in the bar.
Future<void> showStoreLinksSheet(
  BuildContext context, {
  required List<StoreLink> links,
  required bool isLoading,
  required StoreId? current,
  required void Function(StoreLink link) onOpen,
  required VoidCallback onForget,
}) {
  final l10n = AppLocalizations.of(context);
  return CNBottomSheet.show(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              current == null ? l10n.whereToRead : l10n.yourCopy,
              style: AppTextStyles.subtitle,
            ),
          ),
          if (isLoading)
            _Checking(label: l10n.checkingStores)
          else if (links.isEmpty)
            _Nothing(title: l10n.noEbookTitle, body: l10n.noEbookBody)
          else ...[
            for (final link in links)
              _StoreRow(
                link: link,
                isCurrent: link.id == current,
                onTap: () => onOpen(link),
              ),
            // Offered only once there is something to forget. A tap is not a
            // purchase, so a wrong guess must never be a trap.
            if (current != null)
              ListTile(
                leading: Icon(
                  Icons.remove_circle_outline,
                  color: context.colors.secondaryText,
                ),
                // Deliberately NOT destructive styling. `MenuAction` makes red
                // one flag away, but forgetting where a book lives is not
                // deleting a book, and borrowing delete's colour for it would
                // make the two look like the same weight of decision.
                title: Text(l10n.forgetReaderApp),
                onTap: onForget,
              ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// One shop. 56pt, which is what `ListTile` with a leading widget already draws
/// for every other menu in the app — there is no competing content in a sheet, so
/// nothing has to be bought back here.
class _StoreRow extends StatelessWidget {
  const _StoreRow({
    required this.link,
    required this.isCurrent,
    required this.onTap,
  });

  final StoreLink link;
  final bool isCurrent;
  final VoidCallback onTap;

  /// The supporting line, derived from what the link reaches rather than written
  /// per shop.
  ///
  /// **The verb and the line have to agree with the capability**, which is why
  /// both come from [StoreReach]. `Read in Play Books / Opens at this book`
  /// promises a book; `Open Kindle / Opens your Kindle library` promises an app.
  /// A reader who learns that distinction once can trust every row afterwards.
  String _supporting(AppLocalizations l10n) {
    // Libby's acquire row is the one place the reach-derived line is overridden,
    // because nothing here is sold and "opens this book" would misdescribe a
    // borrow. It still splits on the reach rather than being one fixed string:
    //
    //  * [StoreReach.book] means the reader's library is known and the link lands
    //    on this title inside Libby, so the line earns the word "this". Without
    //    that four-character difference the destination would get better and the
    //    row would look identical.
    //  * Anything weaker keeps the general promise. Neither line claims the copy is
    //    *available*: the same title is 87-of-87 at one library and eleven deep in
    //    holds at another, and only the reader's own library can settle it.
    if (link.id == StoreId.libby && link.intent == StoreIntent.acquire) {
      return link.reach == StoreReach.book
          ? l10n.storeBorrowThisBook
          : l10n.storeBorrowFree;
    }
    return switch ((link.reach, link.intent)) {
      (StoreReach.book, StoreIntent.open) => l10n.storeOpensAtThisBook,
      (StoreReach.book, _) => l10n.storeOpensThisBook,
      // Named as a browser destination, because it is one and the reader noticed.
      // `/store/books/details` is claimed by no Google app, so Play Books opens
      // in Safari however installed it is.
      (StoreReach.storePage, _) => l10n.storeOpensStorePage,
      (StoreReach.search, _) => l10n.storeOpensSearch(_searchBrand),
      (StoreReach.app, _) => l10n.storeOpensLibraryApp(link.brand),
    };
  }

  /// Kindle's search happens on Amazon, not in Kindle, and saying "a Kindle
  /// search" would misdescribe where the reader lands.
  String get _searchBrand => link.id == StoreId.kindle ? 'Amazon' : link.brand;

  /// The row's own label.
  ///
  /// [StoreReach.storePage] deliberately takes the same `Read in X` as
  /// [StoreReach.book] at the open intent: both reach the book, and the *second*
  /// line is where the browser-versus-app difference is stated. Splitting the
  /// label too would say it twice.
  String _label(AppLocalizations l10n) => switch ((link.intent, link.reach)) {
    (StoreIntent.acquire, _) => link.brand,
    (StoreIntent.open, StoreReach.book) => l10n.storeReadIn(link.brand),
    (StoreIntent.open, StoreReach.storePage) => l10n.storeReadIn(link.brand),
    (StoreIntent.open, _) => l10n.storeOpenApp(link.brand),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      leading: _Glyph(link: link),
      title: Text(_label(l10n)),
      subtitle: Text(
        _supporting(l10n),
        // `body` in `secondaryText`, which is what every other supporting line in
        // the app uses (see `delete_book_bottom_sheet.dart`). Not `label` at w400:
        // the scale has no 13/w400 step, and spelling one out here is exactly what
        // `text_style_test.dart`'s source scan exists to stop — thirteen sizes
        // within a few features, with nothing failing to tell anyone.
        style: AppTextStyles.body.copyWith(color: context.colors.secondaryText),
      ),
      trailing: isCurrent
          // The current choice takes the same trailing check every other menu in
          // the app uses for a current choice, so this needs no new affordance.
          ? Icon(Icons.check, color: context.colors.brandText)
          : Icon(
              Icons.north_east,
              size: 18,
              color: context.colors.secondaryText,
            ),
      onTap: onTap,
    );
  }
}

/// The leading mark for a shop.
///
/// **All four shops now carry a real mark**, which took two sources rather than
/// one. Simple Icons (CC0) covers Play, Apple and Amazon; it carries nothing for
/// Libby, and Arcticons (CC BY-SA 4.0) is the only licence-clean set that does.
/// An earlier round concluded no mark existed for Kindle or Libby and shipped
/// letter chips instead -- that was wrong on both counts, and the note is left
/// here so the search is not repeated a third time.
///
/// Kindle takes the **Amazon** mark deliberately. Amazon publishes no Kindle
/// glyph in any set that can be legally redistributed, and the row's own second
/// line already reads "Searches Amazon" -- so the mark names the ecosystem, the
/// label names the shop, and the two agree instead of competing.
///
/// Attribution for Arcticons is owed under CC BY-SA and belongs on the licence
/// page reached from `settings_page.dart`.
class _Glyph extends StatelessWidget {
  const _Glyph({required this.link});

  final StoreLink link;

  /// The asset for a shop, and the size to draw it at.
  ///
  /// **The size varies on purpose, and it is not a nudge.** Three of these marks
  /// are solid fills and Libby's is a 3-unit stroke, so at one size the stroked
  /// one carries visibly less ink and reads as the lightest row in the sheet --
  /// see `test/store_marks_probe_test.dart`, which exists to be looked at. 20 of
  /// the 30pt box brings it back to the same optical weight as the solids at 16.
  static (String asset, double size) _mark(StoreId id) => switch (id) {
    StoreId.play => ('assets/icons/storePlayIcon.svg', 16),
    StoreId.apple => ('assets/icons/storeAppleIcon.svg', 16),
    StoreId.kindle => ('assets/icons/storeKindleIcon.svg', 16),
    StoreId.libby => ('assets/icons/storeLibbyIcon.svg', 20),
  };

  @override
  Widget build(BuildContext context) {
    final (asset, size) = _mark(link.id);
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.colors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      // Tinted to `primaryText` for the same reason the empty-state art is
      // tinted: a brand's own colour would be the loudest thing in a sheet that
      // is otherwise entirely typographic, and would not follow dark mode.
      child: SvgPicture.asset(
        asset,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(
          context.colors.primaryText,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}

class _Checking extends StatelessWidget {
  const _Checking({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          const CircularProgressIndicator.adaptive(),
          const SizedBox(height: 16),
          Text(
            label,
            style: AppTextStyles.label.copyWith(
              color: context.colors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Nothing found — title plus body, the shape every other failure in this app
/// takes (see `scanNoMatchTitle`/`Body`).
///
/// Ordinary rather than exceptional: `Book.isbn` is sometimes a Google volume id,
/// and Kakao's mapper keeps only the first space-separated token, so lookups
/// genuinely miss. Deliberately does not print the ISBN — `scanNoMatchBody` does,
/// but there the reader had just scanned a barcode so the number meant something.
class _Nothing extends StatelessWidget {
  const _Nothing({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.subtitle),
          const SizedBox(height: 8),
          Text(
            body,
            style: AppTextStyles.body.copyWith(
              color: context.colors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}
