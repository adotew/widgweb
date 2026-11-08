#!/bin/sh
# Builds an arm64 widgweb.app and packs it into dist/widgweb-<version>.dmg.
set -eu
cd "$(dirname "$0")/.."

VERSION="${1:-0.0.0}"
APP=dist/widgweb.app

swift build -c release --arch arm64
rm -rf dist && mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --arch arm64 --show-bin-path)/widgweb" "$APP/Contents/MacOS/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>widgweb</string>
    <key>CFBundleIdentifier</key><string>com.adotew.widgweb</string>
    <key>CFBundleExecutable</key><string>widgweb</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

# Ad-hoc signature: required to run on Apple Silicon; not notarized.
codesign --force --sign - "$APP"

mkdir dist/dmg
mv "$APP" dist/dmg/
ln -s /Applications dist/dmg/Applications
hdiutil create -volname widgweb -srcfolder dist/dmg -format UDZO -ov "dist/widgweb-$VERSION.dmg"
rm -rf dist/dmg
