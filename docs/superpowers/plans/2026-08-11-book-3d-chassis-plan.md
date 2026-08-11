# Book 3D Chassis and Generated Covers — Implementation Plan

> **For agentic workers:** Implement task-by-task, in order. Steps use checkbox (`- [ ]`) syntax
> for tracking. Read `.agents/skills/flutter-tester/SKILL.md` before writing any test — this
> project has established Given-When-Then and layer-isolation conventions.

**Design:** `docs/superpowers/specs/2026-08-11-book-3d-chassis-design.md`

**Goal:** Replace the flat `Image.network` book with a 3D chassis (back board, page block, cover),
add ISBN-hashed size variation, add a two-stage hold that turns the book, and replace the gray
"no image" fallback with a generated cover.

**Architecture:** `book_widget.dart` stays at its current path so no import churn hits the five
call sites, and becomes a thin gesture-and-state wrapper. The pieces it composes live in a new
`lib/ui/widgets/book/` directory: pure-Dart geometry and jitter, the 3D chassis, and the generated
cover. Geometry is pure Dart with no Flutter dependency beyond `Matrix4`, so it's unit-testable
without pumping widgets.

**Tech Stack:** Flutter 3.32+, Dart 3, `flutter_svg` (already a dependency, for the mascot)

---

## Task 1: Geometry and jitter

**Files:**
- Create: `lib/ui/widgets/book/book_geometry.dart`
- Create: `test/book_geometry_test.dart`

- [ ] **Step 1: Implement the FNV-1a jitter hash**

Write `lib/ui/widgets/book/book_geometry.dart`. The multiply must stay web-safe — this repo has a
`web/` target, and on JS `int` is a double, so a naive `hash * 0x01000193` exceeds 2^53 and loses
precision before masking. Split it using `0x01000193 == (1 << 24) + 403`:

```dart
int _fnv1a(String s) {
  var hash = 0x811C9DC5;
  for (final unit in s.codeUnits) {
    hash ^= unit & 0xFF;
    // hash * 0x01000193 mod 2^32, split so the intermediate stays under 2^53.
    // Only the low 8 bits survive the << 24, and hash * 403 < 2^41.
    hash = (((hash & 0xFF) << 24) + hash * 403) & 0xFFFFFFFF;
  }
  return hash;
}
```

- [ ] **Step 2: Add `BookJitter`**

Two independent draws from disjoint bit ranges so height and thickness don't correlate:

```dart
@immutable
class BookJitter {
  final double heightFactor;    // 0.94 .. 1.06
  final double thicknessFactor; // 0.22 .. 0.34
  const BookJitter(this.heightFactor, this.thicknessFactor);

  static const BookJitter neutral = BookJitter(1.0, 0.28);

  factory BookJitter.fromIsbn(String isbn) {
    if (isbn.isEmpty) return neutral;
    final h = _fnv1a(isbn);
    final a = (h & 0xFFFF) / 0xFFFF;
    final b = ((h >> 16) & 0xFFFF) / 0xFFFF;
    return BookJitter(0.94 + a * 0.12, 0.22 + b * 0.12);
  }
}
```

- [ ] **Step 3: Add `BookMetrics`**

Derives every dimension from a base height, a cover aspect ratio, and the jitter. `coverAspect` is
width ÷ height — from the decoded image for real covers, `2 / 3` for generated ones.

```dart
@immutable
class BookMetrics {
  final double height;      // baseHeight * jitter.heightFactor
  final double width;       // height * coverAspect
  final double thickness;   // width * jitter.thicknessFactor
  final double perspective; // width * 4.6

  factory BookMetrics.from({
    required double baseHeight,
    required double coverAspect,
    required BookJitter jitter,
  });

  /// Left (spine) corners rounder than right, both scaled off the reference's
  /// 196px width, floored at 2px so small books keep a visible radius.
  BorderRadius get radius;
}
```

`radius`: left `(6 * width / 196).clamp(2, 6)`, right `(4 * width / 196).clamp(2, 4)`.

- [ ] **Step 4: Write `test/book_geometry_test.dart`**

Cover, per the design's test list:

- `BookJitter.fromIsbn` pinned to golden values for a fixed set of ISBNs — this is the regression
  guard that stops every shelf silently reshaping if the hash is ever touched.
- `heightFactor` within `[0.94, 1.06]` and `thicknessFactor` within `[0.22, 0.34]` across a few
  thousand generated ISBN strings.
- Empty ISBN returns `BookJitter.neutral`.
- The same ISBN returns identical values across repeated calls.
- `BookMetrics.radius` floors at 2px for a very small book.

- [ ] **Step 5: Run and confirm green**

