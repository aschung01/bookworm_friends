# Reading Shelf Reorder Implementation Plan

**Spec:** `docs/superpowers/specs/2026-09-15-reading-shelf-reorder-design.md`

**Goal:** Drag-and-drop reordering of the Reading shelf in edit mode, persisted in a new
`books.reading_shelf_index` column.

**Order of work:** data layer first (migration → model → provider), then the shared
arithmetic, then the interaction, then the record. Each task is verifiable on its own; the
interaction task is the only one that cannot be tested without the ones before it.

---

## Task 1: Migration

**Files:**

- Create: `supabase/migrations/20260915120000_book_reading_shelf_index.sql`

- [x] **Step 1: Write the migration in house style.** Reasoning comment, then DDL, then
      `COMMENT ON COLUMN`, following `20260822120000_book_cover_color.sql`. The reasoning has
      to cover: why nullable (NULL means "no place on the Reading shelf"), why the backfill is
      right here _unlike_ `cover_color` (the backfilled value **is** the order the reader
      already sees, so deploy day is invisible), why per-user partitioning, why no index, and
      why `books.position` is deliberately left alone.
- [x] **Step 2: `supabase db push --dry-run` first.** ✅ **RESOLVED.** The dry run refuses:
      local `20260908120000` (cover_color_background_policy, comment-only) was never applied to
      the remote, and the remote carries `20260908230250` with no local file — most likely the
      same change applied through the Supabase MCP `apply_migration` tool, which stamps the
      version with the wall clock. `supabase db dump` cannot confirm that, because it needs
      Docker and OrbStack is not running. Resolution options: start OrbStack and `db pull`;
      or `migration repair --status applied 20260908120000` + `--status reverted 20260908230250`;
      or apply the DDL by hand and `repair --status applied 20260915120000`. **Needs a decision
      before anything touches production.**
- [x] **Step 3: Apply, then verify** the column exists and every status-1 row has a
      non-null index, and that no two rows share one within a user.

## Task 2: Model

**Files:**

- Modify: `lib/models/book.dart`
- Modify: `test/book_model_test.dart` (or nearest existing model test)

- [x] **Step 1: Add `readingShelfIndex`** as `int?` — constructor, `fromJson`, `copyWith`.
      `fromJson` must treat an absent key and an explicit null identically, like `pageCount`
      and `coverColor` do, so a row written before the column parses as "no place".
- [x] **Step 2: Document why `position` is not renamed** on `position`'s own doc comment:
      `reading_shelf_index` is named for the shelf it indexes because "reading position" reads
      as progress through the text, and `position` keeps its name because renaming a shipped
      column makes older builds read it as absent, collapsing every book to 0. Without this the
      next reader "fixes" the inconsistency.
- [x] **Step 3: Do not add clearing to `copyWith`.** The file documents that its nullable
      fields can be set but not cleared; the spec's reasoning for why a stale local index is
      harmless goes in a comment so nobody adds a flag for it later.

## Task 3: Ordering and writes

**Files:**

- Modify: `lib/providers/library_provider.dart`
- Modify: `test/library_provider_test.dart` (or nearest)

- [x] **Step 1: Sort in `readingBooksOf`** — `readingShelfIndex` ascending, NULLs last,
      tie-broken by the collected shelf-order ordinal. The tiebreak must be explicit:
      `List.sort` is not guaranteed stable, so "falls back to shelf order" is otherwise luck.
      Update the doc comment, which currently states the order _is_ shelf order and calls that
      the one thing a reader cannot change.
- [x] **Step 2: `LibraryNotifier.reorderReadingBooks(List<String> bookIds)`** — optimistic
      local update, then one `UPDATE … SET reading_shelf_index = i` per id, mirroring
      `reorderBooksInShelf` including its `reorderFailed` error path. Note in the doc that
      unlike that method, `bookIds` is the _whole_ reading set. **`position` is never written.**
- [x] **Step 3: Status transitions in `LibraryActions.updateBookStatus`** — entering status
      1 writes `min - 1` over non-null indices of the current reading set (or `0` when empty);
      leaving for 0 or 2 writes NULL. **Also done in `addBook`**, which is the other path a book
      enters status 1 by; without it a book saved straight as "reading" would arrive null and
      sort to the end of a row it is supposed to head.
