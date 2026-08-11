# Book 3D chassis and generated covers

**Date:** 2026-08-11
**Status:** Approved design, pending implementation plan

## Context

Books are currently drawn as flat `Image.network` rectangles with a single drop shadow
(`lib/ui/widgets/book_widget.dart`). Missing covers fall back to a gray box reading "no image".
On the home page these sit in horizontal rows on top of `ShelfWidget`, an 8px shelf line — a
skeuomorphic bookshelf whose books don't read as physical objects.

This design ports the visual language of Vercel's `Book` component (3D chassis, binding band,
page block, generated cover typography) to Flutter, adapted for phone-sized rendering and touch
input.

## Goals

- Books read as physical objects on the shelf, not flat images.
- Missing covers produce an attractive generated cover instead of an error-looking gray box.
- A hold gesture reveals the book's depth, replacing the hover affordance the reference uses.

## Non-goals

- `BookVertical` (`lib/ui/widgets/book_vertical.dart`, used only by `finished_books_sheet.dart`)
  is not touched.
- No paper-texture overlay. The reference uses a remote AVIF with `mix-blend-hard-light`, which
  has no cheap Flutter equivalent and costs a network asset.
- No new book metadata from upstream catalogs. Real page counts are deliberately not fetched
  (see Decisions).

## Decisions

| Decision                       | Choice                                        | Rationale                                                                                                                                               |
| ------------------------------ | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Resting angle                  | **0°**                                        | Matches the reference literally. Depth still reads because perspective is measured from the book's centre.                                              |
| Depth visible at rest          | **No** (see correction below)                 | The page block projects inside the cover's silhouette and is occluded by it. Depth is a reward for holding, not a resting state.                        |
| Perspective                    | **`4.6 × width`**, not a constant             | A fixed `900px` is tuned for a 196px book; at 88px it yields ~1px of depth. Scaling keeps the look size-invariant.                                      |
| Width                          | From the cover image's intrinsic aspect ratio | Already the behaviour via `BoxFit.fitHeight`. Real signal, free.                                                                                        |
| Height                         | **±6%**, hashed from ISBN                     | No real source exists. Small enough not to read as data, enough to break the ruler-straight top edge.                                                   |
| Thickness                      | **0.22–0.34 × width**, hashed from ISBN       | Also fabricated. Legible once the fore-edge is visible during a turn.                                                                                   |
| Page count as thickness source | **Rejected**                                  | Kakao returns none, and it's the primary provider for Korean titles. Would work for some books and not others — reads as a bug.                         |
| Generated cover ratio          | **2/3**                                       | Matches real covers. At the reference's `49/60` every generated cover would be the widest book on the shelf, which is strange behaviour for a fallback. |
| Turn trigger                   | **Two-stage hold**                            | Stage one turns the book; stage two enters edit mode. The turn doubles as a progress indicator for the long press.                                      |
| Turn angle                     | **16°**                                       | The reference's hover angle.                                                                                                                            |

## Correction: there is no visible depth at rest

An earlier revision of this document claimed the reference shows roughly 2.6px of fore-edge at
`rotate-0`, reasoning that perspective is measured from the book's centre so the right edge sits
off-axis. That was wrong, and the geometry test in `test/book_chassis_geometry_test.dart` now
proves it.

The page block is a quad in the plane `x = width / 2`, spanning z from 0 to the book's thickness.
Receding shrinks a point toward the projection centre, so the block's outer edge lands at
`(width / 2) * p / (p + thickness)`, strictly inside the cover's own right edge at `width / 2`. The
cover paints last, so it occludes the block entirely. The back board is inside it too. At 0 degrees
a book is a rounded rectangle with a binding band and a shadow, and nothing else.

This changes no decision in this document. The resting angle is 0 and the turn is bound to the
hold, so the reference's behaviour is preserved exactly: the reference reveals depth on hover, this
app reveals it on hold. Two consequences are worth stating plainly:

