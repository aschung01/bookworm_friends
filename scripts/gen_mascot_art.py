#!/usr/bin/env python3
"""Generate mascot candidates for Libstack (xAI Grok Imagine).

Two style systems, because the first round proved they are not the same problem.

`--style chalk`
    Round 1. Inherits the empty-state pipeline's hand: mid-grey chalk on keyable
    white, flat, one solid mass, details knocked out as holes. Imports its blocks
    from `gen_empty_state_art.py` so the two sets cannot drift.

    **This round failed, and the failure is instructive.** That pipeline is built
    for *pictograms* -- a 34pt spot illustration that must survive being tinted
    per theme via `BlendMode.srcIn`. A mascot is not a pictogram, and the
    constraints that make a good pictogram are the same ones that make an
    unlovable character:

      * it mandates "no mouth" and *small* eyes; cuteness needs a mouth and eyes
        that dominate the face
      * it is monochrome mid-grey, so the character cannot be endearing by colour
      * it is flat with no shading, so nothing reads as soft or plush
      * it says nothing about proportion, so the model returns adult proportions
      * round 1's subjects were *scenes* (a worm plus a three-book stack, a lamp
        plus a book) where the reference mascots of this genre are one creature
        alone

`--style cute`
    Round 2. Cuteness-first, and deliberately *outside* the chalk system. Baby
    proportions (head >= half the total height), oversized low-set eyes with a
    catchlight, a smile, blush, plush rounded forms, three or four shapes total,
    brand green plus one warm accent, clean flat vector fills.

    Consequence worth stating plainly: a full-colour mascot does not match the
    monochrome chalk icon. That is a real brand decision, not an oversight -- see
    the note in `docs/mockups/mascot/index.html`.

Auth: XAI_API_KEY in the environment. Never commit it, and never put it in
`env.json` -- that file is compiled into the app bundle.

    export XAI_API_KEY=...
    python3 scripts/gen_mascot_art.py --list
    python3 scripts/gen_mascot_art.py --style cute --variants 3
    python3 scripts/gen_mascot_art.py --style cute --only b-worm --variants 4
"""

from __future__ import annotations

import argparse
import base64
import concurrent.futures
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

# Round 1's hand, single-sourced from the shipped empty-state set.
from gen_empty_state_art import (  # noqa: E402
    FLAT,
    GRAIN,
    ICON,
    MASS,
    MODEL,
    SURFACES,
    call,
    prompt_for,
)

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "docs" / "mockups" / "mascot" / "art"

# ---------------------------------------------------------------- round 1

EYES_CHALK = (
    "Two small round eyes are CUT OUT as clean holes right through the chalk so "
    "the plain background shows through them; the eyes are empty background and "
    "are NEVER drawn in chalk on top."
)

CHALK: dict[str, tuple[str, str]] = {
    "a-mark": (
        "the bookmark ribbon as a character",
        "a friendly character made from a BOOKMARK RIBBON rising out of one "
        "closed book. The book stands in the LOWER HALF of the frame: a solid "
        "filled upright rectangle seen straight on from the front, with softly "
        "rounded corners and a narrow chalk spine strip down its left edge. "
        "From behind the book's top edge a single long narrow vertical ribbon "
        "of chalk rises straight UP into the upper half of the frame, about as "
        "tall as the book itself and about one quarter as wide as the book. At "
        "the very top the ribbon widens slightly into a soft rounded head, a "
        "lozenge shape; the ribbon's other end hangs down over the front of "
        "the cover and finishes in a sharp V notch cut into it. The ribbon, "
        "the head and the hanging tail are ONE single continuous connected "
        f"mass of chalk - never two separate objects. {EYES_CHALK} Nothing "
        "else: no mouth, no nose, no arms, no legs, no hands, no hat, no "
        "glasses. The head is a soft rounded lozenge on the end of a ribbon - "
        "it is NOT a circle on a stick, NOT a dome with antennae, NOT a "
        "flower, NOT a balloon, NOT a spoon.",
    ),
    "b-worm": (
        "the bookworm, out of a stack",
        "a friendly BOOKWORM character curling out of a stack of books. THREE "
        "closed books lie FLAT in a stack, stacked one on top of another, "
        "filling the LOWER TWO THIRDS of the frame; each book is a solid "
        "filled horizontal rectangle with softly rounded corners, and the "
        "three are very slightly different widths. A single worm emerges from "
        "the RIGHT-HAND END of the MIDDLE book only: one continuous smooth "
        "thick rounded tube of chalk, as thick as one book is tall, curving up "
        "and to the right and then over, ending in a rounded head that "
        "finishes just ABOVE the level of the top book. The worm is smooth and "
        "soft like a caterpillar with NO legs, NO feet and NO body segments, "
        "and it is ONE connected mass joined to the middle of the stack, never "
        f"a separate floating object. {EYES_CHALK} The head is simply the "
        "smooth rounded end of the tube: it has NO antennae, NO feelers, NO "
        "horns, NO stalks and NO straight lines sticking out of it anywhere, "
        "and it is NOT a dome or half-circle sitting on top of the stack. "
        "Nothing else: no mouth, no arms, no hat, no glasses.",
    ),
    "c-lamp": (
        "the reading lamp, leaning over a book",
        "a friendly DESK LAMP leaning over one closed book. The lamp stands on "
        "the LEFT of the frame, built as one connected mass of chalk: a low "
        "wide rounded base on the ground, a single narrow upright stem rising "
        "from the centre of the base, and at the top a wide cone-shaped "
        "lampshade, WIDER at its bottom opening than at its top, TILTED to the "
        "RIGHT so that it leans over toward the book like a head turning to "
        f"look down at it. The lampshade is a solid filled mass. {EYES_CHALK} "
        "On the RIGHT of the frame stands one closed upright book seen "
        "straight on from the front: a solid filled rectangle with softly "
        "rounded corners and a bookmark ribbon hanging from the top of its "
        "cover ending in a V notch, cut out so the background shows through "
        "it. Between the lamp and the book there is a WIDE EMPTY GAP of clean "
        "background, at least half as wide as the lampshade - the lamp and the "
        "book must never touch, never overlap and never share an edge. Nothing "
        "else: no cord, no cable, no switch, no table, no floor line, no light "
        "rays, no stars.",
    ),
}

# ---------------------------------------------------------------- round 2

# Every clause here answers a specific way round 1 came out unlovable. Read the
# module docstring before trimming any of them.
CUTE_PROPORTION = (
    "PROPORTIONS - THE MOST IMPORTANT RULE: exaggerated baby proportions. The "
    "HEAD is enormous and fills AT LEAST HALF of the character's total height, "
    "and it sits directly on a SHORT, SMALL, plump rounded body. Nothing about "
    "this character is long, thin, tall, spindly, lanky or elegant. It is "
    "short, round and chubby, like a plush toy or a vinyl collectible figure."
)

CUTE_FACE = (
    "FACE: TWO VERY LARGE round eyes that together take up most of the front of "
    "the head - each eye is a big solid dark rounded oval with ONE small white "
    "circular sparkle highlight near its top. The eyes are set LOW on the head "
    "and spaced WIDE apart. Directly below the eyes is a SMALL simple happy "
    "smiling mouth, a soft upward curve. There is one soft round rosy pink "
    "blush patch on each cheek. The expression is sweet, warm and delighted - "
    "never sly, never sleepy, never smug, never blank, never scary."
)

CUTE_FORM = (
    "FORM: every single shape is soft, round, chunky and squishy, with fully "
    "rounded ends. There are NO sharp corners, NO points, NO spikes, NO edges, "
    "NO thin lines and NO long limbs anywhere. Any arms are tiny stubby rounded "
    "nubs. No teeth, no claws, no antennae, no whiskers."
)

CUTE_SIMPLE = (
    "SIMPLICITY - equally important: the entire character must be built from "
    "only THREE OR FOUR simple rounded shapes and must be instantly readable at "
    "a glance and at small size. Radically simplified. NO fine detail, NO "
    "patterns, NO texture, NO small parts, NO accessories, NO clothing, NO hat, "
    "NO glasses, NO shoes. One character alone and nothing else in the frame."
)

CUTE_COLOUR = (
    "COLOUR: the body is a VIVID, SATURATED, punchy jade-mint green - exactly "
    "the brand green #09BC8A, a strong clear green. NOT a pale pastel, NOT a "
    "washed-out sage, NOT a dull grey-green, NOT a mint so light it reads as "
    "white. With it: a soft cream off-white belly and face patch, and exactly "
    "one warm orange accent, #FF922B. Clean flat vector fills with ONE slightly "
    "deeper green "
    "tone for soft gentle shading and a subtle darker green line where forms "
    "overlap. Smooth, crisp and modern - the look of a polished mobile-app "
    "mascot illustration."
)

CUTE_FRAME = (
    "BACKGROUND AND FRAMING: a completely plain, flat, pure white background "
    "(#FFFFFF), perfectly uniform everywhere so it can be keyed out - no scene, "
    "no floor, no ground shadow, no gradient, no vignette, no frame, no border, "
    "no app-icon shape, no text, no letters, no numbers, no watermark, no "
    "signature. The character is centred and seen straight on from the front, "
    "its whole body visible, with generous even margins and nothing cropped. "
    "Not photorealistic, not 3D-rendered, not detailed, not textured, no chalk, "
    "no grain, no sketch lines."
)

CUTE: dict[str, tuple[str, str]] = {
    "a-mark": (
        "cute bookmark character",
        "an ADORABLE little BOOKMARK character. Its body is a short, wide, "
        "plump ribbon shape with a soft shallow V notch in its bottom edge, and "
        "its enormous round head sits right on top of that ribbon body. The "
        "ribbon body is the mint green; the face patch is cream. Nothing else "
        "in the frame at all - no book, no shelf, no page.",
    ),
    "b-worm": (
        "cute bookworm character",
        "an ADORABLE little BOOKWORM character. Its body is one short, plump, "
        "smooth rounded worm curled into a soft fat C shape, with an enormous "
        "round head at its upper end and a small rounded tail tip at the other. "
        "Its body is mint green and its face patch is cream. It has no legs and "
        "no body segments. Nothing else in the frame at all - no books, no "
        "stack, no apple, no leaf, no glasses.",
    ),
    "c-lamp": (
        "cute desk lamp character",
        "an ADORABLE little DESK LAMP character. Its head is an enormous round "
        "dome lampshade, tilted very slightly to one side, in mint green, and "
        "its face is on the front of that dome on a cream patch. It stands on a "
        "very short plump rounded stem and a small soft rounded base. Nothing "
        "else in the frame at all - no book, no table, no desk, no cord, no "
        "cable, no switch, no light rays, no stars.",
    ),
}

# ---------------------------------------------------------------- round 3

# Round 2 failed a test it was never given: flatten all nine to a black
# silhouette and they are the SAME BLOB. Three subjects, nine images, one
# shape -- see `art/silhouette/` and the sheet beside it.
#
# The cause was in the brief, not the model. Four round-2 rules multiply out to
# a blob and leave nothing to tell one creature from another:
#
#   "THREE OR FOUR simple rounded shapes"
#   "no thin lines, no long limbs, no points, no sharp corners"
#   "nothing else in the frame" (no props)
#   "head at least half the total height"
#
# The mistake underneath was treating *cute* and *minimal* as one axis. The
# reference mascot of this genre is not minimal: it has a beak, eyebrows, two
# wings, two feet and three tail feathers -- 15+ deliberate shapes, several of
# them thin. It is cute AND articulated.
#
# So round 3 keeps round 2's baby proportions and face, and reverses the rest:
#
#   * an IDENTITY ANCHOR, which is a prop. Round 2 banned props and every
#     subject promptly lost its name -- a bookmark with no book is a blob, a
#     lamp with no thin neck is a mushroom, a worm with no book is a slug. The
#     prop here is deliberately *the chalk book from the app icon*, which is
#     also the bridge the "mascot inside a chalk-branded app" decision needs.
#   * ARTICULATION: distinct head, body and appendages, 10-14 shapes, thin
#     elements permitted where they carry meaning.
#   * the SILHOUETTE TEST stated as a requirement in the prompt itself.

CHAR_SILHOUETTE = (
    "SILHOUETTE TEST - THE SINGLE MOST IMPORTANT REQUIREMENT: if this whole "
    "drawing were filled in as one flat black shape, a stranger must still be "
    "able to tell exactly what the character is and what it is holding. So the "
    "outline must have clear, distinctive, readable bumps and notches - a "
    "recognisable head shape, visible arms, visible feet, and the prop clearly "
    "breaking the outline. It must NOT be a smooth featureless egg, blob, ball, "
    "bean or lump. Do not let the body merge into one undifferentiated mass."
)

CHAR_BUILD = (
    "BUILD - articulated, not minimal: the character is made of roughly TEN TO "
    "FOURTEEN deliberate shapes, not three. It has a clearly separate head and "
    "body, TWO visible arms ending in simple rounded hands, and TWO visible "
    "feet below the body. Thin shapes ARE allowed and wanted where they carry "
    "meaning - eyebrows, a neck, fingers, a tail tip. Every part is still soft "
    "and rounded with no spikes and no sharp points, but the parts must be "
    "clearly distinguishable from one another."
)

CHAR_FACE = (
    "FACE: exaggerated baby proportions - the head is large, about 45 to 55 "
    "percent of the total height. TWO large round eyes, set low and wide apart, "
    "each a big solid dark oval with one small white circular catchlight near "
    "its top. TWO short curved eyebrows above the eyes, which are what give it "
    "an expression. A small simple happy open smile below. One soft round rosy "
    "blush patch on each cheek. Sweet, warm, alert and delighted - never sly, "
    "sleepy, smug, blank or scary."
)

CHAR_RENDER = (
    "RENDERING - the production quality of a polished, professionally designed "
    "mobile-app mascot: crisp clean vector shapes with smooth confident curves "
    "and precise even edges, flat fills plus exactly ONE darker tone of each "
    "colour used as deliberate shading on the underside of forms, and a clear "
    "darker outline where two shapes overlap so every part stays separable. "
    "Polished and intentional, never sketchy, never mushy, never soft-focus, "
    "never airbrushed, never blurry, never a gradient wash."
)

CHAR_COLOUR = (
    "COLOUR: the character's body is a VIVID, SATURATED jade-mint green, the "
    "brand green #09BC8A - a strong clear green, NOT a pale pastel and NOT a "
    "washed-out sage. A soft cream off-white belly and face patch. A warm "
    "orange #FF922B on the feet and hands. The book it holds is WHITE with a "
    "soft powdery chalk texture, like white chalk drawn on a board, clearly a "
    "different material from the smooth vector character holding it."
)

CHAR_FRAME = (
    "FRAMING: a completely plain, flat, pure white background (#FFFFFF), "
    "perfectly uniform so it can be keyed out - no scene, no floor, no ground "
    "shadow, no gradient, no vignette, no frame, no border, no app-icon shape, "
    "no text, no letters, no numbers, no watermark. One character, centred, "
    "seen straight on from the front, whole body and both feet visible, "
    "generous even margins, nothing cropped. Not photorealistic, not "
    "3D-rendered, no chalk grain on the character itself."
)

# The prop, described once. It is the app icon's own book, so the mascot and the
# chalk brand share an object rather than merely coexisting.
CHAR_BOOK = (
    "a closed white book with a soft chalky texture, seen front-on, with a "
    "narrow spine strip down one edge and a bookmark ribbon hanging from the "
    "top of its cover ending in a V notch"
)

CHARACTER: dict[str, tuple[str, str]] = {
    "a-mark": (
        "articulated bookmark character",
        "an adorable BOOKMARK character standing up and holding a book. Its "
        "body is a long flat ribbon, clearly taller than it is wide, ending at "
        "the bottom in a distinct pointed V-shaped forked tail that is "
        "obviously a bookmark's notch. Its head sits on a short neck at the top "
        f"of the ribbon. It has two stubby arms hugging {CHAR_BOOK} against its "
        "chest, and two small rounded feet poking out below the forked tail. "
        "The V notch and the book must both be unmistakable in the outline.",
    ),
    "b-worm": (
        "articulated bookworm character",
        "an adorable BOOKWORM character reading a book. Its body is a plump "
        "worm with THREE OR FOUR clearly visible soft rounded segments, curving "
        f"up out of a hole in the front cover of {CHAR_BOOK} - the book stands "
        "upright and the worm emerges through a round hole in it, so the book "
        "and the worm are locked together and the hole is visible. The worm has "
        "two tiny stubby arms resting on the top edge of the book. Its head is "
        "clearly distinct from its segmented body. The segments, the hole and "
        "the book must all be unmistakable in the outline.",
    ),
    "c-lamp": (
        "articulated reading lamp character",
        "an adorable DESK LAMP character reading a book. It has a wide "
        "cone-shaped lampshade head, clearly WIDER at its bottom rim than at "
        "the top and tilted down to one side, joined to its body by a NARROW "
        "VISIBLE NECK - the contrast between the wide shade and the thin neck "
        "is what makes it a lamp and not a mushroom, so it must be obvious. "
        "Below that a small rounded body on a flat round base with two little "
        f"feet, and two stubby arms holding {CHAR_BOOK} open in front of it. "
        "The thin neck and the book must both be unmistakable in the outline.",
    ),
}

# ---------------------------------------------------------------- round 4

# Rounds 1-3 varied the SUBJECT and rolled the same prompt. Rounds 1 and 2 both
# failed, and the common cause was the prompt's *register*, not its content:
#
#   * ~2700 characters of rules and negations. Long negative lists are weak
#     levers, and naming a thing in order to forbid it can summon it -- round 1
#     said "NOT a spoon" and returned three spoons.
#   * it described a SPEC, not a picture. "10-14 deliberate shapes, two arms,
#     two feet" makes the model do bookkeeping instead of design.
#   * no artifact-type anchor. Never said "mascot character design" or
#     "character design sheet" -- the phrases that pull toward a well-built
#     character with limbs and a readable silhouette.
#   * no personality. Appeal comes from acting, not geometry.
#
# So round 4 holds the subject FIXED -- the bookworm holding the chalk book,
# which is the decision recorded in the mockup -- and varies the prompt strategy
# instead. Each entry below is a COMPLETE prompt, passed verbatim with no wrapper
# blocks, so the strategies are compared on equal terms.
#
# All four are positive-voice, under ~800 characters, and name what the image
# *is* rather than listing what it must avoid.

PROBES: dict[str, tuple[str, str]] = {
    "s1-direction": (
        "art-direction voice: describe the finished illustration",
        "App mascot character design: a cheerful little bookworm. A plump, "
        "friendly green worm with a big round head, huge sparkling eyes, arched "
        "expressive eyebrows and a wide open smile, two tiny arms hugging a "
        "white chalk-drawn book against its chest, two small orange feet peeking "
        "out below. Its body has three soft rounded segments and curls slightly "
        "to one side so the pose has life. Bold flat vector illustration, "
        "confident clean shapes, bright saturated jade green #09BC8A with a "
        "cream belly and warm orange accents, one darker tone for soft shading. "
        "Centred full-body front view on a plain white background. Charming, "
        "warm, instantly likeable, professional mascot design.",
    ),
    "s2-idiom": (
        "anchor the aesthetic family, not a specific image",
        "A mascot character for a reading app, designed in the visual language of "
        "modern mobile-app mascots: bold flat colour, thick confident shapes, "
        "oversized expressive eyes with bright catchlights, exaggerated cartoon "
        "proportions, high appeal and a strong readable silhouette. The "
        "character is a little green bookworm with a chunky segmented body, "
        "stubby arms and feet, arched eyebrows and a big happy grin, holding a "
        "white chalky storybook. Rich saturated jade green, cream, warm orange. "
        "Clean vector art, crisp edges, flat fills with one tone of soft "
        "shading. Full body, front view, centred, plain white background. "
        "Polished, production-ready mascot illustration.",
    ),
    "s3-acting": (
        "character acting first, let form follow feeling",
        "Meet a tiny, joyful bookworm who has just finished the best book of his "
        "life and is hugging it tight, eyes bright with delight, grinning from "
        "ear to ear. He is round and squishy and vivid green, with a big head, "
        "little stubby arms wrapped around a white chalk-textured book, and two "
        "small orange feet. Drawn as a charming flat-vector app mascot: bold "
        "shapes, warm saturated colours, playful and full of personality, the "
        "kind of character people screenshot and send to a friend. Full body, "
        "front view, centred on plain white. The feeling is pure delight.",
    ),
    "s4-sheet": (
        "invoke the artifact type: a character design sheet",
        "Professional character design sheet: a cute bookworm mascot for a "
        "reading app. Front view, full body, standing. Clearly constructed from "
        "distinct parts - a large round head, arched eyebrows, huge glossy eyes "
        "with catchlights, a wide smile, a chunky three-segment body, two short "
        "rounded arms holding a white chalk-drawn book, and two small orange "
        "feet planted on the ground. Strong readable silhouette with clear "
        "distinct bumps for the head, the arms, the feet and the book. Flat "
        "vector style, bold clean shapes, saturated jade green #09BC8A with "
        "cream and orange, single-tone shading. Plain white background.",
    ),
    "s5-hybrid": (
        "s1's voice + s4's flat discipline + the two silhouette fixes",
        # What each clause here is buying, from the s1-s4 probe:
        #   s1 won on appeal AND on silhouette, so its art-direction voice is
        #     the base.
        #   s2 had the worst outline because an OPEN book held flat against the
        #     belly sits inside the body mass -- so the book is now closed, held
        #     to one side, and required to break the outline.
        #   the TAIL CURL is the single cue that separates worm from chick; s1
        #     had it, s2/s3/s4 lost it. Now stated explicitly.
        #   s3 proved targeted negations are still needed: with "no text"
        #     dropped it wrote BEST BOOK on the cover, and it grew fangs. Three
        #     short negations, not a twenty-item wall.
        #   s1 was glossy and plastic; s4's flat fills read better and survive
        #     being redrawn as vector. Hence flat, no gradients.
        "App mascot character design: a cheerful little bookworm, full of "
        "personality. A big round head with huge bright eyes, a white catchlight "
        "in each, two arched expressive eyebrows, and a wide happy open smile. "
        "Its plump body is made of three soft rounded segments and its tail "
        "curls up and outward to one side, clearly a worm. Two short rounded "
        "arms reach out to one side to hold a closed white chalk-textured book "
        "with a bookmark ribbon, held away from the body so the book sticks "
        "clearly out past its silhouette. Two small orange feet planted below. "
        "Bold flat vector illustration with crisp clean edges, solid flat fills "
        "and one darker tone for gentle shading. Vivid saturated jade green "
        "#09BC8A body, cream belly, warm orange feet. Full body, front view, "
        "centred on plain white. Charming, warm, instantly likeable, polished "
        "professional mascot art. No text or lettering anywhere, no teeth or "
        "fangs, no glossy 3D shine or gradients.",
    ),
    "s6-refine": (
        "img2img refinement pass over our own best output",
        # Used with --reference, so this runs through /v1/images/edits with one of
        # our own s5 images as <IMAGE_0>. This is the standard pro loop -- generate,
        # pick, then refine at higher resolution -- and it is the legitimate form of
        # "pass a great mascot in as context": the reference is OUR character, so
        # nothing derivative of a third party's protected design can come back.
        #
        # Deliberately NOT seeded with a real commercial mascot. Two reasons, and
        # the practical one is as strong as the legal one: this route copies the
        # seed's geometry (see PROMPTS.md, "output quality was capped by the seed's
        # geometry -- it faithfully reproduced a crown-shaped ribbon"), so an owl
        # reference returns an owl, which is both off-brief and a trademark problem
        # for an app that ships.
        "Redraw <IMAGE_0> as a more polished, higher-craft version of the same "
        "character, keeping its exact design, pose, proportions, colours and "
        "expression. Same bookworm, same curled tail, same segmented body, same "
        "closed chalk-textured book held out to one side, same orange feet. "
        "Improve only the execution: cleaner and more confident shape edges, "
        "smoother and more deliberate curves, crisper flat colour fills, better "
        "balanced weight between the head and the body, and more refined hands "
        "and feet. Professional vector mascot finish, the quality of a polished "
        "commercial character design. Flat fills with one darker tone for gentle "
        "shading, no gradients, no glossy 3D shine, no sketch lines, no text, "
        "plain pure white background.",
    ),
}


