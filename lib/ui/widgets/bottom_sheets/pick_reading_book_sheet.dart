import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/services/cover_image.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book/generated_cover.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_bookmark.dart';
import 'package:bookworm_friends/ui/widgets/headers/search_header.dart';

/// The cover's rendered height in a picker row.
///
/// **44×66, and the size is the decision.** Drawn at 26×39 first, where a cover is a
/// colour swatch with a dark edge: legible as *a thing that is a book*, useless as *which
/// book*. At this height the binding reads as a binding, cover art is recognisable, and —
/// the reason it won — there is room for the ribbon. The width is not stated; it comes off
/// [kDefaultCoverAspect] like every other cover in the app, so this row cannot end up
/// drawing a book at an aspect no shelf uses.
///
/// See `cp-d-pick-big` in `docs/mockups/streaks/index.html` for the comparison, and for
/// the shelf-layout variant that lost.
const double kPickerCoverHeight = 66;

/// The row that cover sits in.
///
/// 78 rather than 66 + padding stated separately, because the drawing's cost argument is
/// about the row: five rows are 390pt of list where the small version's were 220, which is
/// what takes the month behind this sheet out of view. Keeping it as one number means that
/// figure stays checkable.
const double kPickerRowHeight = 78;

/// Asks which book tonight's reading was, and returns it.
///
/// **Step one of a pair, and it is mandatory.** Recording a day used to write one
/// `reading_days` row and nothing else; the streak page's button now raises this and then
/// the shipped percent wheel, because recording the night and knowing where you stopped are
/// one event and this is the one moment the reader has the answer in their hand. The
/// argument is *not* that `books.progress` is sparse — that column has never been in a
/// build any reader has, so its row count measures the release rather than the demand. It
/// is that nobody moves a bookmark for fun.
///
/// Resolves to the chosen [Book], or null if the reader dismissed without choosing — which
/// must abandon the whole write rather than stamping a day with no attribution, since a
/// half-completed pair is exactly the silent write this design refuses.
///
/// **Reading books are their own group and come first.** On almost every night the answer
/// is three rows from the top; a reader who has to *search* for the book in their hand has
/// been failed by the ordering rather than by the field. The field exists for the other
/// case — finishing a book never marked Reading, or picking something off a shelf — and it
/// is the app's own [SearchTextField] rather than a new control.
Future<Book?> showPickReadingBookSheet(
  BuildContext context, {

  /// Every book the reader could name. Grouped here by status rather than by the caller,
  /// so the two groups cannot be built from two different reads of the library.
  required List<Book> books,
}) {
  return CNBottomSheet.show<Book>(
    context: context,
    // The search field raises the keyboard, and without this the sheet is capped at
    // 9/16 of the screen with the inset paid out of that same budget — the same reason
    // `select_percent_bottom_sheet` sets it.
    isScrollControlled: true,
    builder: (_) => _PickBookSheet(books: books),
  );
}

class _PickBookSheet extends StatefulWidget {
  const _PickBookSheet({required this.books});

  final List<Book> books;

  @override
  State<_PickBookSheet> createState() => _PickBookSheetState();
}

class _PickBookSheetState extends State<_PickBookSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Case-insensitive across title and authors.
  ///
  /// Authors are in because "the Le Guin one" is how readers hold a book they cannot
  /// spell the title of, and the row already prints them.
  bool _matches(Book book) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    if (book.title.toLowerCase().contains(q)) return true;
    return book.authors.any((a) => a.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    final reading = [
      for (final b in widget.books)
        if (b.status == bookStatusReading && _matches(b)) b,
    ];
    final rest = [
      for (final b in widget.books)
        if (b.status != bookStatusReading && _matches(b)) b,
    ];

    return Padding(
      // Lifts the list clear of the keyboard rather than letting it be covered.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        // Tall enough that the Reading group lands above the fold on an ordinary night,
        // short enough that the page behind is still visible as the thing this is a step
        // in. Proportional rather than fixed, because a 560pt sheet is most of a small
        // phone and half of a large one.
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.streakPickBookTitle,
                      style: AppTextStyles.subtitle,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: SearchFieldPill(
                child: SearchTextField(
                  controller: _controller,
                  // Filtering a list already in memory, so there is nothing to defer to
                  // a submit — unlike Add Book, whose submit runs a paged catalogue
                  // query. Submit is wired to the same thing so the keyboard's search
                  // key is not a dead end.
                  onChanged: (value) => setState(() => _query = value),
                  onFieldSubmitted: (value) => setState(() => _query = value),
                ),
              ),
            ),
            Expanded(
              child: reading.isEmpty && rest.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          // Two different facts, and they get two different lines: a
                          // library with nothing in it is a prompt to add a book, and a
                          // query that matched nothing is not.
                          widget.books.isEmpty
                              ? l10n.streakPickBookEmpty
                              : l10n.streakPickBookNoMatch,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body.copyWith(
                            color: colors.secondaryText,
                          ),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        if (reading.isNotEmpty) ...[
                          _GroupHeader(label: l10n.streakPickBookReading),
                          for (final book in reading) _BookRow(book: book),
                        ],
                        if (rest.isNotEmpty) ...[
                          _GroupHeader(label: l10n.streakPickBookLibrary),
                          for (final book in rest) _BookRow(book: book),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Text(
        label,
        style: AppTextStyles.label.copyWith(
          color: context.colors.secondaryText,
        ),
      ),
    );
  }
}

