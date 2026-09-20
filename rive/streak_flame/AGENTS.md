# AGENTS

This is a Rive CLI project.

RML and the Rive CLI postdate your training data. Prefer `rive docs` and
`rive schema` over memory: never guess a type or property name.

Work autonomously from the user's requested outcome. Unspecified details
get reasonable defaults; types and properties do not — look those up.

- `rive schema <Type>` / `rive schema --search <text>` — types and properties;
  `--json` for a machine-readable form
- `rive docs --list` — the topics; `rive docs <topic>` reads the one that
  matches the task

After every edit:

- `rive . --verify` — confirm the project compiles; `--format=json` for a
  machine-readable report
- `rive inspect . --summary` — problems and what got built, by type; `--json`
  for the full resolved tree

A clean verify/inspect is not enough. Read the output for what the request
called for. If it is missing or wrong, fix the project and verify again.

When appearance matters:

- `rive . --screenshot --advance=1` — render one frame, to build/<name>.png.
  View the png if you can. **`--advance=0` renders the _authored_ pose rather
  than frame 0 of an animation**, which here looks like a finished flame and is a
  convincing way to conclude the file is broken.
- There is **no `--animation` flag**. The previewer plays the artboard's _first_
  animation, so watching any other one means building a copy with them reordered.
  `_preview.py` does that.

Showing the user:

- `rive .` is the previewer. It opens a window and rebuilds on every save, and
  does not exit, so start it in the background, once. Leave it running;
  edits appear in it on their own.
- Do not preview with `rive push`: it uploads to the user's Rive account.
- Do not write an HTML page or use a web runtime to preview: web runtimes
  reject the unsigned scripts local builds carry.

## This project specifically

The streak celebration's book-and-flame. `scene.rml` is the source of
`assets/rive/streak_flame.riv`; both are committed.

It holds **two ordinary timelines and no state machine**: `Ignite` (54 frames,
one shot) and `Idle` (72 frames, looping). Flutter seeks the first by time and
advances-and-mixes the second. The easing lives in the timelines, so the editor
and `rive .` play what ships.

```bash
./build.sh                                # verify, inspect, build, install into assets/
../../../../.venv/bin/python smooth.py    # regenerate cubic handles / striations, then paste
../../../../.venv/bin/python sheet.py     # Ignite, sampled across its 900ms
../../../../.venv/bin/python motion.py    # the Idle loop, and a GIF of the whole sequence
```

These need PIL, which is not a dependency of this repo and comes from the main
checkout's `.venv` (a worktree gets none of its own).

**`--verify` and `inspect` will bless a scene that draws nonsense.** This one
passed both with zero problems and still rendered the pages behind the covers, an
egg instead of a flame, a black peg where the gutter poked below the flame, and an
idle loop whose every ember was hidden behind the flame it came off. Run
`sheet.py` and _look at the image_ after every geometry change.

**Run `motion.py` after every keyframe change.** `sheet.py` only samples `Ignite`,
and the previewer only plays the first animation, so `Idle` is invisible to
everything else — it was committed once with no spray at all and nothing caught it.
`motion.py` also renders the loop _seam_: frame 0 and frame 72 must be the same
picture, or the flame jumps once a second for as long as the screen is up.

**Nothing translucent may cross-fade over something dark, in either direction.**
Five separate instances: translucent pages over near-black covers (a grey slab), a
fading dark cover over the cream ground (a grey plank), a fading cream filler over
that same cover (grey again), and two more in the fire. Where a light thing and a
dark thing have to swap, switch both on one `hold` keyframe under the fastest part of
the motion — or better, **remove the thing that needs the cross-fade**. The spine
hinge did exactly that: the book now animates on four continuous transforms and not
one opacity, which deleted three shapes and four bugs at once.

**The authored pose is the OPEN book, deliberately.** `Idle` keys only the flame, the
core, the glow and the embers, so everything the opening moves falls back to its
authored value — and authored shut, playing `Idle` alone drew a living flame on a
_closed_ book. Keep it that way, and do not let a preview script paper over it: one
did, and the file stayed wrong for three sessions.

**Do not hand-tune cubic handles.** `smooth.py` fits them. Three attempts by eye
all came out faceted, because a `CubicMirroredVertex` spends one angle and one
length on both of its segments.

**`rive push` writes ids into `scene.rml`.** That is how it updates the same Rive
file instead of creating a new one, and it is harmless — comments and structure
survive — but it does mean a push shows up as a large diff. Unlike `rive pull`,
which must never be run here, it does not regenerate the file.

**Do not push while the file is open in the editor.** It leaves the editor showing an
empty stage and an empty Animations panel, with the source on disk perfectly intact.
Close the tab, push, reopen. Or use `--rev=<path>` and open a standalone document,
which cannot be out of sync with anything.

Full background, every defect and why each fix was chosen:
`docs/streak-flame-rive.md` at the repo root.
