#!/bin/bash
# Build Pinax.app (SwiftPM release), ad-hoc sign, và (tuỳ chọn) đóng gói .dmg
set -e
cd "$(dirname "$0")"

APP="Pinax.app"
BIN="$APP/Contents/MacOS/Pinax"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

echo "▸ Biên dịch Pinax ${VERSION} (${BUILD}) – release, arm64…"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

echo "▸ Dọn build cũ…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ Ghi Info.plist…"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Pinax</string>
  <key>CFBundleDisplayName</key><string>Pinax</string>
  <key>CFBundleIdentifier</key><string>com.duchuynguyen93.pinax</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleExecutable</key><string>Pinax</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict></plist>
PLIST

cp "$BIN_DIR/Pinax" "$BIN"

if [ -f assets/AppIcon.icns ]; then
  cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

echo "▸ Ký ad-hoc…"
codesign --force --deep --sign - "$APP"

echo "▸ Kiến trúc: $(lipo -archs "$BIN")"
echo "▸ Xong: $APP"

if [ "$1" = "dmg" ]; then
  NAME="Pinax-${VERSION}-arm64"
  echo "▸ Đóng gói DMG + ZIP…"
  rm -rf dist && mkdir -p dist/stage
  cp -R "$APP" dist/stage/
  ln -s /Applications dist/stage/Applications
  hdiutil create -volname "Pinax" -srcfolder dist/stage \
    -ov -format UDZO "dist/${NAME}.dmg" >/dev/null
  rm -rf dist/stage
  ditto -c -k --keepParent "$APP" "dist/${NAME}.zip"
  (cd dist && shasum -a 256 "${NAME}.dmg" "${NAME}.zip" > SHA256SUMS.txt)
  echo "▸ DMG: dist/${NAME}.dmg"
  echo "▸ ZIP: dist/${NAME}.zip"
  echo "▸ SHA-256:"
  cat dist/SHA256SUMS.txt
fi
