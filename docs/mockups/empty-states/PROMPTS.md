# Empty-state art — generation prompts

For producing the empty-state illustrations in the app icon's chalk style.

> **Start at [Route C](#route-c--xai-grok-imagine-the-one-that-worked).** It is
> the route that produced the accepted set, it is fully scripted, and the two
> post-processing steps it describes are what make the assets shippable. Route A
> (manual prompts) and Route B (Bedrock style-transfer) are kept below because
> their failures are the reason Route C is shaped the way it is — read them
> before proposing a fourth route.

**Attach `assets/branding/app_icon_source.png` as a reference/style image.**
That file _is_ the shipping icon, and it is the whole point — matching its hand
by reference beats describing it. Without a reference image the style block
still works, but expect more drift.

One hard-won rule that applies to every route: **do not seed generation with our
own hand-authored vectors.** Route B did, and output quality was capped by the
seed's geometry — it faithfully reproduced a crown-shaped ribbon and deleted
every green detail. Describe the composition in words and let the model draw it.

**Each prompt = one SUBJECT block + the shared STYLE block, in that order.**
(`scripts/gen_empty_state_art.py` composes them exactly this way, so results
stay comparable between the script and manual runs.)

Generate 2–4 variants per piece and pick; consistency across the set matters
more than any single piece being perfect. **Judge at final size** — pieces 4–7
land at 34–48pt, and `scripts/contact_sheet.py` renders every piece at its real
call-site size on all three app backgrounds.

---

## STYLE — append this to every subject

```
Match the visual style of the attached reference image EXACTLY: white chalk
drawn on a flat surface, soft dry-chalk grain and slightly irregular
hand-drawn edges, bold simple shapes, no outlines, no gradients, no 3D
shading, no perspective. Same chalk stick width and same grain density as the
reference. Single centered subject, generous even margins, nothing cropped.
Flat solid mid-green background (#3BAF8F), no squircle frame, no border, no
rounded-rectangle app-icon shape, no text, no letters, no numbers, no
watermark, no signature, no drop shadow. Square 1:1 composition.
```

Why those negatives: an earlier round produced green squircle plates, which
made every empty state look like an app icon dropped into the UI. The
`no squircle / no border / no app-icon shape` clauses exist to prevent exactly
that. Text negatives matter because chalk styles love inventing scribbled
words.

---

## THE BOOK — reused by several subjects below

Where a subject says _"THE BOOK"_, paste this sentence in its place:

```
The book is the same book as the reference: a closed upright book seen
front-on, its spine slab on the left with the cover lip curling over the top
edge, and a bookmark ribbon hanging from the top of the cover near the right,
the ribbon cut out so the background colour shows through it.
```

---

## 1. `library-empty` — your own empty library (100pt)

`lib/ui/views/library_view.dart` — `LibraryPane`, `hasNoBooks`

```
THE BOOK Beside it on the left stands one empty book-shaped outline drawn as a
dashed chalk rectangle, clearly unfilled, suggesting a space waiting for a
book. Two small four-point chalk sparkles float above the gap between them.
```

## 2. `library-empty-friend` — a friend's empty library (100pt)

Same call site, visitor branch (the hint row is suppressed here, so the art
should ask for nothing).

```
THE BOOK Just the single book alone, calm and centered, nothing else in the
frame.
```

## 3. `search-idle` — add-book sheet, idle (100pt)

`lib/ui/widgets/bottom_sheets/add_book_bottom_sheet.dart` — replaces
`Icons.menu_book_outlined`

```
THE BOOK A simple round magnifying glass with a short straight handle rests
over the lower right of the book cover, drawn in the same chalk.
```

## 4. `search-none` — no results for a query (40pt spot)

Same file. Placement still open: only shows when _both_ sections are empty.

```
One book-shaped outline drawn as a dashed chalk rectangle, clearly unfilled
and empty, with a single large chalk question mark centered inside it. Nothing
else in the frame.
```

## 5. `friends-none` — no friends yet (40pt spot)

`lib/ui/widgets/friends_sheet.dart` — `_NoFriends`

```
Two closed upright books of slightly different heights standing side by side
and leaning gently towards each other so they touch, drawn in the same chalk
as the reference. The right-hand book has a bookmark ribbon hanging from the
top of its cover, cut out so the background shows through. A narrow gap of
background separates them.
```

## 6. `memo-none` — Notes tab, no note yet (48pt)

`lib/ui/views/book_details_tab_view.dart` — `_BookMemoTab`, replaces
`Icons.note_outlined`

```
A closed upright book seen front-on in the same chalk as the reference, with
two short horizontal chalk rule lines written across its cover as if it were a
page, and a simple pencil lying diagonally across the lower right of the
cover, tip pointing down-left.
```

## 7. `scan-nomatch` — scan failed to match (34pt spot)

`lib/ui/pages/scan_book_page.dart` — `_failureCard`

```
One book-shaped outline drawn as a dashed chalk rectangle, clearly unfilled,
with a single large chalk question mark centered inside it, and a small chalk
barcode of a few vertical bars below it.
```

---

## Route B — AWS Bedrock, automated (works today)

`scripts/chalkify_empty_state_art.py`. No prompt-wrangling: it takes the
**vectors we already agreed on** and lets Bedrock supply only the texture.

```
art/cmass-<piece>.svg
  -> plate: white masses on the icon's green (#38b28a), ribbon knocked out
  -> us.stability.stable-style-transfer-v1:0, style_image = the app icon
  -> chalk raster in art/gen/
```

Tuned: `style_strength 0.8`, `composition_fidelity 0.9`. At `1.0/1.0` the
ribbon notch smooths away; below `0.6` our geometry starts dissolving.

**Polarity is the whole trick.** Feeding grey-on-white vector art in makes the
model map white→green and invert the drawing. Matching the icon's own
white-on-green polarity _before_ the call is what fixed it.

Routes tried and rejected (don't burn calls rediscovering these):

| model                                  | outcome                                                                                  |
| -------------------------------------- | ---------------------------------------------------------------------------------------- |
| `amazon.nova-canvas-v1:0`              | 404, marked Legacy on this account                                                       |
| `stable-image-style-guide`             | **style matcher, not compositional** — see below                                         |
| `control-structure` / `control-sketch` | reads filled masses as _outlines_, renders physical chalk sticks on a photographed board |

### Why "send the icon and let the model draw" can't work on this account

Tested directly, not assumed. With the icon as style reference,
`stable-image-style-guide` reduces any prompt to "a book on green":

- At `fidelity 0.9`, **four of six pieces came back byte-identical** (same md5).
  Only the two whose prompts omit the shared book description differed at all.
- A sweep at `0.3 / 0.5 / 0.7 / 0.9` produced one plain white book every time.
  The dashed slot, sparkles, magnifier and pencil never appeared.
- Low fidelity additionally brings back 3D notebooks with cast shadows.

The cause is account-level. Of 14 image-output models available here,
**exactly one is a general text-to-image model** — `amazon.nova-canvas-v1:0` —
and it 404s as Legacy. Every other one is an _edit/control_ model that requires
an input image and is driven by that image's style or structure rather than by
the prompt.

Unblocking prompt-driven generation needs either:

- a current image model enabled in the Bedrock console (Model access, us-east-1), or
- a multimodal model that follows instructions _alongside_ a reference image —
  Gemini `gemini-2.5-flash-image` (`scripts/gen_empty_state_art.py`, blocked by
  the billing dunning flag) or OpenAI `gpt-image`.

Until then the transfer route is the only one that yields a composition at all,
which means **output quality is capped by the input vector's quality**. The
crown-shaped ribbon below is inherited from `cmass-*.svg`, not hallucinated.

### Two known defects in the current output

1. **The ribbon reads as a battlement/crown, not a hanging ribbon.** In
   `cmass-*.svg` it is too wide and too short, and it meets the top edge, so
   once textured the V notch looks like a crenellation. Fix in the vector
   first: narrower and longer.
2. **Green details disappear.** `build_plate()` maps _all_ `#09BC8A` to the
   plate colour, which is right for the ribbon (a knockout) but destroys the
   question mark, magnifier lens and pencil — they become invisible or turn
   into green blobs. Those should be drawn **white**, as part of the mass;
   only the ribbon is a knockout.

### And the finding that matters most

At 34–48pt the chalk texture turns to mud — visible in the small-size strip on
`art/gen/sheet.png`. So the split is now evidence-based, not a guess:

- **100pt heroes** (empty library, add-book idle, auth page) → Bedrock chalk raster.
- **34–48pt spots** (search miss, friends, notes, scan) → vector `solid-mass`,
  which also themes for free.
- **Judge at final size, not 1024px.** Pieces 4–7 land at 34–48pt. Anything
  that only works large is the wrong drawing — that mistake cost several
  rounds already. Downscale and look before committing.
- **Themes.** Raster can't be tinted, so a light/dark pair means two
  generations (or one neutral set). The vector `solid-mass` family in
  `docs/mockups/empty-states/index.html` handles theming for free — consider
  keeping vectors for the small spots and spending generations on the 100pt
  library hero plus the auth page.
- **Watch the green.** `docs/logo-review/README.md`: every AI raster round
  drifted the plate colour. Check the output's green against `#09BC8A`
  (brand) / the icon's own plate before accepting.
- **The auth page** still ships the _retired_ worm
  (`assets/icons/smileBookwormIcon.svg`) — a hero in this style is the natural
  replacement.

---

## Route C — xAI Grok Imagine (the one that worked)

`scripts/gen_empty_state_art.py`. This is the route to use. It abandons Route
B's central assumption: instead of transferring texture onto one of our
vectors, it asks the model to **draw a new illustration**, with the app icon
supplied only as a texture reference.

```
POST https://api.x.ai/v1/images/edits     model: grok-imagine-image-2.0
  images[0] = assets/branding/app_icon_source.png (downscaled to 512px)
  prompt    = subject + SURFACES[surface] + MASS + GRAIN + FLAT
  -> art/gen/<piece>-grok-<surface>-v<n>.jpg  + manifest.json
```

Auth is `XAI_API_KEY` from the environment. ~$0.07 per image; every call is
logged to `art/gen/manifest.json` with its full prompt, route, surface and cost,
so any piece can be re-rolled on identical terms.

```bash
python3 scripts/gen_empty_state_art.py --list
python3 scripts/gen_empty_state_art.py                      # all 6, light
python3 scripts/gen_empty_state_art.py --only duo --variants 4
```

### The prompt clauses that are actually load-bearing

Each of these was added to fix an observed failure, so don't trim them:

| clause                                                                                       | without it                                                                                                        |
| -------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| _"draw a NEW illustration — do not copy or return `<IMAGE_0>`"_                              | it returns the app icon back                                                                                      |
| _"take from it only its chalk texture and book construction… ignore its colours completely"_ | everything comes back on a green plate                                                                            |
| `MASS` — _"SOLID FILLED mass… never an outline drawing"_                                     | `nomatch` and `note` come back as thin line drawings while the rest are filled masses — unshippable as one family |
| `WEIGHT` — _"medium mid-grey, not near-black"_                                               | `rest` renders near-black next to mid-grey siblings                                                               |
| `GRAIN`                                                                                      | clean vector shapes, no chalk at all                                                                              |
| `FLAT` — _"no frame or border, not an app icon"_                                             | drop shadows, 3D thickness, rounded-square frames                                                                 |

### Surfaces

- `paper` (default) — mid-grey `#626A72` chalk on flat pure white. The
  background is specified as flat **so that it can be keyed out**; this is the
  one you want.
- `night` — light grey `#949599` on flat pure black. Made redundant by the
  stencil step below; kept only as evidence.
- `board` — white chalk on the icon's green `#38B28A`. Brand material only. In
  app it reads as an app icon dropped into the UI, which is the objection that
  killed two earlier directions.

### Composition drift, and the fix that generalises

`duo` (two books) took **two rolls of four**. The edits reference _is_ a single
book, so the route keeps collapsing a pair into one; the phrase "leaning
towards each other until their top corners nearly touch" finished the merge.

What fixed it: **state spatial relationships as measurements, not as feelings.**

> a WIDE EMPTY GAP of clean background, at least half as wide as one of the
> books — they must never touch, never overlap and never share an edge

That took it from 2 usable rolls in 4 to 4 in 4. Expect to roll `--variants 3-4`
for any piece with more than one object and pick; rejected rolls belong in
`art/gen/_keep/` marked `rejected` in the manifest, so the accepted one is
visibly a pick rather than a first try.

### Knock details out; never draw them on top

`nomatch` was originally "a book-shaped rectangle drawn only as a dashed chalk
outline, clearly empty, with a question mark inside" — inherited from the vector
families' idea of an empty shelf slot. It passed every contact sheet. It failed
the moment the set was rendered in Flutter at true call-site size:

| piece              | ink coverage |
| ------------------ | ------------ |
| `nomatch` (dashed) | **7.3%**     |
| `invite`           | 21.3%        |
| `search`           | 23.7%        |
| `note`             | 28.1%        |
| `rest`             | 28.4%        |
| `duo`              | 34.7%        |

Thin dashed lines cannot hold their own beside solid masses. Beside its siblings
it read as a smudge, and at the 34pt the scan card uses it nearly disappeared.

The fix was to stop drawing the detail **on** the shape and start cutting it
**out** of it — which is the app icon's own construction, and already how the
ribbon and the magnifier lens work:

> a SOLID FILLED mass of chalk … a single large bold question mark is CUT OUT of
> the middle of the cover, a clean hole right through the chalk so the plain
> background shows through it — the question mark is empty background, never
> drawn in chalk on top of the cover

4 of 4 rolls came back correct, and coverage went to **25.3%**. Generalise it:
**anything meant to read at spot size should be a mass with holes in it, not
lines on top of it.** This supersedes the old "dashed outline = empty" idea
inherited from the vector rounds.

### Post-processing: two steps, both required

**1. Key the plate out** — `scripts/cutout_bg.py` (Bedrock
`stable-image-remove-background`). Not optional: **the xAI endpoint returns
JPEG regardless of `response_format`, and JPEG cannot carry alpha.** Always read
`mime_type` from the response rather than trusting the filename. Bonus: the
white ribbon knockout keys out too, so the real background shows through it —
exactly the icon's own logic.

**2. Bake coverage into alpha** — `scripts/alpha_from_luma.py`. This is what
makes one asset serve both themes:

```
alpha = existing_alpha × darkness      rgb = flat
```

Why it is necessary rather than nice: `scripts/png_probe.py` measured the keyed
cutouts at **~1% partial alpha with a fully opaque mass spread across ten
luminance buckets**. The grain was _colour_, so tinting with `BlendMode.srcIn`
would have flattened every speckle into a solid slab. Moving coverage into
alpha means the tint preserves the texture.

One detail worth keeping: the darkest chalk is anchored at full opacity using
the 2nd percentile of opaque luminance, not by assuming black. The generator
returns mid-grey, so a naive `1 - luma/255` caps the mass near 50% opacity and
washes the drawing out.

```bash
python3 scripts/cutout_bg.py                    # -> cut/*.png, RGBA
python3 scripts/alpha_from_luma.py              # -> cut/stencil/<piece>.png
python3 scripts/contact_sheet.py --surface stencil --out sheet-stencil
```

### What this buys, stated plainly

- **Six assets, not twelve.** One file per piece for both themes.
- **Light and dark cannot drift.** They are the same geometry with a different
  tint. Under Route C's `grok-cutout` stage they _did_ drift: `nomatch` came
  back as a dashed slot on light and a solid outlined book on dark — two
  different drawings of one state.
- **Texture survives at 34–48pt.** This reverses Route B's finding. The mud was
  a consequence of transferring style onto dense vector geometry, not something
  intrinsic to chalk at spot size. Still judge at final size —
  `scripts/contact_sheet.py` renders every piece at its real call-site size on
  `pageBackground`, the mint sheet and the dark page.
- **A contact sheet is not enough.** `nomatch` passed every sheet in this
  directory and still had to be redrawn once it was rendered in Flutter beside
  its siblings. `flutter test --update-goldens
test/empty_state_art_golden_test.dart` writes the two images that actually
  settle it; look at them before calling a piece done.

### Known open items

- `note`'s subject says "no ribbon" and every generation drew one. The ribbon is
  being kept because it is the brand mark; **the prompt is the thing that is
  wrong**, not the asset.
- The `night` generations are now redundant. Left in `art/gen/` as evidence for
  why the stencil step exists.
- The auth page still ships the retired worm (`smileBookwormIcon.svg`). A hero in
  this style is the natural replacement, but it is a 100pt+ piece on a different
  background and has not been generated.

### Shipping it

The set is wired into the app. To regenerate or extend:

```bash
python3 scripts/gen_empty_state_art.py --only <piece> --variants 4   # roll
python3 scripts/cutout_bg.py --glob '<piece>-grok-paper-v<n>*'       # key
python3 scripts/alpha_from_luma.py                                   # stencil
python3 scripts/contact_sheet.py --surface stencil --out sheet-stencil
python3 scripts/cut_empty_state_assets.py                            # ship
flutter test test/empty_state_art_test.dart
```

`assets/icons/empty/` holds the 1x files plus `2.0x/` and `3.0x/` variants;
`pubspec.yaml` declares only the 1x path because Flutter discovers the rest.
Everything is drawn by `lib/ui/widgets/empty_state_art.dart`, whose
`EmptyStateArtwork` enum names _states_ rather than files.

`test/empty_state_art_test.dart` guards the property that matters: that both
themes resolve to the **same asset** with different tints. That is the thing the
drift bug violated, and it fails silently — two assets that disagree still
render fine, they are just no longer the same illustration.

One deliberate asymmetry: of the scanner's six failure modes only
`noCatalogueMatch` gets art, because the others are about the camera, the network
or a quota and an empty-shelf drawing would misdescribe them. Likewise the search
miss only gets a spot when _both_ scopes came up empty.

### Blocked alternative

Gemini `gemini-2.5-flash-image` fails on a billing **dunning** flag
(`"Lightning dunning decision is deny"`) on billing account
`01914B-4E23E1-22F6D5`, despite `billingEnabled: true`. ADC works and
`aiplatform` is enabled on `autoquant-503301`; only the account owner can clear
this. Not worth retrying until then.

### Local tooling constraints

This machine has **no PIL and no ImageMagick**, which is why the PNG probe and
the alpha bake are pure Python (`zlib` plus the spec's scanline filters). Also:
`rsvg-convert` **cannot** render JPEG inside `<image href>` — it silently
produces a blank — so contact sheets must point at the keyed PNGs. `sips` works
for resizing and format conversion.
