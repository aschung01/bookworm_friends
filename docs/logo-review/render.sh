#!/bin/sh
# Renders every numbered candidate SVG in this directory at 1024 (full size) and
# 48 (home-screen squint test, upscaled 6x so the pixel grid is visible).
#
# The glob covers any <letter><digit>*.svg, so new rounds do not need this
# script edited -- it previously matched only v* and s*, which silently skipped
# the n* round.
set -e
cd "$(dirname "$0")"
mkdir -p out
for f in [a-z][0-9]*.svg; do
  name="${f%.svg}"
  rsvg-convert -w 1024 -h 1024 "$f" -o "out/$name-1024.png"
  rsvg-convert -w 48 -h 48 "$f" -o "out/.$name-48.png"
  sips -Z 288 "out/.$name-48.png" --out "out/$name-at48px.png" >/dev/null
  rm "out/.$name-48.png"
done
echo "rendered: $(ls out | wc -l | tr -d ' ') files"