# ---------------------------------------------------------------- round 6

# The library cat, and the format shift that came with it. The reference for this
# round is Duolingo's streak-widget grid: 25 tiles of ONE character across
# escalating states, not a single portrait.
#
# Why a cat beats the worm on the thing that kept failing: ears and a tail are
# exactly the "distinctive bumps" the silhouette test wants, so a cat survives
# being flattened to black where a worm barely does. And a cat has a canonical
# pose vocabulary -- loaf, stretch, curl, arch -- so one design covers many
# states without redesign, which is what a six-moment streak feature needs.
#
# What NOT to copy from the reference grid: its emotional arc. That set escalates
# into guilt -- hellfire, a skeleton, a demon, "Last chance!" -- and
# `docs/superpowers/specs/2026-09-12-reading-streaks-design.md` explicitly refuses
# it ("amber and never red", "no red, no broken-flame illustration, no guilt
# copy", and a broken streak shows *the record*, not a zero). So this cat
# escalates AWAKE -> ASLEEP instead of calm -> damnation: as the streak lapses the
# cat settles and dozes, still keeping your place, which is the same no-guilt
# argument the bookmark made.
#
# All prompts below use everything rounds 4 and 5 established: art-direction
# voice, artifact-type anchor, acting over geometry, few targeted negations, the
# identity-carrying features named out loud (ears, tail, the book stack), 2k.

CAT_STYLE = (
    "Bold flat vector illustration, crisp confident shapes, solid flat colour "
    "fills with one slightly darker tone for gentle shading. Big bright eyes with "
    "one white catchlight in each, a tiny muzzle, and large triangular ears. Full "
    "body, seen straight on from the front, centred on a plain pure white "
    "background with generous even margins, nothing cropped. Charming, warm, "
    "instantly likeable, polished professional app-mascot art. No text or "
    "lettering, no collar, no glasses, no gradients, no glossy 3D shine."
)

CAT_BOOKS = (
    "closed white books with a soft chalky texture, each with a bookmark ribbon "
    "ending in a V notch"
)

CAT: dict[str, tuple[str, str]] = {
    # The one question to settle visually rather than argue about: does the
    # character carry brand green, or stay a natural colour with green accents?
    "cat-green": (
        "brand-green cat",
        "App mascot character design: a cheerful little library cat sitting "
        f"upright and alert on a small stack of two {CAT_BOOKS}. One front paw "
        "rests on the top cover and its long tail curls up beside it. Its fur is "
        "a vivid saturated jade green, the brand green #09BC8A, with a cream "
        "chest and muzzle and warm orange paws and inner ears. "
        f"{CAT_STYLE}",
    ),
    "cat-cream": (
        "natural cat, brand green as accent",
        "App mascot character design: a cheerful little library cat sitting "
        f"upright and alert on a small stack of two {CAT_BOOKS}. One front paw "
        "rests on the top cover and its long tail curls up beside it. Its fur is "
        "soft warm cream and pale grey with darker grey ear tips and tail tip, "
        "and its eyes are a vivid saturated jade green, the brand green #09BC8A. "
        "The books it sits on are that same jade green. "
        f"{CAT_STYLE}",
    ),
    # Pose set, run with --reference against the chosen base so the SAME cat is
    # re-posed rather than redesigned. Mapped to the six moments the streak spec
    # already defines.
    "pose-alert": (
        "sc-increment -- it went up",
        "Redraw the character from <IMAGE_0> in a new pose, keeping its exact "
        "design, colours, proportions and style identical. The cat sits up tall "
        "and bright-eyed on its stack of books, delighted, both ears perked "
        "straight up, its tail raised and curling into a cheerful hook. Same cat, "
        "same palette, new pose. Plain pure white background, no text.",
    ),
    "pose-stretch": (
        "sc-risk -- the evening nudge, never a threat",
        "Redraw the character from <IMAGE_0> in a new pose, keeping its exact "
        "design, colours, proportions and style identical. The cat is mid-stretch "
        "beside its stack of books, front paws reaching forward and back arched "
        "in a long lazy stretch, eyes half closed, mouth open in a wide yawn. "
        "Sleepy and content, absolutely not distressed. Same cat, same palette, "
        "new pose. Plain pure white background, no text.",
    ),
    "pose-curled": (
        "sc-freeze / sc-broken -- a forgiven day, place kept",
        "Redraw the character from <IMAGE_0> in a new pose, keeping its exact "
        "design, colours, proportions and style identical. The cat is curled into "
        "a soft sleeping circle on top of one closed book, tail wrapped around "
        "itself, eyes closed in two gentle curved lines, peaceful and cosy. Same "
        "cat, same palette, new pose. Plain pure white background, no text.",
    ),
    "pose-loaf": (
        "sc-milestone / idle -- settled and proud",
        "Redraw the character from <IMAGE_0> in a new pose, keeping its exact "
        "design, colours, proportions and style identical. The cat sits in a "
        "compact loaf, paws tucked entirely underneath it, on top of a taller "
        "stack of three books, looking straight ahead with a calm satisfied "
        "expression and its tail curled neatly around its side. Same cat, same "
        "palette, new pose. Plain pure white background, no text.",
    ),
    "cat14sq": (
        "14-shape cat, square silhouette, no book",
        "App mascot character design: a simple library cat, built from only about "
        "FOURTEEN flat shapes total, and nothing else in the frame at all.\n\n"
        "PROPORTION IS THE MOST IMPORTANT THING: the character's silhouette must "
        "be roughly SQUARE and fill the frame generously - about as WIDE as it is "
        "TALL, reaching close to the left and right edges as well as the top and "
        "bottom. So the body is wide, round and squat with a broad heavy base, not "
        "a tall narrow column, and the tail sweeps out sideways well away from the "
        "body to help fill the width. No tall empty space and no wide empty margins "
        "at the sides.\n\n"
        "The head and body are ONE single continuous rounded shape, with two small "
        "triangular ear notches at the top and no separate neck and no separate "
        "legs. The face is minimal: two simple half-closed eyes drawn as small "
        "curved lids, a tiny triangular nose, nothing else. Two LARGE white oval "
        "shapes down the front for the chest and belly, big enough to genuinely "
        "break up the body mass. One smooth curved tail shape, and two small "
        "slightly darker shapes suggesting the far legs at the base. Solid flat "
        "vivid jade green #09BC8A with white accents. Radically simple, confident "
        "and geometric - the appeal comes from the silhouette, not from detail. "
        "Front view, centred, plain pure white background. Absolutely no book, no "
        "props, no objects, no whiskers, no fur tufts, no stripes or markings, no "
        "inner-ear colour, no shading, no gradients, no outlines, no text.",
    ),
    "cat14": (
        "14-shape cat, per the Duolingo shape-count guide",
        "App mascot character design: a simple library cat, built from only about "
        "FOURTEEN flat shapes total. The head and body are ONE single continuous "
        "rounded shape - a tall soft blob with two small triangular ear notches at "
        "the top - with no separate neck and no separate legs. The face is minimal: "
        "two simple sleepy half-closed eyes drawn as small curved lids, a tiny "
        "triangular nose, and nothing else at all. Two small white oval shapes on "
        "the front for the chest and belly. One smooth curved tail shape sweeping "
        "out to the side, and two small slightly darker shapes suggesting the far "
        "legs. It sits beside one simple white book. Solid flat vivid jade green "
        "#09BC8A with white accents. Radically simple, confident and geometric - "
        "the appeal comes from the silhouette, not from detail. Front view, "
        "centred, plain pure white background. Absolutely no whiskers, no fur "
        "tufts, no stripes or markings, no inner-ear colour, no shading, no "
        "gradients, no outlines, no text.",
    ),
}


# ---------------------------------------------------------------- round 7
#
# Geometry sweep. Twenty prompts, character ONLY -- no book, no props -- written
# in terse keyword art-direction voice rather than the long paragraph voice of
# earlier rounds, because the aim is to find which *phrasing* lands rather than
# to perfect one description. Shape count is pushed well below fourteen: the note
# from the Duolingo design team is that fewer shapes reads simpler. Framed 4:5 so
# the silhouette gets room in a near-square field.

GEO: dict[str, tuple[str, str]] = {
    "g01-geo": (
        "the brief verbatim: geometric minimalist",
        "Library cat character, flat 2D vector illustration, geometric minimalist "
        "design, minimal linework, NO outlines, solid flat colors, block body, "
        "cylindrical stick limbs, ultra clean, vibrant and approachable, centered "
        "portrait composition. Vivid jade green #09BC8A, white accents, plain white "
        "background. No props, no book, no text.",
    ),
    "g02-block": (
        "block body, stick limbs, hard geometry",
        "Library cat mascot. The body is one BLOCK - a rounded rectangle, wide and "
        "squat. The head is a circle set straight on top of it with two triangle "
        "ears. The limbs are simple CYLINDRICAL STICKS with rounded ends, two arms "
        "and two legs. Flat 2D vector, solid flat jade green #09BC8A, no outlines, "
        "no shading, no gradients. Two dot eyes and a tiny triangle nose, nothing "
        "else on the face. Centered, plain white background, no props.",
    ),
    "g03-loaf": (
        "cat loaf, one mass, near-square",
        "Library cat mascot sitting in a compact loaf, paws tucked under. The whole "
        "animal is ONE continuous rounded mass, as wide as it is tall, with two "
        "triangular ear notches cut into the top edge and a tail curving along the "
        "base. Flat 2D vector, solid jade green #09BC8A, one white oval on the "
        "chest, no outlines, no shading. Face is two closed curved eyes and a tiny "
        "nose. Centered, plain white background, no props.",
    ),
    "g04-eight": (
        "only eight shapes",
        "Library cat mascot built from EXACTLY EIGHT flat shapes and not one more: "
        "one body mass, two ears, two eyes, one nose, one belly patch, one tail. "
        "Nothing else exists. Flat 2D vector, solid jade green #09BC8A and white, "
        "no outlines, no shading, no gradients, no linework. Bold, confident, "
        "instantly readable. Centered portrait, plain white background, no props.",
    ),
    "g05-twelve": (
        "twelve shapes, with limbs",
        "Library cat mascot built from about TWELVE flat shapes: one block body, one "
        "round head, two triangle ears, two stick arms, two stick legs, one tail, "
        "two eyes, one nose. Flat 2D vector illustration, solid flat jade green "
        "#09BC8A with a white chest, no outlines, no shading, no texture. Friendly "
        "and approachable. Centered, plain white background, no props, no text.",
    ),
    "g06-bigears": (
        "ears carry the silhouette",
        "Library cat mascot whose BIG TRIANGULAR EARS are the strongest feature - "
        "wide, tall and far apart, they set the character's whole outline. Below "
        "them a small simple rounded body and a thin curved tail. Flat 2D vector, "
        "solid jade green #09BC8A, white belly, no outlines, no inner-ear colour, "
        "no shading. Minimal face: two small eyes, no mouth. Centered, plain white "
        "background, no props.",
    ),
    "g07-dots": (
        "two dot eyes and nothing else",
        "Library cat mascot, extremely simple. The face is TWO SMALL DARK DOTS for "
        "eyes and nothing else at all - no nose, no mouth, no whiskers, no blush. "
        "The body is one soft rounded mass with ear notches and a curled tail. Flat "
        "2D vector, one solid flat jade green #09BC8A, no outlines, no shading, no "
        "gradients. Quiet, calm, charming. Centered portrait, plain white "
        "background, no props.",
    ),
    "g08-bold": (
        "bold shape-driven mascot, high contrast",
        "Bold flat vector app mascot: a library cat. Big simple shapes, strong "
        "silhouette, high contrast, no small parts and no fine detail anywhere. "
        "Round head, chunky body, stubby limbs, thick tail. Saturated jade green "
        "#09BC8A with crisp white markings. No outlines, no gradients, no shading, "
        "no texture. Playful and modern, the look of a polished mobile game mascot. "
        "Centered, plain white background, no props, no text.",
    ),
    "g09-vinyl": (
        "vinyl-toy proportions, flat render",
        "Library cat mascot with vinyl collectible toy proportions: enormous round "
        "head, tiny short body, stubby cylindrical arms and legs. Drawn FLAT, as 2D "
        "vector shapes with solid fills - not 3D, not rendered, not glossy. Jade "
        "green #09BC8A body, white muzzle, no outlines, no shading. Two large "
        "friendly eyes, small smile. Centered, plain white background, no props.",
    ),
    "g10-negative": (
        "white markings as negative space",
        "Library cat mascot where the white markings do all the work: two LARGE "
        "white shapes - a chest blaze and a belly oval - cut into a solid jade "
        "green #09BC8A body, big enough to break the mass into clear zones. Simple "
        "rounded body, ear notches, one curved tail. Flat 2D vector, no outlines, "
        "no shading, no gradients. Minimal face. Centered portrait, plain white "
        "background, no props.",
    ),
    "g11-mono": (
        "one colour only",
        "Library cat mascot drawn in ONE FLAT COLOUR ONLY - solid jade green "
        "#09BC8A - on plain white. The only white in the character is the two eye "
        "shapes knocked out of the green. One continuous silhouette: rounded body, "
        "ear notches, curved tail, four simple stick legs. Flat 2D vector, no "
        "outlines, no shading, no second tone. Reads perfectly as a solid "
        "silhouette. Centered, no props, no text.",
    ),
    "g12-bean": (
        "bean body",
        "Library cat mascot whose body is a simple BEAN shape - one soft asymmetric "
        "oval leaning slightly to one side, giving the pose life without any "
        "articulation. Two triangle ears on top, one thin curved tail, two tiny "
        "nub feet at the bottom. Flat 2D vector, solid jade green #09BC8A, white "
        "chest, no outlines, no shading. Two half-closed content eyes. Centered, "
        "plain white background, no props.",
    ),
    "g13-tail": (
        "tail as counterweight, fills the frame",
        "Library cat mascot composed so the TAIL sweeps out wide to one side as a "
        "long bold curve, balancing the body and filling the frame edge to edge. "
        "Compact rounded body, ear notches, sitting upright. Flat 2D vector, solid "
        "jade green #09BC8A with a white chest, no outlines, no shading, no "
        "gradients. Simple face, two calm eyes. Centered portrait, plain white "
        "background, no props.",
    ),
    "g14-seated": (
        "seated front view, visible limbs",
        "Library cat mascot seated facing forward, body square to the viewer, two "
        "straight cylindrical front legs planted below it and two rounded back feet "
        "either side. Head is a circle with triangle ears. Tail curls out beside. "
        "Flat 2D vector illustration, geometric, solid flat jade green #09BC8A and "
        "white, minimal linework, NO outlines, no shading. Centered, plain white "
        "background, no props, no text.",
    ),
    "g15-mark": (
        "logo-mark simplicity",
        "A library cat reduced almost to a LOGO MARK: the fewest possible flat "
        "shapes, perfectly balanced, geometric, constructed from circles and "
        "triangles. Still warm and likeable, not cold or corporate. Solid jade "
        "green #09BC8A, white knockouts for the eyes, no outlines, no shading, no "
        "detail of any kind. Centered, plain white background, no props, no text.",
    ),
    "g16-chunky": (
        "chunky, wide, squat",
        "Library cat mascot that is CHUNKY, WIDE and SQUAT - clearly wider than it "
        "is tall, with a heavy broad base, short thick limbs and a fat tapering "
        "tail. Nothing thin, nothing elegant. Flat 2D vector, solid jade green "
        "#09BC8A, one big white belly shape, no outlines, no shading, no gradients. "
        "Simple sleepy face. Centered portrait, plain white background, no props.",
    ),
    "g17-cutout": (
        "paper-cutout collage",
        "Library cat mascot that looks CUT FROM FLAT PAPER and assembled - each part "
        "a clean hard-edged shape of solid colour laid over the next, crisp scissor "
        "edges, no outlines and no shading. Simple rounded body, triangle ears, "
        "curved tail, small stick limbs. Jade green #09BC8A and white on plain "
        "white. Centered, no props, no text.",
    ),
    "g18-happy": (
        "same simplicity, bright and delighted",
        "Library cat mascot, very simple flat 2D vector shapes, but the expression is "
        "BRIGHT AND DELIGHTED - two wide open round eyes, ears perked straight up, "
        "tail raised in a cheerful hook, body leaning forward eagerly. Solid jade "
        "green #09BC8A with a white chest, geometric block body, stick limbs, no "
        "outlines, no shading, minimal linework. Centered, plain white background, "
        "no props.",
    ),
    "g19-sleepy": (
        "same simplicity, sleepy and settled",
        "Library cat mascot, very simple flat 2D vector shapes, expression SLEEPY AND "
        "SETTLED - eyes are two small downward curved lids, ears relaxed and angled "
        "slightly out, body low and rounded, tail wrapped close. Solid jade green "
        "#09BC8A with a white belly, no outlines, no shading, no gradients, minimal "
        "linework. Warm and cosy, never sad. Centered, plain white background, no "
        "props.",
    ),
    "g20-icon": (
        "must survive 24px",
        "Library cat mascot designed to stay readable at 24 pixels: three or four "
        "big flat shapes, enormous clear silhouette, no internal detail, generous "
        "spacing between parts, nothing thinner than the ears. Solid jade green "
        "#09BC8A, white eyes knocked out, no outlines, no shading, no texture. "
        "Centered portrait composition, plain white background, no props, no text.",
    ),
}


# ---------------------------------------------------------------- round 8
#
# Round 7 was read as simultaneously too simple (g11, g15, g20 -- silhouettes, not
# characters), too complicated in one case (g08 -- whiskers, toes and an uninvited
# book), and colour-starved throughout: one green plus white cannot separate ear
# from head from belly, so every form collapsed into the same flat mass.
#
# So this round fixes a FIVE-COLOUR palette and states it identically in every
# prompt, and aims squarely at the middle of the complexity range. The palette is
# named the same way each time on purpose -- it is the one variable held constant
# while silhouette and acting vary, which is what makes the twenty comparable.

PAL5 = (
    "Exactly FIVE colours, no more and no fewer: vivid jade green #09BC8A for the "
    "main body, a deeper forest green #07795C for the ears, the tail and the far "
    "legs so those forms separate clearly from the body, warm cream #FFF3DC for "
    "the belly and muzzle, bright warm orange #FF922B for the nose and paw pads, "
    "and near-black ink #17262E for the eyes. All five are SOLID FLAT fills - no "
    "gradients, no soft shading, no outlines, no texture."
)

GEO5_TAIL = (
    "Plain pure white background, character centred with even margins, nothing "
    "cropped. No book, no props, no objects, no text or lettering, no whiskers, "
    "no stripes."
)

