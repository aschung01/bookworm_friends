#!/bin/sh
# Everything about this page that can be checked without a browser.
#
# Run from the mockup set's directory:  sh _build/verify.sh
#
# Interactive behaviour (hover, keyboard, scroll-spy, the filter combobox)
# is NOT covered here. It belongs to the shell's engine, and the identity
# check below is what licenses trusting it: if SECTION 5 is byte-identical
# to the skill's shell, its behaviour is the skill's behaviour.
set -e
cd "$(dirname "$0")/.."

echo "== extract + syntax =="
python3 - <<'PY'
import re
s = open('index.html').read()
js = re.search(r'<script>\s*\n(.*?)\n\s*</script>', s, re.S).group(1)
open('/tmp/read_pile.js', 'w').write(js)
print('backticks balanced:', 'yes' if js.count('`') % 2 == 0 else 'NO')
print('script bytes:', len(js))
PY
node --check /tmp/read_pile.js
echo "syntax ok"

echo
echo "== engine unmodified =="
python3 - <<'PY'
import pathlib
shell = (pathlib.Path.home() /
         '.agents/skills/design-mockups/assets/shell.html').read_text()
mine = pathlib.Path('index.html').read_text()
cut = lambda s: s[s.find('   SECTION 5: ENGINE'):]
assert cut(shell) == cut(mine), 'ENGINE DIFFERS from the skill shell'
print('engine identical to shell.html (%d bytes)' % len(cut(mine)))
PY

echo
echo "== the pile's parts sum to ReadPile.extent =="
# The one number the CSS and the data both know. `--pile` defaults to 169 in
# frame.css and PILE_EXTENT is summed from its parts in data.js; if they ever
# disagree, the drawn card is the wrong height and nothing says so.
python3 - <<'PY'
import re
css = open('_build/frame.css').read()
m = re.search(r'\.fr \.pile\s*\{([^}]*)\}', css)
assert m, 'no .fr .pile rule'
d = re.search(r'--pile,\s*([\d.]+)px', m.group(1))
assert d and float(d.group(1)) == 169, (
    'frame.css defaults --pile to %s, expected 169' % (d and d.group(1)))
print('frame.css draws a 169pt pile by default')
PY

echo
echo "== the collapsed sheet clears the tab bar =="
# reserve(57) + viewPadding.bottom(34) - the card's own 14pt lift = 77.
# Drawn at 57 once, in the scan-to-add set, and the read pile's plank came
# out under the tab bar's platter -- the one thing bottomReserve promises
# cannot happen.
python3 - <<'PY'
import re
css = open('_build/frame.css').read()
m = re.search(r'\.fr \.card\s*\{([^}]*)\}', css)
assert m, 'no .fr .card rule'
pad = re.search(r'padding-bottom:\s*([\d.]+)px', m.group(1))
assert pad and float(pad.group(1)) == 77, (
    'collapsed card reserves %s, expected 77' % (pad and pad.group(1)))
print('collapsed card reserves 77pt (57 + 34 - 14)')
PY

echo
echo "== the turn pivots on the spine, not the centre =="
# Load-bearing, and named in the `el-faces` note: BookChassis passes
# `alignment: Alignment.center`, which at 90 degrees would slide the book half
# a cover width sideways through its neighbour. If this origin ever goes back
# to 50%, the drawing stops matching the note that explains it.
python3 - <<'PY'
import re
css = open('_build/frame.css').read()
m = re.search(r'\.bk \.in\s*\{([^}]*)\}', css)
assert m, 'no .bk .in rule'
origin = re.search(r'transform-origin:\s*([^;]+);', m.group(1))
assert origin and origin.group(1).strip() == '0 50%', (
    'the turn pivots at %s, expected the spine edge' % (origin and origin.group(1)))
print('the turn pivots at the spine edge (0 50%)')
PY

echo
echo "== the spine's fill has one source =="
# `.sp.tint { background: ... }` outspecifies `.sp` on class count, so a fill
# declared there wins over --bg and every tinted spine painted flat brand --
# the six swatches never appeared. The fill comes from --bg and nowhere else.
python3 - <<'PY'
import re
css = open('_build/frame.css').read()
m = re.search(r'\.sp\.tint\s*\{([^}]*)\}', css)
assert m, 'no .sp.tint rule'
assert 'background' not in m.group(1), (
    '.sp.tint declares a background again, which will outspecify --bg')
assert 'inset -1px' in m.group(1), (
    'the tinted spines lost their separating hairline')
base = re.search(r'^\.sp \{([^}]*)\}', css, re.M)
assert base and '--bg' in base.group(1), '.sp no longer fills from --bg'
print('the spine fill comes from --bg only, and tinted spines are separated')
PY

echo
echo "== the rotated title cannot be shrunk =="
# A flex item shrinks to its container by default, so without this the span
# was squeezed from the spine's height to its width before the rotation and
# every title ellipsized after three characters.
python3 - <<'PY'
import re
css = open('_build/frame.css').read()
m = re.search(r'\.sp b span\s*\{([^}]*)\}', css)
assert m, 'no .sp b span rule'
assert re.search(r'flex:\s*0 0 auto', m.group(1)), (
    'the rotated title can shrink again')
print('the rotated title is flex: 0 0 auto')
PY

echo
echo "== load under a DOM stub =="
cat _build/stub.js /tmp/read_pile.js > /tmp/read_pile_load.js
node /tmp/read_pile_load.js
echo "load ok (no top-level render errors)"

echo
echo "== assertions =="
cat _build/stub.js /tmp/read_pile.js _build/assert.js > /tmp/read_pile_assert.js
node /tmp/read_pile_assert.js
