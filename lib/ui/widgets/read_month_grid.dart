import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';

/// One month's read books: a name, a count, and the covers.
class ReadMonth {
  /// First day of the month, or `null` for the group of books that are finished
  /// but carry no finish date.
  final DateTime? month;
  final List<Book> books;

  const ReadMonth({required this.month, required this.books});
}

/// The read view's **expanded** state: covers grouped by the month they were
/// finished in, newest first.
///
/// Lazy on purpose. The sheet hands this a bounded height, so a `ListView` builds
/// only the rows that fit rather than every cover a heavy reader owns — which
/// matters because each [BookWidget] loads an image through its own
/// `ImageStream`. A `Column` inside a `SingleChildScrollView` would build all of
/// them.
class ReadMonthGrid extends StatelessWidget {
  final List<ReadMonth> months;

  /// Extra room at the bottom, so the last row clears whatever floats over the
  /// sheet.
  final double bottomPadding;

  const ReadMonthGrid({
    super.key,
    required this.months,
    this.bottomPadding = 0,
  });

  /// Four across, at the 2:3 the drawings use.
  static const int _columns = 4;
  static const double _coverAspect = 2 / 3;
  static const double _gap = 10;

  /// Groups by finish date, newest month first.
  ///
  /// Undated books get their own trailing group rather than being dropped. The
  /// header shows a count, and silently omitting rows from a total the user can
  /// see is the kind of bug nobody reports — they just distrust the number.
  static List<ReadMonth> group(List<Book> books) {
    final byMonth = <DateTime, List<Book>>{};
    final undated = <Book>[];
    for (final book in books) {
      final finished = book.finishDate;
      if (finished == null) {
        undated.add(book);
        continue;
      }
      final key = DateTime(finished.year, finished.month);
      byMonth.putIfAbsent(key, () => []).add(book);
    }
    final keys = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final key in keys) ReadMonth(month: key, books: byMonth[key]!),
      if (undated.isNotEmpty) ReadMonth(month: null, books: undated),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (months.isEmpty) {
      return Center(
        child: Text(
          l10n.noFinishedBooks,
          style: TextStyle(color: context.colors.secondaryText, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.only(bottom: bottomPadding),
      itemCount: months.length,
      itemBuilder: (context, index) {
        final group = months[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.month == null
                            ? l10n.readNoDate
                            : l10n.monthYearLabel(
                                group.month!.year,
                                '${group.month!.month}',
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${group.books.length}',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              GridView.builder(
                // The outer list scrolls; each month's grid is laid out at its
                // natural height inside it.
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _columns,
                  childAspectRatio: _coverAspect,
                  crossAxisSpacing: _gap,
                  mainAxisSpacing: _gap,
                ),
                itemCount: group.books.length,
                itemBuilder: (context, i) {
                  final book = group.books[i];
                  return LayoutBuilder(
                    builder: (context, constraints) => BookWidget(
                      imageUrl: book.thumbnail,
                      isbn: book.isbn,
                      title: book.title,
                      height: constraints.maxHeight,
                      // The cells are already a uniform 2:3, so the shelf's
                      // height jitter has nothing to vary against here and only
                      // makes neighbouring covers look misaligned.
                      jitter: false,
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.details,
                        arguments: book,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