GEO5: dict[str, tuple[str, str]] = {
    "h01-eight": (
        "round 7's g04 silhouette, five colours",
        "Library cat mascot sitting upright, seen straight on. Head and body are one "
        "continuous rounded mass with two clear triangular ears, one large oval "
        f"belly patch, and a long tail curving out to one side. {PAL5} About a dozen "
        f"flat shapes - simple, but with enough parts to read as a character rather "
        f"than a symbol. {GEO5_TAIL}",
    ),
    "h02-chunky": (
        "round 7's g16 silhouette, five colours",
        "Library cat mascot, chunky and squat, wider than it is tall, with a heavy "
        "broad base and a big rounded belly patch filling most of the front. Short "
        "thick limbs, a fat tapering tail curled along the ground, sleepy "
        f"half-closed eyes. {PAL5} Cosy and settled. {GEO5_TAIL}",
    ),
    "h03-sweep": (
        "round 7's g19 silhouette, five colours",
        "Library cat mascot with a long bold tail sweeping out in a wide curve to one "
        "side, balancing a compact rounded body so the whole shape nearly fills a "
        f"square. Relaxed, eyes softly closed, ears angled gently outward. {PAL5} "
        f"{GEO5_TAIL}",
    ),
    "h04-seated": (
        "seated, front legs visible",
        "Library cat mascot seated facing forward with two straight front legs "
        "planted below it and two rounded back feet either side, paw pads showing. "
        "Round head with triangular ears, cream muzzle, tail curling out beside the "
        f"body. {PAL5} Flat geometric vector construction, twelve to fifteen shapes. "
        f"{GEO5_TAIL}",
    ),
    "h05-standing": (
        "standing on two legs, stubby arms",
        "Library cat mascot standing upright on two short legs like a little person, "
        "two stubby rounded arms at its sides, big round head, cream chest and "
        f"muzzle, tail curving up behind. Friendly and approachable. {PAL5} Flat "
        f"vector, chunky proportions, nothing thin or spindly. {GEO5_TAIL}",
    ),
    "h06-loaf": (
        "loaf, one mass",
        "Library cat mascot sitting in a compact loaf with its paws tucked "
        "underneath, the whole animal one continuous rounded mass as wide as it is "
        "tall, triangular ears on top, tail wrapped neatly around one side, eyes two "
        f"calm closed curves. {PAL5} {GEO5_TAIL}",
    ),
    "h07-bean": (
        "bean body, slight lean",
        "Library cat mascot whose body is one soft bean shape leaning slightly to one "
        "side so the pose has life without articulation. Triangular ears, a cream "
        "belly oval, a thick curved tail, two small paw shapes at the base, and a "
        f"content half-lidded expression. {PAL5} {GEO5_TAIL}",
    ),
    "h08-bigeyes": (
        "big eyes carry the charm",
        "Library cat mascot with TWO LARGE round ink-black eyes set low and wide on a "
        "big round head, each with one small cream catchlight, a tiny orange "
        "triangle nose and a small soft smile. Short plump body below, cream belly, "
        f"tail curling out. {PAL5} Sweet and delighted. {GEO5_TAIL}",
    ),
    "h09-tuxedo": (
        "cream markings do the work",
        "Library cat mascot with bold cream markings breaking up the green: a wide "
        "cream blaze up the chest into the muzzle and a large cream belly oval, so "
        "the body reads as clear separate zones. Upright sitting pose, deeper green "
        f"ears and tail, orange nose. {PAL5} {GEO5_TAIL}",
    ),
    "h10-stretch": (
        "mid-stretch, long and low",
        "Library cat mascot mid-stretch: front paws reaching forward, back arched "
        "high, rear end up, eyes squeezed shut, mouth open in a wide yawn. Long low "
        f"silhouette, tail raised behind. {PAL5} Sleepy and content, never "
        f"distressed. {GEO5_TAIL}",
    ),
    "h11-curled": (
        "curled asleep",
        "Library cat mascot curled into a soft sleeping circle, tail wrapped right "
        "around its own body, nose tucked near the tail tip, eyes two gentle closed "
        "curves, ears relaxed and flat. A cream belly patch shows where the body "
        f"curls. {PAL5} Peaceful and cosy. {GEO5_TAIL}",
    ),
    "h12-perked": (
        "alert and delighted",
        "Library cat mascot sitting up tall and bright-eyed, both ears perked "
        "straight up, tail raised and curling into a cheerful hook, front paws "
        f"together, wide open happy eyes. {PAL5} Energetic and pleased. {GEO5_TAIL}",
    ),
    "h13-headbig": (
        "oversized head, tiny body",
        "Library cat mascot with an enormous round head filling the top half of the "
        "figure and a tiny short plump body beneath it, stubby limbs, a small tail. "
        "Cream muzzle patch, orange nose, large friendly eyes. Vinyl-collectible "
        f"proportions but drawn completely FLAT as 2D vector shapes. {PAL5} "
        f"{GEO5_TAIL}",
    ),
    "h14-threequarter": (
        "three-quarter view",
        "Library cat mascot sitting in a three-quarter view, body turned slightly so "
        "one shoulder is nearer the viewer and the tail sweeps across behind. Head "
        "turned to face forward, triangular ears, cream chest, orange nose. Flat "
        f"vector, clean geometric construction. {PAL5} {GEO5_TAIL}",
    ),
    "h15-blocky": (
        "hard geometry, soft colour",
        "Library cat mascot built from frankly geometric parts - a rounded rectangle "
        "body, a circle head, two clean triangles for ears, cylindrical limbs with "
        "rounded ends, one tapering tail - assembled so it still feels warm and "
        f"likeable rather than mechanical. {PAL5} The five colours are what keep the "
        f"parts distinct. {GEO5_TAIL}",
    ),
    "h16-plush": (
        "plush toy, flat rendered",
        "Library cat mascot that looks like a soft plush toy - every form fat, "
        "rounded and squeezable, no sharp corners anywhere, short stubby limbs, "
        "round belly, big cream muzzle. Drawn flat as clean 2D vector shapes, not "
        f"photographed and not 3D. {PAL5} {GEO5_TAIL}",
    ),
    "h17-earsdown": (
        "relaxed ears, warm expression",
        "Library cat mascot with its ears relaxed and angled outward rather than "
        "pointed up, giving a soft unguarded expression. Rounded body, cream belly, "
        "thick tail curled forward beside the front paws, eyes half-lidded and "
        f"warm. {PAL5} {GEO5_TAIL}",
    ),
    "h18-paws": (
        "orange paws as the accent",
        "Library cat mascot sitting upright where the ORANGE is concentrated in four "
        "clear paw shapes and the nose, giving the figure bright anchor points at "
        "the bottom. Green body, deeper green ears and tail, large cream belly. "
        f"{PAL5} {GEO5_TAIL}",
    ),
    "h19-tallsit": (
        "upright column, tail as base",
        "Library cat mascot sitting very upright in a tall narrow column, front paws "
        "neatly together, with the tail curving around the base to widen the "
        "silhouette into a near-square footprint. Calm dignified expression, small "
        f"cream bib. {PAL5} {GEO5_TAIL}",
    ),
    "h20-peek": (
        "cheeky, head tilted",
        "Library cat mascot with its head tilted to one side, one ear flopping over, "
        "eyes bright and slightly mischievous, one front paw raised in a small wave. "
        f"Compact rounded body, cream chest, tail flicking up behind. {PAL5} "
        f"{GEO5_TAIL}",
    ),
}


# ---------------------------------------------------------------- round 9
#
# Round 8's colour read as teal and its eyes read as flat lids -- not vibrant, not
# passionate. And the shape budget was spent in the wrong place: fifteen shapes
# spread evenly over a whole cat leaves three or four for the face, which is
# exactly backwards. The face is where every mascot's charm lives.
#
# So round 9 inverts the budget: MOST shapes go to the face, and the body drops to
# two or three plain masses with nothing inside them. The one variable swept across
# the twenty is the EYE AND EXPRESSION treatment, because that is what "not
# passionate enough" is about. Palette is stated as hot and saturated with the
# specific failure mode -- teal -- named, since "jade green" alone drifted there
# twenty times out of twenty.

HOT5 = (
    "COLOUR - must be VIBRANT, HOT and SATURATED, full of energy: the body is an "
    "intense electric spring green #09BC8A pushed as bright and punchy as it will "
    "go, a green that glows. It is NOT teal, NOT blue-green, NOT sea green, NOT "
    "muted, NOT dusty, NOT pastel, NOT olive. With it: a deep rich emerald #06825F "
    "for ears and tail, bright warm cream #FFF6E0, a hot punchy coral orange "
    "#FF5E1F for the nose and mouth, and deep ink #10242B for the eyes. All solid "
    "flat fills - no gradients, no soft shading, no outlines."
)

FACE_BUDGET = (
    "SHAPE BUDGET - the most important rule: about three quarters of all the shapes "
    "in this drawing are in the FACE, and the face is large and fills most of the "
    "head. The BODY is only two or three plain simple masses - a single rounded "
    "body shape, one tail, and nothing else - with absolutely no internal detail, "
    "no markings, no separate limbs, no paw pads, no belly patch. All the craft and "
    "all the small shapes go into the eyes and expression."
)

FACE_TAIL = (
    "Flat 2D vector illustration, bold clean shapes. Plain pure white background, "
    "centred, nothing cropped. No book, no props, no text, no whiskers."
)

FACE: dict[str, tuple[str, str]] = {
    "f01-tall": (
        "tall oval eyes, double catchlight",
        "Library cat mascot. EYES: two TALL rounded-oval ink eyes, big and glossy, "
        "each with one large cream catchlight high up and one small one low down, set "
        "wide apart and low on the face. A small coral triangle nose and a short "
        f"upward-curving smile below. Bright and eager. {FACE_BUDGET} {HOT5} "
        f"{FACE_TAIL}",
    ),
    "f02-brows": (
        "thick arched eyebrows",
        "Library cat mascot. EYES: two big round ink eyes with a cream catchlight "
        "each, and above them TWO THICK EXPRESSIVE EYEBROWS arched high in delight - "
        "the eyebrows are the loudest shapes in the drawing. Coral nose, wide open "
        f"smiling mouth. Full of enthusiasm. {FACE_BUDGET} {HOT5} {FACE_TAIL}",
    ),
    "f03-sparkle": (
        "four-point star sparkles in the eyes",
        "Library cat mascot. EYES: two large ink eyes each containing a bright "
        "FOUR-POINTED CREAM STAR SPARKLE instead of a plain round highlight, so the "
        "eyes look thrilled and shining. Small coral nose, big happy open mouth, one "
        f"soft coral blush patch on each cheek. Excited and passionate. "
        f"{FACE_BUDGET} {HOT5} {FACE_TAIL}",
    ),
    "f04-determined": (
        "upward-slanting determined eyes",
        "Library cat mascot. EYES: two ink eyes that SLANT UPWARD AND INWARD at a "
        "confident angle, with a straight bold brow line over each and a single cream "
        "catchlight, giving a fired-up determined look. Coral nose, mouth open in a "
        f"keen grin. Bold and driven, never angry. {FACE_BUDGET} {HOT5} {FACE_TAIL}",
    ),
    "f05-huge": (
        "eyes fill half the face",
        "Library cat mascot. EYES: two ENORMOUS round ink eyes that together take up "
        "HALF THE ENTIRE FACE, each with a big cream catchlight and a smaller second "
        "one. Everything else on the face is tiny by comparison: a minute coral nose "
        f"and a small soft smile. Wide-eyed wonder. {FACE_BUDGET} {HOT5} "
        f"{FACE_TAIL}",
    ),
    "f06-arcs": (
        "joyful closed arcs and a wide grin",
        "Library cat mascot. EYES: two happy CLOSED EYES drawn as bold upward arcs "
        "like the tops of two circles, squeezed shut with joy, with a short curved "
        "crease under each. Below, a WIDE open grinning mouth showing a coral tongue, "
        f"and a coral blush on each cheek. Delighted. {FACE_BUDGET} {HOT5} "
        f"{FACE_TAIL}",
    ),
    "f07-shock": (
        "wide open thrilled eyes",
        "Library cat mascot. EYES: two very wide OPEN eyes - a large cream oval with a "
        "big ink pupil floating inside it and a bright highlight, ringed all around "
        "so the whole eye shows, giving a thrilled just-saw-something look. Small "
        f"coral nose, small open round mouth. Surprised and excited. {FACE_BUDGET} "
        f"{HOT5} {FACE_TAIL}",
    ),
    "f08-hearts": (
        "heart-shaped catchlights",
        "Library cat mascot. EYES: two big ink eyes each holding a small cream "
        "HEART-SHAPED highlight, so the character looks smitten and full of love. "
        "Coral nose, soft closed smile curving up at both ends, one coral blush patch "
        f"per cheek. Warm and adoring. {FACE_BUDGET} {HOT5} {FACE_TAIL}",
    ),
    "f09-smug": (
        "raised brow, confident half-lid",
        "Library cat mascot. EYES: two ink eyes half covered by bold curved upper "
        "lids, with ONE eyebrow raised much higher than the other, giving a playful "
        "knowing confidence. Coral nose, mouth a small crooked smirk pulled up on one "
        f"side. Charismatic and self-assured, never mean. {FACE_BUDGET} {HOT5} "
        f"{FACE_TAIL}",
    ),
    "f10-tongue": (
        "big open laugh with tongue",
        "Library cat mascot. FACE: a BIG WIDE OPEN LAUGHING MOUTH is the largest "
        "feature, a bold rounded shape with a coral tongue inside it. Above it two "
        "round ink eyes squeezed into happy curves with catchlights, and two arched "
        f"brows. Loud, joyful, bursting with energy. {FACE_BUDGET} {HOT5} "
        f"{FACE_TAIL}",
    ),
    "f11-anime": (
        "tall rounded-rectangle eyes",
        "Library cat mascot. EYES: two TALL ROUNDED-RECTANGLE ink eyes, much taller "
        "than they are wide, each with a large cream highlight at the top and a thin "
        "bold lash line across the upper edge. Tiny coral nose, small pleased smile. "
        f"Sharp, modern and striking. {FACE_BUDGET} {HOT5} {FACE_TAIL}",
    ),
    "f12-wink": (
        "one eye winking",
        "Library cat mascot. EYES: one big round open ink eye with a bright cream "
        "catchlight, and the other WINKED SHUT as a bold downward curve with a small "
        "crease. Coral nose, cheeky open smile pulled to one side, coral blush under "
        f"the winking eye. Playful and full of life. {FACE_BUDGET} {HOT5} "
        f"{FACE_TAIL}",
    ),
    "f13-fired": (
        "squint and gritted grin",
        "Library cat mascot. FACE: eyes SQUEEZED into two determined narrow slants "
        "under strong straight brows, and a wide gritted grin below showing a bold "
        "cream band of teeth. The look of someone giving it everything. Coral nose. "
        f"Fierce enthusiasm, never aggression. {FACE_BUDGET} {HOT5} {FACE_TAIL}",
    ),
    "f14-lowlid": (
        "cheerful lower lids",
        "Library cat mascot. EYES: two round ink eyes sitting on THICK CURVED LOWER "
        "LIDS that push up from beneath, the way eyes crinkle in a real smile, each "
        "with a cream catchlight. Coral nose, broad closed smile, blush on both "
        f"cheeks. Genuinely warm and beaming. {FACE_BUDGET} {HOT5} {FACE_TAIL}",
    ),
    "f15-starry": (
        "starry-eyed, blushing",
        "Library cat mascot. EYES: two big ink eyes almost entirely filled with bright "
        "cream STAR SHAPES, starry-eyed with admiration, plus small sparkle marks at "
        "the outer corners. Coral nose, small open awed mouth, strong coral blush on "
        f"both cheeks. Passionate and dazzled. {FACE_BUDGET} {HOT5} {FACE_TAIL}",
    ),
    "f16-quirk": (
        "mismatched eye sizes",
        "Library cat mascot. EYES: two ink eyes of DELIBERATELY DIFFERENT SIZES - one "
        "noticeably bigger and rounder than the other - each with a cream catchlight, "
        "under two brows set at different heights. Coral nose, lopsided open smile. "
        f"Quirky, alive, full of character. {FACE_BUDGET} {HOT5} {FACE_TAIL}",
    ),
    "f17-detail": (
        "maximum detail in the face only",
        "Library cat mascot where the FACE carries every small shape in the drawing: "
        "two large ink eyes with two catchlights each, bold upper lash lines, two "
        "arched eyebrows, a cream muzzle, a coral nose, a smiling mouth, and a blush "
        "patch on each cheek. The body beneath is ONE plain green mass and one tail, "
        f"totally featureless. Rich face, empty body. {HOT5} {FACE_TAIL}",
    ),
    "f18-portrait": (
        "head fills the frame, body a sliver",
        "Library cat mascot as a close PORTRAIT: the head is huge and fills most of "
        "the frame with two big bright ink eyes, catchlights, arched brows, a cream "
        "muzzle, coral nose and an open happy smile. Only a small sliver of plain "
        f"green body shows at the very bottom, with no detail in it at all. {HOT5} "
        f"{FACE_TAIL}",
    ),
    "f19-shout": (
        "eyes and mouth wide, cheering",
        "Library cat mascot CHEERING: eyes wide and bright with big catchlights, brows "
        "flung up high, ears straight up, mouth wide open in a shout of celebration "
        "with a coral tongue inside. Two small sparkle marks beside the head. Body is "
        f"one plain mass. Electric, passionate, triumphant. {FACE_BUDGET} {HOT5} "
        f"{FACE_TAIL}",
    ),
    "f20-freckle": (
        "blush and freckle dots",
        "Library cat mascot. FACE: two big round ink eyes with bright catchlights, a "
        "cream muzzle, a coral heart-shaped nose, a soft open smile, a coral blush "
        "patch on each cheek and three tiny freckle dots on each side. Body below is "
        f"one plain green mass with a single tail. Sweet, vivid and full of "
        f"personality. {HOT5} {FACE_TAIL}",
    ),
}


# ---------------------------------------------------------------- round 9
#
# Three notes from round 8, and they pull in the same direction:
#
#   * the colour read muted and the eyes read flat -- every eye was a plain ink
#     oval, so no image had any heat in it
#   * the shape budget was spread evenly over the whole animal; it should be
#     concentrated in the FACE, with the body carried by fewer, bolder shapes
#     (fewer, not cruder -- an under-drawn body is its own failure)
#   * round 8's prompts were over-specified. Naming a hex per body part and
#     enumerating shapes left the model nothing to invent, which is why twenty
#     prompts produced one pose twenty times. These are deliberately looser and
#     roughly half the length: a palette mood, a face direction, an emotion, and
#     room to move.
#
# So this round varies ONE thing: what the face is doing. The body brief is held
# constant and kept short on purpose.

HEAT = (
    "Punchy high-saturation palette, around five colours: electric jade green, "
    "deep emerald, warm cream, hot orange, inky near-black. The colour should feel "
    "energetic and alive - not dusty, not muted, not washed out, and not teal."
)

BODY = (
    "Put most of the drawing's detail into the FACE and keep the body to a few "
    "bold confident shapes - simplified, but still well drawn. Flat vector, solid "
    "fills, no outlines. Plain white background, no props, no text."
)

FACE: dict[str, tuple[str, str]] = {
    "f01-spark": (
        "wide sparkling eyes, pure joy",
        "A library cat mascot, beaming with joy. Big wide sparkling eyes full of "
        f"light, an open happy smile. {HEAT} {BODY}",
    ),
    "f02-fired": (
        "fired up, determined brows",
        "A library cat mascot, fired up and ready. Determined eyes under strong "
        f"angled brows, mouth set in a confident grin. {HEAT} {BODY}",
    ),
    "f03-crescent": (
        "happy squint, crescent eyes",
        "A library cat mascot, delighted. Its eyes are two upturned crescents from "
        f"smiling so hard, cheeks lifted, mouth wide open laughing. {HEAT} {BODY}",
    ),
    "f04-glossy": (
        "huge glossy eyes",
        "A library cat mascot with enormous glossy eyes that dominate its face, "
        f"catching the light, and a small soft smile below. {HEAT} {BODY}",
    ),
    "f05-wonder": (
        "starry-eyed wonder",
        "A library cat mascot struck with wonder, eyes shining wide and bright as if "
        f"it has just seen something amazing, mouth open in awe. {HEAT} {BODY}",
    ),
    "f06-smirk": (
        "mischievous, one brow up",
        "A library cat mascot being cheeky. One eyebrow raised, a knowing sideways "
        f"look, one corner of its mouth curled up in a smirk. {HEAT} {BODY}",
    ),
    "f07-proud": (
        "proud and pleased with itself",
        "A library cat mascot looking very pleased with itself, chest lifted, eyes "
        f"bright and half-closed with satisfaction, chin up. {HEAT} {BODY}",
    ),
    "f08-cosy": (
        "warm sleepy lids, still vivid",
        "A library cat mascot cosy and content, eyes soft half-moons of relaxed "
        f"lids, a small warm smile, blush on its cheeks. {HEAT} {BODY}",
    ),
    "f09-surprise": (
        "surprised, wide open",
        "A library cat mascot caught by surprise, eyes flung wide open with big round "
        f"pupils, small round open mouth, ears shot straight up. {HEAT} {BODY}",
    ),
    "f10-laugh": (
        "laughing, eyes screwed shut",
        "A library cat mascot laughing out loud, eyes screwed tightly shut, head "
        f"tipped back, mouth wide open. {HEAT} {BODY}",
    ),
    "f11-adore": (
        "adoring, melting with affection",
        "A library cat mascot melting with affection, eyes warm and adoring, a big "
        f"soft smile, cheeks flushed. {HEAT} {BODY}",
    ),
    "f12-curious": (
        "curious head tilt",
        "A library cat mascot tilting its head in curiosity, one ear cocked, eyes "
        f"big and questioning, mouth a small open circle. {HEAT} {BODY}",
    ),
    "f13-cheer": (
        "cheering, paws up",
        "A library cat mascot cheering, both front paws thrown up in celebration, "
        f"eyes bright and gleeful, mouth open in a shout of delight. {HEAT} {BODY}",
    ),
    "f14-hero": (
        "bold and heroic",
        "A library cat mascot standing bold and heroic, sharp confident eyes looking "
        f"straight at you, a fearless little grin. {HEAT} {BODY}",
    ),
    "f15-focus": (
        "absorbed, locked in",
        "A library cat mascot completely absorbed, eyes narrowed in concentration and "
        f"fixed on something just out of frame, mouth a small serious line. {HEAT} "
        f"{BODY}",
    ),
    "f16-wink": (
        "playful wink",
        "A library cat mascot winking playfully, one eye shut tight and the other "
        f"wide and bright, a lopsided grin. {HEAT} {BODY}",
    ),
    "f17-greet": (
        "beaming hello",
        "A library cat mascot beaming a big friendly hello, eyes crinkled with "
        f"warmth, one paw raised in a wave. {HEAT} {BODY}",
    ),
    "f18-scrappy": (
        "scrappy little attitude",
        "A library cat mascot with attitude, eyes narrowed and cocky, one brow up, a "
        f"crooked confident smile, tail flicking. {HEAT} {BODY}",
    ),
    "f19-dreamy": (
        "dreamy, gazing up",
        "A library cat mascot gazing dreamily upward, eyes soft and shining, a faint "
        f"wistful smile. {HEAT} {BODY}",
    ),
    "f20-gasp": (
        "can't believe it",
        "A library cat mascot that cannot believe its luck, eyes enormous and "
        f"glittering, both paws pressed to its cheeks, mouth open in a gasp. {HEAT} "
        f"{BODY}",
    ),
}


# Round 10. The user supplied the spine of this prompt verbatim and asked for it
# to be filled in 20 ways, so STORY_TAIL is reproduced word for word and only the
# character slot and the mini-story vary. Two carry-overs from round 9 are folded
# into the character slot rather than bolted on as extra clauses: the orange is
# named as nose-and-paw-pads so it stops growing into ginger fur, and the green is
# named as the dominant so the near-black stops taking over. Nothing else is
# specified -- round 9 established that tighter prompts collapse the 20 into one.
STORY_TAIL = (
    "flat vector illustration, bold rounded shapes, oversized head and expressive "
    "oversized eyes, tiny simplified limbs, flat solid saturated fills, no "
    "outlines, caricatured proportions, one clear silhouette, centered on pure "
    "white background, generous negative space, playful and funny, mobile app icon "
    "art, 2D vector, no shading, no gradients"
)

WHO = (
    "round jade-green library cat, cream belly, hot orange nose and paw pads, "
    "inky eyes, green reading as the dominant colour"
)

