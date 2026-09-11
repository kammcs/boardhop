#!/usr/bin/env bash
# Drives an iOS simulator and saves a screenshot. Companion of shot.sh.
#
#   tool/shot-ios.sh <name> [tap X Y | swipe X1 Y1 X2 Y2 MS | text "..." | back | home | wait S]...
#
# Coordinates are in 400-px-wide thumbnail space (the thumbnails this
# script writes) and are converted to points from the device's own
# dimensions, so the same numbers work for any simulator. Pick the
# simulator with DEVICE=iphone|ipad (default iphone) or UDID=<udid>.
# Output goes to $SHOT_DIR (default: ./.shots, gitignored) as <name>.png
# and <name>_s.png.
#
# Needs Meta's idb (brew install facebook/fb/idb-companion; pip install
# fb-idb, this script looks in ~/.venvs/idb) for input, and xcrun simctl
# for screenshots. The thumbnail needs Python 3 with Pillow.
set -euo pipefail

SHOT_DIR="${SHOT_DIR:-.shots}"
THUMB_W="${THUMB_W:-400}"
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

# Points width from the screenshot size and the device scale factor.
name=$1; shift
mkdir -p "$SHOT_DIR"
if [ -z "${SCALE:-}" ]; then
  SCALE=$("$IDB" describe --udid "$UDID" --json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)['screen_dimensions']
print(d['width']/d['density']/$THUMB_W)")
fi
px() { python3 -c "print(int(round($1 * $SCALE)))"; }
while [ $# -gt 0 ]; do
  case $1 in
    tap)   "$IDB" ui tap --udid "$UDID" "$(px "$2")" "$(px "$3")"; shift 3; sleep 1.5;;
    swipe) "$IDB" ui swipe --udid "$UDID" --duration "$(python3 -c "print($6/1000)")" "$(px "$2")" "$(px "$3")" "$(px "$4")" "$(px "$5")"; shift 6; sleep 1;;
    text)  "$IDB" ui text --udid "$UDID" "$2"; shift 2; sleep 0.5;;
    back)  "$IDB" ui swipe --udid "$UDID" --duration 0.3 2 "$(px 300)" "$(px 300)" "$(px 300)"; shift; sleep 1.5;;
    home)  "$IDB" ui button --udid "$UDID" HOME; shift; sleep 1.5;;
    wait)  sleep "$2"; shift 2;;
    *) echo "unknown step: $1" >&2; exit 2;;
  esac
done
xcrun simctl io "$UDID" screenshot "$SHOT_DIR/$name.png" >/dev/null
python3 - "$SHOT_DIR/$name.png" "$SHOT_DIR/${name}_s.png" "$THUMB_W" <<'EOF' 2>/dev/null || true
import sys
from PIL import Image
im = Image.open(sys.argv[1])
w = int(sys.argv[3])
im.resize((w, int(im.height * w / im.width))).save(sys.argv[2])
EOF
echo "$SHOT_DIR/${name}_s.png"
