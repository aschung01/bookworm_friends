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

- `rive . --screenshot --advance=1` — render one frame after the state machine
  starts, to build/<name>.png. View the png if you can.

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

```bash
./build.sh                               # verify, inspect, build, install into assets/
../../../../.venv/bin/python sheet.py    # the six keyed poses
../../../../.venv/bin/python between.py  # every 4% across the scrub
../../../../.venv/bin/python motion.py   # on the curve the app actually drives it with
```

These need PIL, which is not a dependency of this repo and comes from the main
checkout's `.venv` (a worktree gets none of its own).

**`--verify` and `inspect` will bless a scene that draws nonsense.** This one
passed both with zero problems and still rendered the pages behind the covers, an
egg instead of a flame, and a black peg where the gutter poked below the flame.
Run `sheet.py` and _look at the image_ after every geometry change.

**Run `between.py` after every keyframe change.** A blend state interpolates each
property independently and linearly, so two poses that are both correct can pass
through something that is not — which is how a half-transparent page over a
near-black cover made the book a grey slab for the first fifth of the sequence
while both ends looked right.

**Run `motion.py` if the pose axis or the driving curve moves.** Neither sheet
above scrubs `progress` the way the app does, and the first curve raced 0 → 100 in
185ms and then overshot past the last pose, so 62% of the window was a held frame
and the whole thing played in three. Every pose and every blend was correct.

Full background, every defect and why each fix was chosen:
`docs/streak-flame-rive.md` at the repo root.