STORY: dict[str, tuple[str, str]] = {
    "s01-leap": (
        "mid-air triumphant leap",
        f"A {WHO}, launching itself into a triumphant mid-air leap with all four "
        f"paws flung wide, {STORY_TAIL}",
    ),
    "s02-flop": (
        "belly-up, dead asleep",
        f"A chubby {WHO}, flopped over belly-up and utterly asleep with its limbs "
        f"sticking straight up, {STORY_TAIL}",
    ),
    "s03-stretch": (
        "absurdly long stretch",
        f"A {WHO}, caught mid-stretch with its back arched into an absurdly long "
        f"curve, {STORY_TAIL}",
    ),
    "s04-yawn": (
        "enormous yawn",
        f"A sleepy {WHO}, in the middle of a yawn so enormous its whole head tips "
        f"back, {STORY_TAIL}",
    ),
    "s05-peek": (
        "peeking round a corner",
        f"A shy {WHO}, peeking around an unseen corner with only half of itself "
        f"committed to being visible, {STORY_TAIL}",
    ),
    "s06-startle": (
        "bolt upright, startled",
        f"A {WHO}, sitting bolt upright and startled, ears flared and fur spiked in "
        f"surprise, {STORY_TAIL}",
    ),
    "s07-sneak": (
        "exaggerated tiptoe",
        f"A mischievous {WHO}, tiptoeing along in slow motion with one paw held "
        f"comically high, {STORY_TAIL}",
    ),
    "s08-smug": (
        "arms folded, smug",
        f"A smug little {WHO}, arms folded and one eyebrow raised as if it knew "
        f"something you don't, {STORY_TAIL}",
    ),
    "s09-tailhug": (
        "hugging its own tail",
        f"A bashful {WHO}, hugging its own enormous fluffy tail to its chest, "
        f"{STORY_TAIL}",
    ),
    "s10-dance": (
        "tiny victory dance",
        f"A {WHO}, doing a tiny victory dance with both paws thrown up and one foot "
        f"kicked out, {STORY_TAIL}",
    ),
    "s11-sneeze": (
        "mid-sneeze",
        f"A {WHO}, mid-sneeze with its eyes squeezed shut and its whole body "
        f"recoiling, {STORY_TAIL}",
    ),
    "s12-loaf": (
        "perfect contented loaf",
        f"A perfectly contented {WHO}, sitting folded into a neat loaf shape with "
        f"its paws tucked out of sight, {STORY_TAIL}",
    ),
    "s13-topple": (
        "rolling off balance",
        f"A clumsy {WHO}, toppling sideways mid-roll with its legs flailing, "
        f"{STORY_TAIL}",
    ),
    "s14-wave": (
        "over-enthusiastic wave",
        f"A friendly {WHO}, waving hello so enthusiastically that it is leaning off "
        f"balance, {STORY_TAIL}",
    ),
    "s15-present": (
        "presenting with a flourish",
        f"A theatrical {WHO}, presenting something invisible with a grand sweeping "
        f"flourish of one paw, {STORY_TAIL}",
    ),
    "s16-tipping": (
        "dozing upright, tipping over",
        f"A drowsy {WHO}, dozing off while sitting upright and slowly tipping to one "
        f"side, {STORY_TAIL}",
    ),
    "s17-pounce": (
        "crouched to pounce",
        f"A {WHO}, flattened low to the ground and wiggling, an instant away from "
        f"pouncing, {STORY_TAIL}",
    ),
    "s18-curious": (
        "craning up, curious",
        f"A curious {WHO}, craning its neck up impossibly far to get a better look at "
        f"something above it, {STORY_TAIL}",
    ),
    "s19-spin": (
        "chasing its own tail",
        f"A giddy {WHO}, spinning in a circle chasing its own tail, {STORY_TAIL}",
    ),
    "s20-drape": (
        "draped over an edge, limbs dangling",
        f"A boneless {WHO}, draped over an invisible ledge with all four limbs "
        f"dangling down, {STORY_TAIL}",
    ),
}


# Round 11. Two changes from round 10. First, the brand green is parked: the user
# asked for light grey plus whatever accents read naturally, and a grey cat is the
# most natural cat there is, so the accent is a single warm apricot. Second, the
# word "library" is gone -- in round 10 it summoned books, mortarboards and
# reading glasses entirely on its own, in a round that asked for no props.
#
# The style notes here are lifted from the Duolingo reference the user supplied,
# but *described in words*, never passed as a seed image: the /edits route copies
# the seed's geometry, and shipping a derivative of a trademarked mascot in an App
# Store app is a real exposure. See the round-1 owl note above.
#
# This table varies the CHARACTER STYLE and holds the pose constant -- the inverse
# of round 10. Every entry is the same neutral forward-facing sit, so the 20 are
# directly comparable on shape language, proportion and eye construction alone.
GREY = (
    "Soft light warm grey body, one slightly darker grey used sparingly for the "
    "ears and tail, off-white belly and eye whites, charcoal for the eyes, and a "
    "single warm apricot orange for the nose and paw pads. Around five colours, "
    "every one a flat solid fill."
)

LOOK_TAIL = (
    "flat vector illustration, bold rounded shapes, oversized head and expressive "
    "oversized eyes, tiny simplified limbs, flat solid fills, no outlines, "
    "caricatured proportions, one clear silhouette, centered on pure white "
    "background, generous negative space, playful and friendly, mobile app icon "
    "art, 2D vector, no shading, no gradients, no books, no hats, no clothing, "
    "no accessories, no text"
)

SIT = "sitting calmly facing forward, relaxed and friendly"

LOOK: dict[str, tuple[str, str]] = {
    "L01-twotone": (
        "two tones of one hue only",
        f"A cat mascot {SIT}, drawn in only two tones of the same grey so the ears "
        f"and tail separate from the body by tone alone, huge rounded-rectangle "
        f"white eyes with dark charcoal pupils, one small orange nose. {GREY} "
        f"{LOOK_TAIL}",
    ),
    "L02-circles": (
        "built entirely from circles",
        f"A cat mascot {SIT}, its whole body built from overlapping perfect circles "
        f"of different sizes, nothing angular anywhere. {GREY} {LOOK_TAIL}",
    ),
    "L03-blocky": (
        "square blocky build",
        f"A cat mascot {SIT}, with a squarish block of a body and a broad square "
        f"head, corners softly rounded. {GREY} {LOOK_TAIL}",
    ),
    "L04-teardrop": (
        "one teardrop mass",
        f"A cat mascot {SIT}, its head and body a single smooth teardrop mass that "
        f"tapers to a narrow base. {GREY} {LOOK_TAIL}",
    ),
    "L05-bighead": (
        "head three times the body",
        f"A cat mascot {SIT}, with an enormous head roughly three times the size of "
        f"its tiny tucked body. {GREY} {LOOK_TAIL}",
    ),
    "L06-bean": (
        "soft bean silhouette",
        f"A cat mascot {SIT}, shaped like a soft leaning bean with no visible neck "
        f"or waist. {GREY} {LOOK_TAIL}",
    ),
    "L07-dots": (
        "eyes as solid dots",
        f"A cat mascot {SIT}, its eyes just two solid charcoal dots with no whites "
        f"at all, the whole expression carried by placement and a small mouth. "
        f"{GREY} {LOOK_TAIL}",
    ),
    "L08-eyesdom": (
        "eyes dominate the face",
        f"A cat mascot {SIT}, with eyes so large the white shapes take up most of "
        f"the face and everything else is squeezed to the edges. {GREY} "
        f"{LOOK_TAIL}",
    ),
    "L09-halflid": (
        "heavy half-closed lids",
        f"A cat mascot {SIT}, eyes half closed under heavy relaxed lids, looking "
        f"utterly content. {GREY} {LOOK_TAIL}",
    ),
    "L10-sideglance": (
        "pupils pushed to one side",
        f"A cat mascot {SIT}, both pupils pushed right over to one side of the eye "
        f"whites in a curious sideways glance. {GREY} {LOOK_TAIL}",
    ),
    "L11-nolimbs": (
        "no limbs at all",
        f"A cat mascot {SIT}, with no visible legs or arms whatsoever, just one "
        f"rounded mass with ears and a tail. {GREY} {LOOK_TAIL}",
    ),
    "L12-mittens": (
        "thick mitten paws",
        f"A cat mascot {SIT}, with thick soft oversized mitten paws and stubby "
        f"limbs. {GREY} {LOOK_TAIL}",
    ),
    "L13-tufts": (
        "sharp tufted ears",
        f"A cat mascot {SIT}, its silhouette broken by two sharply pointed tufted "
        f"ears against an otherwise entirely round body. {GREY} {LOOK_TAIL}",
    ),
    "L14-toneline": (
        "mouth as a tone-on-tone line",
        f"A cat mascot {SIT}, its smile and cheeks drawn only as a slightly darker "
        f"grey line on the grey face rather than a separate colour. {GREY} "
        f"{LOOK_TAIL}",
    ),
    "L15-blush": (
        "apricot cheek patches",
        f"A cat mascot {SIT}, with two soft apricot cheek patches as the warmest "
        f"note in the drawing. {GREY} {LOOK_TAIL}",
    ),
    "L16-muzzle": (
        "separate off-white muzzle",
        f"A cat mascot {SIT}, with a large off-white muzzle shape covering the "
        f"lower half of the face like a mask. {GREY} {LOOK_TAIL}",
    ),
    "L17-asym": (
        "one asymmetric detail",
        f"A cat mascot {SIT}, perfectly symmetrical except for one bent ear that "
        f"gives the whole character its personality. {GREY} {LOOK_TAIL}",
    ),
    "L18-lowset": (
        "eyes set very low and wide",
        f"A cat mascot {SIT}, its eyes set very low and very far apart, leaving a "
        f"tall open forehead above them. {GREY} {LOOK_TAIL}",
    ),
    "L19-tailwrap": (
        "tail wrapping the body",
        f"A cat mascot {SIT}, its thick tail curling all the way around the front of "
        f"its body as the main graphic element. {GREY} {LOOK_TAIL}",
    ),
    "L20-fiveshape": (
        "five shapes total",
        f"A cat mascot {SIT}, reduced to about five shapes in total and nothing "
        f"more, radically simple but still warm. {GREY} {LOOK_TAIL}",
    ),
}


# Round 12. The identity round. IDENT is held verbatim across all 20 and the only
# thing that varies is how hard the body gets deformed -- including the
# destructive states from Duolingo's streak widget matrix (puddle, stone, ghost),
# because that matrix is the proof of the whole idea: the body geometry is
# disposable if the marks survive. If a melted puddle still reads as our cat, the
# marks are load-bearing. If it doesn't, they're decoration and the spec is wrong.
#
# Spec lives in docs/mockups/mascot/CHARACTER.md -- keep the two in step.
IDENT = (
    "Always the same character: head and body are ONE rounded mass whose top edge "
    "rises into two soft ear peaks in a single unbroken curve, never two separate "
    "triangle ears. A large off-white mask surrounds both eyes and joins across "
    "the bridge, like goggles. Eyes are tall rounded-rectangle whites with "
    "charcoal pupils and one small catchlight at each pupil's top left. One small "
    "warm apricot nose sits in the dip where the mask meets. Three short stacked "
    "lines on the chest, like the page edges of a book. The mouth is only a "
    "slightly darker line on the body colour. Paws float detached from the body."
)

IDENT_TAIL = (
    "Light warm grey body in two tones, the darker tone on ears and tail, "
    "off-white mask and belly, charcoal eyes, apricot nose and paw pads only. "
    "Flat vector illustration, bold rounded shapes, oversized head, flat solid "
    "fills, no outlines, one clear silhouette, centered on pure white background, "
    "generous negative space, mobile app icon art, 2D vector, no shading, no "
    "gradients, no props, no clothing, no text"
)

IDENTITY: dict[str, tuple[str, str]] = {
    "i01-neutral": (
        "baseline: neutral sit",
        f"A cat mascot sitting calmly facing forward. {IDENT} {IDENT_TAIL}",
    ),
    "i02-squat": (
        "squashed extremely wide",
        f"A cat mascot squashed extremely wide and low, twice as wide as it is "
        f"tall. {IDENT} {IDENT_TAIL}",
    ),
    "i03-tall": (
        "stretched extremely tall",
        f"A cat mascot stretched absurdly tall and narrow like a column. {IDENT} "
        f"{IDENT_TAIL}",
    ),
    "i04-puddle": (
        "melted into a puddle",
        f"A cat mascot melted into a soft puddle spreading across the floor, its "
        f"body no longer holding any shape at all. {IDENT} {IDENT_TAIL}",
    ),
    "i05-leap": (
        "mid-air leap, paws flung",
        f"A cat mascot leaping joyfully through the air with its paws flung wide. "
        f"{IDENT} {IDENT_TAIL}",
    ),
    "i06-curled": (
        "curled into a tight spiral asleep",
        f"A cat mascot curled into a tight spiral, fast asleep, its tail wrapped "
        f"right around itself. {IDENT} {IDENT_TAIL}",
    ),
    "i07-stone": (
        "carved from stone",
        f"A cat mascot as a weathered grey stone statue, chipped and ancient, still "
        f"the same character underneath. {IDENT} {IDENT_TAIL}",
    ),
    "i08-ghost": (
        "a floating ghost with a wavy hem",
        f"A cat mascot as a pale floating ghost with a soft wavy hem instead of "
        f"legs. {IDENT} {IDENT_TAIL}",
    ),
    "i09-peek": (
        "only the top half visible",
        f"A cat mascot with only the top half of its head visible, peering up over "
        f"a low edge. {IDENT} {IDENT_TAIL}",
    ),
    "i10-back": (
        "seen from behind, glancing back",
        f"A cat mascot seen from behind, twisting to glance back over its shoulder. "
        f"{IDENT} {IDENT_TAIL}",
    ),
    "i11-loaf": (
        "folded into a neat loaf",
        f"A cat mascot folded into a neat loaf with every paw tucked out of sight. "
        f"{IDENT} {IDENT_TAIL}",
    ),
    "i12-stretch": (
        "long waking stretch",
        f"A cat mascot in a long luxurious waking stretch, back arched deeply. "
        f"{IDENT} {IDENT_TAIL}",
    ),
    "i13-cheer": (
        "both paws thrown up cheering",
        f"A cat mascot throwing both paws up in the air to cheer, mouth wide with "
        f"delight. {IDENT} {IDENT_TAIL}",
    ),
    "i14-tiny": (
        "shrunk to a tiny ball",
        f"A cat mascot shrunk into a tiny round ball, almost all head. {IDENT} "
        f"{IDENT_TAIL}",
    ),
    "i15-yawn": (
        "enormous yawn, head tipped back",
        f"A cat mascot mid-yawn so enormous its whole head tips backwards. {IDENT} "
        f"{IDENT_TAIL}",
    ),
    "i16-float": (
        "drifting asleep in mid-air",
        f"A cat mascot drifting weightlessly asleep in mid-air, limbs hanging "
        f"loose. {IDENT} {IDENT_TAIL}",
    ),
    "i17-profile": (
        "strict side profile",
        f"A cat mascot in strict side profile, sitting upright, facing left. "
        f"{IDENT} {IDENT_TAIL}",
    ),
    "i18-flat": (
        "flattened face down",
        f"A cat mascot flattened face down on the floor like a pancake, thoroughly "
        f"defeated. {IDENT} {IDENT_TAIL}",
    ),
    "i19-sneak": (
        "creeping low on tiptoe",
        f"A cat mascot creeping low along the ground on exaggerated tiptoe. "
        f"{IDENT} {IDENT_TAIL}",
    ),
    "i20-upsidedown": (
        "hanging upside down",
        f"A cat mascot hanging completely upside down from above, ears dangling. "
        f"{IDENT} {IDENT_TAIL}",
    ),
}


# Round 13. Round 12 proved the *mechanism* -- hold a few marks constant and the
# body can be destroyed without losing the character -- but the mark it used was
# an eye mask, which is an OWL solution: owls have a facial disc, so Duo's mask is
# just anatomy turned into a logo. A cat needs a cat answer, so this round
# auditions candidate marks one at a time.
#
# Everything except the candidate is held flat and neutral, and the mask is
# explicitly negated, so each mark is judged alone rather than on top of the
# device it is meant to replace. Nothing here is a full identity yet -- the
# winner (or two) gets built out into one in the next round.
NEUT = (
    "A cat mascot sitting calmly facing forward, head and body one rounded mass "
    "with an oversized head, tiny paws floating detached from the body, tall white "
    "eyes with charcoal pupils, a small apricot nose, and a mouth drawn only as a "
    "slightly darker line."
)

NEUT_TAIL = (
    "Light warm grey body in two tones, the darker tone on ears and tail, "
    "off-white belly, charcoal eyes, apricot only on the nose and paw pads. Flat "
    "vector illustration, bold rounded shapes, flat solid fills, no outlines, one "
    "clear silhouette, centered on pure white background, generous negative "
    "space, mobile app icon art, 2D vector, no shading, no gradients. No mask or "
    "patch around the eyes, no props, no clothing, no text."
)

MARKS: dict[str, tuple[str, str]] = {
    "c01-slit": (
        "vertical slit pupils",
        f"{NEUT} Its defining feature: narrow vertical slit pupils, unmistakably "
        f"feline. {NEUT_TAIL}",
    ),
    "c02-dilated": (
        "hugely dilated round pupils",
        f"{NEUT} Its defining feature: enormously dilated pitch-black round pupils "
        f"that fill almost the whole eye. {NEUT_TAIL}",
    ),
    "c03-m": (
        "tabby M on the forehead",
        f"{NEUT} Its defining feature: a bold darker tabby M marking across its "
        f"forehead between the ears. {NEUT_TAIL}",
    ),
    "c04-dots": (
        "whisker-pad dots",
        f"{NEUT} Its defining feature: two round raised whisker pads under the nose, "
        f"each stamped with three clear dots. {NEUT_TAIL}",
    ),
    "c05-philtrum": (
        "triangle nose with a Y line",
        f"{NEUT} Its defining feature: a crisp apricot triangle nose with a short "
        f"Y-shaped line dropping from it into the mouth. {NEUT_TAIL}",
    ),
    "c06-innerear": (
        "apricot inner ears",
        f"{NEUT} Its defining feature: bright apricot triangles filling the inside "
        f"of both ears, the warmest note in the drawing. {NEUT_TAIL}",
    ),
    "c07-dogear": (
        "one ear folded like a page corner",
        f"{NEUT} Its defining feature: the tip of one ear is folded over in a neat "
        f"triangle, exactly like the dog-eared corner of a book page. {NEUT_TAIL}",
    ),
    "c08-notch": (
        "one notched ear",
        f"{NEUT} Its defining feature: a small V notch bitten out of the edge of "
        f"one ear, like a scrappy old street cat. {NEUT_TAIL}",
    ),
    "c09-tuxedo": (
        "tuxedo blaze and mismatched socks",
        f"{NEUT} Its defining feature: tuxedo markings, a crisp off-white bib and "
        f"blaze with mismatched white socks on the paws. {NEUT_TAIL}",
    ),
    "c10-ruff": (
        "huge flaring cheek ruff",
        f"{NEUT} Its defining feature: enormous fluffy cheek ruffs flaring out much "
        f"wider than its head. {NEUT_TAIL}",
    ),
    "c11-almond": (
        "upturned almond eyes",
        f"{NEUT} Its defining feature: almond-shaped eyes tilted sharply up at the "
        f"outer corners. {NEUT_TAIL}",
    ),
    "c12-tailhook": (
        "upright tail with a hooked tip",
        f"{NEUT} Its defining feature: a thick tail held bolt upright with a crisp "
        f"hook at the very tip, like a question mark. {NEUT_TAIL}",
    ),
    "c13-tailrings": (
        "three rings on the tail",
        f"{NEUT} Its defining feature: exactly three darker rings banding the end of "
        f"its thick tail. {NEUT_TAIL}",
    ),
    "c14-loaf": (
        "default form is a perfect loaf",
        f"A cat mascot folded into a perfect symmetrical loaf, paws completely "
        f"hidden, a smooth unbroken dome with two ears on top. Oversized head, tall "
        f"white eyes with charcoal pupils, a small apricot nose, mouth only a "
        f"darker line. {NEUT_TAIL}",
    ),
    "c15-browdots": (
        "two dots above the eyes",
        f"{NEUT} Its defining feature: two small darker dots sitting high above the "
        f"eyes like permanently raised eyebrows. {NEUT_TAIL}",
    ),
    "c16-bigears": (
        "oversized satellite ears",
        f"{NEUT} Its defining feature: absurdly oversized ears, each nearly as big "
        f"as its head. {NEUT_TAIL}",
    ),
    "c17-stripes": (
        "exactly three back stripes",
        f"{NEUT} Its defining feature: exactly three bold darker stripes running "
        f"across its back. {NEUT_TAIL}",
    ),
    "c18-blaze": (
        "white blaze up the nose",
        f"{NEUT} Its defining feature: a clean off-white blaze running straight up "
        f"the bridge of its nose and splitting its forehead. {NEUT_TAIL}",
    ),
    "c19-heartnose": (
        "heart-shaped nose",
        f"{NEUT} Its defining feature: an unmistakable apricot heart-shaped nose, "
        f"large and centred. {NEUT_TAIL}",
    ),
    "c20-onesock": (
        "a single odd white paw",
        f"{NEUT} Its defining feature: three grey paws and one bright off-white "
        f"paw, a single odd sock. {NEUT_TAIL}",
    ),
}


# Round 14. More candidate marks. Round 13's dogear, heartnose and stripes were
# rejected for not being feline enough -- a folded page corner is a book idea, a
# heart nose is a Valentine idea and stripes read as knitwear. So this round is
# restricted to things that are actually cat: real breed traits (Scottish Fold
# ears, American Curl ears, lynx tufts, Siamese points, blotched tabby swirl,
# rosettes), real cat anatomy (kohl eye rims, whisker pads, crown stripes) and
# real cat behaviour (independent ear swivel, tail wrapped over the front paws,
# the happy crescent squint).
#
# Same neutral base as round 13 so the two sheets are directly comparable.
MARKS2: dict[str, tuple[str, str]] = {
    "c21-eyeliner": (
        "kohl eye rims",
        f"{NEUT} Its defining feature: dark charcoal eyeliner rimming each eye and "
        f"tapering back toward the ears, like an Egyptian Mau. {NEUT_TAIL}",
    ),
    "c22-fold": (
        "Scottish Fold ears folded flat",
        f"{NEUT} Its defining feature: Scottish Fold ears folded completely flat "
        f"down against its head, so the head is a smooth round dome with no ear "
        f"peaks at all. {NEUT_TAIL}",
    ),
    "c23-lynx": (
        "lynx tufts on the ear tips",
        f"{NEUT} Its defining feature: sharp lynx tufts spiking up from the tip of "
        f"each ear. {NEUT_TAIL}",
    ),
    "c24-curl": (
        "American Curl ears curling back",
        f"{NEUT} Its defining feature: American Curl ears that curl backwards away "
        f"from its face in a smooth arc. {NEUT_TAIL}",
    ),
    "c25-points": (
        "Siamese colourpoint",
        f"{NEUT} Its defining feature: Siamese colourpoint markings, a pale body "
        f"with distinctly darker ears, muzzle, paws and tail. {NEUT_TAIL}",
    ),
    "c26-dippedtail": (
        "tail tip dipped in colour",
        f"{NEUT} Its defining feature: the last third of its tail is a completely "
        f"different pale colour, as though dipped in paint. {NEUT_TAIL}",
    ),
    "c27-swirl": (
        "blotched tabby bullseye swirl",
        f"{NEUT} Its defining feature: one bold blotched tabby swirl spiralling on "
        f"its side like a bullseye. {NEUT_TAIL}",
    ),
    "c28-spots": (
        "spotted rosettes",
        f"{NEUT} Its defining feature: a scatter of soft darker rosette spots across "
        f"its back and flanks. {NEUT_TAIL}",
    ),
    "c29-crown": (
        "crown stripes fanning back",
        f"{NEUT} Its defining feature: a neat fan of short darker stripes over the "
        f"crown of its head between the ears. {NEUT_TAIL}",
    ),
    "c30-whiskerarcs": (
        "whiskers as bold tapered shapes",
        f"{NEUT} Its defining feature: three bold tapered whisker shapes sweeping "
        f"from each cheek, drawn as solid forms rather than thin lines. "
        f"{NEUT_TAIL}",
    ),
    "c31-muzzle": (
        "two round whisker-pad mounds",
        f"{NEUT} Its defining feature: two large round whisker-pad mounds bulging "
        f"out either side of a tiny nose, giving it a proper cat muzzle. "
        f"{NEUT_TAIL}",
    ),
    "c32-crescent": (
        "crescent happy squint",
        f"{NEUT} Its defining feature: eyes permanently closed into two upward "
        f"crescents, the contented cat squint. {NEUT_TAIL}",
    ),
    "c33-snaggle": (
        "one tiny fang",
        f"{NEUT} Its defining feature: one tiny pointed fang poking out over its "
        f"lip. {NEUT_TAIL}",
    ),
    "c34-earswivel": (
        "one ear swivelled independently",
        f"{NEUT} Its defining feature: one ear swivelled right round to the side "
        f"while the other points forward, listening to two things at once. "
        f"{NEUT_TAIL}",
    ),
    "c35-tailwrap": (
        "tail wrapped over the front paws",
        f"{NEUT} Its defining feature: its thick tail curled neatly around the "
        f"front of its body and laid over its front paws, the classic cat sit. "
        f"{NEUT_TAIL}",
    ),
    "c36-noodle": (
        "liquid noodle proportions",
        f"A cat mascot poured into a long soft noodle of a body, boneless and "
        f"liquid, oversized head, tiny floating paws, tall white eyes with charcoal "
        f"pupils, small apricot nose, mouth only a darker line. {NEUT_TAIL}",
    ),
    "c37-chinpatch": (
        "white chin and chest patch",
        f"{NEUT} Its defining feature: a crisp off-white patch covering its chin and "
        f"running down its chest in one shape. {NEUT_TAIL}",
    ),
    "c38-freckles": (
        "freckles across the nose bridge",
        f"{NEUT} Its defining feature: a scatter of small apricot freckles across "
        f"the bridge of its nose and cheeks. {NEUT_TAIL}",
    ),
    "c39-plume": (
        "enormous plume tail held up",
        f"{NEUT} Its defining feature: an enormous soft plume of a tail held "
        f"straight up like a flag, wider than its body. {NEUT_TAIL}",
    ),
    "c40-handsy": (
        "front paws tucked together",
        f"{NEUT} Its defining feature: both front paws tucked neatly together under "
        f"its chin like little folded hands. {NEUT_TAIL}",
    ),
}


