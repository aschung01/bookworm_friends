# Reordering the Reading shelf

Give the reader a drag-and-drop order for the Reading shelf, and somewhere for that
order to live.

## The problem this closes

`readingBooksOf` collects every book at `bookStatusReading` across all shelves and
returns them in **shelf order**. Its own doc comment already concedes the gap:

> Order is shelf order rather than by `start_date` … Note that this makes the Reading
> shelf's order a consequence of where the books came from, which is the one thing a
> reader cannot change about it.

Every other row in the library can be arranged. This one cannot, and the reason is
structural rather than an omission: the Reading shelf is a _view_ over books drawn from
different queue shelves, and `books.position` means "place within my own shelf". There
is nowhere for a Reading-shelf order to be written.

## Decisions

### The gesture is edit mode

A hold enters edit mode and the Reading covers become draggable, exactly as the queue
shelves below behave.

Rejected: **a separate direct-long-press gesture outside edit mode**, which would keep
"the Reading shelf is inert in edit mode" literally true but leave two rows on one
screen answering the same gesture differently — which reads as a bug rather than as a
distinction. Also rejected: **both**, which is the same problem plus a second code path.

This inverts a pinned assertion. `reading_shelf_row_test.dart` currently holds _"Given a
long press on an open cover, Then edit mode is not entered"_; that flips. The rest of the
`edit-mode` decision stands unchanged — **no delete badges, no rename, no delete, no
cross-shelf drop** — so the shelf is still inert in every respect but this one.

