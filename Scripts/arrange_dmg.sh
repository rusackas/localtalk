#!/bin/bash
# Arranges icons in a mounted DMG volume via Finder AppleScript.
# Usage: bash Scripts/arrange_dmg.sh <volume-name> <app-name>
set -e
VOL="$1"
APP="$2"

osascript << EOF
tell application "Finder"
  tell disk "${VOL}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 680, 380}
    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set position of item "${APP}" to {140, 130}
    set position of item "Applications" to {340, 130}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
