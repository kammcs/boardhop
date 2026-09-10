#!/usr/bin/env bash
# Spike F4 gesture battery. Drives the board probe page on the Android
# emulator (1280x2856, boardhop_pixel_10_pro) with the same interactions for
# every candidate, then presses "Copy report" so the numbers land in the
# `flutter run` log as an I/flutter line block.
#
# Usage: research/spikes/f4_drive.sh            # run the battery once
# Prerequisites: app running on the emulator with the board probe page open
# and the candidate already selected; the first column visible on the left.
set -euo pipefail
ADB="${ADB:-$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe}"
sh() { "$ADB" shell "$@"; }
ev() { sh input motionevent "$@"; }

echo "reset"
sh input tap 1024 240     # restart icon (reset data + stats)
sleep 1.5

echo "flings in the first column"
for i in 1 2 3; do sh input swipe 500 2400 500 900 120; sleep 0.8; done
for i in 1 2 3; do sh input swipe 500 900 500 2400 120; sleep 0.8; done
sleep 1

echo "drag 1: card to the right edge, hold for auto-scroll, drop mid-screen"
ev DOWN 500 1000; sleep 0.9
ev MOVE 520 1010; sleep 0.1
ev MOVE 800 1100; sleep 0.1
ev MOVE 1100 1200; sleep 0.1
ev MOVE 1240 1300; sleep 1.2
"$ADB" exec-out screencap -p > "${SHOTS:-.}/f4-mid-drag.png"
sleep 1.3
ev MOVE 900 1400; sleep 0.1
ev MOVE 640 1500; sleep 0.5
ev UP 640 1500
sleep 1.5

echo "scroll the board back to the first column"
for i in 1 2 3 4 5; do sh input swipe 200 2600 1200 2600 300; sleep 0.6; done
sleep 1
"$ADB" exec-out screencap -p > "${SHOTS:-.}/f4-after-scrollback.png"

echo "drag 2: adjacent cross-column drop, quick"
ev DOWN 500 1300; sleep 0.9
ev MOVE 520 1310; sleep 0.1
ev MOVE 800 1400; sleep 0.1
ev MOVE 1075 1500; sleep 0.3
ev UP 1075 1500
sleep 1.5

echo "drag 3: reorder within the first column, top card below the third"
ev DOWN 500 1000; sleep 0.9
ev MOVE 510 1020; sleep 0.1
ev MOVE 510 1400; sleep 0.1
ev MOVE 510 1900; sleep 0.4
ev UP 510 1900
sleep 1.5

echo "refresh + copy report"
sh input tap 920 240      # refresh icon
sleep 0.5
sh input tap 1180 240     # copy report icon
sleep 0.5
echo "done"