# Round 15. The user picked c06 (apricot inner ears), c29 (crown stripes) and c30
# (whisker arcs) and called out swirl, muzzle and noodle as ugly. The common
# thread in the three winners is fine tidy detail on the HEAD with the body left
# clean -- and the common thread in the three rejects is a big graphic form
# imposed on the body. Note that c30 survived despite being the thin-line whisker
# treatment that earlier rounds banned, so the ban was about crudeness, not about
# whiskers.
#
# So: fifteen more in that same delicate family, plus five straight COMBINATIONS
# of the three winners, since the next decision is how many of them to run at
# once rather than which single one wins.
FINE: dict[str, tuple[str, str]] = {
    "d01-browwhisk": (
        "brow whiskers above the eyes",
        f"{NEUT} Its defining feature: a few fine long brow whiskers arching up from "
        f"above each eye. {NEUT_TAIL}",
    ),
    "d02-earrim": (
        "darker rim tracing the ears",
        f"{NEUT} Its defining feature: a fine darker rim tracing the outer edge of "
        f"each ear. {NEUT_TAIL}",
    ),
    "d03-furnish": (
        "pale fur furnishings inside the ears",
        f"{NEUT} Its defining feature: soft pale fur furnishings peeking out from "
        f"inside each ear. {NEUT_TAIL}",
    ),
    "d04-eartip": (
        "ear tips dipped darker",
        f"{NEUT} Its defining feature: just the very tips of its ears dipped in a "
        f"darker tone. {NEUT_TAIL}",
    ),
    "d05-chevron": (
        "single fine chevron on the forehead",
        f"{NEUT} Its defining feature: one fine darker chevron pointing forward on "
        f"its forehead. {NEUT_TAIL}",
    ),
    "d06-pinstripe": (
        "many fine crown pinstripes",
        f"{NEUT} Its defining feature: a delicate fan of very fine darker pinstripes "
        f"across the crown of its head. {NEUT_TAIL}",
    ),
    "d07-diamond": (
        "small forehead diamond",
        f"{NEUT} Its defining feature: one small neat darker diamond centred on its "
        f"forehead. {NEUT_TAIL}",
    ),
    "d08-spine": (
        "fine line down the spine",
        f"{NEUT} Its defining feature: a single fine darker line running down its "
        f"spine. {NEUT_TAIL}",
    ),
    "d09-cheekarcs": (
        "fine arcs on the cheeks",
        f"{NEUT} Its defining feature: two fine curved lines sweeping back across "
        f"each cheek. {NEUT_TAIL}",
    ),
    "d10-eyetick": (
        "fine tick at the outer eye corner",
        f"{NEUT} Its defining feature: one fine short line at the outer corner of "
        f"each eye, tapering back. {NEUT_TAIL}",
    ),
    "d11-lashes": (
        "three tiny lashes per eye",
        f"{NEUT} Its defining feature: three tiny lashes at the outer corner of each "
        f"eye. {NEUT_TAIL}",
    ),
    "d12-points": (
        "apricot tri-point accent system",
        f"{NEUT} Its defining feature: apricot appears in exactly three places and "
        f"nowhere else - the nose, the inside of both ears, and the very tip of the "
        f"tail. {NEUT_TAIL}",
    ),
    "d13-tailtip": (
        "apricot tail tip alone",
        f"{NEUT} Its defining feature: the very tip of its tail is apricot, as if "
        f"dipped. {NEUT_TAIL}",
    ),
    "d14-ruffline": (
        "fine ruff line at the neck",
        f"{NEUT} Its defining feature: one fine soft ruff line encircling its neck "
        f"where the head meets the body. {NEUT_TAIL}",
    ),
    "d15-longwhisk": (
        "very long sweeping whiskers",
        f"{NEUT} Its defining feature: extremely long fine whiskers sweeping out "
        f"well past the width of its body. {NEUT_TAIL}",
    ),
    # The five combinations. c06 + c29 + c30, taken two and three at a time.
    "d16-ear-crown": (
        "combo: inner ears + crown stripes",
        f"{NEUT} Its defining features, both together: bright apricot triangles "
        f"inside both ears, and a neat fan of fine darker stripes across the crown "
        f"of its head. {NEUT_TAIL}",
    ),
    "d17-ear-whisk": (
        "combo: inner ears + whiskers",
        f"{NEUT} Its defining features, both together: bright apricot triangles "
        f"inside both ears, and three fine tapered whiskers sweeping from each "
        f"cheek. {NEUT_TAIL}",
    ),
    "d18-crown-whisk": (
        "combo: crown stripes + whiskers",
        f"{NEUT} Its defining features, both together: a neat fan of fine darker "
        f"stripes across the crown of its head, and three fine tapered whiskers "
        f"sweeping from each cheek. {NEUT_TAIL}",
    ),
    "d19-all-three": (
        "combo: all three",
        f"{NEUT} Its defining features, all three together: bright apricot triangles "
        f"inside both ears, a neat fan of fine darker stripes across the crown of "
        f"its head, and three fine tapered whiskers sweeping from each cheek. "
        f"{NEUT_TAIL}",
    ),
    "d20-all-three-tail": (
        "combo: all three + apricot tail tip",
        f"{NEUT} Its defining features, all together: bright apricot triangles "
        f"inside both ears, a neat fan of fine darker stripes across the crown, "
        f"three fine tapered whiskers per cheek, and an apricot tail tip. "
        f"{NEUT_TAIL}",
    ),
}


# Round 16. Two specific asks: mix d12 (apricot restricted to nose, inner ears and
# tail tip) with d15 (very long sweeping whiskers), and redo d18's crown fan with
# three lines rather than five -- d20 showed the fan going helmet-like when it got
# dense, so the count matters. Both constants are pulled out so the mixes stay
# identical apart from the axis being tested, and the crown count is swept 2/3/4
# to make the choice visible rather than asserted.
TRIPOINT = (
    "Apricot appears in exactly three places and nowhere else: the nose, the inside "
    "of both ears, and the very tip of the tail."
)

LONGWHISK = (
    "Extremely long fine whiskers sweeping out well past the width of its body."
)

MIX: dict[str, tuple[str, str]] = {
    "e01-mix": (
        "tri-point + long whiskers",
        f"{NEUT} Its defining features: {TRIPOINT} {LONGWHISK} {NEUT_TAIL}",
    ),
    "e02-mix-crown3": (
        "tri-point + long whiskers + 3 crown lines",
        f"{NEUT} Its defining features: {TRIPOINT} {LONGWHISK} Exactly three fine "
        f"darker lines across the crown of its head, no more. {NEUT_TAIL}",
    ),
    "e03-crown3": (
        "3 crown lines + whiskers, no tri-point",
        f"{NEUT} Its defining features: exactly three fine darker lines across the "
        f"crown of its head, no more, and three fine tapered whiskers sweeping from "
        f"each cheek. {NEUT_TAIL}",
    ),
    "e04-crown2": (
        "only 2 crown lines",
        f"{NEUT} Its defining features: exactly two fine darker lines across the "
        f"crown of its head, and long fine whiskers. {NEUT_TAIL}",
    ),
    "e05-crown4": (
        "4 crown lines",
        f"{NEUT} Its defining features: exactly four fine darker lines across the "
        f"crown of its head, and long fine whiskers. {NEUT_TAIL}",
    ),
    "e06-crown3-short": (
        "3 short crown ticks",
        f"{NEUT} Its defining features: three very short darker ticks high on its "
        f"forehead, and long fine whiskers. {TRIPOINT} {NEUT_TAIL}",
    ),
    "e07-crown3-thick": (
        "3 bold thick crown strokes",
        f"{NEUT} Its defining features: three bold thick darker strokes across its "
        f"forehead, and long fine whiskers. {TRIPOINT} {NEUT_TAIL}",
    ),
    "e08-crown3-curved": (
        "3 curved crown lines",
        f"{NEUT} Its defining features: three gently curved darker lines fanning "
        f"across its forehead, and long fine whiskers. {TRIPOINT} {NEUT_TAIL}",
    ),
    "e09-whisk2": (
        "tri-point + two long whiskers per side",
        f"{NEUT} Its defining features: {TRIPOINT} Just two very long fine whiskers "
        f"sweeping from each cheek. {NEUT_TAIL}",
    ),
    "e10-whisk4": (
        "tri-point + four long whiskers per side",
        f"{NEUT} Its defining features: {TRIPOINT} Four very long fine whiskers "
        f"sweeping from each cheek. {NEUT_TAIL}",
    ),
    "e11-droop": (
        "whiskers drooping down",
        f"{NEUT} Its defining features: {TRIPOINT} Long fine whiskers drooping "
        f"downward and outward. {NEUT_TAIL}",
    ),
    "e12-up": (
        "whiskers swept upward",
        f"{NEUT} Its defining features: {TRIPOINT} Long fine whiskers swept "
        f"confidently upward and outward. {NEUT_TAIL}",
    ),
    "e13-asym": (
        "asymmetric whiskers",
        f"{NEUT} Its defining features: {TRIPOINT} Long fine whiskers set "
        f"asymmetrically, one side riding higher than the other. {NEUT_TAIL}",
    ),
    "e14-apricotwhisk": (
        "the whiskers themselves apricot",
        f"{NEUT} Its defining features: {TRIPOINT} And the long fine whiskers are "
        f"themselves apricot rather than grey. {NEUT_TAIL}",
    ),
    "e15-nowhisk": (
        "tri-point + 3 crown lines, no whiskers",
        f"{NEUT} Its defining features: {TRIPOINT} Exactly three fine darker lines "
        f"across the crown of its head. No whiskers at all. {NEUT_TAIL}",
    ),
    "e16-full": (
        "everything: tri-point, 3 crown, whiskers, furnishings",
        f"{NEUT} Its defining features: {TRIPOINT} {LONGWHISK} Exactly three fine "
        f"darker lines across the crown, and soft pale fur furnishings inside the "
        f"ears. {NEUT_TAIL}",
    ),
    "e17-tailup": (
        "tail held up to show the apricot tip",
        f"{NEUT} Its defining features: {TRIPOINT} {LONGWHISK} Its tail is held "
        f"straight up so the apricot tip sits high and obvious. {NEUT_TAIL}",
    ),
    "e18-cheekarc": (
        "mix + fine cheek arcs",
        f"{NEUT} Its defining features: {TRIPOINT} {LONGWHISK} Plus two fine curved "
        f"arcs sweeping back across each cheek. {NEUT_TAIL}",
    ),
    "e19-eartip": (
        "mix + darker ear tips",
        f"{NEUT} Its defining features: {TRIPOINT} Exactly three fine darker lines "
        f"across the crown, long fine whiskers, and the very tips of both ears "
        f"dipped darker. {NEUT_TAIL}",
    ),
    "e20-min": (
        "the mix and nothing else",
        f"{NEUT} Its only features: {TRIPOINT} {LONGWHISK} Absolutely no other "
        f"markings, stripes or detail anywhere - radically clean. {NEUT_TAIL}",
    ),
}


# Round 17. Whiskers and crown stripes are both out, so the tri-point apricot
# (nose, inner ears, tail tip) is now the whole identity and the eyes have to carry
# everything else. Hence a round that is mostly an eye-construction sweep.
#
# Worth being precise about the reference: in Duo's face the catchlight is not a
# white dot laid on top of the pupil, it is a NOTCH bitten out of the pupil's
# top-left corner -- the pupil is a solid shape with a bite taken from it. That
# reads differently (and cleaner in flat vector, since it is one shape not two),
# so both constructions are tested here rather than assumed.
CLEAN = (
    "A cat mascot sitting calmly facing forward, head and body one rounded mass "
    "with an oversized head, tiny paws floating detached from the body, tall "
    "rounded white eyes with charcoal pupils, and a mouth drawn only as a slightly "
    "darker line."
)

CLEAN_TAIL = (
    "Light warm grey body in two tones, the darker tone on ears and tail, "
    "off-white belly, charcoal eyes. Flat vector illustration, bold rounded "
    "shapes, flat solid fills, no outlines, one clear silhouette, centered on pure "
    "white background, generous negative space, mobile app icon art, 2D vector, no "
    "shading, no gradients. No whiskers at all, no stripes and no markings of any "
    "kind, no mask or patch around the eyes, no props, no clothing, no text."
)

TWINKLE: dict[str, tuple[str, str]] = {
    "t01-dot": (
        "one small round catchlight",
        f"{CLEAN} {TRIPOINT} Each pupil carries one small round white catchlight at "
        f"its top left, giving the eyes a twinkle. {CLEAN_TAIL}",
    ),
    "t02-notch": (
        "catchlight as a notch bitten out",
        f"{CLEAN} {TRIPOINT} Each pupil is a single solid shape with a rounded notch "
        f"bitten out of its top left corner, so the twinkle is a bite in the pupil "
        f"rather than a dot on top of it. {CLEAN_TAIL}",
    ),
    "t03-two": (
        "two catchlights per eye",
        f"{CLEAN} {TRIPOINT} Each pupil carries two white catchlights, a large one "
        f"high on the left and a small one low on the right. {CLEAN_TAIL}",
    ),
    "t04-crescent": (
        "crescent catchlight",
        f"{CLEAN} {TRIPOINT} Each pupil carries a thin white crescent catchlight "
        f"hugging its top edge. {CLEAN_TAIL}",
    ),
    "t05-big": (
        "oversized catchlight",
        f"{CLEAN} {TRIPOINT} Each pupil carries one large white catchlight taking up "
        f"a third of the pupil, making the eyes very glossy. {CLEAN_TAIL}",
    ),
    "t06-pin": (
        "tiny pinpoint catchlight",
        f"{CLEAN} {TRIPOINT} Each pupil carries a single tiny pinpoint of white, "
        f"barely there. {CLEAN_TAIL}",
    ),
    "t07-star": (
        "four-point star sparkle",
        f"{CLEAN} {TRIPOINT} Each eye carries a small four-point star sparkle "
        f"instead of a round catchlight. {CLEAN_TAIL}",
    ),
    "t08-outside": (
        "sparkle beside the pupil",
        f"{CLEAN} {TRIPOINT} A small bright sparkle sits on the white of each eye "
        f"beside the pupil rather than on it. {CLEAN_TAIL}",
    ),
    "t09-teardrop": (
        "teardrop pupil",
        f"{CLEAN} {TRIPOINT} Each pupil is a soft teardrop tapering up toward the "
        f"top left, with a small catchlight in the taper. {CLEAN_TAIL}",
    ),
    "t10-tall": (
        "tall pupil with a high notch",
        f"{CLEAN} {TRIPOINT} Each pupil is a tall rounded bar with a notch bitten "
        f"high out of one side. {CLEAN_TAIL}",
    ),
    "t11-wide": (
        "eyes set very wide apart",
        f"{CLEAN} {TRIPOINT} Its eyes are set very wide apart with a small round "
        f"catchlight in each pupil. {CLEAN_TAIL}",
    ),
    "t12-close": (
        "eyes set close together",
        f"{CLEAN} {TRIPOINT} Its eyes are set close together with a small round "
        f"catchlight in each pupil. {CLEAN_TAIL}",
    ),
    "t13-huge": (
        "eyes fill the face",
        f"{CLEAN} {TRIPOINT} Its eyes are enormous, filling most of the face, each "
        f"with a bright catchlight. {CLEAN_TAIL}",
    ),
    "t14-small": (
        "small eyes, big head",
        f"{CLEAN} {TRIPOINT} Its eyes are small and neat on a very large head, each "
        f"with a tiny catchlight. {CLEAN_TAIL}",
    ),
    "t15-lookup": (
        "pupils looking up",
        f"{CLEAN} {TRIPOINT} Both pupils sit high in the eyes as though looking "
        f"hopefully upward, catchlight at the top. {CLEAN_TAIL}",
    ),
    "t16-bighead": (
        "head three times the body",
        f"{CLEAN} {TRIPOINT} Its head is roughly three times the size of its tiny "
        f"body, eyes twinkling. {CLEAN_TAIL}",
    ),
    "t17-squat": (
        "squat and wide",
        f"{CLEAN} {TRIPOINT} Its body is squat and much wider than it is tall, eyes "
        f"twinkling. {CLEAN_TAIL}",
    ),
    "t18-tailbig": (
        "oversized apricot tail tip",
        f"{CLEAN} {TRIPOINT} The apricot tail tip is generous and bold, a clear "
        f"focal point at the end of a thick tail. Eyes twinkling. {CLEAN_TAIL}",
    ),
    "t19-earbig": (
        "oversized apricot-lined ears",
        f"{CLEAN} {TRIPOINT} Its ears are oversized, nearly as big as its head, with "
        f"the apricot inners clearly visible. Eyes twinkling. {CLEAN_TAIL}",
    ),
    "t20-min": (
        "radically minimal",
        f"{CLEAN} {TRIPOINT} One catchlight per pupil. Radically clean - the whole "
        f"drawing is a handful of shapes and nothing else at all. {CLEAN_TAIL}",
    ),
}


# Round 18. t02's notch twinkle is chosen, so NOTCH becomes a held constant
# alongside TRIPOINT and the varying axis moves back to the animal itself: build,
# head shape, ear size, tail. No whiskers and no crown markings, per round 17.
#
# Worth watching for: with no head marking in the prompt, round 17 kept inventing a
# dark cap or hood to fill the space. If that recurs here it is a real signal that
# the crownless direction leaves a vacuum, rather than a one-off misfire.
NOTCH = (
    "Each pupil is a single solid charcoal shape with a rounded notch bitten out of "
    "its top left corner, so the twinkle is a bite in the pupil rather than a white "
    "dot laid on top of it."
)

