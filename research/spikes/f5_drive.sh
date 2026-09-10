#!/usr/bin/env bash
# Spike F5 gesture battery for the diff probe page on the Android emulator
# (1280x2856). Flings the diff, opens a gutter composer, jumps to a line
# through the dialog, then presses "Copy report" so the numbers land in the
# `flutter run` log.
#
# Usage: SHOTS=<dir> research/spikes/f5_drive.sh
# Prerequisites: the diff probe page is open with a diff loaded and the
# desired list implementation selected.
set -euo pipefail
ADB="${ADB:-$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe}"
sh() { "$ADB" shell "$@"; }
shot() { "$ADB" exec-out screencap -p > "${SHOTS:-.}/$1.png"; }

echo "refresh (resets nothing, just paints the strip)"
sh input tap 1062 240; sleep 0.8

echo "flings"
for i in 1 2 3; do sh input swipe 640 2500 640 900 120; sleep 1.0; done
for i in 1 2 3; do sh input swipe 640 900 640 2500 120; sleep 1.0; done
sleep 0.5

echo "gutter tap opens a composer"
sh input tap 80 1300; sleep 1.2
shot f5-composer

echo "jump to line via the dialog (Enter submits the prefilled value)"
sh input tap 918 240; sleep 1.2
sh input keyevent 66; sleep 1.5
shot f5-after-jump

echo "refresh + copy report"
sh input tap 1062 240; sleep 0.5
sh input tap 1206 240; sleep 0.5
echo done