/// One candidate: the app's own book at [kPickerCoverHeight], its title, and where the
/// app currently thinks the reader is.
class _BookRow extends StatelessWidget {
  const _BookRow({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const coverWidth = kPickerCoverHeight * kDefaultCoverAspect;
    final progress = book.progress;

    return InkWell(
      onTap: () => Navigator.pop(context, book),
      child: SizedBox(
        height: kPickerRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              SizedBox(
                width: coverWidth,
                height: kPickerCoverHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Clipped and hairlined so it reads as a jacket rather than a swatch,
                    // which at this size is the whole difference between "a book" and "a
                    // coloured rectangle".
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: colors.divider,
                              width: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: _cover(),
                        ),
                      ),
                    ),
                    // **The ribbon earns its place rather than decorating.** The next
                    // step asks *how far are you now*, so a reader choosing here is
                    // looking at where the app already thinks they are — and it is the
                    // same picture they see on the shelf.
                    //
                    // Only on an open book, which is the shipped rule: a book that is
                    // not being read carries no mark, and drawing one would claim a
                    // position it has no business having.
                    if (book.status == bookStatusReading)
                      Positioned(
                        top: 0,
                        // The card's own rule for a smaller cover: the asset scaled by
                        // this cover's height over the shelf book's, and the track
                        // scaled with it so the mark sits proportionally where the
                        // shelf's does instead of reading a different value at a
                        // different size.
                        right: readingBookmarkInsetFor(
                          progress,
                          coverWidth: coverWidth,
                          scale: kPickerCoverHeight / kReadingBookmarkBook,
                        ),
                        child: const ReadingBookmark(
                          scale: kPickerCoverHeight / kReadingBookmarkBook,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body,
                    ),
                    if (book.authors.isNotEmpty)
                      Text(
                        book.authors.first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: colors.secondaryText,
                        ),
                      ),
                  ],
                ),
              ),
              // The exact figure beside the approximate one. The ribbon says *about two
              // thirds*, which is all a cover can say; this says 64%, and the wheel one
              // step later is where it is changed. Absent rather than 0% when there is
              // nothing recorded — see `Book.progress`, where null and zero are
              // deliberately different facts.
              if (progress != null)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(
                    '${(progress * 100).round()}%',
                    style: AppTextStyles.label.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The stored cover when there is one, the book's own tone when there is not — and
  /// **no title on the jacket either way.**
  ///
  /// [GeneratedCover] is deliberately not used here, and the reason is its own documented
  /// floor: the title it draws is 13.5% of the cover's width, so below
  /// [kGeneratedCoverMinWidth] (≈52pt) it sets under 7pt and reads as a rendering fault
  /// rather than as a small title. This cover is [kPickerCoverHeight] tall, so about 44
  /// wide — under the floor. `CardCoverRow` and the add-book sheet's owned-book row both
  /// make exactly this trade for exactly this reason.
  ///
  /// Which is also what the design record asks for on its own grounds: the row already
  /// carries the title at 15pt beside the cover, and a Korean title at 44pt wide is two
  /// unreadable lines of duplicate information.
  ///
  /// `Book.coverColor` is preferred over the ISBN hash, because it is the colour something
  /// already decoded off this book's real cover — so a coverless row still belongs to the
  /// book rather than to its identifier.
  Widget _cover() {
    final block = ColoredBox(
      color: book.coverColor ?? generatedCoverColor(book.isbn),
    );
    if (book.thumbnail.isEmpty) return block;
    return Image(
      image: coverImageProvider(book.thumbnail),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => block,
    );
  }
}
