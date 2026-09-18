import 'dart:async';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/libby_library_provider.dart';
import 'package:bookworm_friends/services/libby_library_lookup.dart';
import 'package:bookworm_friends/ui/widgets/empty_state_art.dart';
import 'package:bookworm_friends/ui/widgets/headers/search_header.dart';

/// Asking which library the reader belongs to, once.
///
/// **Why this exists at all is a routing fact, not a preference.** Libby resolves
/// `title/<id>` only beneath `library/<key>` — its router builds the path from its
/// ancestor route — so without a key the Libby row cannot reach a book inside the
/// app. A device proved it: `libbyapp.com/title/<id>` shows *"View not found."* and
/// lands on the Shelf. One key is the difference.
///
/// **Just-in-time, and that is the whole reason it is affordable.** Not onboarding
/// and not a Settings chore: it appears the first time the reader taps Libby, when
/// they have just shown they want it, and never again. `LibbyLibraryChoice` keeps
/// three states precisely so "never asked" and "asked and declined" can be told
/// apart — re-asking someone who declined is nagging.
///
/// **A sheet rather than a pushed page**, because it is one choice made once,
/// reached from inside another sheet. A route would take the reader further from the
/// book than the decision warrants.
///
/// **Dismissing never blocks.** It falls back to what the row did before — an exact
/// OverDrive page in the browser, or a search — which works. Nothing here is
/// load-bearing for reading the book.
///
/// Returns the chosen library, or null for a dismissal. **Recording the choice is
/// the caller's job**, because the caller is also the thing that has to rebuild its
/// links and re-launch; doing half of it here would split one action across two
/// files.
Future<LibbyLibrary?> showLibbyLibrarySheet(BuildContext context) {
  return CNBottomSheet.show<LibbyLibrary>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.sheetBackground,
    builder: (ctx) => const _LibbyLibrarySheet(),
  );
}

/// How long after the last keystroke before asking.
///
/// The endpoint is keyless and fast, but it is one request per burst of typing
/// rather than per letter. 300ms is the usual "they have stopped for a moment"
/// threshold and is short enough that the list feels attached to the field.
const _debounce = Duration(milliseconds: 300);

/// Tallest the results list is allowed to get.
///
/// Bounded rather than free so the field, the why-line and the way out all stay on
/// screen with a keyboard up. The list scrolls past this.
const double _maxResultsHeight = 300;

class _LibbyLibrarySheet extends ConsumerStatefulWidget {
  const _LibbyLibrarySheet();

  @override
  ConsumerState<_LibbyLibrarySheet> createState() => _LibbyLibrarySheetState();
}

class _LibbyLibrarySheetState extends ConsumerState<_LibbyLibrarySheet> {
  final _controller = TextEditingController();
  Timer? _timer;

  /// The debounced query actually being asked about, which is deliberately *not*
  /// the field's text: watching the controller directly would key a provider on
  /// every keystroke and fire a request per letter.
  String _query = '';

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    final next = value.trim();
    // Clearing the field is immediate, not debounced: there is nothing to wait
    // for, and leaving stale results under an empty field looks like a bug.
    if (next.isEmpty) {
      if (_query.isNotEmpty) setState(() => _query = '');
      return;
    }
    _timer = Timer(_debounce, () {
      if (mounted && next != _query) setState(() => _query = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        // The keyboard's own inset, so the why-line and "Not now" are not buried
        // under it while the field is focused.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                l10n.libbyLibraryTitle,
                textAlign: TextAlign.center,
                style: AppTextStyles.subtitle,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SearchFieldPill(
                child: SearchTextField(
                  controller: _controller,
                  hintText: l10n.libbyLibraryHint,
                  // Arriving here there is nothing to do but type, and the sheet
                  // was opened by a deliberate tap.
                  autofocus: true,
                  onChanged: _onChanged,
                  // Submitting is the same request the debounce would have made;
                  // running it immediately respects an impatient return key.
                  onFieldSubmitted: _onChanged,
                ),
              ),
            ),
            Flexible(child: _results(l10n)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                l10n.libbyLibraryWhy,
                style: AppTextStyles.caption.copyWith(
                  color: context.colors.secondaryText,
                ),
              ),
            ),
            // Dismissing is a first-class outcome, not an escape hatch, so it gets
            // a real control rather than only the drag-to-close gesture. Returning
            // null is what tells the caller to record a decline.
            ListTile(
              title: Text(
                l10n.libbyLibrarySkip,
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(
                  color: context.colors.secondaryText,
                ),
              ),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _results(AppLocalizations l10n) {
    // Below the minimum the endpoint matches thousands of branches and tells the
    // reader nothing, so nothing is shown rather than a misleading partial list.
    if (_query.length < libbyMinQueryLength) {
      return const SizedBox(height: 12);
    }
    final results = ref.watch(libbyLibrarySearchProvider(_query));
    return results.when(
      loading: () => _Notice(label: l10n.libbyLibrarySearching),
      // `libbyLibrarySearch` never throws, so this arm is unreachable in practice.
      // Treated as "nothing found" rather than a distinct error state, because the
      // reader's next move is the same either way: try different words.
      error: (_, _) => _Empty(l10n: l10n),
      data: (libraries) {
        if (libraries.isEmpty) return _Empty(l10n: l10n);
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: _maxResultsHeight),
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: libraries.length,
            itemBuilder: (context, i) {
              final library = libraries[i];
              return ListTile(
                title: Text(library.name, style: AppTextStyles.body),
                // **Two lines, and the second is not decoration.** "King County
                // Library System" (Washington) and "Kings County Library"
                // (California) are one letter apart, and the region is the only
                // thing on screen that distinguishes them.
                subtitle: library.region.isEmpty
                    ? null
                    : Text(
                        library.region,
                        style: AppTextStyles.caption.copyWith(
                          color: context.colors.secondaryText,
                        ),
                      ),
                onTap: () => Navigator.pop(context, library),
              );
            },
          ),
        );
      },
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppTextStyles.body.copyWith(color: context.colors.secondaryText),
      ),
    );
  }
}

/// Nothing by that name.
///
/// Takes the shape every other failure in the app takes — art, what happened, what
/// to try — rather than inventing one. The body offers all three things that work,
/// which is worth stating because **an earlier draft of this screen warned the
/// reader off searching a branch** and that would have been wrong: the endpoint
/// searches branches and resolves them to the system that runs them, so "Mission Bay
/// Branch Library" finds San Francisco Public Library.
class _Empty extends StatelessWidget {
  const _Empty({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        children: [
          const EmptyStateArt(EmptyStateArtwork.noMatch, size: 40),
          const SizedBox(height: 12),
          Text(
            l10n.libbyLibraryNoneTitle,
            textAlign: TextAlign.center,
            style: AppTextStyles.subtitle,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.libbyLibraryNoneBody,
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(
              color: context.colors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}
