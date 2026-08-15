#!/bin/sh
# Rebuilds the standalone mockup pages from the fragments in this directory.
#
# The screens were authored as HTML fragments for the brainstorming companion,
# which supplied the surrounding document, base CSS and the toggleSelect helper.
# This wraps each fragment in _head.html / _foot.html so it opens directly in a
# browser, styled by ../shared.css.
#
# Usage:  sh docs/mockups/library-shell/_src/build.sh
set -e
cd "$(dirname "$0")"
OUT=..

for f in nav-architecture friends-tab read-view app-states three-directions \
         encased-variants stripped-chrome one-world bar-owns-identity \
         capsule-tabs friend-transition; do
  cat _head.html "$f.html" _foot.html > "$OUT/$f.html"
  echo "built $f.html"
done
