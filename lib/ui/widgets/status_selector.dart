import 'package:flutter/material.dart';

import 'package:bookworm_friends/ui/widgets/glass_segmented_control.dart';

/// Picks a book's reading status: interested / reading / finished.
///
/// Three short, mutually exclusive options, which is exactly what a segmented
/// control is for — so this is a [GlassSegmentedControl]: native `CNSegmentedControl`
/// on iOS 26+, the app's pill chips everywhere else.
///
/// **Kept as a named wrapper rather than inlined at the call sites.** It is only a
/// label-to-status mapping, but that mapping is the thing worth naming: [labels] is
/// ordered by status *value*, so index 0 is "interested", 1 "reading", 2 "finished",
/// and a caller that shuffles them silently rewrites what every book means.
class BookStatusSelector extends StatelessWidget {
  const BookStatusSelector({
    super.key,
    required this.labels,
    required this.status,
    required this.onChanged,
  });

  final List<String> labels;

  /// Currently selected status, as an index into [labels].
  final int status;

  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => GlassSegmentedControl(
    labels: labels,
    selectedIndex: status,
    onChanged: onChanged,
  );
}