- Thickness variation is invisible at rest. The hashed `thicknessFactor` only reads while a book is
  held. Still worth having, because that is when it is looked at, but it does no work on a shelf at
  a glance.
- The shelf gains no depth. What shelves gain is the binding band, asymmetric corners, the
  four-layer shadow, size variation, and generated covers in place of gray "no image" boxes.

If depth at rest is wanted later, either the resting angle becomes non-zero, or the page block is
drawn outside the cover's right edge as a flat fore-edge sliver rather than as a receding 3D face.

## Geometry

Flutter has no `transform-style: preserve-3d` — `Transform` flattens its children. The book is
therefore assembled as three sibling flat quads in a `Stack`, each carrying the full composed
matrix.

Build one parent matrix per book:

```
parent = perspective(4.6 × width) × rotateY(θ)
```

then pre-multiply each face's local transform into it:

| Face       | Local transform                                                  | Paint order |
| ---------- | ---------------------------------------------------------------- | ----------- |
| Back board | `translateZ(thickness)`                                          | 1st         |
| Page block | hinge at right edge, `rotateY(90°)`, push out by `thickness / 2` | 2nd         |
| Cover      | identity                                                         | 3rd         |

Paint order is fixed and correct for all `|θ| < 90°`, so no z-sorting is required.

`setEntry(3, 2, 1 / (4.6 × width))` supplies perspective. **Flutter's z sign is inverted relative
to CSS**, so the back board translates _positive_ z. Verify empirically rather than by algebra;
the invariant to check on device is: the page block lands on the **right** and the back board
**recedes**.

Cover geometry comes from the decoded image's intrinsic ratio. Generated covers use `2/3`.

## Jitter hash

A single function returns two independent values, drawn from different bit ranges so height and
thickness don't correlate:

```
_bookJitter(String isbn) -> (heightFactor, thicknessFactor)
  heightFactor    ∈ [0.94, 1.06]
  thicknessFactor ∈ [0.22, 0.34]
```

Implemented with **FNV-1a**, not `String.hashCode`. Dart does not guarantee `hashCode` stability
across SDK versions; if it shifted, every book on every shelf would silently change height after
a Flutter upgrade. FNV-1a pins the values permanently.

Books with an empty `isbn` fall back to `heightFactor = 1.0`, `thicknessFactor = 0.28`.

`heightFactor` multiplies the `height` parameter, and width follows from the cover's aspect ratio,
so a book that hashes tall is also proportionally wider. The hash is applied on every surface, so
a given book keeps consistent proportions across shelves, search, and the details page — which
also keeps the `Hero` flight between shelf and details a pure scale, with no shape change.

## Interaction: two-stage hold

| t         | Event          | Visual                                                                                  |
| --------- | -------------- | --------------------------------------------------------------------------------------- |
| 0ms       | `onTapDown`    | Shadow blur and offsets scale to 0.85×, over 90ms — reads as contact                    |
| 140ms     | Hold confirmed | Begin turn                                                                              |
| 140–400ms | —              | Rotate 0° → 16°, `easeOutCubic`, 260ms                                                  |
| 400–700ms | —              | Held at 16°                                                                             |
| 700ms     | Stage two      | `onLongPress` fires (edit mode). Return to 0° over 120ms `easeOut` as the wiggle starts |

Release handling:

- Before 140ms → clean tap. No turn. `onTap` navigates, as today.
- Between 140ms and 700ms → cancel stage two, return to 0° over 180ms `easeOut`, then `onTap`
  navigates. Holding to inspect and releasing behaves like a tap, which matches current semantics.
- `onTapCancel` (the horizontal `ListView` won the gesture and started scrolling) → cancel the
  stage-two timer, return to 0°, no navigation.

Stage two runs off an internal `Timer` rather than `GestureDetector.onLongPress`, because
`GestureDetector` does not expose the long-press deadline and the default 500ms leaves only
~100ms of fully-turned book. The existing `onLongPress` parameter is retained as the stage-two
callback so no call site changes meaning.

