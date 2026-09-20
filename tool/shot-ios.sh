#!/usr/bin/env bash
# Drives an iOS simulator and saves a screenshot. Companion of shot.sh.
#
#   tool/shot-ios.sh <name> [tap X Y | press "label" | swipe X1 Y1 X2 Y2 MS |
#                            text "..." | back | home | wait S]...
#
# Coordinates are in thumbnail space: the thumbnails this script writes
# are THUMB_W (default 400) px wide in portrait, and they are converted
# to points from the device's own dimensions, so the same numbers work
# for any simulator. Pick the simulator with DEVICE=iphone|ipad|duo
# (default iphone) or UDID=<udid>; `iphone` never matches an iPhone Duo,
# so a Duo booted beside an iPhone 17 is unambiguous. When the device is
# rotated, set ROT=left (home indicator on the right, Dynamic Island /
# status bar along the raw frame's left edge, so the island shows on the
# right) or ROT=right (the other way round, island on the left): the
# thumbnail is then rotated to read normally and coordinates are taken in
# that rotated space; simctl screenshots and idb taps both stay in the raw
# portrait frame, which this script maps back. Output goes to
# $SHOT_DIR (default: ./.shots, gitignored) as <name>.png (raw frame) and
# <name>_s.png (thumbnail, rotated when ROT is set).
#
# **iPhone Duo (DEVICE=duo).** The Duo has two panels and
# `simctl io … screenshot` needs to be told which: DISPLAY=inner (default,
# `--display=3`, 951 x 669 pt) or DISPLAY=outer (the cover, `--display=1`,
# 466 x 678 pt). The panel that is not active captures as solid black.
# Screenshots follow the rotation on this device (after one Rotate Right
# the inner panel captures 2007 x 2853, not 2853 x 2007), unlike the
# iPhone 17 whose raw frame stays portrait-native, so the frame size is
# read from the image itself and the **thumbnail is never rotated** here:
# it already reads the right way up. ROT is therefore only a tap mapping
# on the Duo, and it is `left` after one `tool/duo-pose rotate`
# (verified 2026-09-20). Fold and rotate the Duo with
# `tool/duo-pose closed|book|open|rotate`.
#
# **Driving the Duo:** idb's HID taps only reach the *cover* panel (idb
# describes the Duo as a 466 x 678 device and coordinate taps on the inner
# panel land nowhere; verified 2026-09-20, research/23 §9). Use `press
# "<label>"` there, which taps through idb's accessibility backend and
# does reach the inner panel; the label is matched against AXLabel, so it
# is the widget's semantics label ("Summary", "Work", "Diagnostics").
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

booted() { xcrun simctl list devices booted; }

if [ -z "${UDID:-}" ]; then
  case "${DEVICE:-iphone}" in
    # An iPhone Duo is an iPhone by name, so `iphone` excludes it on
    # purpose: both can be booted at once.
    iphone) pattern='iPhone'; reject='iPhone Duo';;
    ipad)   pattern='iPad';   reject='';;
    duo)    pattern='iPhone Duo'; reject='';;
    *) pattern="$DEVICE"; reject='';;
  esac
  line=$(booted | grep "$pattern" | { [ -n "$reject" ] && grep -v "$reject" || cat; } | head -1)
  UDID=$(printf '%s' "$line" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  [ -n "$UDID" ] || { echo "no booted simulator matches $pattern" >&2; exit 2; }
fi

# The Duo is handled by name, so an explicit UDID gets the same treatment.
DUO=0
case "$(booted | grep "$UDID" || true)" in *"iPhone Duo"*) DUO=1;; esac

# Which panel simctl captures. Only the Duo takes the flag at all, so a
# DISPLAY left over from X11 cannot affect any other device.
SHOT_ARGS=()
if [ "$DUO" = 1 ]; then
  case "${DISPLAY:-inner}" in
    outer|cover|1) SHOT_ARGS=(--display=1);;
    *)             SHOT_ARGS=(--display=3);;
  esac
