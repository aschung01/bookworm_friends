import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/models/book_compliment.dart';
import 'package:flutter/material.dart';

/// The emoji praise a book has collected, as chips beside the cover.
///
/// Shown to visitors *and* to the owner. The button that adds praise is hidden
/// on your own book — you should not praise yourself — but the praise itself is
/// the entire point of persisting the reaction, so the recipient has to be able
/// to see it. It previously sat behind the same `!isSelf` guard as the button,
/// which meant the person praised never saw it anywhere in the app.
class ComplimentBlock extends StatelessWidget {
  const ComplimentBlock({super.key, required this.compliments});

  final List<BookCompliment> compliments;

  @override
  Widget build(BuildContext context) {
    if (compliments.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        alignment: WrapAlignment.end,
        children: compliments
            .map(
              (c) => Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.pageBackground,
                  border: Border.all(
                    color: context.colors.brand.withValues(alpha: 0.3),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(c.compliment, style: const TextStyle(fontSize: 14)),
              ),
            )
            .toList(),
      ),
    );
  }
}
