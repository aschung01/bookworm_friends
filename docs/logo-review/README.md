# Logo exploration

Scratch design work — nothing here is wired into the app except the current
source, `ai-moodboard/m4-single-book.png`, which is copied to
`assets/branding/app_icon_source.png`. Delete freely otherwise.

## Files

- `p1`–`p8*.svg` — the single-book direction, taken from `m4`. `p1` is `m4`
  corrected (on-palette, scaled to 76%, ribbon cut in as a notch) with nothing
  else changed; `p3`/`p4` add the spine band; `p8` restores a pile by running
  `m4`'s own layering device three times. `p6` (open book) and `p7` (landscape)
  are the two that fail.
- `o1`–`o8*.svg` — eight flat marks reducing `n1`/`n2` along a different axis
  each, from three shapes down to one. `o1` (two plain slabs) and `o6` (a single
  chevron) are deliberate floors; `o2` (width taper, no bookmark), `o4` (one mass
  with green rules cut through it) and `o8` (spine bands instead of a bookmark)
  are the ones that hold up.
- `n1`/`n2*.svg` — the flat-vector reading of “simpler”: `k4b`’s composition with
  the chalk texture removed.
- `s3a`–`s3k*.svg` — variations on `s3` (the fanned stack), varying fan
  geometry, layer count, orientation, and per-layer detail. `s3j` is the
  resolved one: no spine, bookmark at the fore-edge. `s3k` is `s3j` with a
  deeper ribbon notch.
- `s1`–`s6*.svg` — six directions for the **Libstack** rename, built around the
  stack motif the new name hands you.
- `v1`–`v6*.svg` — six hand-authored app-icon directions, 1024×1024, brand
  palette only (`#09BC8A` + white). Pre-rename, bookworm-led.
- `mock-a`/`mock-b`/`mock-c*.svg` — earlier round: minimal edits to the existing
  `assets/icons/bookwormIcon.svg` geometry, used to isolate _why_ the current
  mark fails. `mock-c` is the useful one: it proves that inverting to a green
  plate does **not** fix the Android-bugdroid read — the antennae do that.
- `current-at-48px.png` — the shipping icon downsampled to home-screen size.
- `render.sh` — regenerates `out/` from every `<letter><digit>*.svg`, so a new
  lettered round needs no edit to the script.
- `out/` — `*-1024.png` (full size) and `*-at48px.png` (rendered at 48px then
  upscaled 6× so the pixel grid is visible).

## Regenerating

```sh
./docs/logo-review/render.sh
```

Requires `rsvg-convert` (`brew install librsvg`) and macOS `sips`.

## Constraints any final mark has to satisfy

- **Legible at 48px first.** Design there, then scale up — not the reverse.
- **Brand green cannot carry contrast on white.** It scores 2.45:1 (see
  `lib/constants/app_theme.dart`), so the plate is green and the mark is white,
  never the other way round.
- **Android adaptive safe zone** is the inner 66% diameter circle. Art here
  fills ~76% of the canvas, which is fine for iOS but must be re-cropped for
  the Android foreground layer.
- **No straight antennae on a dome.** That silhouette is Bugdroid.
- **Thin per-layer detail dies at 48px.** Spine hairlines on a fanned stack turn
  into scratches (`s3a`); a bookmark shape survives (`s3f`). Prefer a landmark
  over a texture. A ~44px spine _band_ survives where a ~20px line does not
  (`s3i` vs `s3h`).
- **Watch the vertical-stroke count.** A fanned stack already spends two
  verticals on the back-layer slivers. Adding a spine and a bookmark takes it to
  four, which reads as stripes at 48px — consider a simplified mark for the
  ≤60px slots.
- **In a fanned stack, graduate the card sizes front-to-back.** Equal-size cards
  leave a stray crescent where the middle layer pokes past the front one.
- **Graduate something, or it is punctuation.** Two or three equal slabs, evenly
  aligned with no landmark, read as `=` (`o1`). Tapering the widths fixes it at
  no extra shape cost, and does the bookmark's job for free (`o2`).
- **One mass beats several slabs at 48px.** Cutting green rules through a single
  white block (`o4`) keeps one closed outer outline, so there is no thin white
  edge to lose — it outperforms the same composition drawn as separate slabs.
- **A spine band beats a bookmark as the one detail.** Confirmed twice: `s3i` vs
  `s3h`, then `o8` vs `n2`. A band cut through the full slab height reads as
  spine-plus-cover; a ribbon laid on white has no contrast to work with.
- **One shape is too few.** A single chevron (`o6`) is perfectly legible at any
  size and still fails, because legibility was never the constraint that was
  binding — meaning is. Reduction has a floor above one shape.
- **Check the plate colour on anything AI-generated.** Every raster round drifted
  off brand: `m4` sampled `#27B98C` against `#09BC8A`. Sample it, do not eyeball
  it — the two are close enough to pass a glance and fail side by side.
- **Check the scale too.** `m4` filled 47.5% × 61.3% of its canvas where the
  target is ~76%, the same fault `k5` had already found and fixed in `h7`. A
  generated mark will sit too small in frame unless told otherwise.
- **A board behind a cover reads as a second book.** This is the useful loophole:
  a “single book” drawn with an offset back board (`m4`, `p1`) already implies
  two, and a third offset (`p8`) reads as a pile while still looking like one
  object — which is how a one-book mark can serve a name like Libstack.
- **Offset minus gap is what you actually see.** Layering two white boards needs
  a green separation of ~44 to survive downscaling, so the offset has to be
  ~104 to leave a 60-wide strip of board visible. Picking the offset first and
  the gap second is how you end up with a 12px sliver that vanishes.
- **A lone book needs to stay portrait.** `s3e` found orientation was
  load-bearing for a fanned stack; `p7` shows it holds for one book too —
  landscape plus a tab reads as a folder.
