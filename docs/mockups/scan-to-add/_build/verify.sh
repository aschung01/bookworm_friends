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
open('/tmp/scan_to_add.js', 'w').write(js)
print('backticks balanced:', 'yes' if js.count('`') % 2 == 0 else 'NO')
print('script bytes:', len(js))
PY
node --check /tmp/scan_to_add.js
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
echo "== no stray coordinates in frame.css =="
# LAY in data.js owns the scanner's vertical layout. A `top:` reappearing on
# one of those selectors is a second source of truth for the same number.
python3 - <<'PY'
import re
css = open('_build/frame.css').read()
bad = []
for sel in ('.fr .stop', '.fr .retic', '.fr .isbn',
            '.fr .shint', '.fr .nudge', '.fr .shut', '.fr .slab',
            '.fr .card', '.fr .subj', '.fr .eanwrap'):
    m = re.search(re.escape(sel) + r'\s*\{([^}]*)\}', css)
    if m and re.search(r'(^|\s)top:', m.group(1)):
        bad.append(sel)
assert not bad, 'top: duplicated from LAY on ' + ', '.join(bad)
print('scanner tops live only in LAY')
PY

echo
echo "== the collapsed sheet clears the tab bar =="
# reserve(57) + viewPadding.bottom(34) - the card's own 14pt lift = 77.
# Drawn at 57 once, and the read pile's plank came out under the tab bar's
# platter -- the one thing bottomReserve promises cannot happen.
python3 - <<'PY'
import re
css = open('_build/frame.css').read()
m = re.search(r'\.fr \.lsheet\s*\{([^}]*)\}', css)
assert m, 'no .fr .lsheet rule'
pad = re.search(r'padding-bottom:\s*([\d.]+)px', m.group(1))
assert pad and float(pad.group(1)) == 77, (
    'collapsed sheet reserves %s, expected 77' % (pad and pad.group(1)))
print('collapsed sheet reserves 77pt (57 + 34 - 14)')
PY

echo
echo "== load under a DOM stub =="
cat _build/stub.js /tmp/scan_to_add.js > /tmp/scan_to_add_load.js
node /tmp/scan_to_add_load.js
echo "load ok (no top-level render errors)"

echo
echo "== assertions =="
cat _build/stub.js /tmp/scan_to_add.js _build/assert.js > /tmp/scan_to_add_assert.js
node /tmp/scan_to_add_assert.js