```bash
flutter test test/book_geometry_test.dart
```

---

## Task 2: The 3D chassis

**Files:**
- Create: `lib/ui/widgets/book/book_chassis.dart`

- [ ] **Step 1: Build the shared parent matrix**

Perspective scales with width, which is the fix for depth collapsing to ~1px at shelf size:

```dart
Matrix4 _parent(BookMetrics m, double angle) => Matrix4.identity()
  ..setEntry(3, 2, 1 / m.perspective)
  ..rotateY(angle);
```

- [ ] **Step 2: Compose one full matrix per face**

Flutter has no `transform-style: preserve-3d`, and **nesting `Transform`s does not work here** — an
inner `Transform` projects its child orthographically before the outer perspective is applied, so a
z-translation becomes a visual no-op and all depth is lost. Each face must therefore receive a
single pre-multiplied `parent × local` matrix.

Every face is wrapped in a `SizedBox(width: m.width, height: m.height)` — identical box for all
three — with its content positioned inside. This matters: `Transform(alignment: Alignment.center)`
resolves the perspective origin from the child's box, so faces of differing sizes would each get a
*different* origin and the geometry would not line up.

| Face | Local matrix | Content |
| --- | --- | --- |
| Back board | `translate(0, 0, thickness)` | Full-size rounded rect |
| Page block | `translate(width - thickness / 2 - 2, 0, 0)` → `rotateY(π / 2)` → `translate(thickness / 2, 0, 0)` | `thickness` wide, `height - 4` tall, aligned left |
| Cover | identity | Full-size cover |

Paint them in that order in a `Stack`. Order is fixed and correct for all `|angle| < π / 2`, so no
z-sorting is needed.

- [ ] **Step 3: Verify the sign conventions on a device**

**Do not trust the algebra here.** Flutter's z axis is inverted relative to CSS, and `rotateY` sign
follows suit. Run the app and check two invariants, flipping the sign of the `translate` z term
and/or the `rotateY` argument until both hold:

1. The page block appears on the **right** of the cover, not the left.
2. The back board **recedes** — it must not paint over the cover or extend leftward.

Verify at a non-zero angle (temporarily hardcode ~16°), since at 0° the fore-edge is only ~2.6px
and too small to judge.

- [ ] **Step 4: Page block gradients**

Two stacked gradients, no page lines — lines look cheap at 86px:

```dart
// horizontal: edge shading nearest the cover, fading out by 70%
LinearGradient(begin: centerLeft, end: centerRight,
  colors: [pageEdge, Colors.transparent], stops: [0.0, 0.7])
// under it, vertical: pageBase -> pageBaseLow
```

Light: `pageEdge` `#eaeaea`, base `#fff` → `#fafafa`. Dark: `pageEdge` black 35%, base
`surfaceVariant` → `#262628`. Back board: `#e3e3e3` light, `#2A2A2C` dark. Left near-white these
glow on `#121212`.

- [ ] **Step 5: Binding band**

8.2% of width, at the cover's left edge, above the cover image. Gradient stops — the white stop is
the highlight ridge and the trailing black stop is the crease; without both it reads as a dark
smear rather than a binding:

| Stop | Value |
| --- | --- |
| 0.0 | black 26% |
| 0.34 | black 7% |
| 0.78 | white 30% |
| 1.0 | black 11% |

Attempt `BoxDecoration(gradient: ..., backgroundBlendMode: BlendMode.overlay)` first. This needs an
isolated layer to blend against, so it must sit inside the `ClipRRect` that wraps the cover.
**If the blend leaks to the page background or no-ops, fall back** to a two-layer alpha
approximation: a dark gradient plus a separate white highlight gradient, both plain alpha. Record
which path was taken in a code comment.

- [ ] **Step 6: Shadow**

Four layers, with offsets and blur scaled by `width / 196` so an 86px book doesn't carry a
196px book's shadow:

```
(0, 1)  blur 1   black 3.5%
(0, 3)  blur 6   black 4.5%
(0, 10) blur 18  black 5%
(0, 22) blur 36  black 5.5%
```

Dark mode: two layers at ~1.6× alpha, plus a 1px top rim at white 6%. Shadows barely read on
`#121212`, so the rim does the edge-definition work instead.

Add a `RepaintBoundary` around each book — at rest the transform is static, so Flutter caches the
layer and only the held book repaints.

---

## Task 3: Generated cover

**Files:**
- Create: `lib/ui/widgets/book/generated_cover.dart`

- [ ] **Step 1: Palette hashed from ISBN**

Reuse `_fnv1a` via a small exported helper rather than duplicating it. Six swatches:

