#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
configuration="${1:-debug}"
/bin/zsh scripts/swift-local.sh build -c "$configuration"
binary_dir="$(/bin/zsh scripts/swift-local.sh build -c "$configuration" --show-bin-path)"
app_dir="$project_dir/build/File Converter.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/FileConverter" "$app_dir/Contents/MacOS/.FileConverter.next"
mv -f "$app_dir/Contents/MacOS/.FileConverter.next" "$app_dir/Contents/MacOS/FileConverter"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.local.file-converter</string>
<key>CFBundleName</key><string>File Converter</string>
<key>CFBundleDisplayName</key><string>File Converter</string>
<key>CFBundleExecutable</key><string>FileConverter</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir"
print -r -- "$app_dir"