fi

name=$1; shift
mkdir -p "$SHOT_DIR"
shoot() { xcrun simctl io "$UDID" screenshot "${SHOT_ARGS[@]}" "$1" >/dev/null 2>&1; }

if [ "$DUO" = 1 ]; then
  # The Duo's frame follows both the pose and the rotation, and idb
  # describes only the cover, so read the frame from the image. @3x.
  probe="$SHOT_DIR/.$name.probe.png"
  shoot "$probe"
  read -r W_PTS H_PTS < <(python3 -c "
from PIL import Image
im = Image.open('$probe')
print(im.width / 3, im.height / 3)")
  rm -f "$probe"
else
  # Raw (portrait) frame size in points, and the thumbnail scale.
  read -r W_PTS H_PTS < <("$IDB" describe --udid "$UDID" --json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)['screen_dimensions']
print(d['width']/d['density'], d['height']/d['density'])")
fi
SCALE="${SCALE:-$(python3 -c "print($W_PTS/$THUMB_W)")}"
# On the Duo the raw frame already follows the rotation, so ROT rotates
# nothing in the thumbnail; it only maps taps back into idb's frame.
THUMB_ROT="$ROT"
RAW_W="$W_PTS"; RAW_H="$H_PTS"
if [ "$DUO" = 1 ]; then
  THUMB_ROT=""
  # idb still speaks the portrait frame (466 x 678) even when the image
  # has turned, so the mapping below needs the unrotated size.
  if [ -n "$ROT" ]; then RAW_W="$H_PTS"; RAW_H="$W_PTS"; fi
fi
# Thumbnail coordinates -> raw frame points, honouring ROT.
conv() {
  python3 -c "
x, y = $1 * $SCALE, $2 * $SCALE
if '$ROT' == 'left':
    x, y = y, $RAW_H - x
elif '$ROT' == 'right':
    x, y = $RAW_W - y, x
print(int(round(x)), int(round(y)))"
}
tap() { read -r x y < <(conv "$1" "$2"); "$IDB" ui tap --api hid --udid "$UDID" "$x" "$y"; }
swipe() {
  read -r x1 y1 < <(conv "$1" "$2"); read -r x2 y2 < <(conv "$3" "$4")
  "$IDB" ui swipe --udid "$UDID" --duration "$(python3 -c "print($5/1000)")" "$x1" "$y1" "$x2" "$y2"
}
while [ $# -gt 0 ]; do
  case $1 in
    tap)   tap "$2" "$3"; shift 3; sleep 1.5;;
    press) "$IDB" ui tap --api ax --udid "$UDID" "$2"; shift 2; sleep 1.5;;
    swipe) swipe "$2" "$3" "$4" "$5" "$6"; shift 6; sleep 1;;
    text)  "$IDB" ui text --udid "$UDID" "$2"; shift 2; sleep 0.5;;
    back)  swipe 1 200 200 200 300; shift; sleep 1.5;;
    home)  "$IDB" ui button --udid "$UDID" HOME; shift; sleep 1.5;;
    wait)  sleep "$2"; shift 2;;
    *) echo "unknown step: $1" >&2; exit 2;;
  esac
done
shoot "$SHOT_DIR/$name.png"
python3 - "$SHOT_DIR/$name.png" "$SHOT_DIR/${name}_s.png" "$THUMB_W" "$THUMB_ROT" <<'EOF' 2>/dev/null || true
import sys
from PIL import Image
im = Image.open(sys.argv[1])
w = int(sys.argv[3])
im = im.resize((w, int(im.height * w / im.width)))
if sys.argv[4] == 'left':
    im = im.rotate(-90, expand=True)
elif sys.argv[4] == 'right':
    im = im.rotate(90, expand=True)
im.save(sys.argv[2])
EOF
echo "$SHOT_DIR/${name}_s.png"