```dart
const _palette = [
  Color(0xFF09BC8A), // brand green
  Color(0xFF0E7C7B), // deep teal
  Color(0xFF2F6690), // slate blue
  Color(0xFFE0644E), // coral
  Color(0xFFF2B544), // amber
  Color(0xFF7C5CBF), // violet
];
```

The color block carries no text, so there is no contrast constraint on the palette.

- [ ] **Step 2: Layout**

`stripe` variant from the reference: a `Column` with the color block at `flex: 1` on top and a
`surface`-toned area at `flex: 1` below carrying the title. Padding `6.1%` on three sides,
`14.3%` on the left so the text clears the binding band.

Title color is **always `primaryText`** — it sits on the `surface` half, never on the color block —
so the cover adapts to dark mode with no separate palette.

- [ ] **Step 3: Size tiers**

The widest book anywhere in the app is the details page at ~120px, so any threshold above that is
dead code:

| Width | Mascot | Title size | Max lines |
| --- | --- | --- | --- |
| ≥ 110px | Shown | 11.5% of width | 3 |
| < 110px | Hidden | 13.5% of width | 3 |

Mascot is `assets/icons/smileBookwormIcon.svg` via `flutter_svg`, recolored to `primaryText`.
Titles ellipsize at 3 lines.

---

## Task 4: Rewrite `BookWidget`

**Files:**
- Modify: `lib/ui/widgets/book_widget.dart`

- [ ] **Step 1: New API**

`isbn` and `title` are new and required. They're separate scalars rather than a `Book`, because
`search_book_page.dart` holds a `BookSearchResult`:

```dart
BookWidget({
  double? height,              // base height, before jitter
  required String imageUrl,
  required String isbn,        // drives jitter + generated-cover color
  required String title,       // generated-cover text
  VoidCallback? onTap,
  VoidCallback? onLongPress,   // stage two
  String? heroTag,
  bool pressEffect = true,     // gates the turn AND stage two
})
```

- [ ] **Step 2: Resolve the cover aspect ratio**

Real covers need their intrinsic ratio before metrics can be computed. Resolve the `ImageStream`
and use `2 / 3` until the first frame arrives, so the book never jumps size mid-load. Fall back to
the generated cover when `imageUrl.isEmpty` or when `errorBuilder` fires.

- [ ] **Step 3: Two-stage hold**

Replace the existing `_isPressed` lift with a turn. The gesture handlers already on this widget
(`onTapDown` / `onTapUp` / `onTapCancel`) drive stage one; stage two runs off an internal `Timer`,
**not** `GestureDetector.onLongPress`, because `GestureDetector` doesn't expose the long-press
deadline and its 500ms default leaves only ~100ms of fully-turned book.

| t | Event | Visual |
| --- | --- | --- |
| 0ms | `onTapDown` | Shadow blur and offsets to 0.85×, over 90ms |
| 140ms | Hold confirmed | Begin turn |
| 140–400ms | — | 0° → 16°, `easeOutCubic`, 260ms |
| 400–700ms | — | Held at 16° |
| 700ms | Stage two | Fire `onLongPress`; return to 0° over 120ms `easeOut` |

Release handling:

- Before 140ms → clean tap, no turn, `onTap` fires.
- 140–700ms → cancel the stage-two timer, return to 0° over 180ms `easeOut`, then `onTap` fires.
- `onTapCancel` (the horizontal `ListView` won the gesture) → cancel timer, return to 0°, **no**
  navigation.

`pressEffect: false` disables both stages. Skip the turn entirely when
`MediaQuery.disableAnimations` is set; stage two still fires at 700ms.

- [ ] **Step 4: Cancel the timer in `dispose`**

A book scrolled off-screen mid-hold must not fire `onLongPress` after unmount.

---

## Task 5: Update the five call sites

**Files:**
- Modify: `lib/ui/pages/home_page.dart`
- Modify: `lib/ui/pages/search_book_page.dart`
- Modify: `lib/ui/pages/user_library_page.dart`
- Modify: `lib/ui/views/book_details_tab_view.dart`
- Modify: `lib/ui/widgets/bottom_sheets/book_info_bottom_sheet.dart`

- [ ] **Step 1: Pass `isbn` and `title` at each site**

| File | Line | Source |
| --- | --- | --- |
| `home_page.dart` | ~990 | `book.isbn`, `book.title` |
| `home_page.dart` | ~1087 | `book.isbn`, `book.title` (`Draggable` feedback) |
| `search_book_page.dart` | ~231 | `results[...].isbn`, `.title` |
| `user_library_page.dart` | ~268 | `book.isbn`, `book.title` |
| `book_details_tab_view.dart` | ~119 | `book.isbn`, `book.title` |
| `book_info_bottom_sheet.dart` | ~58 | `book.isbn`, `book.title` |

