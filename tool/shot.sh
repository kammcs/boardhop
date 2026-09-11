#!/usr/bin/env bash
# Drives the Android emulator and saves a screenshot.
#
#   tool/shot.sh <name> [tap X Y | swipe X1 Y1 X2 Y2 MS | text "..." | back | wait S]...
#
# Coordinates are in 400-px-wide thumbnail space (the thumbnails this
# script writes), scaled by SCALE (default 3.2 for the 1280-px-wide phone
# AVD; use SCALE=2.5 with a 2000-px tablet size). Output goes to
# $SHOT_DIR (default: ./.shots, gitignored) as <name>.png and <name>_s.png.
# Needs adb on PATH or ANDROID_HOME set; the thumbnail needs Python with
# Pillow and is skipped when unavailable.
set -euo pipefail

SCALE="${SCALE:-3.2}"
SHOT_DIR="${SHOT_DIR:-.shots}"
if command -v adb >/dev/null 2>&1; then ADB=adb
elif [ -n "${ANDROID_HOME:-}" ]; then ADB="$ANDROID_HOME/platform-tools/adb"
elif [ -n "${LOCALAPPDATA:-}" ]; then ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
else ADB="$HOME/Library/Android/sdk/platform-tools/adb"; fi

name=$1; shift
mkdir -p "$SHOT_DIR"
px() { python -c "print(int(round($1 * $SCALE)))"; }
while [ $# -gt 0 ]; do
  case $1 in
    tap)   "$ADB" shell input tap "$(px "$2")" "$(px "$3")"; shift 3; sleep 1.5;;
    swipe) "$ADB" shell input swipe "$(px "$2")" "$(px "$3")" "$(px "$4")" "$(px "$5")" "$6"; shift 6; sleep 1;;
    text)  "$ADB" shell input text "$2"; shift 2; sleep 0.5;;
    back)  "$ADB" shell input keyevent 4; shift; sleep 1.5;;
    wait)  sleep "$2"; shift 2;;
    *) echo "unknown step: $1" >&2; exit 2;;
  esac
done
"$ADB" exec-out screencap -p > "$SHOT_DIR/$name.png"
python - "$SHOT_DIR/$name.png" "$SHOT_DIR/${name}_s.png" <<'EOF' 2>/dev/null || true
import sys
from PIL import Image
im = Image.open(sys.argv[1])
im.resize((400, int(im.height * 400 / im.width))).save(sys.argv[2])
EOF
echo "$SHOT_DIR/${name}_s.png"
