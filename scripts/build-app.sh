#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
source "$project_dir/scripts/signing-config.sh"
configuration="${1:-debug}"
case "$configuration" in
  debug) xcode_configuration=Debug ;;
  release) xcode_configuration=Release ;;
  *) print -u2 "Choose debug or release"; exit 2 ;;
esac
identity="${CONVERTER_SIGN_IDENTITY:--}"
# macOS container ACLs distinguish ad-hoc and Developer ID identities. Keep
# development scratch data separate from the signed production worker.
worker_service="io.local.file-converter.worker.development"
if [[ "$identity" != "-" ]]; then worker_service="io.local.file-converter.worker.production"; fi
/bin/zsh scripts/swift-local.sh build -c "$configuration"
binary_dir="$(/bin/zsh scripts/swift-local.sh build -c "$configuration" --show-bin-path)"
xcode_arguments=(-quiet -project FileConverter.xcodeproj -scheme FileConverter -configuration "$xcode_configuration" -destination "platform=macOS,arch=arm64" -derivedDataPath build/Xcode -clonedSourcePackagesDirPath build/Packages "CODE_SIGN_IDENTITY=$identity" CODE_SIGN_STYLE=Manual "CONVERTER_WORKER_SERVICE_IDENTIFIER=$worker_service")
if [[ -n "${CONVERTER_DEVELOPMENT_TEAM:-}" ]]; then xcode_arguments+=("DEVELOPMENT_TEAM=$CONVERTER_DEVELOPMENT_TEAM"); fi
xcodebuild "${xcode_arguments[@]}" build
app_dir="$project_dir/build/File Converter.app"
next_dir="$project_dir/build/File Converter.next.app"
rm -rf "$next_dir"
ditto "$project_dir/build/Xcode/Build/Products/$xcode_configuration/File Converter.app" "$next_dir"
cp "$binary_dir/convert-file" "$next_dir/Contents/MacOS/convert-file"
cp "$binary_dir/converter-worker" "$next_dir/Contents/MacOS/converter-worker"
test -f "$next_dir/Contents/Resources/EngineCatalog.json"
test -f "$next_dir/Contents/Resources/ThirdParty/libwebp-COPYING.txt"
signing_arguments=(--force --options runtime --sign "$identity")
if [[ "$identity" != "-" ]]; then signing_arguments+=(--timestamp); fi
codesign "${signing_arguments[@]}" "$next_dir/Contents/MacOS/convert-file"
codesign "${signing_arguments[@]}" "$next_dir/Contents/MacOS/converter-worker"
codesign "${signing_arguments[@]}" --entitlements Configuration/Worker.entitlements "$next_dir/Contents/XPCServices/ConversionWorker.xpc"
codesign "${signing_arguments[@]}" "$next_dir"
codesign --verify --deep --strict "$next_dir"
rm -rf "$app_dir"
mv "$next_dir" "$app_dir"
print -r -- "$app_dir"
