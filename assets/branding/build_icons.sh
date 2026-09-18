#!/bin/sh
# Builds the Libstack icon masters, then regenerates every platform icon.
#
# app_icon_source.png is the source of truth: the chalk artwork, on its
# as-generated background. build_master.py derives an alpha channel from it and
# emits the five masters; flutter_launcher_icons fans those out to the
# platforms. Never hand-edit the masters, or anything under ios/, android/,
# web/, macos/ or windows/.
#
# Requires: Pillow. If .venv/ does not exist this script creates it.
set -e
cd "$(dirname "$0")"

# Absolute, because this script later cd's to the repo root.
VENV=$(cd ../.. && pwd)/.venv
if [ ! -x "$VENV/bin/python" ]; then
  echo "==> creating .venv and installing Pillow"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --disable-pip-version-check Pillow
fi

echo "==> building masters from app_icon_source.png"
"$VENV/bin/python" build_master.py

echo "==> generating platform icons"
cd ../..
dart run flutter_launcher_icons

# flutter_launcher_icons copies the full-bleed icon into the manifest's
# `purpose: maskable` slots, but a maskable icon can be cropped to a circle of
# 80% of the canvas, which would clip the mark. Overwrite with the inset
# variant build_master.py produced for exactly this.
echo "==> overwriting web maskable icons with the safe-zone variant"
"$VENV/bin/python" - <<'PY'
from PIL import Image
src = Image.open("assets/branding/app_icon_maskable.png")
for size in (192, 512):
    src.resize((size, size), Image.LANCZOS).save(f"web/icons/Icon-maskable-{size}.png")
# The generator emits no favicon at all.
Image.open("assets/branding/app_icon.png").resize((32, 32), Image.LANCZOS).save("web/favicon.png")
PY

echo
echo "Done. Check assets/branding/_mask_preview.png (Android masks) and"
echo "assets/branding/_dark_preview.png (iOS dark/tinted) before committing."