- [x] **Step 4a: Sort tests** — added to `test/shelf_reading_out_test.dart` (6 cases: stored
      order beats shelf order, negative index heads the row, NULLs last, shared index falls back
      to shelf order, idempotence, and the pre-column fallback).
- [x] **Step 4b: Write-path tests** — not yet. `reorderReadingBooks`, the front insert and
      the null-out all go straight to Supabase, and the repo has no fake for that (there is no
      test for `reorderBooksInShelf` either). **Proposal:** give the reading-index write the same
      `@visibleForTesting` seam `writeCoverColor` has, so the _rules_ (min-1, exclusion of the
      book itself, null on the way out) are testable against the real method rather than a
      reimplementation of it.

## Task 4: Extract the drop-index arithmetic

**Files:**

- Create: `lib/ui/widgets/shelf_drop_index.dart`
- Modify: `lib/ui/widgets/shelf_row.dart`
- Create: `test/shelf_drop_index_test.dart`

- [x] **Step 1: Move the arithmetic verbatim** into
      `dropIndexForPointer({required double pointerX, required List<double?> slotCentres})`,
      keeping all three rules: compare against each cover's **centre** so a book is stepped
      over only past halfway; place unmeasured (null) centres by which end they are off, since
      a lazily-built row has no box for covers scrolled away; clamp via the existing
      `clampDropIndex`. Carry the "a preview that has to be corrected on release is a preview
      that lied" reasoning across.
- [x] **Step 2: `ShelfRow._dropIndexFor` becomes a wrapper** that builds the centres list
      from its slot keys with the lifted book removed.
- [x] **Step 3: Test the helper directly**, including off-screen nulls and the clamp, then
      confirm the existing shelf drag tests still pass — this task must be behaviour-neutral.

## Task 5: The drag

**Files:**

- Modify: `lib/ui/widgets/reading_shelf_row.dart`
- Modify: `lib/ui/views/library_view.dart`
- Modify: `lib/ui/pages/home_page.dart`

- [x] **Step 1: `ReadingBookDrag`** — a new payload type, which is the whole mechanism
      keeping the drag inside this row. No `shelfId` checks anywhere.
- [x] **Step 2: `ReadingShelfRow` → `ConsumerStatefulWidget`** with `mode` and `onReorder`;
      thread `onReorder` from `home_page.dart` through `LibraryPane` as `onReorderBooks`
      already is.
- [x] **Step 3: The single hold.** `LongPressDraggable` in both modes; keyed per book in
      view mode so the element and its in-flight gesture survive the rebuild into edit mode;
      keyless in edit mode _except_ the carried book, because a recognizer's delay is fixed at
      construction; `kBookStageTwoDelay` in view mode and `kShelfLiftDelay` in edit mode; the
      lift seeds the drop index to the lifted book's own position **and** calls the
      enter-edit-mode callback. Prune handover keys for books that leave the row.
      No lift _turn_ — a Reading cover is always face-out — only the lift scale.
