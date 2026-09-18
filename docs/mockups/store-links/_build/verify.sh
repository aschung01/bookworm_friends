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
open('/tmp/store_links.js', 'w').write(js)
print('backticks balanced:', 'yes' if js.count('`') % 2 == 0 else 'NO')
print('script bytes:', len(js))
PY
node --check /tmp/store_links.js
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
echo "== load under a DOM stub =="
cat _build/stub.js /tmp/store_links.js > /tmp/store_links_load.js
node /tmp/store_links_load.js
echo "load ok (no top-level render errors)"

echo
echo "== assertions =="
cat _build/stub.js /tmp/store_links.js _build/assert.js > /tmp/store_links_assert.js
node /tmp/store_links_assert.js
