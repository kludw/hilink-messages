#!/bin/bash
# Builds the app and wraps the binary in a .app bundle (no Xcode required).
# Usage: scripts/bundle.sh [--open]
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/HiLink Messages.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/HiLinkMessages"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/HiLinkMessages"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>HiLink Messages</string>
    <key>CFBundleDisplayName</key><string>HiLink Messages</string>
    <key>CFBundleIdentifier</key><string>local.hilink-messages</string>
    <key>CFBundleExecutable</key><string>HiLinkMessages</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSLocalNetworkUsageDescription</key><string>Connects to the Huawei LTE stick to send and receive text messages.</string>
    <key>NSContactsUsageDescription</key><string>Shows contact names and photos next to your text messages.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key><true/>
    </dict>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"

if [[ "${1:-}" == "--open" ]]; then
    open "$APP"
fi
