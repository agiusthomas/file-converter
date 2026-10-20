#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
source "$project_dir/scripts/signing-config.sh"
: "${CONVERTER_SIGN_IDENTITY:?Set a Developer ID Application signing identity}"
: "${CONVERTER_NOTARY_PROFILE:?Set an existing notarytool keychain profile name}"
[[ "$CONVERTER_SIGN_IDENTITY" != "-" ]] || { print -u2 "Public releases require Developer ID signing"; exit 2; }
./scripts/build-app.sh release
version="$(plutil -extract CFBundleShortVersionString raw -o - "$project_dir/build/File Converter.app/Contents/Info.plist")"
[[ "$version" == [0-9]* && "$version" != *[^0-9.]* ]] || { print -u2 "Invalid app version"; exit 2; }
archive="$project_dir/build/File-Converter-$version.zip"
ditto -c -k --sequesterRsrc --keepParent "$project_dir/build/File Converter.app" "$archive"
notary_arguments=(--keychain-profile "$CONVERTER_NOTARY_PROFILE")
if [[ -n "$CONVERTER_NOTARY_KEYCHAIN" ]]; then notary_arguments+=(--keychain "$CONVERTER_NOTARY_KEYCHAIN"); fi
xcrun notarytool submit "$archive" "${notary_arguments[@]}" --wait
xcrun stapler staple "$project_dir/build/File Converter.app"
spctl --assess --type execute --verbose "$project_dir/build/File Converter.app"
ditto -c -k --sequesterRsrc --keepParent "$project_dir/build/File Converter.app" "$archive"
./scripts/package-dmg.sh
cd "$project_dir/build"
checksums="File-Converter-$version-SHA256SUMS.txt"
shasum -a 256 "File-Converter-$version.dmg" "File-Converter-$version.zip" > "$checksums"
cat "$checksums"
