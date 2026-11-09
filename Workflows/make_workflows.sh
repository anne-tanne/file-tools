#!/bin/zsh
# Builds a Finder Quick Action (.workflow) from each *.zsh script here: the script runs in a "Run Shell Script"
# action with the selected files as arguments. Install on a Mac by double-clicking the .workflow.
set -e
cd "$(dirname "$0")"
for script in *.zsh; do
    title=$(sed -n 's/^# \(.*\): Finder Quick Action.*/\1/p' "$script")
    wf="${script:r}.workflow"
    rm -rf "$wf"; mkdir -p "$wf/Contents"
    cp template.wflow "$wf/Contents/document.wflow"
    plutil -replace actions.0.action.ActionParameters.COMMAND_STRING -string "$(<"$script")" "$wf/Contents/document.wflow"
    plutil -convert xml1 "$wf/Contents/document.wflow"
    cat > "$wf/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>NSServices</key><array><dict>
<key>NSIconName</key><string>NSActionTemplate</string>
<key>NSMenuItem</key><dict><key>default</key><string>$title</string></dict>
<key>NSMessage</key><string>runWorkflowAsService</string>
<key>NSRequiredContext</key><dict><key>NSApplicationIdentifier</key><string>com.apple.finder</string></dict>
<key>NSSendFileTypes</key><array><string>public.folder</string><string>com.adobe.pdf</string><string>public.image</string></array>
</dict></array></dict></plist>
PLIST
    rm -f "${script:r}.zip"
    ditto -c -k --keepParent "$wf" "${script:r}.zip"
    echo "built $wf"
done
