#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP="File Tools.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library Sources/*.swift -o "$APP/Contents/MacOS/FileTools"
# Layered Liquid Glass icon (AppIcon.icon, made by icon_layers.swift) needs Xcode's actool;
# without it, fall back to the flat AppIcon.icns
if xcrun --find actool >/dev/null 2>&1; then
    xcrun actool AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
        --minimum-deployment-target 26.0 --app-icon AppIcon \
        --output-partial-info-plist /dev/null >/dev/null
else
    cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>File Tools</string>
<key>CFBundleDisplayName</key><string>File Tools</string>
<key>CFBundleIdentifier</key><string>local.filetools</string>
<key>CFBundleExecutable</key><string>FileTools</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIconName</key><string>AppIcon</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo built