`pressEffect: false` disables both the turn and stage two. Edit mode already passes
`pressEffect: !isEditMode` and `onLongPress: null`, so books stay flat while wiggling and the
250ms `_DelayedReorderableListener` reorder drag is unaffected. The `Draggable` feedback book
also stays flat.

When `MediaQuery.disableAnimations` is set, the turn is skipped entirely; stage two still fires
at 700ms.

## Generated covers

Rendered when `thumbnail.isEmpty` **or** when `Image.network`'s `errorBuilder` fires. Replaces
the current gray "no image" box.

Layout follows the reference's `stripe` variant: a color block filling the top 50%, and below it
a `surface`-toned area carrying the title. Padding is `6.1%` on three sides and `14.3%` on the
left, so the text clears the binding band.

Color is hashed from the ISBN out of a fixed palette:

| Color     | Use         |
| --------- | ----------- |
| `#09BC8A` | brand green |
| `#0E7C7B` | deep teal   |
| `#2F6690` | slate blue  |
| `#E0644E` | coral       |
| `#F2B544` | amber       |
| `#7C5CBF` | violet      |

Title color is always `primaryText`, because in the `stripe` layout the title sits on the
`surface`-toned lower half and never on the color block. No luminance calculation is needed, and
the cover adapts to dark mode with no separate palette. The color block carries no text, so the
palette has no contrast constraint.

Size tiers, by rendered width. Only two tiers, because the actual size range in the app is narrow:

| Surface                  | Height                | Rendered width |
| ------------------------ | --------------------- | -------------- |
| Home shelves             | `screenHeight × 0.15` | ~86px          |
| `search_book_page`       | default (same)        | ~86px          |
| `user_library_page`      | `screenHeight × 0.15` | ~86px          |
| `book_info_bottom_sheet` | 120                   | ~79px          |
| `book_details_tab_view`  | 180                   | ~120px         |

| Width   | Mascot | Title size     | Max lines |
| ------- | ------ | -------------- | --------- |
| ≥ 110px | Shown  | 11.5% of width | 3         |
| < 110px | Hidden | 13.5% of width | 3         |

The 110px threshold means the mascot appears on the details page only. Any threshold above 120px
would be dead code, since no surface renders a book wider than that.

The mascot is `assets/icons/smileBookwormIcon.svg`, recolored to the title color. Titles ellipsize
at 3 lines.

## Chassis tokens

Corner radii scale with size: left `6 × (width / 196)`, right `4 × (width / 196)`, each clamped to
a 2px minimum.

Binding band, 8.2% of width, `BlendMode.overlay`, horizontal gradient:

| Stop | Value     |
| ---- | --------- |
| 0%   | black 26% |
| 34%  | black 7%  |
| 78%  | white 30% |
| 100% | black 11% |

The white stop at 78% is the highlight ridge and the black stop at 100% is the crease — without
both, the band reads as a dark smear rather than a binding.

Page block, light mode: horizontal `#eaeaea` → transparent at 70%, layered over vertical
`#fff` → `#fafafa`. No page lines; they make it look cheap at small sizes.

Shadow, light mode — four layers, with offsets and blur radii scaled by `width / 196` so small
books don't carry oversized shadows:

```
(0, 1)  blur 1   black 3.5%
(0, 3)  blur 6   black 4.5%
(0, 10) blur 18  black 5%
(0, 22) blur 36  black 5.5%
```

Dark mode overrides:

| Element         | Light              | Dark                                                    |
| --------------- | ------------------ | ------------------------------------------------------- |
| Page block base | `#fff` → `#fafafa` | `surfaceVariant` → `#262628`                            |
| Page block edge | `#eaeaea`          | black 35%                                               |
| Back board      | `#e3e3e3`          | `#2A2A2C`                                               |
| Shadow          | 4 layers as above  | 2 layers at ~1.6× alpha, plus a 1px top rim at white 6% |

Left near-white, the page block and back board glow against `#121212`.

## Widget API and call sites

`BookWidget` gains two required parameters:

