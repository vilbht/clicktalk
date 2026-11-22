#!/bin/bash
# Packs EucLink.app into a disk image that opens to a drag-to-Applications window.
# Needs macOS, a built EucLink.app (./build.sh ci) and dmgbuild, which this script
# installs into a private virtual environment on first use.
#
#   dmg/make.sh EucLink.dmg
#
# The background is dmg/background.png and @2x, rendered from dmg/background.html.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-EucLink.dmg}"
[ -d EucLink.app ] || { echo "EucLink.app not found. Run ./build.sh ci first."; exit 1; }

VENV="${TMPDIR:-/tmp}/euclink-dmgbuild"
if [ ! -x "$VENV/bin/dmgbuild" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet "dmgbuild>=1.6,<2"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# One TIFF holding both resolutions, so Retina screens get the sharp version.
tiffutil -cathidpicheck dmg/background.png dmg/background@2x.png -out "$WORK/background.tiff"

rm -f "$OUT"
"$VENV/bin/dmgbuild" -s dmg/settings.py -D app=EucLink.app -D background="$WORK/background.tiff" \
  "EucLink" "$OUT"
echo "Disk image: $OUT"