> **Superseded on the badges.** See [Amendment: the covers wobble and carry the badge
> too](#amendment-the-covers-wobble-and-carry-the-badge-too) at the foot of this file. The
> sentence above draws the line in the wrong place, and the reason is in the amendment.

### Reorder only, enforced by the payload type

A Reading cover cannot be dragged out of the row, and a queue book cannot be dropped
into it.

The enforcement is a **new `ReadingBookDrag` type** rather than an `if`. A queue shelf's
`DragTarget<ShelfBookDrag>` cannot accept a `ReadingBookDrag`, and the Reading row's
`DragTarget<ReadingBookDrag>` cannot accept a queue book. There is no `shelfId` check for
a future caller to forget.

This matters because the permissive version is quietly broken rather than merely
generous: if Reading covers carried `ShelfBookDrag`, every queue shelf below would
already accept the drop, and `onMoveBook` rewrites `shelf_id` and positions but **not**
`status` — so the book would stay at status 1, reappear immediately on the Reading shelf,
and the only thing that changed would be an invisible "belongs to" field.

Rejected: **dropping onto a queue shelf means "stop reading"** and **dragging a queue
book in means "start reading"**. Both make an irreversible-looking state change reachable
by a slightly-off drag — one clears `status`, the other sets `start_date` and starts the
day stamp counting. `book_info_bottom_sheet` already owns status behind an explicit tap,
and that stays the only way to change it.

### The order lives in a new column, `books.reading_shelf_index`

Rejected: **reuse `books.position`**. Two books lifted from different shelves collide,
and writing it rewrites each book's slot in its own queue shelf — which reintroduces
precisely the wart `withoutReadingBooks` was built to kill. That filter's doc promises
"clearing the status puts the cover back on that plank in the position it was authored
in", and this feature must not spend that promise.

Rejected: **sort by `start_date`**. Not an authored order at all, so it does not answer
the request. Shelf order already serves as the null fallback.

### Why not `reading_position`, and why `position` keeps its name

`reading_position` was the first candidate and is actively misleading in a _reading_ app:
it reads as progress through the text, the ebook sense of "where I am". `reading_shelf_index`
cannot be misread that way, because it names the shelf it indexes.

The follow-on question — rename `books.position` to `shelf_index` for symmetry — is
**declined, and deliberately not bundled here**:

- **A rename silently breaks already-distributed builds.** `Book.fromJson` reads
  `position: json['position'] as int? ?? 0`. That defensive default exists for _forward_
  compatibility (rows written before a column existed). Rename the column and an older
  build reads `position` as absent, so every book collapses to `0` and
  `shelf.books.sort(...)` degenerates into arbitrary order, while `update({'position': i})`
  becomes a PostgREST 400. Scrambled shelves, no in-app explanation.
- **Adding a column is backward compatible; renaming one is a hard break.** An old build
  ignores `reading_shelf_index` and orders the Reading shelf by shelf order — exactly
  today's behaviour. It degrades to the status quo instead of breaking.
- **Renaming only `books.position` creates a fresh inconsistency** with `shelves.position`,
  and renaming that one too reaches `.order('position')` in the library fetch, where an
  old client would 400 on the whole query and get no library at all.

If it is ever wanted, the safe route is expand/contract (add `shelf_index`, dual-write,
backfill, ship, wait for clients to roll over, drop `position`) as its own change. Bundling
it here would hold the reorder work hostage to a cosmetic migration. `book.dart` gets a
comment recording this, so the next reader finds the reason rather than "fixing" the wobble.

### Built in the row, with one extraction

The drag is written bespoke in `ReadingShelfRow`: draggable covers, a row-level drop
target, the gap preview, row auto-scroll near either end, lift and set-down. **Not**
built: the density turn, cross-shelf handover, pane auto-scroll — none of which a
single-row reorder has any use for.

Rejected: **extracting a full shared reorder engine from `shelf_row.dart`**. Its version
is welded to the density turn and to cross-shelf handover; the extraction would be a
large refactor of the file the whole library depends on, risking ~1,270 passing tests for
a benefit that is hypothetical while there are two callers.

Rejected: **making the Reading shelf a mode of `ShelfRow`**, which the record already
declined — "a separate widget from `ShelfRow` rather than a mode of it, deliberately" —
and which drags back every piece of machinery the split removed.

What _is_ shared is the one piece that must not drift: the pointer→drop-index
arithmetic, whose own comment insists "a preview that has to be corrected on release is a
preview that lied." Two implementations of that would eventually disagree.

## Schema

New migration, `supabase/migrations/20260915120000_book_reading_shelf_index.sql`, following
the house style of `20260822120000_book_cover_color.sql` — the reasoning, then the DDL, then
`COMMENT ON COLUMN`.

```sql
ALTER TABLE public.books ADD COLUMN reading_shelf_index integer;
```

**Nullable, no default.** NULL means "has no place on the Reading shelf", which is the
truth for every book that is not at status 1. A `NOT NULL DEFAULT 0` would assert that
every finished and unstarted book sits first on a shelf it is not on.

**Backfilled, unlike `cover_color`.** That column refused a server-side backfill because
no server-side average could equal Flutter's own downsample, so every book would visibly
change tone on the day it ran. The opposite holds here: the value being backfilled _is_
the order the reader currently sees, so the backfill is what makes deploy day invisible.
Partitioned per user, because the Reading shelf belongs to one reader.

```sql
WITH ordered AS (
  SELECT b.id,
         ROW_NUMBER() OVER (PARTITION BY b.user_id
                            ORDER BY s.position, b.position, b.created_at) - 1 AS rn
    FROM public.books b
    JOIN public.shelves s ON s.id = b.shelf_id
   WHERE b.status = 1
)
UPDATE public.books b SET reading_shelf_index = ordered.rn
  FROM ordered WHERE ordered.id = b.id;
```

No RLS change — a new column inherits the table's policies. No index: the library already
fetches every shelf and book for the user in one query, and this is sorted client-side.

## Ordering

`readingBooksOf` collects at status 1 in shelf order as today, then sorts by
`readingShelfIndex` ascending with **NULLs last**, tie-broken by the collected ordinal.

The tiebreak is explicit rather than relying on sort stability: Dart's `List.sort` does
not guarantee it, so "falls back to shelf order" has to be written down or it is luck.
Both callers inherit this for free, since it is a pure function over shelves —
`LibraryPane`, which has no `ref`, and `readingBooksProvider`.

## Writes

| When                 | What happens                                                                                                                                                                                        |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A reorder lands      | `LibraryNotifier.reorderReadingBooks(bookIds)` — optimistic local update, then one `UPDATE … SET reading_shelf_index = i` per id, mirroring `reorderBooksInShelf`. **`position` is never touched.** |
| Book → status 1      | `reading_shelf_index = min - 1`, where `min` is the smallest non-null index among books currently at status 1, or `0` when there are none                                                           |
| Book → status 0 or 2 | `reading_shelf_index = NULL` in the database                                                                                                                                                        |

**Front insert, in one UPDATE.** A book being opened goes to the head of the Reading
shelf. Appending would hide it: the row clips at about three covers behind
`ShelfEdgeFades`, so a fourth open book would arrive off-screen and the "the shelf
arrived" feedback the zero-state decision rests on would be lost. `min - 1` places it
there without shifting the others, so one write does what a shift would spend _n_ on.
Values may drift negative, which is harmless for ordering and is normalised back to
`0…n-1` by the next reorder. Books whose index is still NULL are ignored when taking the
minimum, since they sort last and so are not at the head for the new book to get in front
of.

Unlike `reorderBooksInShelf`, whose doc notes it "only has to cover the books the caller
can see" because finished books are hidden from the shelves, **`bookIds` here is the whole
reading set**: the Reading row clips visually but every open book is in its list, so there
are no absent books whose stored index has to survive the write.

**The local `Book` keeps its stale index when a book leaves Reading**, deliberately.
`copyWith` documents that its nullable fields "can be set but not cleared", and this is
not worth breaching that invariant for: a book at status 0 or 2 is filtered off the
Reading shelf, so the value is invisible, and if it is re-opened in the same session the
front insert overwrites it. Only the database write nulls it, which is what keeps the
column honest for the next fetch.

## Interaction

`ReadingShelfRow` becomes a `ConsumerStatefulWidget` and gains `mode` plus an `onReorder`
callback. The callback is threaded from `home_page.dart` through `LibraryPane` exactly as
`onReorderBooks` already is, rather than the row reaching for the notifier itself:
`LibraryPane`'s callback seam is the established pattern and it keeps the row testable
without a provider override. Dragging is unreachable while visiting a friend for free,
since edit mode is already impossible inside a visit.

### The single hold that both enters edit mode and starts carrying

Replicated from `shelf_row.dart`, because a drag cannot be started programmatically and a
`Draggable` that appears after the finger is already down can never adopt that pointer — a
recognizer claims its pointer route at pointer-down. The recipe, all four parts of which
are load-bearing:

1. **The cover is a `LongPressDraggable` in both modes**, so the draggable that will carry
   the book exists before the hold completes.
2. **Keyed in view mode** with a per-book `GlobalKey`, so the element — and with it the
   in-flight gesture — survives the rebuild into edit mode. In edit mode every cover is
   built _keyless_ except the one being carried, because a recognizer's delay is fixed at
   construction: an element that survives keeps the long view-mode delay it was born with,
   which is wanted only for the gesture actually in flight.
3. **Delays match the shelves** — the view-mode hold waits `kBookStageTwoDelay`, the same
   wait that has always entered edit mode, and a lift inside edit mode is the quicker
   `kShelfLiftDelay`. Reusing the constants is what makes the two rows feel identical.
4. **The lift seeds the drop index** to the lifted book's own position, and calls the
   enter-edit-mode callback. Seeding is not decoration: in view mode there is no
   `DragTarget` yet — the row only becomes one on the frame edit mode arrives — and
   `onMove` answers pointer _movement_, not a target appearing under a finger holding
   still. Without the seed the covers to the right would slide over the held book's slot
   and stay there until the finger moved.

`_handoverKeys`' pruning behaviour comes along with it: keys for books no longer in the
row are dropped in `didUpdateWidget`.

What is _not_ replicated: the lift turn. A Reading cover is always face-out — there is no
`spines` density here and no surfacing step — so only the lift _scale_ is needed as the
cue that the book has come loose, since it is picked up where it stood.

### Other mechanics

- **Row auto-scroll** near either end is required, not optional: the row clips at about
  three covers and can hold seven or more, so without it the books past the fade are
  unreachable by drag.
- **`ShelfEdgeFades` stays in edit mode.** The Reading row clips by design, and the fade
  is what makes the clip read as an unfinished edge rather than a rendering fault. The
  dragged cover is in an `Overlay` and so is unaffected by the row's clip.
- **A vanishing book cancels the drag.** If the lifted book leaves the reading set
  mid-gesture — finished on another device — `didUpdateWidget` cancels and sets it down,
  mirroring how `ShelfRow` handles edit mode ending mid-gesture.

## The extraction

New pure helper, called by both rows:

```dart
/// Where a book held at [pointerX] would be inserted.
///
/// [slotCentres] is one entry per book in the row **with the lifted book removed**, in
/// row order; null where a cover is scrolled off and has no laid-out box to measure.
int dropIndexForPointer({
  required double pointerX,
  required List<double?> slotCentres,
});
```

It carries over all three rules from `_dropIndexFor` verbatim: compare the finger against
each cover's **centre**, so a book is stepped over only once the finger is more than
halfway past it; place unmeasured covers by which end they are off, since a lazily-built
row has no box for the ones scrolled away; and clamp to the row's ends via the existing
`clampDropIndex`, so the gap never opens where the book cannot land.

`ShelfRow._dropIndexFor` becomes a thin wrapper that builds the centres list from its slot
keys, so there is one implementation of the arithmetic and two callers of it.

## Testing

**`reading_shelf_reorder_test.dart`** (new)

- A drag reorders the row and reports ids in the new order.
- No drag in view mode; a tap still opens details.
- A single hold enters edit mode **and** leaves the cover carried — the handover.
- A Reading cover is refused by a queue shelf; a queue book is refused by the Reading row.
- The drop preview matches where the book actually lands.
- A book leaving the reading set mid-drag cancels cleanly.

**`reading_shelf_row_test.dart`** (amended)

- The "long press does not enter edit mode" case inverts.
- The pinned `delete_book_r0 findsNothing` beside `delete_book_w0 findsOne` **stays** — the
  shelf gains a drag and nothing else. _(Superseded — it inverts too. See the amendment.)_

**Provider tests**

- Sort: `reading_shelf_index` ascending, NULLs last, shelf order as tiebreak.
- `reorderReadingBooks` writes `0…n-1` and leaves every `position` untouched.
- Front insert on entering Reading; NULL on leaving.

**Drop-index tests** — the extracted helper, including the off-screen (null centre) cases
and the clamp, so the shared arithmetic is pinned once rather than through two widgets.

## Record

- `docs/mockups/reading-shelf/index.html` — the `edit-mode` entry changes from "unchanged
  and inert" to inert _except for reorder_, with the reasoning above and the note that
  badges, rename, delete and cross-shelf drop are still absent.
- `docs/mockups/index.html` — the Reading shelf row's summary gains the reorder.
- The migration cites this spec by path, as `book_cover_color.sql` cites its own.

## Parked

Renaming `books.position` to `shelf_index`. Not blocking; needs an answer on whether any
client other than the next build talks to this database before it can be scheduled as an
expand/contract change.

## Amendment: the covers wobble and carry the badge too

Shipped immediately after the above, and it **contradicts** the "no delete badges" line in
_The gesture is edit mode_ rather than extending it. In edit mode a Reading cover now
behaves exactly like a queue cover: it wobbles, it carries the remove badge at its
top-left, it reorders. The single remaining difference is that it cannot land on another
shelf.

**Why the original line was wrong.** It rested on the phrase "this shelf is not a place the
reader arranges" — which is the sentence the reorder had just falsified. What the split
actually produced on screen is a row whose covers wobble under a hold, side by side with
rows whose identical wobbling covers each carry a badge. A reader cannot learn that as a
restraint; they read it as the badge having failed to draw. The distinction the spec was
trying to protect — that a book's _status_ is not draggable — is carried entirely by the
`ReadingBookDrag` payload type and needs no second expression.

**Why "delete from here" is not ambiguous**, which was `edit-mode`'s original objection
("delete the book, or close it?"). The badge is not a delete: it opens the same
confirmation sheet a queue book's does, and `_HomePageState._onDeleteBook` takes a book id
with no shelf attached, because a book has exactly one home shelf whatever row it is
currently standing on. Closing a book is a _tap_ in `book_info_bottom_sheet` and always
was, so the two acts were never competing for one gesture.

**What this forced in the code**, none of which the reorder needed:

- `_DeleteBookButton` is lifted out of `shelf_row.dart` as
  `lib/ui/widgets/shelf/delete_book_badge.dart`'s `DeleteBookBadge`, with
  `DeleteBookBadge.keyFor(bookId)` owning the `delete_book_<id>` convention. Two rows
  drawing their own disc under the same key is how they drift.
- **The Reading row stops clipping in edit mode.** The badge lands ~7pt above the row's box
  and 22pt left of the leading cover, so `ListView.clipBehavior` becomes `Clip.none` there
  and `ShelfEdgeFades` becomes view mode's only — a fade needs a clipped edge to mean
  anything. `ShelfRow` splits the two modes the same way and says so. This reverses a note
  written one step earlier that kept the fade in both.
- `reading_shelf_reorder_test.dart` can no longer `pumpAndSettle` in edit mode: `Wiggle`
  repeats, so there is no quiescent frame. Seven cases went red on exactly that and now use
  a bounded `_settle`.

**Still absent, and not an inconsistency:** the _shelf's_ own editing. No rename, no delete
on the tab, because the reader did not make this shelf. And no cross-shelf drop.

### Follow-up: the cover in flight is the cover that was lifted

Asked for by eye once the badges were in: **a lifted cover was losing its ribbon.** Every
book on this shelf is at `bookStatusReading` and wears one, so the drag un-marked it for
exactly as long as the reader was looking straight at it.

The cause is that `_DraggedCover` builds the drawing from scratch rather than reusing
`_OpenBook`, and a second miss was sitting beside it: **`BookWidget.pageCount` was never
passed**, and the jitter is hashed from the ISBN _and_ the page count — so the cover under
the finger was a hair's different height and thickness from the one that left the row, whose
slot is what the preview gap was measured from. `ShelfRow`'s own feedback already carried a
note about exactly that trap. `pressEffect` is now `false` too; nothing can hold a widget in
an `Overlay` the finger never addresses.

**The day stamp deliberately does not come with it.** `D+n` is an annotation about a book
sitting on a shelf being read, not about an object in transit, and at 1.06x under a finger it
is the one element small enough to read as debris. The ribbon is part of the book; the stamp
is a mark on the row. This is why the fix is not simply `_OpenBook(withHero: false)`.

Pinned in `reading_shelf_reorder_test.dart` by lifting a cover and counting ribbons: two
while a book is in the air — the invisible ghost holding the slot keeps its own — with
exactly one of them outside `ReadingShelfRow`, since the feedback mounts in the route's
`Overlay`. A `reading_3_edit_lifted` preview frame is the eyes-on half, because "the flying
cover still wears its mark" is not something a resting frame can show.

The pinned case in `reading_shelf_row_test.dart` inverts to `delete_book_r0 findsOne`, and
is joined by cases for the wobble (`ShelfBookTile.isEditMode`, every `Wiggle` enabled), the
absence of both at rest, and the badge tap reaching the confirmation. The record entries in
`docs/mockups/reading-shelf/index.html` (`edit-mode`, and the callout on the frame itself,
now titled _overturned_) and `docs/mockups/index.html` carry the same reversal.
`test/reading_shelf_render_preview.dart` gained a `reading_3_edit` frame, because "the badge
is not sheared off by the row's clip" is not a claim a widget tree can make.
