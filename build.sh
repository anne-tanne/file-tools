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
# Finder quick actions (macOS Services handled by the running app, see Services.swift)
IMG="public.image"; PDF="com.adobe.pdf"
WORD="org.openxmlformats.wordprocessingml.document com.microsoft.word.doc public.rtf org.oasis-open.opendocument.text"
SERVICES=""
service() {   # title, message, UTIs...
    local title="$1" msg="$2"; shift 2
    local types=""; for t in "$@"; do types+="<string>$t</string>"; done
    SERVICES+="<dict><key>NSMenuItem</key><dict><key>default</key><string>$title</string></dict><key>NSMessage</key><string>$msg</string><key>NSPortName</key><string>File Tools</string><key>NSRequiredContext</key><dict/><key>NSSendFileTypes</key><array>$types</array></dict>"
}
service "Compress with File Tools" compress $IMG $PDF
service "Remove Info with File Tools" removeInfo $IMG $PDF
service "Add Watermark with File Tools" watermark $IMG $PDF
service "Make Searchable with File Tools" makeSearchable $PDF $IMG
service "Recognize Text with File Tools" recognizeText $IMG $PDF
service "Convert Word to PDF with File Tools" wordToPDF $=WORD
service "Run File Tools Preset…" runPreset $IMG $PDF $=WORD
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
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>de</string><string>fr</string></array>
<key>NSAppleEventsUsageDescription</key><string>File Tools asks Microsoft Word to save your Word documents as PDF.</string>
<key>NSServices</key><array>$SERVICES</array>
</dict></plist>
PLIST
# The app's own texts are translated in L10n.swift; these folders only tell macOS which languages
# exist, so its own menus (Edit, Window, …) and the permission prompt follow the chosen language
mkdir -p "$APP/Contents/Resources/"{en,de,fr}.lproj
echo '"NSAppleEventsUsageDescription" = "File Tools bittet Microsoft Word, Ihre Word-Dokumente als PDF zu sichern.";' \
    > "$APP/Contents/Resources/de.lproj/InfoPlist.strings"
echo '"NSAppleEventsUsageDescription" = "File Tools demande à Microsoft Word d’enregistrer vos documents Word en PDF.";' \
    > "$APP/Contents/Resources/fr.lproj/InfoPlist.strings"
codesign --force --sign - "$APP"
echo built