- [ ] **Step 2: Confirm long-press semantics are unchanged**

`home_page.dart:877` passes `onLongPress: onEnterEditMode` into `_ShelfRow`, which forwards it at
line ~1014. That callback is now stage two, so entering edit mode takes 700ms instead of the
platform's 500ms. The Edit button in `_LibrarySubHeader` (line ~271) is unchanged and remains the
discoverable path. Do not rewire either.

---

## Task 6: Per-book height in `_ShelfRow`

**Files:**
- Modify: `lib/ui/pages/home_page.dart`

- [ ] **Step 1: Replace the shared `bookHeight`**

`bookHeight` at line ~1122 is currently one value threaded to four consumers. Each must now derive
its own from the book's ISBN: `_buildBookContent`, `_buildEditableBookList`, the `Draggable`
feedback (currently `bookHeight * 1.1`), and the row `SizedBox`.

- [ ] **Step 2: Size the row to the maximum, not the base**

The row `SizedBox` currently equals `bookHeight` exactly. With +6% jitter this clips any book that
hashes taller. Size it to **`bookHeight * 1.06`**. The shelf line sits directly below, so the row
grows 6% and vertical shelf spacing shifts — expected, not a bug.

- [ ] **Step 3: Bottom-align the list**

Books of differing heights must sit **on** the shelf line, not hang from the top of the row. The
horizontal `ListView` gives children tight cross-axis constraints, so wrap each item in
`Align(alignment: Alignment.bottomCenter)`.

- [ ] **Step 4: Check the reading-status badge still tracks the book**

The bookmark at line ~1007 is `Positioned(top: 0, right: 8)` inside the per-book `Stack`, so it
should follow the book's own top edge rather than the row's. Confirm visually with a book that
hashes short and one that hashes tall — a short book's badge must not float above its cover.

---

## Task 7: Tests

**Files:**
- Create: `test/book_generated_cover_test.dart`
- Create: `test/book_hold_gesture_test.dart`
- Modify: `test/library_delete_book_test.dart`

- [ ] **Step 1: Generated cover**

- Renders when `imageUrl` is empty.
- Renders when the network image fails, via `errorBuilder`.
- Mascot hidden at 86px wide, shown at 120px — pins the 110px tier boundary.
- The same ISBN always yields the same palette color.

- [ ] **Step 2: Hold gesture**

Use `WidgetTester.startGesture` plus `pump(Duration(...))` to step the clock.

- Hold past 140ms sets the turned state.
- Release between 140ms and 700ms returns to 0° and fires `onTap`.
- `onTapCancel` returns to 0° and does **not** fire `onTap`.
- Stage two fires at 700ms and not at 699ms.
- `pressEffect: false` yields neither turn nor stage two.
- A widget disposed mid-hold does not fire `onLongPress`.

- [ ] **Step 3: Shelf row does not clip**

Pump a shelf containing a book whose ISBN hashes to near the maximum height factor and assert no
overflow is recorded.

- [ ] **Step 4: Repair the existing test**

`test/library_delete_book_test.dart:50` finds by `BookWidget` type, which still works, but any
direct construction needs the two new required parameters. `test/finished_books_sheet_test.dart`
targets `BookVertical` and is untouched by this work.

- [ ] **Step 5: Full suite**

```bash
flutter analyze
flutter test
```

`flutter analyze` must be clean of errors before this task is considered done.

---

## Task 8: Device verification

- [ ] **Step 1: Both themes**

Light and dark, on a real device — the page block and back board are the risk. Confirm neither
glows on `#121212` and that the dark rim reads.

- [ ] **Step 2: Judge the resting fore-edge**

At 86px the resting fore-edge is ~2.6px. This is faithful to the reference, but the reference
renders at 196px. If it reads as too subtle, **raise the thickness range, not the angle** — the
resting angle is 0° by decision, and thickness adds depth without foreshortening the artwork.
Changing the range means updating the `BookJitter` bounds and the golden values in Task 1 Step 4
together.

- [ ] **Step 3: Profile a full library**

Every book paints three layers even at rest, so a shelf row triples its layer count. Scroll a
library with several full shelves in profile mode and confirm no dropped frames. If there are,
check the `RepaintBoundary` from Task 2 Step 6 is actually caching.

- [ ] **Step 4: Confirm edit mode is intact**

Long-press a shelf book → the book turns, then edit mode engages at 700ms. Books stay flat while
wiggling. The 250ms `_DelayedReorderableListener` reorder drag still works, and cross-shelf
vertical `Draggable` still works.
