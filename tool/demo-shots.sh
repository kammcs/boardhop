#!/usr/bin/env bash
# Store screenshots from the demo build (BOARDHOP_DEMO, lib/demo): no sign-in,
# no network, invented data about Boardhop building itself.
#
#   tool/demo-shots.sh <udid> <out-dir> <name>=<route>[@wait] ...
#
# The demo build must already be installed on the simulator, e.g.
#   flutter run -d <udid> --dart-define=BOARDHOP_DEMO=true
# (a debug simulator build keeps running on its own after `flutter run` quits).
#
# For every shot the app is relaunched with its route file set (a path
# below /a/{account}/orgs/kammcs/, e.g. projects/Boardhop/boards), left
# alone for <wait> seconds (default 6) and captured at the device's native
# resolution to <out-dir>/<name>.png. The status bar is set to Apple's
# marketing look first. Orientation and appearance are the simulator's: set
# them before calling (idb ui rotate, xcrun simctl ui <udid> appearance).
set -euo pipefail

UDID="$1"; OUT="$2"; shift 2
BUNDLE=com.kammcs.boardhop
mkdir -p "$OUT"
DOCS="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)/Documents"
mkdir -p "$DOCS"

xcrun simctl status_bar "$UDID" override --time 9:41 \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 \
  --batteryState discharging --batteryLevel 100 >/dev/null 2>&1 || true

for spec in "$@"; do
  name="${spec%%=*}"
  rest="${spec#*=}"
  route="${rest%@*}"
  wait=6
  [ "$rest" != "$route" ] && wait="${rest##*@}"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  printf '%s' "$route" > "$DOCS/boardhop_demo_route"
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1
  echo "$OUT/$name.png"
done
rm -f "$DOCS/boardhop_demo_route"