CATS: dict[str, tuple[str, str]] = {
    "u01-squat": (
        "squat and wide",
        f"{CLEAN} Squat and low, noticeably wider than it is tall. {NOTCH} "
        f"{TRIPOINT} {CLEAN_TAIL}",
    ),
    "u02-tall": (
        "tall and narrow",
        f"{CLEAN} Tall and narrow, sitting upright and elongated. {NOTCH} "
        f"{TRIPOINT} {CLEAN_TAIL}",
    ),
    "u03-round": (
        "a perfect circle",
        f"{CLEAN} Its whole body is very nearly a perfect circle. {NOTCH} "
        f"{TRIPOINT} {CLEAN_TAIL}",
    ),
    "u04-pear": (
        "pear-shaped, heavy at the base",
        f"{CLEAN} Pear-shaped, narrow at the shoulders and heavy and wide at the "
        f"base. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "u05-bighead": (
        "head three times the body",
        f"{CLEAN} Its head is roughly three times the size of its tiny body. "
        f"{NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "u06-chonk": (
        "gloriously fat",
        f"{CLEAN} Gloriously, comically fat, spilling outward at the bottom. "
        f"{NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "u07-kitten": (
        "tiny kitten proportions",
        f"{CLEAN} A very small young kitten, delicate and slight. {NOTCH} "
        f"{TRIPOINT} {CLEAN_TAIL}",
    ),
    "u08-bigears": (
        "oversized ears",
        f"{CLEAN} Its ears are enormous, nearly as tall as its head. {NOTCH} "
        f"{TRIPOINT} {CLEAN_TAIL}",
    ),
    "u09-smallears": (
        "tiny ears",
        f"{CLEAN} Its ears are tiny, little nubs on a big round head. {NOTCH} "
        f"{TRIPOINT} {CLEAN_TAIL}",
    ),
    "u10-roundears": (
        "soft round ears, no points",
        f"{CLEAN} Its ears are soft rounded arcs with no points at all. {NOTCH} "
        f"{TRIPOINT} {CLEAN_TAIL}",
    ),
    "u11-loaf": (
        "a perfect loaf",
        f"{CLEAN} Folded into a perfect loaf, a smooth unbroken dome with every paw "
        f"hidden. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "u12-tailthick": (
        "enormous thick tail",
        f"{CLEAN} Its tail is enormously thick, as substantial as its body. {NOTCH} "
        f"{TRIPOINT} {CLEAN_TAIL}",
    ),
    "u13-tailcurl": (
        "tail curled into a spiral",
        f"{CLEAN} Its tail curls into a neat spiral beside it. {NOTCH} {TRIPOINT} "
        f"{CLEAN_TAIL}",
    ),
    "u14-tailup": (
        "tail bolt upright",
        f"{CLEAN} Its tail stands bolt upright behind it, the apricot tip at the "
        f"very top of the silhouette. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "u15-nolimbs": (
        "no limbs at all",
        f"A cat mascot sitting calmly facing forward, one rounded mass with ears and "
        f"a tail and no visible limbs whatsoever, oversized head, tall rounded white "
        f"eyes, mouth only a darker line. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "u16-longbody": (
        "long and low",
        f"{CLEAN} Long-bodied and low to the ground, stretched out horizontally. "
        f"{NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "u17-blocky": (
        "square build",
        f"{CLEAN} Built from squares - a square head and a square body with softly "
        f"rounded corners. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "u18-egg": (
        "egg-shaped, narrow at the top",
        f"{CLEAN} Egg-shaped, narrow at the top and swelling wide toward the "
        f"bottom. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "u19-wideface": (
        "very wide flat face",
        f"{CLEAN} Its face is very wide and flat, set low on a broad head. {NOTCH} "
        f"{TRIPOINT} {CLEAN_TAIL}",
    ),
    "u20-cheeks": (
        "big cheeks flaring at the jaw",
        f"{CLEAN} Big rounded cheeks flaring out at the jawline, wider than the top "
        f"of its head. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
}


# Round 19. Every variant must have visible arms AND feet, because the streak
# matrix needs the character posed later and a limbless dome cannot cheer, stretch
# or slump. This is the reason Duo's feet are detached pill shapes: floating limbs
# can be moved anywhere without redrawing the body, which is why LIMBS insists on
# detached rather than attached -- v16 attaches them on purpose as the control.
#
# Held constant: NOTCH (chosen round 17) and TRIPOINT. Varying: limb shape, limb
# scale, limb position, and the round-18 bodies that scored best with limbs added.
BODYBASE = (
    "A cat mascot sitting facing forward, head and body one rounded mass with an "
    "oversized head, tall rounded white eyes, and a mouth drawn only as a slightly "
    "darker line."
)

LIMBS = (
    "Its arms and feet are clearly visible and unmistakable: two arms and two feet, "
    "each a simple bold shape floating detached from the body the way a mascot's "
    "limbs float so it can be posed freely."
)

POSEABLE: dict[str, tuple[str, str]] = {
    "v01-pill": (
        "limbs as floating pill capsules",
        f"{BODYBASE} {LIMBS} Each arm and foot is a plain rounded pill capsule. "
        f"{NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "v02-mitten": (
        "thick mitten paws",
        f"{BODYBASE} {LIMBS} The arms end in thick soft mitten paws and the feet are "
        f"chunky rounded pads. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "v03-fin": (
        "arms as soft tapered fins",
        f"{BODYBASE} {LIMBS} The arms are soft tapered fin shapes, wide at the "
        f"shoulder and narrowing to a point. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "v04-stub": (
        "very short stubby arms",
        f"{BODYBASE} {LIMBS} The arms are comically short stubby cylinders. {NOTCH} "
        f"{TRIPOINT} {CLEAN_TAIL}",
    ),
    "v05-long": (
        "longer noodle arms",
        f"{BODYBASE} {LIMBS} The arms are long soft noodles, loose and flexible. "
        f"{NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "v06-teardrop": (
        "teardrop arms, heavy at the paw",
        f"{BODYBASE} {LIMBS} Each arm is a teardrop, narrow at the shoulder and "
        f"heavy at the paw. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "v07-bigfeet": (
        "oversized feet, small arms",
        f"{BODYBASE} {LIMBS} Its feet are oversized and planted wide while its arms "
        f"stay small. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "v08-bigarms": (
        "oversized arms, small feet",
        f"{BODYBASE} {LIMBS} Its arms are big and expressive while its feet stay "
        f"small and neat. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "v09-splay": (
        "visible splayed toes",
        f"{BODYBASE} {LIMBS} Each foot shows three clearly splayed toes. {NOTCH} "
        f"{TRIPOINT} {CLEAN_TAIL}",
    ),
    "v10-beans": (
        "apricot paw undersides",
        f"{BODYBASE} {LIMBS} The undersides of its paws show apricot pads, turned "
        f"just enough to be seen. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "v11-outstretch": (
        "arms held out from the body",
        f"{BODYBASE} {LIMBS} Both arms are held out and away from its sides, ready "
        f"to gesture. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "v12-down": (
        "arms hanging relaxed",
        f"{BODYBASE} {LIMBS} Both arms hang straight down, completely relaxed. "
        f"{NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "v13-onepaw": (
        "one arm raised",
        f"{BODYBASE} {LIMBS} One arm is raised in a small wave while the other rests "
        f"down. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "v14-bothup": (
        "both arms thrown up",
        f"{BODYBASE} {LIMBS} Both arms are thrown up above its head in delight. "
        f"{NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "v15-together": (
        "paws together in front",
        f"{BODYBASE} {LIMBS} Both arms come forward with the paws held together in "
        f"front of its chest. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "v16-attached": (
        "control: limbs attached, not floating",
        f"{BODYBASE} Its arms and feet are clearly visible and joined directly onto "
        f"the body rather than floating. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "v17-squat": (
        "squat body with limbs",
        f"{BODYBASE} Squat and low, wider than it is tall. {LIMBS} {NOTCH} "
        f"{TRIPOINT} {CLEAN_TAIL}",
    ),
    "v18-bighead": (
        "big head with limbs",
        f"{BODYBASE} Its head is nearly three times the size of its small body. "
        f"{LIMBS} {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "v19-tailup": (
        "upright tail with limbs",
        f"{BODYBASE} Its tail stands bolt upright behind it with the apricot tip at "
        f"the top of the silhouette. {LIMBS} {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "v20-chonk": (
        "gloriously fat with limbs",
        f"{BODYBASE} Gloriously, comically fat. {LIMBS} {NOTCH} {TRIPOINT} "
        f"{CLEAN_TAIL}",
    ),
}


# Round 20. v10 is chosen, with three corrections to round 19: limbs join the body
# smoothly instead of floating, and they take the SAME tone as the body rather than
# the darker one. That combination is what made v01/v03/v05/v12 lose their arms
# entirely, so the apricot jelly-bean pads now carry a second job beyond being an
# accent -- they are the thing that tells you where a paw is. Worth checking in the
# results that paws stay legible in poses where they overlap the torso.
#
# Held constant: NOTCH, TRIPOINT, beans, body-toned connected limbs. Varying: pose,
# chosen to cover the six streak moments plus general marketing use.
V10BASE = (
    "A cat mascot. Head and body are one rounded mass with an oversized head, tall "
    "rounded white eyes, and a mouth drawn only as a slightly darker line. Its arms "
    "and feet are the same light grey as its body and join smoothly onto it - never "
    "detached, never floating apart from it. The underside of each paw shows soft "
    "apricot jelly-bean pads."
)

POSES: dict[str, tuple[str, str]] = {
    "p01-sit": (
        "baseline neutral sit",
        f"{V10BASE} Sitting calmly facing forward, content. {NOTCH} {TRIPOINT} "
        f"{CLEAN_TAIL}",
    ),
    "p02-wave": (
        "waving hello",
        f"{V10BASE} Waving hello with one paw raised, beans showing. {NOTCH} "
        f"{TRIPOINT} {CLEAN_TAIL}",
    ),
    "p03-cheer": (
        "both arms up cheering",
        f"{V10BASE} Both arms thrown up above its head, cheering with delight. "
        f"{NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "p04-clap": (
        "clapping",
        f"{V10BASE} Clapping its front paws together, pleased. {NOTCH} {TRIPOINT} "
        f"{CLEAN_TAIL}",
    ),
    "p05-stretch": (
        "long waking stretch",
        f"{V10BASE} In a long luxurious stretch, front paws reaching forward and "
        f"back arched. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "p06-yawn": (
        "big yawn",
        f"{V10BASE} Mid-yawn, head tipped back, one paw rubbing an eye. {NOTCH} "
        f"{TRIPOINT} {CLEAN_TAIL}",
    ),
    "p07-sleep": (
        "curled up asleep",
        f"{V10BASE} Curled up fast asleep, tail wrapped around itself, eyes closed "
        f"into soft downward curves. {TRIPOINT} {CLEAN_TAIL}",
    ),
    "p08-drowsy": (
        "drowsy, half-lidded",
        f"{V10BASE} Sitting drowsily with heavy half-closed lids, about to nod off. "
        f"{NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "p09-walk": (
        "walking along",
        f"{V10BASE} Walking along in profile, mid-step, tail up. {NOTCH} {TRIPOINT} "
        f"{CLEAN_TAIL}",
    ),
    "p10-run": (
        "running excitedly",
        f"{V10BASE} Running excitedly, legs mid-stride, ears back with speed. "
        f"{NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "p11-jump": (
        "mid-air jump",
        f"{V10BASE} Jumping in mid-air, all four paws off the ground and beans "
        f"showing. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "p12-together": (
        "paws held together",
        f"{V10BASE} Sitting with both front paws held neatly together in front of "
        f"its chest. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "p13-present": (
        "presenting with one paw",
        f"{V10BASE} Presenting to one side with one paw extended open, beans "
        f"showing. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "p14-point": (
        "pointing off to the side",
        f"{V10BASE} Pointing off to one side with one paw, looking that way too. "
        f"{NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "p15-slump": (
        "slumped and deflated",
        f"{V10BASE} Slumped and deflated, shoulders down and arms hanging limp. "
        f"{NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "p16-lie": (
        "lying down, paws forward",
        f"{V10BASE} Lying down on its front with both paws stretched forward, "
        f"relaxed. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "p17-rollover": (
        "on its back, beans up",
        f"{V10BASE} Rolled onto its back, all four paws up in the air so every "
        f"apricot bean pad is on show. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "p18-shy": (
        "paws over the face",
        f"{V10BASE} Bashfully covering half its face with both paws, peeking over "
        f"the top. {NOTCH} {TRIPOINT} {CLEAN_TAIL}",
    ),
    "p19-hip": (
        "one paw on hip, cocky",
        f"{V10BASE} Standing with one paw on its hip, pleased with itself. {NOTCH} "
        f"{TRIPOINT} {CLEAN_TAIL}",
    ),
    "p20-lookup": (
        "gazing up hopefully",
        f"{V10BASE} Gazing up hopefully with both paws clasped, eyes wide. {NOTCH} "
        f"{TRIPOINT} {CLEAN_TAIL}",
    ),
}


# Round 21. The apricot tail tip is dropped, so the accent now lives on the nose,
# the inner ears and the bean pads only. That reopens a question the tip was
# answering: what tone is the tail? q01-q06 sweep that (darker vs body-tone) and a
# few tail shapes on the neutral sit, while the rest carry the change across the
# pose set so it can be judged in use rather than in isolation.
#
# q20 is a second attempt at the broken-streak pose. Round 20's "slumped and
# deflated" read as plain sitting, so the emotion is spelled out mechanically here
# -- shoulders down, ears flat, gaze on the floor -- rather than named.
ACCENT3 = (
    "Apricot appears in exactly three places and nowhere else: the nose, the inside "
    "of both ears, and the jelly-bean pads under the paws. The tail is one single "
    "flat colour from base to tip, with no differently coloured tip at all."
)

TAILONE: dict[str, tuple[str, str]] = {
    "q01-sit-dark": (
        "tail in the darker tone",
        f"{V10BASE} Sitting calmly facing forward. Its tail is a single flat darker "
        f"grey along its whole length. {NOTCH} {ACCENT3} {CLEAN_TAIL}",
    ),
    "q02-sit-body": (
        "tail in the body tone",
        f"{V10BASE} Sitting calmly facing forward. Its tail is exactly the same "
        f"light grey as its body along its whole length. {NOTCH} {ACCENT3} "
        f"{CLEAN_TAIL}",
    ),
    "q03-sit-thick": (
        "thick single-tone tail",
        f"{V10BASE} Sitting calmly facing forward with a very thick heavy tail in "
        f"one flat tone. {NOTCH} {ACCENT3} {CLEAN_TAIL}",
    ),
    "q04-sit-short": (
        "short stubby tail",
        f"{V10BASE} Sitting calmly facing forward with a short stubby tail in one "
        f"flat tone. {NOTCH} {ACCENT3} {CLEAN_TAIL}",
    ),
    "q05-sit-up": (
        "tail bolt upright",
        f"{V10BASE} Sitting calmly with its tail standing bolt upright behind it in "
        f"one flat tone. {NOTCH} {ACCENT3} {CLEAN_TAIL}",
    ),
    "q06-sit-curl": (
        "tail curled in a spiral",
        f"{V10BASE} Sitting calmly with its tail curled into a neat spiral beside "
        f"it, all one flat tone. {NOTCH} {ACCENT3} {CLEAN_TAIL}",
    ),
    "q07-wave": (
        "waving hello",
        f"{V10BASE} Waving hello with one paw raised, beans showing. {NOTCH} "
        f"{ACCENT3} {CLEAN_TAIL}",
    ),
    "q08-cheer": (
        "both arms up cheering",
        f"{V10BASE} Both arms thrown up above its head, cheering with delight. "
        f"{NOTCH} {ACCENT3} {CLEAN_TAIL}",
    ),
    "q09-drowsy": (
        "drowsy, half-lidded",
        f"{V10BASE} Sitting drowsily with heavy half-closed lids, about to nod off. "
        f"{NOTCH} {ACCENT3} {CLEAN_TAIL}",
    ),
    "q10-sleep": (
        "curled up asleep",
        f"{V10BASE} Curled up fast asleep, tail wrapped around itself, eyes closed "
        f"into soft downward curves. {ACCENT3} {CLEAN_TAIL}",
    ),
    "q11-hip": (
        "one paw on hip, cocky",
        f"{V10BASE} Standing with one paw on its hip, pleased with itself. {NOTCH} "
        f"{ACCENT3} {CLEAN_TAIL}",
    ),
    "q12-stretch": (
        "long waking stretch",
        f"{V10BASE} In a long luxurious stretch, front paws reaching forward and "
        f"back arched. {NOTCH} {ACCENT3} {CLEAN_TAIL}",
    ),
    "q13-rollover": (
        "on its back, beans up",
        f"{V10BASE} Rolled onto its back with all four paws up in the air so every "
        f"bean pad is on show. {NOTCH} {ACCENT3} {CLEAN_TAIL}",
    ),
    "q14-shy": (
        "paws over the face",
        f"{V10BASE} Bashfully covering half its face with both paws, peeking over "
        f"the top. {NOTCH} {ACCENT3} {CLEAN_TAIL}",
    ),
    "q15-lookup": (
        "gazing up hopefully",
        f"{V10BASE} Gazing up hopefully with both paws clasped, eyes wide. {NOTCH} "
        f"{ACCENT3} {CLEAN_TAIL}",
    ),
    "q16-present": (
        "presenting with one paw",
        f"{V10BASE} Presenting to one side with one paw extended open, beans "
        f"showing. {NOTCH} {ACCENT3} {CLEAN_TAIL}",
    ),
    "q17-together": (
        "paws held together",
        f"{V10BASE} Sitting with both front paws held neatly together in front of "
        f"its chest. {NOTCH} {ACCENT3} {CLEAN_TAIL}",
    ),
    "q18-lie": (
        "lying down, paws forward",
        f"{V10BASE} Lying down on its front with both paws stretched forward, "
        f"relaxed. {NOTCH} {ACCENT3} {CLEAN_TAIL}",
    ),
    "q19-jump": (
        "mid-air jump",
        f"{V10BASE} Jumping in mid-air, all four paws off the ground and beans "
        f"showing. {NOTCH} {ACCENT3} {CLEAN_TAIL}",
    ),
    "q20-slump": (
        "deflated: shoulders down, ears flat, gaze low",
        f"{V10BASE} Sitting with its shoulders dropped low, both ears folded flat "
        f"down against its head, arms hanging limp at its sides and its eyes cast "
        f"down at the floor. Small and defeated. {NOTCH} {ACCENT3} {CLEAN_TAIL}",
    ),
}


# ---------------------------------------------------------------------------
# THE CORE PROMPT (round 22)
#
# q06 is the locked reference. Every hex below was sampled off
# q06-sit-curl-tailone-v1.png rather than eyeballed, so this block is the
# canonical description of the character and should be reused verbatim -- append a
# pose to it, never rewrite it. Mirrored in docs/mockups/mascot/CHARACTER.md.
#
# The paw rule is the new thing and the reason this round exists: a paw whose
# underside faces the viewer shows the jelly (four apricot circles - one larger
# centre pad plus three smaller toe pads above it); a paw seen from above or
# planted on the ground shows only two short slits. Earlier rounds sprayed bean
# pads onto every paw regardless of orientation, which is why q17 looked like it
# had buttons on its belly. Poses below deliberately mix both states, and r15/r20
# mix them within a single drawing.
# ---------------------------------------------------------------------------
CORE_BUILD = (
    "BUILD: one single rounded mass - a large round head sitting directly on a soft "
    "egg-shaped body that is widest near the base, no neck. Head is about as wide "
    "as the body. Two soft triangular ears with rounded tips, set wide on top of "
    "the head, each filled with an apricot inner triangle. Arms and feet are the "
    "same grey as the body and join smoothly onto it - never detached, never "
    "floating. A large soft off-white belly patch shaped like a rounded teardrop "
    "covers the lower front. The tail is one smooth tapering sweep in a single flat "
    "darker grey, curling into a spiral, with no differently coloured tip. "
)

# The eye clause, pulled out so rounds 25-27 could sweep it as a single axis.
#
# LOCKED round 27: k09-duoratio. A tall off-white capsule with the charcoal pupil
# filling only its upper half, so a broad sweep of off-white shows below. This is
# the construction in the reference the user supplied, and it replaces the
# round-22 clause kept below, whose wide off-white field with a pupil floating in
# it read slightly googly.
#
# `eye()` and EYE_TWINKLE live here rather than in the round-27 block because the
# default has to be built from them. The twinkle wording is load-bearing: saying
# "top-left of that PUPIL" landed 6/6, where "top-left corner" alone drifted to
# top-right in 2 of 5.
EYE_TWINKLE = (
    "and the twinkle is a rounded notch bitten out of that pupil's top-left "
    "corner. "
)


def eye(shape: str) -> str:
    # `shape` names the eye and its pupil and ends on a comma; placement and the
    # twinkle are appended as their own clause so the sentence reads in order
    # rather than opening on a dangling modifier.
    return (
        shape.rstrip().rstrip(",")
        + ". Both eyes sit wide apart and low on the head, "
        + EYE_TWINKLE
    )


# The winner, and the two runners-up. Switching the default is one line: point
# CORE_EYES at a different one of these. k05 reads as max charm but is round
# rather than tall; k02 is the most distinctly ours rather than Duo-adjacent.
EYE_CAPSULE = eye(  # k09-duoratio -- DEFAULT
    "two tall off-white capsule eyes, each holding a dark charcoal pupil that "
    "fills only the upper half so a broad sweep of off-white shows below and "
    "around it,"
)
EYE_HUGE = eye(  # k05-huge
    "two enormous perfectly circular off-white eyes so big they almost touch the "
    "nose and reach up toward the ears, each holding a big dark charcoal pupil,"
)
EYE_RRECT = eye(  # k02-rrect
    "two off-white eyes shaped like upright rounded rectangles with softly squared "
    "corners, clearly taller than wide, each holding a large dark charcoal pupil,"
)

CORE_EYES = EYE_CAPSULE

# Retired round-22 clause, kept so the pre-round-27 `core` renders on disk can
# still be traced back to the text that made them. Do not use for new work.
CORE_EYES_R22 = (
    "two tall rounded off-white eye shapes set wide apart and low on the "
    "head. Inside each, one large dark charcoal pupil, and the twinkle is a rounded "
    "notch bitten out of the pupil's top-left corner rather than a white dot laid "
    "on top. "
)

CORE_REST_OF_FACE = (
    "A small apricot nose shaped like a rounded triangle with soft corners, "
    "centred between the eyes. Below it a fine darker curved line forming a small "
    "contented mouth. No whiskers, no eyebrows, no forehead or body markings of any "
    "kind. "
)

CORE_PAWS = (
    "PAWS: when a paw's underside faces the viewer or points upward, it shows the "
    "jelly - exactly four apricot circles, one larger oval pad in the centre with "
    "three smaller round toe pads arranged above it. When a paw is planted on the "
    "ground or seen from above, it shows no jelly at all, only two short darker "
    "slits suggesting toes. "
)


def core_form(eyes: str = CORE_EYES) -> str:
    return CORE_BUILD + "FACE: " + eyes + CORE_REST_OF_FACE + CORE_PAWS


CORE_FORM = core_form()

CORE_PALETTE = (
    "PALETTE, five flat solid colours and nothing else: body and limbs light warm "
    "grey #D6D2D1, belly and eye whites off-white #ECE8E5, ears and tail mid grey "
    "#A4A4A6, nose and inner ears and jelly pads apricot #F9AF87, eyes and mouth "
    "charcoal #54575B. "
)

CORE_STYLE = (
    "STYLE: flat vector, bold rounded shapes, solid fills only, no outlines, no "
    "gradients, no shading, no texture, one clear silhouette, mobile app mascot "
    "art, no props, no clothing, no text."
)

CORE_INTRO = (
    "Flat 2D vector mascot illustration of a cat, front-facing, centred on a pure "
    "white background with generous margins. "
)


def core(eyes: str = CORE_EYES) -> str:
    return CORE_INTRO + core_form(eyes) + CORE_PALETTE + CORE_STYLE


CORE = core()

JELLY = "Its raised paws face the viewer, so the four-circle jelly pads are visible."
SLITS = (
    "Its paws are planted or seen from above, so they show only the two short "
    "slits and no jelly pads."
)

COREPOSES: dict[str, tuple[str, str]] = {
    "r01-sit": (
        "canonical sit, jelly showing",
        f"{CORE} POSE: sitting calmly facing forward, content, front paws resting "
        f"with their undersides toward the viewer. {JELLY}",
    ),
    "r02-planted": (
        "sit with paws planted, slits",
        f"{CORE} POSE: sitting upright facing forward with both front paws planted "
        f"flat on the ground in front of it. {SLITS}",
    ),
    "r03-wave": (
        "waving, one jelly",
        f"{CORE} POSE: waving hello, one paw raised high with its underside toward "
        f"the viewer, the other resting down. {JELLY}",
    ),
    "r04-cheer": (
        "both arms up, jelly",
        f"{CORE} POSE: both arms thrown straight up above its head, cheering with "
        f"delight, palms up. {JELLY}",
    ),
    "r05-clap": (
        "clapping, jelly",
        f"{CORE} POSE: clapping its front paws together in front of its chest, "
        f"pleased. {JELLY}",
    ),
    "r06-rollover": (
        "on its back, all four jelly",
        f"{CORE} POSE: rolled onto its back with all four paws up in the air. "
        f"{JELLY}",
    ),
    "r07-jump": (
        "mid-air jump, jelly",
        f"{CORE} POSE: jumping in mid-air with all four paws off the ground and "
        f"turned toward the viewer. {JELLY}",
    ),
    "r08-shy": (
        "paws over face, jelly",
        f"{CORE} POSE: bashfully covering the lower half of its face with both "
        f"front paws, peeking over the top. {JELLY}",
    ),
    "r09-lookup": (
        "gazing up, paws clasped",
        f"{CORE} POSE: gazing up hopefully with both front paws clasped together at "
        f"its chest, eyes wide. {JELLY}",
    ),
    "r10-present": (
        "presenting, one open paw",
        f"{CORE} POSE: presenting to one side with one front paw extended open, palm "
        f"up. {JELLY}",
    ),
    "r11-walk": (
        "walking in profile, slits",
        f"{CORE} POSE: walking along in side profile, mid-step, tail up. {SLITS}",
    ),
    "r12-run": (
        "running, slits",
        f"{CORE} POSE: running eagerly forward, legs mid-stride. {SLITS}",
    ),
    "r13-stretch": (
        "stretching, slits",
        f"{CORE} POSE: in a long luxurious stretch, front paws reaching forward flat "
        f"on the ground and back arched high. {SLITS}",
    ),
    "r14-lie": (
        "lying down, slits",
        f"{CORE} POSE: lying down on its front, both front paws stretched forward "
        f"flat, relaxed. {SLITS}",
    ),
    "r15-stand": (
        "standing, mixed paws",
        f"{CORE} POSE: standing upright on its hind feet which are planted flat on "
        f"the ground, both front paws raised with undersides toward the viewer. So "
        f"the raised front paws show the four-circle jelly while the planted hind "
        f"feet show only slits.",
    ),
    "r16-sleep": (
        "curled asleep",
        f"{CORE} POSE: curled up fast asleep, tail wrapped around itself, paws "
        f"tucked away out of sight, eyes closed into two soft downward curves.",
    ),
    "r17-drowsy": (
        "drowsy, jelly",
        f"{CORE} POSE: sitting drowsily with heavy half-closed lids, about to nod "
        f"off, front paws resting with undersides toward the viewer. {JELLY}",
    ),
    "r18-slump": (
        "deflated, slits",
        f"{CORE} POSE: sitting with shoulders dropped low, both ears folded flat down "
        f"against its head, arms hanging limp at its sides and eyes cast down at the "
        f"floor. Small and defeated. {SLITS}",
    ),
    "r19-back": (
        "seen from behind",
        f"{CORE} POSE: seen from behind, sitting, twisting to glance back over one "
        f"shoulder. {SLITS}",
    ),
    "r20-hip": (
        "paw on hip, mixed",
        f"{CORE} POSE: standing pleased with itself, one front paw on its hip and "
        f"the other raised with its underside toward the viewer, hind feet planted. "
        f"The raised paw shows the four-circle jelly, the planted feet show only "
        f"slits.",
    ),
}


# ---------------------------------------------------------------------------
# Round 25. THE REFERENCE SHEET.
#
# Goal: one image that shows every locked trait done correctly, so it can
# replace q06 as the thing later rounds are judged against. r03-wave was the
# starting point but a wave only ever demonstrates ONE paw state; this pose
# raises one paw (jelly) and plants the other (slits), so a single drawing
# carries both halves of the paw rule.
#
# The swept axis is the eye construction and nothing else -- CORE_BUILD,
# CORE_REST_OF_FACE, CORE_PAWS, CORE_PALETTE, CORE_STYLE and the pose are all
# held constant. The complaint driving it is that the round-22 eye is a wide
# off-white field with a pupil floating in it, which reads slightly googly; four
# of the five below delete the off-white entirely and let the dark eye sit on the
# fur the way Duo's does, and y04 keeps it but shrinks it to a rim.
#
# CORE_PALETTE still names "eye whites off-white", which is only true for y04.
# It is left in place deliberately: changing two things at once would make the
# five incomparable. Each no-sclera clause negates it explicitly instead.
# ---------------------------------------------------------------------------
REF_POSE = (
    " POSE: sitting upright and waving hello, one front paw raised high with its "
    "underside turned toward the viewer so its four-circle jelly shows clearly, the "
    "other front paw resting planted on the ground so it shows only the two short "
    "slits and no jelly. Tail curling into its spiral at one side."
)

EYES: dict[str, tuple[str, str]] = {
    "y01-almond": (
        "solid charcoal almond, no sclera",
        core(
            "two large charcoal almond eyes set wide apart and low on the head, each "
            "a soft oval slightly wider than tall with gently tapered outer corners, "
            "drawn straight onto the fur with no off-white shape behind them. The "
            "twinkle is a rounded notch bitten out of each eye's top-left corner. "
        )
        + REF_POSE,
    ),
    "y02-round": (
        "big round charcoal, no sclera",
        core(
            "two big perfectly round charcoal eyes set wide apart and low on the "
            "head, drawn straight onto the fur with no off-white shape behind them. "
            "The twinkle is a rounded notch bitten out of each eye's top-left "
            "corner. "
        )
        + REF_POSE,
    ),
    "y03-tallcat": (
        "tall upright ovals, no sclera",
        core(
            "two tall upright charcoal ovals set wide apart and low on the head, "
            "clearly taller than they are wide the way a cat's are, drawn straight "
            "onto the fur with no off-white shape behind them. The twinkle is a "
            "rounded notch bitten out of each eye's top-left corner. "
        )
        + REF_POSE,
    ),
    "y04-rim": (
        "pupil fills the eye, off-white only a rim",
        core(
            "two tall rounded eyes set wide apart and low on the head, each pupil so "
            "large and dark that the off-white behind it is reduced to a thin bright "
            "rim around its edge rather than a wide white field. The twinkle is a "
            "rounded notch bitten out of each pupil's top-left corner. "
        )
        + REF_POSE,
    ),
    "y05-softd": (
        "heavy-lidded soft D, no sclera",
        core(
            "two large charcoal eyes set wide apart and low on the head, each shaped "
            "like a soft D with a flatter heavy-lidded top edge and a fully rounded "
            "bottom, drawn straight onto the fur with no off-white shape behind "
            "them. The twinkle is a rounded notch bitten out of each eye's top-left "
            "corner. "
        )
        + REF_POSE,
    ),
}


# ---------------------------------------------------------------------------
# Round 26. Tuning inside the y04 family.
#
# y04 won round 25: an off-white eye shape with a big dark charcoal pupil inside
# it that leaves a clear white RIM all around, and the twinkle as a notch at the
# pupil's top-left. That construction is now fixed. What is still unknown is its
# proportions, so each entry below changes exactly ONE thing against the y04
# baseline -- eye scale, rim thickness, eye shape, spacing, twinkle size -- and
# everything else, including REF_POSE, is held. Anything that reads better than
# the baseline tells us which single knob to turn.
#
# Note the twinkle corner: round 25 put the dot top-RIGHT in two of five renders
# from an identical top-left instruction, so every clause below says top-left of
# the PUPIL explicitly rather than of the eye.
# ---------------------------------------------------------------------------
EYES2: dict[str, tuple[str, str]] = {
    "z01-baseline": (
        "y04 construction restated",
        core(
            "two large rounded off-white eye shapes set wide apart and low on the "
            "head. Inside each sits a big dark charcoal pupil leaving a clear "
            "off-white rim visible all the way around it, and the twinkle is a "
            "rounded notch bitten out of that pupil's top-left corner. "
        )
        + REF_POSE,
    ),
    "z02-bigger": (
        "same, eyes scaled up",
        core(
            "two very large rounded off-white eye shapes set wide apart and low on "
            "the head, taking up a good part of the face. Inside each sits a big dark "
            "charcoal pupil leaving a clear off-white rim visible all the way around "
            "it, and the twinkle is a rounded notch bitten out of that pupil's "
            "top-left corner. "
        )
        + REF_POSE,
    ),
    "z03-thickrim": (
        "same, thicker white rim",
        core(
            "two large rounded off-white eye shapes set wide apart and low on the "
            "head. Inside each sits a dark charcoal pupil, smaller than the eye so a "
            "generous wide off-white rim shows all the way around it, and the twinkle "
            "is a rounded notch bitten out of that pupil's top-left corner. "
        )
        + REF_POSE,
    ),
    "z04-tall": (
        "same, tall upright eye shape",
        core(
            "two tall upright off-white eye shapes set wide apart and low on the "
            "head, clearly taller than they are wide. Inside each sits a big dark "
            "charcoal pupil leaving a clear off-white rim visible all the way around "
            "it, and the twinkle is a rounded notch bitten out of that pupil's "
            "top-left corner. "
        )
        + REF_POSE,
    ),
    "z05-bigtwinkle": (
        "same, bolder twinkle",
        core(
            "two large rounded off-white eye shapes set wide apart and low on the "
            "head. Inside each sits a big dark charcoal pupil leaving a clear "
            "off-white rim visible all the way around it, and a big bold twinkle is "
            "bitten out of that pupil's top-left corner as a generous rounded notch. "
        )
        + REF_POSE,
    ),
    "z06-wideset": (
        "same, set wider and lower",
        core(
            "two large rounded off-white eye shapes set very wide apart and sitting "
            "low on the head, close to the nose. Inside each sits a big dark charcoal "
            "pupil leaving a clear off-white rim visible all the way around it, and "
            "the twinkle is a rounded notch bitten out of that pupil's top-left "
            "corner. "
        )
        + REF_POSE,
    ),
}


# ---------------------------------------------------------------------------
# Round 27. Actual variation in the eye.
#
# Round 26 failed as a sweep: six entries that differed only by an adjective
# ("large" / "very large" / "tall upright") came back as six near-identical eyes.
# The lesson is that this model discriminates on GEOMETRY WORDS, not on degree.
# So every clause below names a different shape outright -- pill, rounded
# rectangle, egg, teardrop, circle, lozenge, half-moon -- and states the
# width-to-height ratio in plain terms instead of grading it.
#
# It also retracts round 26's "tall eyes are a dead end" call. That conclusion
# came from two renders that asked for "tall upright ovals" and got small squinty
# ones; the reference the eye is being matched to is a tall vertical capsule, so
# the shape was never the problem. k01/k02/k12 retry it with capsule and
# rounded-rectangle wording.
#
# Held constant: off-white eye shape, dark charcoal pupil inside it, twinkle as a
# notch bitten out of THAT PUPIL's top-left corner (the phrasing that fixed the
# corner drift, 6/6 in round 26), and REF_POSE. `eye()` and EYE_TWINKLE now live
# up in the CORE block, because k09 below became the default.
# ---------------------------------------------------------------------------
EYES3: dict[str, tuple[str, str]] = {
    "k01-pill": (
        "vertical pill, 2x taller than wide",
        core(
            eye(
                "two off-white eyes shaped like vertical pills standing on end, each "
                "about twice as tall as it is wide, with a big dark charcoal pupil "
                "sitting high inside,"
            )
        )
        + REF_POSE,
    ),
    "k02-rrect": (
        "upright rounded rectangle",
        core(
            eye(
                "two off-white eyes shaped like upright rounded rectangles with "
                "softly squared corners, clearly taller than wide, each holding a "
                "large dark charcoal pupil,"
            )
        )
        + REF_POSE,
    ),
    "k03-egg": (
        "egg, narrow top wide bottom",
        core(
            eye(
                "two off-white eyes shaped like eggs, narrow at the top and wide at "
                "the bottom, each holding a round dark charcoal pupil near the top,"
            )
        )
        + REF_POSE,
    ),
    "k04-teardrop": (
        "teardrop leaning outward",
        core(
            eye(
                "two off-white eyes shaped like teardrops that lean gently outward "
                "away from the nose, each holding a rounded dark charcoal pupil,"
            )
        )
        + REF_POSE,
    ),
    "k05-huge": (
        "enormous circles, max size",
        core(
            eye(
                "two enormous perfectly circular off-white eyes so big they almost "
                "touch the nose and reach up toward the ears, each holding a big dark "
                "charcoal pupil,"
            )
        )
        + REF_POSE,
    ),
    "k06-lozenge": (
        "wide flat lozenge, wider than tall",
        core(
            eye(
                "two off-white eyes shaped like wide flat lozenges, distinctly wider "
                "than they are tall, each holding an oval dark charcoal pupil,"
            )
        )
        + REF_POSE,
    ),
    "k07-beady": (
        "small beady, min size",
        core(
            eye(
                "two small neat off-white eyes, no bigger than the nose, set far "
                "apart, each holding a tiny dark charcoal pupil,"
            )
        )
        + REF_POSE,
    ),
    "k08-halfmoon": (
        "bottom-heavy half-moon",
        core(
            eye(
                "two off-white eyes shaped like half-moons with a flat top edge and a "
                "deep rounded bottom, each holding a dark charcoal pupil low inside,"
            )
        )
        + REF_POSE,
    ),
    "k09-duoratio": (
        "big white, moderate pupil high up",
        core(
            eye(
                "two tall off-white capsule eyes, each holding a dark charcoal pupil "
                "that fills only the upper half so a broad sweep of off-white shows "
                "below and around it,"
            )
        )
        + REF_POSE,
    ),
    "k10-slant": (
        "ovals tilted outward",
        core(
            eye(
                "two oval off-white eyes each tilted outward so their inner ends sit "
                "lower than their outer ends, each holding a dark charcoal pupil,"
            )
        )
        + REF_POSE,
    ),
    "k11-gazein": (
        "pupils pushed to inner top",
        core(
            eye(
                "two big round off-white eyes, each with its dark charcoal pupil "
                "pushed toward the inner top of the eye so the cat seems to look "
                "slightly upward and inward,"
            )
        )
        + REF_POSE,
    ),
    "k12-narrow": (
        "narrow tall slivers",
        core(
            eye(
                "two narrow tall off-white eyes like upright almonds, much taller "
                "than wide and slim, each holding a slender dark charcoal pupil,"
            )
        )
        + REF_POSE,
    ),
}


# ---------------------------------------------------------------------------
# Round 28. A PROPER EDIT PROMPT.
#
# Rounds 1-27 sent the same full CORE text on both routes, because --reference
# switched the route without switching the prompt strategy. Per xAI's own docs
# (docs.x.ai Imagine > Image Editing) every official edit example is a short
# imperative -- "Render this as a pencil sketch with detailed shading" -- and the
# vendor guidance is explicit that re-describing the whole image "invites the
# model to regenerate it and lose the source".
#
# Three rules from that guidance, all of which CORE violated as an edit prompt:
#   1. Describe the CHANGE, not the image.
#   2. NAME WHAT STAYS. Without it the model treats the whole frame as fair game.
#   3. FRONT-LOAD the change. Aurora renders sequentially, the first 20-30 words
#      carry the most weight, and a key action in the last sentence arrives late.
#      CORE put the pose in the last 25 words of 2165 -- which is almost certainly
#      why the two-arms-up cheer came back as the seed's one-arm wave.
#
# Negations are also "often ignored" per the same guidance, so the KEEP clause is
# phrased positively and leans on the source image to carry what CORE used to
# spell out with "no ..." lists.
#
# Poses that deliberately change the eyes or ears (sleep, drowsy, slump) pass
# keep_eyes=False, so the KEEP clause stops claiming the eyes are unchanged and
# lets the change clause own them. Claiming both is a contradiction, and
# contradictions are what the round-24..27 failures were made of.
# ---------------------------------------------------------------------------
EDIT_KEEP_EYES = (
    "the same tall off-white capsule eyes with a charcoal pupil and a twinkle notch "
    "at each pupil's top-left, "
)


def core_edit(change: str, keep_eyes: bool = True) -> str:
    return (
        "Change only the pose. "
        + change
        + " Keep everything else exactly as in the source image: the same cat, the "
        "same round head on an egg-shaped body, "
        + (EDIT_KEEP_EYES if keep_eyes else "")
        + "the same apricot nose and apricot inner ears, the same off-white belly "
        "patch, the same single flat grey spiral tail, the same body-grey limbs "
        "joined smoothly onto the body, and the same flat vector style with solid "
        "fills on a plain white background."
    )


EDITPOSES: dict[str, tuple[str, str]] = {
    "p01-sit": (
        "edit: canonical sit",
        core_edit(
            "The cat sits calmly facing forward, content, with both front paws "
            "resting so their undersides face the viewer and the four-circle jelly "
            "pads show."
        ),
    ),
    "p03-wave": (
        "edit: wave",
        core_edit(
            "The cat waves hello, one front paw raised high with its underside "
            "toward the viewer so its four-circle jelly shows, the other front paw "
            "planted so it shows only two short slits."
        ),
    ),
    "p04-cheer": (
        "edit: both arms up",
        core_edit(
            "Both arms are thrown straight up above the head, cheering with delight, "
            "palms turned toward the viewer so the four-circle jelly pads show on "
            "both raised paws. The hind feet stay planted and show only two short "
            "slits each."
        ),
    ),
    "p09-lookup": (
        "edit: gazing up, paws clasped",
        core_edit(
            "The cat gazes upward hopefully with both front paws clasped together at "
            "its chest, jelly pads facing the viewer, eyes wide and looking up."
        ),
    ),
    "p16-sleep": (
        "edit: curled asleep",
        core_edit(
            "The cat is curled up fast asleep, tail wrapped around itself, front and "
            "hind paws tucked away out of sight, and both eyes closed into two soft "
            "downward curves. Because no paw underside is visible, no jelly pads "
            "appear anywhere.",
            keep_eyes=False,
        ),
    ),
    "p17-drowsy": (
        "edit: drowsy, heavy lids",
        core_edit(
            "The cat sits drowsily, about to nod off, with heavy half-closed lids: "
            "each capsule eye keeps its off-white shape but the top is flattened by "
            "a lowered lid and the charcoal pupil sits low inside. Front paws rest "
            "with their undersides toward the viewer, jelly pads showing.",
            keep_eyes=False,
        ),
    ),
    "p18-slump": (
        "edit: deflated, ears folded",
        core_edit(
            "Both ears fold flat down against the head and the shoulders drop low, "
            "arms hanging limp at the sides, eyes cast downward at the floor. Small "
            "and defeated.",
            keep_eyes=False,
        ),
    ),
}


# ---------------------------------------------------------------------------
# Round 29. STREAK WIDGET EXPRESSION MATRIX.
#
# Modelled on Duolingo's streak-widget grid, which is not a set of poses but a set
# of CHARACTER VARIANTS: Duo flexing, Duo melted into a puddle, Duo in tears, Duo
# in sunglasses. Four bands here -- energy, winding down, alarm, flair.
#
# Two deliberate departures from CORE, both approved:
#   - Props and accessories are allowed (book, sunglasses, hearts, music notes,
#     sparkles). CORE forbids them; the widget matrix needs them. Note this is not
#     actually a conflict in the sent prompt, because core_edit() never repeats
#     CORE's "no props" clause -- the accessory just has to be named.
#   - Expressions that change the eyes pass keep_eyes=False so the preservation
#     clause stops claiming the eyes are untouched.
#
# The mouth is specified explicitly in every clause rather than left to the model.
# An earlier cheer edit came back with an open mouth filled rose-pink, a sixth
# colour outside the palette, so open mouths are named as charcoal and the puddle
# tongue as apricot. Stated positively, because the vendor guidance is that
# negations are often ignored.
#
# Sleep marks are described as shapes, never as the letter Z, and the book carries
# no title -- lettering is a known instability and "no text" has failed before.
# ---------------------------------------------------------------------------
WIDGET: dict[str, tuple[str, str]] = {
    # -- energy -------------------------------------------------------------
    "m01-flex": (
        "bicep flex, proud",
        core_edit(
            "The cat curls one front arm upward into a bicep flex with its chest "
            "pushed out, looking proud, the other paw planted. Its mouth stays a "
            "fine dark curved line."
        ),
    ),
    "m02-effort": (
        "eyes screwed shut, mid-chop",
        core_edit(
            "The cat's eyes are squeezed tightly shut into two short downward "
            "creases and its mouth is open in a burst of effort, drawn as one simple "
            "dark charcoal shape, with both front paws swung forward mid-chop.",
            keep_eyes=False,
        ),
    ),
    "m03-reading": (
        "absorbed in an open book",
        core_edit(
            "The cat sits holding an open book in both front paws, head tilted down "
            "toward the page, absorbed. Its eyes look downward, each charcoal pupil "
            "sitting low in its off-white capsule. The book is plain, off-white "
            "pages with a mid-grey cover and a blank surface. Its mouth stays a fine "
            "dark curved line.",
            keep_eyes=False,
        ),
    ),
    "m04-stretch": (
        "big yawn-stretch",
        core_edit(
            "The cat stretches with both arms reaching high overhead and its back "
            "arched, mouth open in a wide yawn drawn as one simple dark charcoal "
            "shape, eyes squeezed shut into two short curves.",
            keep_eyes=False,
        ),
    ),
    # -- winding down -------------------------------------------------------
    "m05-puddle": (
        "melted into a flat puddle",
        core_edit(
            "The cat has melted into a soft flat puddle, its body spreading low and "
            "wide with the head sunk down into it, eyes closed into two soft "
            "downward curves and its tongue lolling out as one small flat apricot "
            "shape. The ears, the apricot inner ears and the grey spiral tail still "
            "read clearly out of the puddle.",
            keep_eyes=False,
        ),
    ),
    "m06-snooze": (
        "curled asleep",
        core_edit(
            "The cat is curled up fast asleep with its tail wrapped around itself "
            "and its paws tucked out of sight, eyes closed into two soft downward "
            "curves and its mouth a small dark oval. Three small pale rounded puffs "
            "drift upward beside its head to show it sleeping.",
            keep_eyes=False,
        ),
    ),
    "m07-drowsy": (
        "heavy half-lids",
        core_edit(
            "The cat sits drowsily, about to nod off, with heavy half-closed lids: "
            "each capsule eye keeps its off-white shape but its top is flattened by "
            "a lowered lid and the charcoal pupil sits low inside. Its mouth stays a "
            "fine dark curved line.",
            keep_eyes=False,
        ),
    ),
    # -- alarm --------------------------------------------------------------
    "m08-teary": (
        "brimming with tears",
        core_edit(
            "The cat's eyes brim with tears: each off-white capsule is filled almost "
            "entirely by a large glossy charcoal pupil, one small pale tear runs "
            "down each cheek, and its mouth is a small wobbling downward curve.",
            keep_eyes=False,
        ),
    ),
    "m09-shock": (
        "startled, tiny pupils",
        core_edit(
            "The cat is startled: both eyes open very wide with tiny charcoal pupils "
            "in a large field of off-white, both ears stand straight up, and its "
            "mouth is a small dark open oval.",
            keep_eyes=False,
        ),
    ),
    "m10-stern": (
        "arms crossed, side-eye",
        core_edit(
            "The cat sits with both front arms folded across its chest, its mouth a "
            "flat straight dark line, and both charcoal pupils slid to one side in a "
            "level unimpressed side-eye.",
            keep_eyes=False,
        ),
    ),
    "m11-glare": (
        "lowered lids, unimpressed",
        core_edit(
            "The cat glares: the top of each off-white capsule eye is cut flat by a "
            "heavily lowered lid so only the lower part of the charcoal pupil shows, "
            "and its mouth is a flat straight dark line.",
            keep_eyes=False,
        ),
    ),
    "m12-panic": (
        "paws on cheeks, mouth wide",
        core_edit(
            "The cat panics with its mouth stretched wide open as one large simple "
            "dark charcoal shape, both front paws pressed flat to its cheeks, and "
            "both eyes opened wide with small charcoal pupils.",
            keep_eyes=False,
        ),
    ),
    # -- flair --------------------------------------------------------------
    "m13-blush": (
        "bashful, hearts",
        core_edit(
            "The cat's eyes are shut happily into two upward curves, a soft apricot "
            "blush sits on each cheek, its mouth is a small contented curve, and a "
            "few small apricot hearts float in the air beside its head.",
            keep_eyes=False,
        ),
    ),
    "m14-sing": (
        "singing, music notes",
        core_edit(
            "The cat sings with its mouth open as a small dark charcoal oval and its "
            "head tilted back a little, and two small mid-grey music notes float in "
            "the air beside its head."
        ),
    ),
    "m15-smug": (
        "half-lidded, sparkles",
        core_edit(
            "The cat looks pleased with itself: the top of each capsule eye is "
            "lowered into a confident half-lid, its mouth curves up on one side "
            "only, and a few small apricot sparkles sit in the air around its head.",
            keep_eyes=False,
        ),
    ),
    "m16-cool": (
        "sunglasses, smirk",
        core_edit(
            "The cat wears a pair of simple flat charcoal sunglasses covering both "
            "eyes, with a small confident smirk for a mouth. Its apricot nose stays "
            "visible just below the sunglasses.",
            keep_eyes=False,
        ),
    ),
}


# Round 23. The cat re-skinned in the app icon's chalk hand. CORE_FORM is reused
# verbatim so the geometry is identical and only the rendering changes -- that is
# the whole point of having split CORE.
#
# Two things taken from the real icon (macos/.../app_icon_512.png) rather than
# invented: it is white chalk on brand green #09BC8A, and interior details are
# KNOCKED OUT as green holes through the chalk rather than drawn on top of it -- the
# ribbon on the book works exactly that way, and docs/mockups/empty-states/
# PROMPTS.md says the same about the empty-state stencils.
#
# The honest tension to look for in the results: the icon hand is monochrome, so
# group A has to throw away the five-colour palette and the apricot accent that the
# last several rounds were built around. Group B keeps the palette and only borrows
# the chalk texture; group C tries other sketchy media for comparison.
CHALK_ICON = (
    "Rendered exactly like a white chalk drawing on a solid brand-green #09BC8A "
    "background: the entire cat is one flat white chalk shape with soft grainy "
    "chalky edges and a faint chalk-dust grain inside, slightly wobbly hand-drawn "
    "contours, no outlines and no second colour anywhere. The eyes, nose, mouth and "
    "paw pads are KNOCKED OUT as green holes straight through the white chalk "
    "rather than drawn on top of it. Centred with generous margins, no text."
)

CHALK_TEXTURE = (
    "Rendered with a hand-drawn chalk texture: the same flat colours, but every "
    "shape has soft grainy chalky edges and a faint chalk-dust grain inside, with "
    "slightly wobbly hand-drawn contours instead of crisp vector curves. Plain "
    "white background, centred, no outlines, no text."
)

SKETCH: dict[str, tuple[str, str]] = {
    # Group A -- icon-matched: white chalk on brand green, monochrome.
    "w01-chalk-sit": (
        "icon chalk, sitting",
        f"A cat mascot sitting calmly facing forward, front paws resting with their "
        f"undersides toward the viewer. {CORE_FORM} {CHALK_ICON}",
    ),
    "w02-chalk-wave": (
        "icon chalk, waving",
        f"A cat mascot waving hello, one paw raised high. {CORE_FORM} {CHALK_ICON}",
    ),
    "w03-chalk-cheer": (
        "icon chalk, cheering",
        f"A cat mascot with both arms thrown up above its head, cheering. "
        f"{CORE_FORM} {CHALK_ICON}",
    ),
    "w04-chalk-drowsy": (
        "icon chalk, drowsy",
        f"A cat mascot sitting drowsily with heavy half-closed lids. {CORE_FORM} "
        f"{CHALK_ICON}",
    ),
    "w05-chalk-sleep": (
        "icon chalk, asleep",
        f"A cat mascot curled up fast asleep, tail wrapped around itself, eyes "
        f"closed into soft downward curves. {CORE_FORM} {CHALK_ICON}",
    ),
    "w06-chalk-rollover": (
        "icon chalk, on its back",
        f"A cat mascot rolled onto its back with all four paws up in the air, jelly "
        f"pads showing. {CORE_FORM} {CHALK_ICON}",
    ),
    "w07-chalk-lookup": (
        "icon chalk, gazing up",
        f"A cat mascot gazing up hopefully with both front paws clasped at its "
        f"chest. {CORE_FORM} {CHALK_ICON}",
    ),
    "w08-chalk-slump": (
        "icon chalk, deflated",
        f"A cat mascot sitting with shoulders dropped, ears folded flat down and "
        f"eyes cast at the floor, small and defeated. {CORE_FORM} {CHALK_ICON}",
    ),
    # Group B -- chalk texture, palette retained.
    "w09-tex-sit": (
        "chalk texture, palette kept, sitting",
        f"A cat mascot sitting calmly facing forward, front paws resting with their "
        f"undersides toward the viewer. {CORE_FORM} {CORE_PALETTE} {CHALK_TEXTURE}",
    ),
    "w10-tex-wave": (
        "chalk texture, palette kept, waving",
        f"A cat mascot waving hello, one paw raised high. {CORE_FORM} "
        f"{CORE_PALETTE} {CHALK_TEXTURE}",
    ),
    "w11-tex-cheer": (
        "chalk texture, palette kept, cheering",
        f"A cat mascot with both arms thrown up above its head, cheering. "
        f"{CORE_FORM} {CORE_PALETTE} {CHALK_TEXTURE}",
    ),
    "w12-tex-sleep": (
        "chalk texture, palette kept, asleep",
        f"A cat mascot curled up fast asleep, tail wrapped around itself. "
        f"{CORE_FORM} {CORE_PALETTE} {CHALK_TEXTURE}",
    ),
    "w13-tex-rollover": (
        "chalk texture, palette kept, on its back",
        f"A cat mascot rolled onto its back with all four paws up, jelly pads "
        f"showing. {CORE_FORM} {CORE_PALETTE} {CHALK_TEXTURE}",
    ),
    "w14-tex-green": (
        "chalk texture, brand green body",
        f"A cat mascot sitting calmly facing forward. {CORE_FORM} Its body is brand "
        f"green #09BC8A instead of grey, with an off-white belly, a deeper green "
        f"tail and ears, and apricot nose, inner ears and jelly pads. "
        f"{CHALK_TEXTURE}",
    ),
    # Group C -- other sketchy media, for comparison.
    "w15-pencil": (
        "graphite pencil sketch",
        f"A cat mascot sitting calmly facing forward. {CORE_FORM} Drawn as a loose "
        f"graphite pencil sketch on off-white paper, visible sketchy construction "
        f"strokes and light hatching, no colour.",
    ),
    "w16-ink": (
        "wobbly ink line drawing",
        f"A cat mascot sitting calmly facing forward. {CORE_FORM} Drawn as a loose "
        f"hand-inked line drawing with a wobbly uneven brush line and no fills, on "
        f"plain white.",
    ),
    "w17-crayon": (
        "wax crayon",
        f"A cat mascot sitting calmly facing forward. {CORE_FORM} {CORE_PALETTE} "
        f"Drawn in waxy crayon with visible grainy stroke direction and patchy "
        f"coverage, on plain white.",
    ),
    "w18-slate": (
        "white chalk on dark slate",
        f"A cat mascot sitting calmly facing forward. {CORE_FORM} Drawn in white "
        f"chalk on a dark slate blackboard, grainy and dusty, monochrome.",
    ),
    "w19-charcoal": (
        "soft charcoal",
        f"A cat mascot sitting calmly facing forward. {CORE_FORM} Drawn in soft "
        f"smudgy charcoal on textured paper, monochrome.",
    ),
    "w20-chalkline": (
        "chalk outline only",
        f"A cat mascot sitting calmly facing forward. {CORE_FORM} Drawn as a white "
        f"chalk OUTLINE only on solid brand-green #09BC8A, hollow and unfilled, with "
        f"a grainy chalky line and wobbly hand-drawn contours.",
    ),
}


# Round 24. Correction to round 23: "chalk style" meant the TEXTURE only. Keep the
# white background and the locked five-colour palette, and just give the shapes a
# dry chalk grain. Round 23's group A wrongly reskinned the character as white
# chalk on brand green, which threw away the notch pupils and the apricot.
#
# Round 23 also drifted dimensional -- soft volume, drop shadows, an almost felted
# look -- so FLATCHALK carries hard negations against that. x01-x08 sweep how much
# grain to use and where; x09 onward apply a mid setting across the pose set.
def flatchalk(grain: str) -> str:
    return (
        f"{grain} Everything else stays perfectly FLAT: no drop shadow, no cast "
        "shadow, no 3D or dimensional rendering, no volume, no soft shading, no "
        "gloss, no fur rendering. Plain pure white background, centred with generous "
        "margins, no outlines, no text."
    )


CHALK_MED = flatchalk(
    "Rendered with a dry chalk texture: each flat colour shape keeps its exact "
    "colour but gains a soft grainy chalk edge and a faint even chalk-dust grain "
    "across its fill, with slightly wobbly hand-drawn contours instead of crisp "
    "vector curves."
)

CHALKTEX: dict[str, tuple[str, str]] = {
    "x01-subtle": (
        "barely-there grain",
        f"A cat mascot sitting calmly facing forward, front paws resting with their "
        f"undersides toward the viewer. {CORE_FORM} {CORE_PALETTE} "
        + flatchalk(
            "Rendered with a very subtle chalk texture - just a whisper of grain at "
            "the edges of each shape, otherwise clean."
        ),
    ),
    "x02-medium": (
        "medium grain",
        f"A cat mascot sitting calmly facing forward, front paws resting with their "
        f"undersides toward the viewer. {CORE_FORM} {CORE_PALETTE} {CHALK_MED}",
    ),
    "x03-heavy": (
        "heavy chalky grain",
        f"A cat mascot sitting calmly facing forward, front paws resting with their "
        f"undersides toward the viewer. {CORE_FORM} {CORE_PALETTE} "
        + flatchalk(
            "Rendered with a heavy dry chalk texture - coarse grain right through "
            "every fill and crumbly broken edges, like thick chalk dragged over "
            "rough paper."
        ),
    ),
    "x04-edges": (
        "grain at the edges only",
        f"A cat mascot sitting calmly facing forward, front paws resting with their "
        f"undersides toward the viewer. {CORE_FORM} {CORE_PALETTE} "
        + flatchalk(
            "Rendered so the chalk grain appears only along the edges of each shape "
            "while the interiors stay completely clean and flat."
        ),
    ),
    "x05-rough": (
        "rough hand-drawn contours",
        f"A cat mascot sitting calmly facing forward, front paws resting with their "
        f"undersides toward the viewer. {CORE_FORM} {CORE_PALETTE} "
        + flatchalk(
            "Rendered with strongly wobbly, uneven, obviously hand-drawn contours "
            "and a light chalk grain - the shapes look sketched by hand rather than "
            "drafted."
        ),
    ),
    "x06-dry": (
        "patchy dry-brush coverage",
        f"A cat mascot sitting calmly facing forward, front paws resting with their "
        f"undersides toward the viewer. {CORE_FORM} {CORE_PALETTE} "
        + flatchalk(
            "Rendered with patchy dry chalk coverage, so the fills are uneven and "
            "the white background shows faintly through in places."
        ),
    ),
    "x07-pastel": (
        "soft pastel chalk",
        f"A cat mascot sitting calmly facing forward, front paws resting with their "
        f"undersides toward the viewer. {CORE_FORM} {CORE_PALETTE} "
        + flatchalk(
            "Rendered in soft pastel chalk with a powdery grain and gently feathered "
            "edges."
        ),
    ),
    "x08-construction": (
        "chalk plus faint construction lines",
        f"A cat mascot sitting calmly facing forward, front paws resting with their "
        f"undersides toward the viewer. {CORE_FORM} {CORE_PALETTE} "
        + flatchalk(
            "Rendered with a light chalk grain plus a few faint visible "
            "construction strokes left showing at the edges, as though the artist's "
            "underdrawing was never erased."
        ),
    ),
    # Mid setting across the pose set.
    "x09-wave": (
        "waving",
        f"A cat mascot waving hello, one paw raised high with its underside toward "
        f"the viewer. {CORE_FORM} {CORE_PALETTE} {CHALK_MED}",
    ),
    "x10-cheer": (
        "cheering",
        f"A cat mascot with both arms thrown straight up above its head, cheering, "
        f"palms up. {CORE_FORM} {CORE_PALETTE} {CHALK_MED}",
    ),
    "x11-drowsy": (
        "drowsy",
        f"A cat mascot sitting drowsily with heavy half-closed lids, about to nod "
        f"off. {CORE_FORM} {CORE_PALETTE} {CHALK_MED}",
    ),
    "x12-sleep": (
        "asleep",
        f"A cat mascot curled up fast asleep, tail wrapped around itself, paws "
        f"tucked away, eyes closed into two soft downward curves. {CORE_FORM} "
        f"{CORE_PALETTE} {CHALK_MED}",
    ),
    "x13-rollover": (
        "on its back",
        f"A cat mascot rolled onto its back with all four paws up in the air, every "
        f"jelly pad showing. {CORE_FORM} {CORE_PALETTE} {CHALK_MED}",
    ),
    "x14-lookup": (
        "gazing up",
        f"A cat mascot gazing up hopefully with both front paws clasped at its "
        f"chest. {CORE_FORM} {CORE_PALETTE} {CHALK_MED}",
    ),
    "x15-shy": (
        "paws over face",
        f"A cat mascot bashfully covering the lower half of its face with both front "
        f"paws, peeking over the top. {CORE_FORM} {CORE_PALETTE} {CHALK_MED}",
    ),
    "x16-slump": (
        "deflated",
        f"A cat mascot sitting with shoulders dropped low, both ears folded flat down "
        f"against its head, arms hanging limp and eyes cast down at the floor. "
        f"{CORE_FORM} {CORE_PALETTE} {CHALK_MED}",
    ),
    "x17-clap": (
        "clapping",
        f"A cat mascot clapping its front paws together in front of its chest. "
        f"{CORE_FORM} {CORE_PALETTE} {CHALK_MED}",
    ),
    "x18-planted": (
        "paws planted, slits only",
        f"A cat mascot sitting upright with both front paws planted flat on the "
        f"ground, so they show only the two short slits and no jelly pads. "
        f"{CORE_FORM} {CORE_PALETTE} {CHALK_MED}",
    ),
    "x19-stand": (
        "standing, mixed paws",
        f"A cat mascot standing upright on planted hind feet with both front paws "
        f"raised, undersides toward the viewer - so the raised front paws show the "
        f"four-circle jelly while the planted hind feet show only slits. "
        f"{CORE_FORM} {CORE_PALETTE} {CHALK_MED}",
    ),
    "x20-hip": (
        "paw on hip",
        f"A cat mascot standing pleased with itself, one front paw on its hip and the "
        f"other raised with its underside toward the viewer. {CORE_FORM} "
        f"{CORE_PALETTE} {CHALK_MED}",
    ),
}


STYLES = {
    "chalk": CHALK,
    "cute": CUTE,
    "character": CHARACTER,
    "probe": PROBES,
    "cat": CAT,
    "geo": GEO,
    "geo5": GEO5,
    "face": FACE,
    "story": STORY,
    "look": LOOK,
    "identity": IDENTITY,
    "marks": MARKS,
    "marks2": MARKS2,
    "fine": FINE,
    "mix": MIX,
    "twinkle": TWINKLE,
    "cats": CATS,
    "poseable": POSEABLE,
    "poses": POSES,
    "tailone": TAILONE,
    "core": COREPOSES,
    "eyes": EYES,
    "eyes2": EYES2,
    "eyes3": EYES3,
    "edit": EDITPOSES,
    "widget": WIDGET,
    "sketch": SKETCH,
    "chalktex": CHALKTEX,
}


def character_prompt_for(subject: str) -> str:
    return (
        f"Draw: {subject} {CHAR_SILHOUETTE} {CHAR_BUILD} {CHAR_FACE} "
        f"{CHAR_RENDER} {CHAR_COLOUR} {CHAR_FRAME}"
    )


def cute_prompt_for(subject: str) -> str:
    return (
        f"Draw: {subject} {CUTE_PROPORTION} {CUTE_FACE} {CUTE_FORM} "
        f"{CUTE_SIMPLE} {CUTE_COLOUR} {CUTE_FRAME}"
    )


def data_url(src: Path) -> str:
    """`src` downscaled to 512px as a data URL. Plenty for a style reference."""
    OUT.mkdir(parents=True, exist_ok=True)
    small = OUT / "_ref512.png"
    subprocess.run(
        ["sips", "-Z", "512", str(src), "--out", str(small)],
        check=True,
        capture_output=True,
    )
    raw = small.read_bytes()
    small.unlink()
    return "data:image/png;base64," + base64.b64encode(raw).decode()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--style", choices=list(STYLES), default="cute")
    ap.add_argument("--surface", choices=list(SURFACES), default="paper")
    ap.add_argument("--only", nargs="+", metavar="NAME")
    ap.add_argument("--variants", type=int, default=3)
    ap.add_argument("--resolution", choices=["1k", "2k"], default="1k")
    ap.add_argument(
        "--aspect",
        default="1:1",
        # The endpoint validates this against a fixed list, so 4:5 is out -- 3:4 is
        # the nearest near-square portrait it accepts.
        choices=[
            "1:1",
            "3:4",
            "4:3",
            "2:3",
            "3:2",
            "9:16",
            "16:9",
        ],
        metavar="W:H",
        help="Frame aspect ratio. 1:1 crops a tall character tight at top and "
        "bottom while leaving dead margins at the sides; 3:4 gives a near-square "
        "field with room around the whole silhouette.",
    )
    ap.add_argument(
        "--reference",
        metavar="PATH",
        help="Use this image as the edit reference instead of the app icon, and "
        "force the /v1/images/edits route. This is how a refinement pass is run "
        "over one of our own earlier generations -- see the s6-refine probe.",
    )
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    if args.list:
        for style, table in STYLES.items():
            print(style)
            for name, (label, _) in table.items():
                print(f"  {name:8s} {label}")
        return

    table = STYLES[args.style]
    todo = args.only or list(table)
    if bad := [t for t in todo if t not in table]:
        sys.exit(f"unknown name(s): {', '.join(bad)} (try --list)")

    # Neither cute nor character takes a reference image: passing the chalk icon
    # drags the output straight back into round 1's monochrome grain, which is
    # the whole thing those styles exist to escape. An explicit --reference
    # overrides that, for a refinement pass over one of our own generations.
    ref = None
    route = "generations"
    if args.reference:
        # Resolved, because `relative_to(REPO)` below needs an absolute path and a
        # relative --reference used to crash the run *after* the images had been
        # generated and written -- billing for four images whose provenance was
        # then lost with the traceback.
        src = Path(args.reference).resolve()
        if not src.exists():
            sys.exit(f"reference not found: {src}")
        ref = data_url(src)
        route = "edits"
    elif args.style == "chalk":
        if not ICON.exists():
            sys.exit(f"reference icon missing: {ICON}")
        ref = data_url(ICON)
        route = "edits"

    OUT.mkdir(parents=True, exist_ok=True)
    mf_path = OUT / "manifest.json"
    manifest = json.loads(mf_path.read_text()) if mf_path.exists() else {}
    infix = "" if args.style == "chalk" else f"-{args.style}"
    jobs = [(n, v + 1) for n in todo for v in range(args.variants)]

    def run(job):
        name, v = job
        label, subject = table[name]
        if args.style in (
            "probe",
            "cat",
            "geo",
            "geo5",
            "face",
            "story",
            "look",
            "identity",
            "marks",
            "marks2",
            "fine",
            "mix",
            "twinkle",
            "cats",
            "poseable",
            "poses",
            "tailone",
            "core",
            "eyes",
            "eyes2",
            "eyes3",
            "edit",
            "widget",
            "sketch",
            "chalktex",
        ):
            # Verbatim: these ARE complete prompts, and wrapping them would
            # destroy the thing being measured.
            prompt = subject
        elif args.style == "cute":
            prompt = cute_prompt_for(subject)
        elif args.style == "character":
            prompt = character_prompt_for(subject)
        else:
            prompt = prompt_for(subject, route, args.surface)
        body = {
            "model": MODEL,
            "prompt": prompt,
            "aspect_ratio": args.aspect,
            "resolution": args.resolution,
            "response_format": "b64_json",
        }
        if ref:
            body["images"] = [{"url": ref}]
        img, err, ticks, ext = call(route, body)
        key = f"{name}{infix}-v{v}"
        if img is None:
            return f"  {key}: {err}", None, 0.0
        fname = f"{key}.{ext}"
        (OUT / fname).write_bytes(img)
        cost = ticks / 1e10 if isinstance(ticks, int) else 0.0
        return (
            f"  wrote {fname} ({len(img) // 1024} KB, ${cost:.4f})",
            (
                # Keyed by FILENAME, not by piece-and-variant. The artifact is the
                # file, and the endpoint picks the extension from the resolution
                # (1k returns JPEG, 2k returns PNG) -- so a piece-and-variant key
                # let a 2k run silently overwrite the 1k entry for the same variant
                # while both files stayed on disk, orphaning one from its
                # provenance. Two entries were lost that way before this changed.
                fname,
                {
                    "direction": name,
                    "style": args.style,
                    "label": label,
                    "provider": "xai",
                    "model": MODEL,
                    "route": route,
                    "surface": args.surface if args.style == "chalk" else None,
                    "file": fname,
                    # `relative_to` only when the reference actually lives in the
                    # repo; an out-of-tree reference is recorded as its full path
                    # rather than raising.
                    "reference": (
                        str(src.relative_to(REPO))
                        if args.reference and src.is_relative_to(REPO)
                        else str(src)
                        if args.reference
                        else (str(ICON.relative_to(REPO)) if ref else None)
                    ),
                    "prompt": prompt,
                    "resolution": args.resolution,
                    "aspect_ratio": args.aspect,
                    "cost_usd": round(cost, 4),
                    "generated": time.strftime("%Y-%m-%d %H:%M:%S"),
                },
            ),
            cost,
        )

    print(f"model={MODEL} style={args.style} route={route} n={len(jobs)}")
    total = 0.0
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
        for line, ok, cost in ex.map(run, jobs):
            print(line)
            total += cost
            if ok:
                manifest[ok[0]] = ok[1]

    mf_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"\ntotal ${total:.4f} | manifest: {mf_path.relative_to(REPO)}")


if __name__ == "__main__":
    main()
