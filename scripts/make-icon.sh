#!/bin/bash
# Sinh assets/AppIcon.icns và assets/AppIcon-1024.png từ scripts/make-icon.swift
set -e
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swift scripts/make-icon.swift "$TMP/png"
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET" assets
for f in icon_16x16 icon_16x16@2x icon_32x32 icon_32x32@2x icon_128x128 icon_128x128@2x \
         icon_256x256 icon_256x256@2x icon_512x512 icon_512x512@2x; do
  cp "$TMP/png/$f.png" "$SET/$f.png"
done
iconutil -c icns "$SET" -o assets/AppIcon.icns
cp "$TMP/png/icon_1024.png" assets/AppIcon-1024.png
echo "▸ assets/AppIcon.icns + assets/AppIcon-1024.png"
