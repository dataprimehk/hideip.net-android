#!/bin/sh
# Renders the launcher icon sources (assets/icon/*.png) from app-icon.html
# with headless Chrome, then regenerates every platform icon through
# flutter_launcher_icons. Run from anywhere; requires Chrome and Flutter.
set -eu

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
HTML="$REPO_DIR/scripts/app-icon.html"
OUT="$REPO_DIR/assets/icon"

shot() {
    "$CHROME" --headless --disable-gpu --force-device-scale-factor=1 \
        --window-size=1024,1024 --default-background-color=00000000 \
        --virtual-time-budget=4000 \
        --screenshot="$OUT/$2" "file://$HTML?v=$1" 2>/dev/null
    echo "rendered $OUT/$2"
}

shot full app_icon.png
shot fg app_icon_foreground.png
shot mono app_icon_monochrome.png

cd "$REPO_DIR"
dart run flutter_launcher_icons

# flutter_launcher_icons wraps the adaptive foreground/monochrome in a
# hard-coded 16% inset, shrinking the artwork to 68% before the mask.
# app-icon.html already positions everything against the real mask circle
# on the full 1024 canvas, so strip the inset.
LAUNCHER_XML="$REPO_DIR/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
sed -i '' 's/android:inset="16%"/android:inset="0%"/g' "$LAUNCHER_XML"
echo "stripped 16% inset from $LAUNCHER_XML"
