#!/bin/zsh
# Bygger NotchTodo.app, legger den i ~/Applications og starter den.
set -e
cd "$(dirname "$0")"

APP=build/NotchTodo.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 -target arm64-apple-macos14 Sources/**/*.swift -o "$APP/Contents/MacOS/NotchTodo"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>NotchTodo</string>
  <key>CFBundleIdentifier</key><string>no.davidpopovic.notchtodo</string>
  <key>CFBundleExecutable</key><string>NotchTodo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"

mkdir -p ~/Applications
pkill -x NotchTodo 2>/dev/null || true
rm -rf ~/Applications/NotchTodo.app
cp -R "$APP" ~/Applications/
open ~/Applications/NotchTodo.app
echo "NotchTodo kjører."