- [x] **Step 4: `DragTarget<ReadingBookDrag>` over the row**, gap preview by paint (slide
      covers, don't re-lay-out, so the scroll extent and the keyed boxes stay put), row
      auto-scroll near either end (required: the row clips at ~3 covers and can hold 7+),
      set-down on a refused drop.
- [x] **Step 5: Cancel on vanish** — if the lifted book leaves the reading set mid-drag,
      `didUpdateWidget` cancels and sets down.
- [x] **Step 6: Keep `ShelfEdgeFades` in edit mode** and confirm the dragged cover is
      unaffected by the row's clip (it renders in an `Overlay`).

## Task 6: Tests

**Files:**

- Create: `test/reading_shelf_reorder_test.dart`
- Modify: `test/reading_shelf_row_test.dart`
- Modify: `test/support/home_page_harness.dart` (if the harness needs a reading-row lift)

- [x] **Step 1: New cases** — a drag reorders and reports ids in the new order; no drag in
      view mode and a tap still opens details; one hold both enters edit mode and leaves the
      cover carried; a Reading cover is refused by a queue shelf and a queue book by the
      Reading row; the preview matches where the book lands; a mid-drag status change cancels.
- [x] **Step 2: Invert the pinned inert case** — "long press does not enter edit mode"
      becomes "does". Keep `delete_book_r0 findsNothing` beside `delete_book_w0 findsOne`.

## Task 7: Record

**Files:**

- Modify: `docs/mockups/reading-shelf/index.html`
- Modify: `docs/mockups/index.html`

- [x] **Step 1: Amend the `edit-mode` entry** from "unchanged and inert" to inert except
      for reorder, keeping the reasoning that badges, rename, delete and cross-shelf drop are
      still absent.
- [x] **Step 2: Amend the summary** in `docs/mockups/index.html`.
- [x] **Step 3: `node docs/mockups/reading-shelf/verify.js`** and confirm the
      `<a class="row">` / `</a>` counts stay balanced at 18/18.

## Task 8: Validation

- [x] `flutter analyze 2>&1 | grep -E "^\s*error •" | grep -vE "•\s*build/"` — clean.
- [x] Full suite: expect the 3 documented stale `library_read_books_test.dart` failures and
      nothing else.
- [x] `flutter test test/reading_shelf_render_preview.dart` — the lamp frames must be
      unchanged by any of this.

## Task 9: Follow-up — the covers wobble and carry the remove badge

Asked for immediately after Task 8 landed, and it **reverses Task 6 Step 2 and Task 7 Step
1**: the badges are not absent after all. See the amendment at the foot of
`docs/superpowers/specs/2026-09-15-reading-shelf-reorder-design.md` for why the line was
drawn in the wrong place. The only difference left between an open cover and a shelved one
is that an open cover cannot land on another shelf.

**Files:**

- Create: `lib/ui/widgets/shelf/delete_book_badge.dart`
- Modify: `lib/ui/widgets/shelf_row.dart`, `lib/ui/widgets/reading_shelf_row.dart`,
  `lib/ui/views/library_view.dart`
- Modify: `test/reading_shelf_row_test.dart`, `test/reading_shelf_reorder_test.dart`,
  `test/reading_shelf_render_preview.dart`, `test/support/home_page_harness.dart`,
  `test/shelf_two_step_tap_test.dart`
- Modify: `docs/mockups/reading-shelf/index.html`, `docs/mockups/index.html`,
  `docs/superpowers/specs/2026-09-15-reading-shelf-reorder-design.md`

- [x] **Step 1: Extract the badge.** `_DeleteBookButton` leaves `shelf_row.dart` as
      `DeleteBookBadge`, with `DeleteBookBadge.keyFor(bookId)` owning `delete_book_<id>` so
      the two rows cannot draw different discs under one key.
- [x] **Step 2: Draw it on an open cover.** `_OpenBook` takes `isEditMode` and
      `deleteBadge` and hands both to `ShelfBookTile`, which already implements the wobble
      and the top-left placement. No badge on `childWhenDragging` — an `Opacity(0)` subtree
      still hit-tests.
- [x] **Step 3: Stop clipping in edit mode.** `ListView.clipBehavior` becomes `Clip.none`
      and `ShelfEdgeFades` becomes view mode's only, reversing the note written one step
      earlier that kept the fade in both. Without this the badge is sheared off ~7pt above
      the row's box.
- [x] **Step 4: Wire it.** `LibraryPane` passes its existing `onDeleteBook` to
      `ReadingShelfRow`, gated on edit mode exactly as the queue rows are. No provider
      change: `_onDeleteBook` is shelf-agnostic.
- [x] **Step 5: Invert the pin.** `delete_book_r0 findsOne`, joined by cases for the wobble,
      for neither appearing at rest, and for the badge tap reaching the confirmation sheet.
      `reading_shelf_reorder_test.dart` loses `pumpAndSettle` in edit mode — `Wiggle` repeats
      forever, which is what turned seven of its cases red.
- [x] **Step 6: Record and validate.** The `edit-mode` entry and its frame callout, the
      summary row, the spec amendment; a `reading_3_edit` preview frame, because "the badge
      is not clipped" needs eyes. `flutter analyze` clean, suite green at 1315, verify.js
      passing, `<a class="row">` balanced at 19/19.
- [x] **Step 7: The cover in flight keeps its ribbon.** Spotted by eye straight after: a
      lifted cover was un-marked for as long as it was in the air, because `_DraggedCover`
      rebuilds the drawing instead of reusing `_OpenBook`. Two more misses in the same three
      lines — `pageCount` was never passed, so the flying cover's jitter did not match the
      slot the gap was measured from, and `pressEffect` was left on. The day stamp stays off
      on purpose; see the spec. Pinned by counting ribbons mid-drag and by a
      `reading_3_edit_lifted` preview frame.