```dart
BookWidget({
  double? height,              // base height, before jitter
  required String imageUrl,
  required String isbn,        // NEW — drives jitter and generated-cover color
  required String title,       // NEW — generated-cover text
  VoidCallback? onTap,
  VoidCallback? onLongPress,   // stage two
  String? heroTag,
  bool pressEffect = true,     // now gates the turn and stage two
})
```

`isbn` and `title` rather than a `Book` object, because `search_book_page.dart` holds
`BookSearchResult`, not `Book`.

Five call sites to update: `home_page.dart` (×2), `search_book_page.dart`,
`user_library_page.dart`, `book_details_tab_view.dart`, `book_info_bottom_sheet.dart`.

`_ShelfRow` changes: the shared `bookHeight` computed at `home_page.dart:1122` becomes a
per-book height. Four consumers each compute their own — `_buildBookContent`,
`_buildEditableBookList`, the `Draggable` feedback (currently `bookHeight * 1.1`), and the row
`SizedBox`. The row's `ListView` bottom-aligns its children so shorter books sit on the shelf
line rather than floating.

The row `SizedBox` must be sized to **`bookHeight × 1.06`**, the maximum the jitter can produce,
not to `bookHeight`. Today the two are equal, so leaving it would clip every book that hashes
taller than the base. The shelf line sits directly beneath this box, so the row grows by 6% and
vertical shelf spacing shifts slightly.

## Performance

Every book renders three layers at all times, even at rest, so a shelf row triples its layer
count. Each book gets a `RepaintBoundary`; at rest the transform is static so Flutter caches the
layer, and only the held book animates. Worth profiling a library with several full shelves
before shipping.

## Testing

- Generated cover renders when `thumbnail` is empty.
- Generated cover renders when `Image.network` fails, via `errorBuilder`.
- `_bookJitter` pinned to golden values for a fixed set of ISBNs, so heights cannot drift.
- Jittered height stays within ±6% of the base for a large sample of ISBNs.
- Empty ISBN yields the neutral fallback factors.
- Hold past 140ms sets the turned state; release returns it; `onTapCancel` returns it without
  navigating.
- Stage two fires at 700ms and not before.
- `pressEffect: false` produces neither turn nor stage two.
- The shelf row does not clip a book that hashes to the maximum height factor (1.06).
- The mascot is hidden at 86px wide and shown at 120px, pinning the 110px tier boundary.
- The mascot is hidden at 86px wide and shown at 120px, pinning the 110px tier boundary.

Existing tests: `library_delete_book_test.dart` finds by `BookWidget` type and should keep
passing once the new required parameters are supplied. `finished_books_sheet_test.dart` targets
`BookVertical` and is unaffected.

## Risks

- **The page block is the one face that can collapse silently.** The cover and back board are handed
  tight constraints by the chassis; the page block sizes itself, and a childless `DecoratedBox` is a
  `RenderProxyBox` that takes `constraints.smallest`. When it collapses the failure is invisible
  rather than loud, because the flat back board sits directly behind and shows through the fore-edge
  as a uniform slab. Guarded by `test/book_page_block_test.dart`.
- **Flutter gradients default to horizontal, CSS defaults to vertical.** `linear-gradient(#fff,
#fafafa)` is top-to-bottom; `LinearGradient(colors: [...])` is left-to-right. Any gradient
  transliterated from the reference needs `begin`/`end` stated explicitly. Also guarded by
  `test/book_page_block_test.dart`.

- **No depth at rest.** See the correction above. Shelves get the chassis, the size variation and
  generated covers; the fore-edge only appears while a book is held. If that reads as too little on
  device, the resting angle has to change. Raising thickness will not help, because thickness is
  occluded at 0 degrees no matter how large it is.
- **Generated covers will look better than real ones.** The reference's appeal is largely its
  typography and flat color, which only the fallback path gets. Photographic Kakao covers receive
  the chassis only. Accepted.
- **Long-press muscle memory.** Entering edit mode now takes 700ms instead of the platform
  default 500ms. The Edit button in `_LibrarySubHeader` remains unchanged.
