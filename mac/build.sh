#!/usr/bin/env bash
# Dyna Capture (Mac) をビルドして .app に組み立てる
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Dyna Capture"
BIN_NAME="DynaCapture"
BUILD="build"
APP="$BUILD/$APP_NAME.app"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▶ コンパイル"
swiftc -O -target arm64-apple-macosx13.0 \
  -o "$APP/Contents/MacOS/$BIN_NAME" \
  Sources/*.swift \
  -framework AppKit -framework Carbon

echo "▶ アイコン"
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
SRC="../icon-512.png"
for s in 16 32 64 128 256 512; do
  sips -z $s $s "$SRC" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "▶ Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$BIN_NAME</string>
  <key>CFBundleIdentifier</key><string>io.github.inbox-tools.dynacapture</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>inbox-tools</string>
</dict>
</plist>
PLIST

echo "▶ 署名（アドホック）"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  署名は省略されました"

echo "▶ 設置"
DEST="$HOME/Applications"
mkdir -p "$DEST"
ditto "$APP" "$DEST/$APP_NAME.app"

# ビルド用の複製を残すと Alfred が2つ索引して「dyna」の候補を汚すので片付ける
rm -rf "$BUILD"

echo "✓ 設置しました: $DEST/$APP_NAME.app"
