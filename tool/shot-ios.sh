#!/usr/bin/env bash
# Drives an iOS simulator and saves a screenshot. Companion of shot.sh.
#
#   tool/shot-ios.sh <name> [tap X Y | swipe X1 Y1 X2 Y2 MS | text "..." | back | home | wait S]...
#
# Coordinates are in thumbnail space: the thumbnails this script writes
# are THUMB_W (default 400) px wide in portrait, and they are converted
# to points from the device's own dimensions, so the same numbers work
# for any simulator. Pick the simulator with DEVICE=iphone|ipad (default
# iphone) or UDID=<udid>. When the device is rotated, set ROT=left (home
# indicator on the right, status bar along the raw frame's left edge):
# the thumbnail is then rotated to read normally and coordinates are
# taken in that rotated space; simctl screenshots and idb taps both stay
# in the raw portrait frame, which this script maps back. Output goes to
# $SHOT_DIR (default: ./.shots, gitignored) as <name>.png (raw frame) and
# <name>_s.png (thumbnail, rotated when ROT is set).
#
# Needs Meta's idb (brew install facebook/fb/idb-companion; pip install
# fb-idb, this script looks in ~/.venvs/idb) for input, and xcrun simctl
# for screenshots. The thumbnail needs Python 3 with Pillow.
set -euo pipefail

SHOT_DIR="${SHOT_DIR:-.shots}"
THUMB_W="${THUMB_W:-400}"
ROT="${ROT:-}"
IDB="${IDB:-$HOME/.venvs/idb/bin/idb}"
[ -x "$IDB" ] || IDB=idb

if [ -z "${UDID:-}" ]; then
  case "${DEVICE:-iphone}" in
    iphone) pattern='iPhone';;
    ipad)   pattern='iPad';;
    *) pattern="$DEVICE";;
  esac
  UDID=$(xcrun simctl list devices booted | grep "$pattern" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  [ -n "$UDID" ] || { echo "no booted simulator matches $pattern" >&2; exit 2; }
fi

name=$1; shift
mkdir -p "$SHOT_DIR"
# Raw (portrait) frame size in points, and the thumbnail scale.
read -r W_PTS H_PTS < <("$IDB" describe --udid "$UDID" --json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)['screen_dimensions']
print(d['width']/d['density'], d['height']/d['density'])")
SCALE="${SCALE:-$(python3 -c "print($W_PTS/$THUMB_W)")}"
# Thumbnail coordinates -> raw frame points, honouring ROT.
conv() {
  python3 -c "
x, y = $1 * $SCALE, $2 * $SCALE
if '$ROT' == 'left':
    x, y = y, $H_PTS - x
print(int(round(x)), int(round(y)))"
}
tap() { read -r x y < <(conv "$1" "$2"); "$IDB" ui tap --udid "$UDID" "$x" "$y"; }
swipe() {
  read -r x1 y1 < <(conv "$1" "$2"); read -r x2 y2 < <(conv "$3" "$4")
  "$IDB" ui swipe --udid "$UDID" --duration "$(python3 -c "print($5/1000)")" "$x1" "$y1" "$x2" "$y2"
}
while [ $# -gt 0 ]; do
  case $1 in
    tap)   tap "$2" "$3"; shift 3; sleep 1.5;;
    swipe) swipe "$2" "$3" "$4" "$5" "$6"; shift 6; sleep 1;;
    text)  "$IDB" ui text --udid "$UDID" "$2"; shift 2; sleep 0.5;;
    back)  swipe 1 200 200 200 300; shift; sleep 1.5;;
    home)  "$IDB" ui button --udid "$UDID" HOME; shift; sleep 1.5;;
    wait)  sleep "$2"; shift 2;;
    *) echo "unknown step: $1" >&2; exit 2;;
  esac
done
xcrun simctl io "$UDID" screenshot "$SHOT_DIR/$name.png" >/dev/null 2>&1
python3 - "$SHOT_DIR/$name.png" "$SHOT_DIR/${name}_s.png" "$THUMB_W" "$ROT" <<'EOF' 2>/dev/null || true
import sys
from PIL import Image
im = Image.open(sys.argv[1])
w = int(sys.argv[3])
im = im.resize((w, int(im.height * w / im.width)))
if sys.argv[4] == 'left':
    im = im.rotate(-90, expand=True)
im.save(sys.argv[2])
EOF
echo "$SHOT_DIR/${name}_s.png"
